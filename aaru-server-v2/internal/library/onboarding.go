package library

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"aaru-go-api/internal/safe"
	"context"
	"errors"
	"strconv"
	"time"

	"github.com/google/uuid"
)

// OnboardingKind is the journal kind of a first-run step's picks (ONB-001). It is undated
// (UndatedKinds) and not live (gamification.LiveKinds): what someone picks while setting up was
// watched, read or heard before, so it earns no points and no streak day, and the Recap leaves it
// out.
const OnboardingKind = "onboarding"

// Onboarding pick limits.
const (
	MaxOnboardingPicks = 60
	// onboardingResolveFanOut bounds the refs resolved at once; each provider keeps its own pace.
	onboardingResolveFanOut = 4
	// onboardingEpisodesDeadline bounds fetching episodes for the shows a step added, past the request.
	onboardingEpisodesDeadline = 2 * time.Minute
)

// Pick is one title picked in a first-run step, with the status chosen for it (wishlist when nil).
type Pick struct {
	Ref    core.MediaRef
	Status *core.LibraryStatus
}

// PickedItem is a pick's library item, by its position in the request.
type PickedItem struct {
	Index   int
	ItemID  uuid.UUID
	TitleID uuid.UUID
}

// PicksResult is a step's picks in the library. Missed counts refs that named no title; ActionID
// is the one journaled action, nil when every pick was already in the library.
type PicksResult struct {
	Items    []PickedItem
	Missed   int
	ActionID *uuid.UUID
}

// AddPicks adds a first-run step's picks (ONB-001) as one journaled action, so one undo takes them
// all back. A title already in the library comes back as it is; a title picked twice is added
// once. A status other than wishlist is set by hand (the user's tap), so a later import never moves
// it back. A show picked as finished ticks every aired episode, as a single add does (PROG-005).
// Unlike a single add, a finished pick has no finish date: it was finished before, not today.
func (s *Service) AddPicks(ctx context.Context, picks []Pick, user uuid.UUID) (PicksResult, error) {
	if len(picks) < 1 || len(picks) > MaxOnboardingPicks {
		return PicksResult{}, validation("items", "Pick between 1 and "+strconv.Itoa(MaxOnboardingPicks)+" titles.")
	}
	titles, err := s.resolvePicks(ctx, picks)
	if err != nil {
		return PicksResult{}, err
	}
	result, err := s.addPicks(ctx, picks, titles, user)
	var conflict *StoreConflict
	if errors.As(err, &conflict) {
		// Another write added one of these titles meanwhile: read the library again, once.
		result, err = s.addPicks(ctx, picks, titles, user)
	}
	return result, err
}

// resolvePicks is each pick's title, nil for a ref no provider knows.
func (s *Service) resolvePicks(ctx context.Context, picks []Pick) ([]*core.Title, error) {
	resolver := s.Catalog.Resolver()
	titles := make([]*core.Title, len(picks))
	g, gctx := safe.WithContext(ctx)
	g.SetLimit(onboardingResolveFanOut)
	for i, pick := range picks {
		g.Go(func() error {
			title, err := resolver.Resolve(gctx, pick.Ref, nil)
			if err != nil {
				if unresolvable(err) {
					return nil
				}
				return err
			}
			titles[i] = &title
			return nil
		})
	}
	if err := g.Wait(); err != nil {
		return nil, err
	}
	return titles, nil
}

// unresolvable is a ref that names no title: no provider knows it, or it is not a valid ref.
func unresolvable(err error) bool {
	if errors.Is(err, catalog.ErrUnresolvable) || provider.IsNotFound(err) {
		return true
	}
	if e := apperr.From(err); e != nil && e.Status < 500 {
		return true
	}
	return false
}

func (s *Service) addPicks(ctx context.Context, picks []Pick, titles []*core.Title, user uuid.UUID) (PicksResult, error) {
	result := PicksResult{Items: []PickedItem{}}
	itemOf := map[uuid.UUID]uuid.UUID{}
	var ops []Op
	var shows []uuid.UUID
	for i, title := range titles {
		if title == nil {
			result.Missed++
			continue
		}
		item, seen := itemOf[title.ID]
		if !seen {
			existing, err := s.Store.EntryForTitle(ctx, user, title.ID, s.now())
			if err != nil {
				return PicksResult{}, err
			}
			if existing != nil {
				item = existing.Item.ID
			} else {
				write, err := s.prepareAddWatched(ctx, *title, picks[i].Status, UserCaller)
				if err != nil {
					return PicksResult{}, err
				}
				snapshot := *write.Op.Snapshot
				snapshot.Fields.FinishedAt = nil
				ops = append(ops, InsertItem(snapshot))
				item = write.ItemID
				// A show picked as finished read its episodes already.
				if title.Type == core.MediaShow && snapshot.Fields.Status != core.StatusFinished {
					shows = append(shows, title.ID)
				}
			}
			itemOf[title.ID] = item
		}
		result.Items = append(result.Items, PickedItem{Index: i, ItemID: item, TitleID: title.ID})
	}
	if len(ops) == 0 {
		return result, nil
	}
	action, err := s.Store.Apply(ctx, Batch(ops...), user, UserCaller, OnboardingKind, onboardingSummary(len(ops)))
	if err != nil {
		return PicksResult{}, err
	}
	result.ActionID = &action.ID
	if s.Gamification != nil {
		s.Gamification.BatchApplied(ctx, user, &action.ID, false)
	}
	s.fetchEpisodes(ctx, shows)
	return result, nil
}

func onboardingSummary(added int) string {
	if added == 1 {
		return "Added 1 title while setting up"
	}
	return "Added " + strconv.Itoa(added) + " titles while setting up"
}

// fetchEpisodes reads the added shows' episodes past the request, so the calendar and Up Next have
// them, as a single add does. Best effort: the calendar retries.
func (s *Service) fetchEpisodes(ctx context.Context, shows []uuid.UUID) {
	if len(shows) == 0 || s.Catalog == nil || s.Catalog.Service == nil {
		return
	}
	ctx, cancel := context.WithTimeout(context.WithoutCancel(ctx), onboardingEpisodesDeadline)
	go func() {
		defer cancel()
		err := safe.Step(func() error {
			for _, id := range shows {
				if _, err := s.Catalog.Service.Detail(ctx, id); err != nil {
					s.log().DebugContext(ctx, "episodes after onboarding", "title", id, "error", err)
				}
			}
			return nil
		})
		if err != nil {
			s.log().Error("Episodes after onboarding failed", "error", err.Error())
		}
	}()
}
