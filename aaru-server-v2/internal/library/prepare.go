package library

import (
	"aaru-go-api/internal/core"
	"context"
	"slices"
	"strconv"
	"strings"

	"github.com/google/uuid"
)

// PreparedWrite is a library write worked out against the current state but not applied. A tap
// commits it at once; an agent's larger change stores it in a plan, and approval runs the same op
// (AG-003).
type PreparedWrite struct {
	Op Op
	// Kind is the journal's `kind` when committed alone.
	Kind string
	// Summary is what it does, without a caller's name: "Marked S01E01 of Andor watched".
	Summary string
	// ItemID is the item it touches, or creates.
	ItemID uuid.UUID
	Title  core.Title
	// Adds is true when it creates the item, so a plan checks the title is still absent.
	Adds     bool
	Episodes int
}

// Commit applies one prepared write as one journaled action, then runs the gamification hooks.
func (s *Service) Commit(ctx context.Context, w PreparedWrite, user uuid.UUID, caller Caller) (ActionRecord, error) {
	action, err := s.Store.Apply(ctx, w.Op, user, caller, w.Kind, caller.Summary(w.Summary))
	if err != nil {
		return ActionRecord{}, err
	}
	if s.Gamification != nil {
		id := action.ID
		s.Gamification.AfterWrite(ctx, user, &id)
	}
	return action, nil
}

// PrepareAdd is a new item for title (wishlist when status is nil).
func (s *Service) PrepareAdd(title core.Title, status *core.LibraryStatus, caller Caller) PreparedWrite {
	st := core.StatusWishlist
	if status != nil {
		st = *status
	}
	now := s.now()
	// A wishlist add says nothing yet; an import may still move it forward.
	byHand := caller.Actor == ActorUser && st != core.StatusWishlist
	fields := ItemFields{Status: st, StatusByHand: &byHand}
	if st == core.StatusFinished {
		fields.FinishedAt = &now
	}
	snapshot := ItemSnapshot{ID: uuid.New(), TitleID: title.ID, Fields: fields, AddedAt: now, Watched: []core.EpisodeKey{}}
	return PreparedWrite{
		Op: InsertItem(snapshot), Kind: "add", Summary: "Added " + title.Title + " to " + StatusLabel(st, title.Type),
		ItemID: snapshot.ID, Title: title, Adds: true,
	}
}

// PreparePatch is a patch as a write; nil when it changes nothing.
func (s *Service) PreparePatch(current Entry, patch ItemPatch, caller Caller) (*PreparedWrite, error) {
	fields, err := s.PatchedFields(current, patch, caller)
	if err != nil {
		return nil, err
	}
	if fields.Equal(current.Fields()) {
		return nil, nil //nolint:nilnil // nothing to write
	}
	return &PreparedWrite{
		Op: SetFields(current.Item.ID, fields), Kind: "update", Summary: UpdateSummary(current, fields),
		ItemID: current.Item.ID, Title: current.Title,
	}, nil
}

// PatchedFields are the item's fields with the patch applied.
func (s *Service) PatchedFields(current Entry, patch ItemPatch, caller Caller) (ItemFields, error) {
	fields := current.Fields()
	if patch.Status != nil && *patch.Status != fields.Status {
		fields.Status = *patch.Status
		fields.FinishedAt = nil
		if *patch.Status == core.StatusFinished {
			now := s.now()
			fields.FinishedAt = &now
		}
		if caller.Actor == ActorUser {
			byHand := true
			fields.StatusByHand = &byHand
		}
	}
	if patch.Clear[ClearRating] {
		fields.Rating = nil
	} else if patch.Rating != nil {
		rating, err := core.NewRating(*patch.Rating)
		if err != nil {
			return ItemFields{}, err
		}
		v := rating.Value()
		fields.Rating = &v
	}
	if patch.Clear[ClearNotes] {
		fields.Notes = nil
	} else if patch.Notes != nil {
		fields.Notes = nilIfBlank(*patch.Notes)
	}
	if patch.IsOwned != nil {
		fields.IsOwned = *patch.IsOwned
	}
	if err := applyBookProgress(patch, &fields, current.Title.Type); err != nil {
		return ItemFields{}, err
	}
	if err := applyMangaProgress(patch, &fields, current.Title.Type); err != nil {
		return ItemFields{}, err
	}
	// LIB-007: reading on from a page or chapter resumes an on-hold item, unless the same tap put
	// it on hold.
	readsOn := patch.BookPage != nil || patch.BookPercent != nil || patch.MangaChapter != nil || patch.MangaVolume != nil
	if fields.Status == core.StatusOnHold && patch.Status == nil && readsOn {
		fields.Status = core.StatusInProgress
	}
	return fields, nil
}

func nilIfBlank(s string) *string {
	trimmed := strings.TrimSpace(s)
	if trimmed == "" {
		return nil
	}
	return &trimmed
}

// PrepareDelete removes the item.
func (s *Service) PrepareDelete(current Entry) PreparedWrite {
	return PreparedWrite{
		Op: DeleteItem(current.Item.ID), Kind: "remove", Summary: "Removed " + current.Title.Title,
		ItemID: current.Item.ID, Title: current.Title,
	}
}

func showKeys(show ShowContext) map[core.EpisodeKey]bool {
	known := map[core.EpisodeKey]bool{}
	for _, ep := range show.Episodes {
		if k, err := core.NewEpisodeKey(ep.Season, ep.Episode); err == nil {
			known[k] = true
		}
	}
	return known
}

// PrepareEpisodes is the episodes the show has and that are not already in the asked state; nil
// when none are.
func (s *Service) PrepareEpisodes(ctx context.Context, show ShowContext, keys []core.EpisodeKey, watched bool) (*PreparedWrite, error) {
	known := showKeys(show)
	current, err := s.Store.Watched(ctx, show.Entry.Item.ID)
	if err != nil {
		return nil, err
	}
	seen := map[core.EpisodeKey]bool{}
	var changing []core.EpisodeKey
	for _, k := range keys {
		if seen[k] {
			continue
		}
		seen[k] = true
		if known[k] && current[k] != watched {
			changing = append(changing, k)
		}
	}
	if len(changing) == 0 {
		return nil, nil //nolint:nilnil // nothing to write
	}
	slices.SortFunc(changing, core.EpisodeKey.Compare)
	verb := "unwatched"
	var watch, unwatch []core.EpisodeKey
	if watched {
		verb = "watched"
		watch = changing
	} else {
		unwatch = changing
	}
	what := changing[0].String()
	if len(changing) > 1 {
		what = strconv.Itoa(len(changing)) + " episodes"
	}
	w, err := s.PrepareProgress(ctx, watch, unwatch, show, nil, "episode",
		"Marked "+what+" of "+show.Entry.Title.Title+" "+verb)
	if err != nil {
		return nil, err
	}
	return &w, nil
}

// PrepareSeason is every aired episode of a season; unaired ones are left alone. The ticks are
// undated (the journal kind "season"): a season tick is a catch-up, not this week's watching.
func (s *Service) PrepareSeason(ctx context.Context, show ShowContext, season int) (PreparedWrite, error) {
	var aired []core.EpisodeKey
	inSeason := 0
	for _, ep := range show.Episodes {
		if ep.Season != season {
			continue
		}
		inSeason++
		if HasAired(ep, show.Status, s.now()) {
			if k, err := core.NewEpisodeKey(ep.Season, ep.Episode); err == nil {
				aired = append(aired, k)
			}
		}
	}
	if inSeason == 0 {
		return PreparedWrite{}, &core.ValidationError{Kind: core.InvalidEpisodeNumber, Season: season, Episode: 1}
	}
	summary := "Marked season " + strconv.Itoa(season) + " of " + show.Entry.Title.Title + " watched (" +
		strconv.Itoa(len(aired)) + " episodes)"
	return s.PrepareProgress(ctx, aired, nil, show, nil, "season", summary)
}

// PrepareShowWatched (PROG-005) is the whole show watched, as one action. Every aired regular
// episode is ticked, undated (the journal kind "show"), and the show finishes, running or not
// (owner, 2026-10-30): a running one moves back to in progress when its next episode airs
// (ReopenAired). patch carries any other fields of the same tap (its status is the reason for this
// write and is not applied as such). Nil when nothing would change.
func (s *Service) PrepareShowWatched(ctx context.Context, show ShowContext, patch ItemPatch, caller Caller) (*PreparedWrite, error) {
	rest := patch
	rest.Status = nil
	fields, err := s.PatchedFields(show.Entry, rest, caller)
	if err != nil {
		return nil, err
	}
	current, err := s.Store.Watched(ctx, show.Entry.Item.ID)
	if err != nil {
		return nil, err
	}
	airedRegular := 0
	var unwatched []core.EpisodeKey
	for _, ep := range show.Episodes {
		if ep.Season <= 0 || !HasAired(ep, show.Status, s.now()) {
			continue
		}
		airedRegular++
		if k, err := core.NewEpisodeKey(ep.Season, ep.Episode); err == nil && !current[k] {
			unwatched = append(unwatched, k)
		}
	}
	if airedRegular > 0 && fields.Status != core.StatusFinished {
		fields.Status = core.StatusFinished
		now := s.now()
		fields.FinishedAt = &now
		if caller.Actor == ActorUser {
			byHand := true
			fields.StatusByHand = &byHand
		}
	}
	summary := "Marked " + show.Entry.Title.Title + " watched (" + strconv.Itoa(len(unwatched)) + " episodes)"
	w, err := s.PrepareProgress(ctx, unwatched, nil, show, &fields, "show", summary)
	if err != nil {
		return nil, err
	}
	if len(w.Op.Ops) <= 1 && len(unwatched) == 0 {
		return nil, nil //nolint:nilnil // nothing to write
	}
	return &w, nil
}

// PrepareProgress is an episode op together with the status it implies, as one action: the first
// tick moves wishlist → in progress, and a new tick resumes an on-hold item (LIB-007); watching
// every aired episode of an ended or canceled show finishes it. A running show never
// auto-finishes. base replaces the entry's fields as the starting point when set.
func (s *Service) PrepareProgress(ctx context.Context, watch, unwatch []core.EpisodeKey, show ShowContext, base *ItemFields, kind, summary string) (PreparedWrite, error) {
	current := show.Entry
	id := current.Item.ID
	op := SetEpisodes(id, watch, unwatch)
	watched, err := s.Store.Watched(ctx, id)
	if err != nil {
		return PreparedWrite{}, err
	}
	for _, k := range watch {
		watched[k] = true
	}
	for _, k := range unwatch {
		delete(watched, k)
	}
	fields := current.Fields()
	if base != nil {
		fields = *base
	}
	if fields.Status == core.StatusWishlist && len(watched) > 0 {
		fields.Status = core.StatusInProgress
	}
	if fields.Status == core.StatusOnHold && len(watch) > 0 {
		fields.Status = core.StatusInProgress
	}
	airedRegular, allWatched := 0, true
	for _, ep := range show.Episodes {
		if ep.Season <= 0 || !HasAired(ep, show.Status, s.now()) {
			continue
		}
		airedRegular++
		if !watched[core.EpisodeKey{Season: ep.Season, Episode: ep.Episode}] {
			allWatched = false
		}
	}
	if airedRegular > 0 && allWatched && endedOrCanceled(show.Status) && fields.Status != core.StatusFinished {
		fields.Status = core.StatusFinished
		now := s.now()
		fields.FinishedAt = &now
	}
	ops := []Op{op}
	if !fields.Equal(current.Fields()) {
		ops = append(ops, SetFields(id, fields))
	}
	return PreparedWrite{
		Op: Batch(ops...), Kind: kind, Summary: summary, ItemID: id, Title: current.Title,
		Episodes: len(watch) + len(unwatch),
	}, nil
}
