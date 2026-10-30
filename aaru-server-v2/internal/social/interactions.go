package social

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/core"
	"context"
	"fmt"
	"net/http"
	"slices"
	"strings"

	"github.com/google/uuid"
)

// SOC-007 reactions and SOC-006 recommendations (InteractionService.swift). Both are between
// friends only: anything else is the same 404 as nobody being there. Agents get neither.

const (
	// MaxRecipients is how many friends one recommendation may go to.
	MaxRecipients = 10
	// MaxRecommendationNote bounds a recommendation's note.
	MaxRecommendationNote = 140
	// InboxLimit is how many waiting recommendations the inbox shows.
	InboxLimit = 50
)

// ErrNoSuchRow is the one 404 for a row the viewer cannot react to.
var ErrNoSuchRow = apperr.NotFound("That activity isn't there.")

// ErrNoSuchRecommendation is the one 404 for a recommendation that is not waiting.
var ErrNoSuchRecommendation = apperr.NotFound("That recommendation is gone.")

func unprocessable(message string) *apperr.Error {
	return apperr.New(http.StatusUnprocessableEntity, "validation_failed", message)
}

// React sets or clears the viewer's reaction on a friend's row. Your own rows take no reactions.
func (s *Service) React(ctx context.Context, emoji *string, id string, viewer uuid.UUID) error {
	row, ok := ParseActivityKey(id)
	if !ok || row.Owner == viewer {
		return ErrNoSuchRow
	}
	visible, err := s.canSee(ctx, row.Owner, viewer)
	if err != nil {
		return err
	}
	if !visible {
		return ErrNoSuchRow
	}
	has, err := s.Store.HasTitle(ctx, row.Owner, row.TitleID)
	if err != nil {
		return err
	}
	if !has {
		return ErrNoSuchRow
	}
	if emoji != nil && !slices.Contains(Reactions, *emoji) {
		return unprocessable("Pick one of " + strings.Join(Reactions, " ") + ".")
	}
	return s.Store.React(ctx, emoji, row, viewer, s.now())
}

// Recommend sends one title to up to ten friends, with an optional short note.
func (s *Service) Recommend(ctx context.Context, ref core.MediaRef, note *string, to []uuid.UUID, viewer uuid.UUID) error {
	if _, err := s.RequireHandle(ctx, viewer); err != nil {
		return err
	}
	recipients := uniqueIDs(to)
	if len(recipients) == 0 || len(recipients) > MaxRecipients {
		return unprocessable(fmt.Sprintf("Send it to between 1 and %d friends.", MaxRecipients))
	}
	var kept *string
	if note != nil {
		trimmed := strings.TrimSpace(*note)
		if core.Length(trimmed) > MaxRecommendationNote {
			return unprocessable(fmt.Sprintf("Keep the note under %d characters.", MaxRecommendationNote))
		}
		if trimmed != "" {
			kept = &trimmed
		}
	}
	if slices.Contains(recipients, viewer) {
		return ErrNoSuchUser
	}
	for _, r := range recipients {
		friend, err := s.isFriend(ctx, r, viewer)
		if err != nil {
			return err
		}
		if !friend {
			return ErrNoSuchUser
		}
	}
	if !s.recommendLimiter.Allow(viewer.String(), s.now()) {
		return apperr.RateLimited("Too many recommendations. Try later.")
	}
	title, err := s.resolveTitle(ctx, ref)
	if err != nil {
		return err
	}
	sent := s.now()
	items := make([]Recommendation, 0, len(recipients))
	for _, r := range recipients {
		items = append(items, Recommendation{
			ID: uuid.New(), Sender: viewer, Recipient: r, TitleID: title.ID, Note: kept, CreatedAt: sent,
		})
	}
	return s.Store.Recommend(ctx, items)
}

// InboxItem is a waiting recommendation with who sent it and the title.
type InboxItem struct {
	Recommendation Recommendation
	From           User
	Title          core.Title
}

// Inbox is the viewer's waiting recommendations, newest first.
func (s *Service) Inbox(ctx context.Context, viewer uuid.UUID) ([]InboxItem, error) {
	waiting, err := s.Store.Inbox(ctx, viewer, InboxLimit)
	if err != nil {
		return nil, err
	}
	out := []InboxItem{}
	if len(waiting) == 0 {
		return out, nil
	}
	friends, err := s.Store.Friends(ctx, viewer)
	if err != nil {
		return nil, err
	}
	byID := map[uuid.UUID]User{}
	for _, f := range friends {
		if _, seen := byID[f.ID]; !seen {
			byID[f.ID] = f
		}
	}
	ids := make([]uuid.UUID, 0, len(waiting))
	for _, w := range waiting {
		ids = append(ids, w.TitleID)
	}
	titles, err := s.titles(ctx, ids)
	if err != nil {
		return nil, err
	}
	for _, w := range waiting {
		from, okFrom := byID[w.Sender]
		title, okTitle := titles[w.TitleID]
		if okFrom && okTitle {
			out = append(out, InboxItem{Recommendation: w, From: from, Title: title})
		}
	}
	return out, nil
}

// AddRecommendation adds a recommended title to Plan to watch, as a tap would; a title already
// in the library keeps its status. The recommendation leaves the inbox either way.
func (s *Service) AddRecommendation(ctx context.Context, id, viewer uuid.UUID) error {
	item, err := s.Store.ResolveRecommendation(ctx, id, viewer, true, s.now())
	if err != nil {
		return err
	}
	if item == nil {
		return ErrNoSuchRecommendation
	}
	title, err := s.title(ctx, item.TitleID)
	if err != nil {
		return err
	}
	if title == nil {
		return ErrNoSuchRecommendation
	}
	return s.addToPlan(ctx, *title, viewer)
}

// DismissRecommendation removes a waiting recommendation.
func (s *Service) DismissRecommendation(ctx context.Context, id, viewer uuid.UUID) error {
	item, err := s.Store.ResolveRecommendation(ctx, id, viewer, false, s.now())
	if err != nil {
		return err
	}
	if item == nil {
		return ErrNoSuchRecommendation
	}
	return nil
}

func (s *Service) isFriend(ctx context.Context, other, viewer uuid.UUID) (bool, error) {
	blocked, err := s.Store.IsBlocked(ctx, viewer, other)
	if err != nil || blocked {
		return false, err
	}
	return s.Store.AreFriends(ctx, viewer, other)
}

// canSee is true for a friend whose library is shown to friends.
func (s *Service) canSee(ctx context.Context, owner, viewer uuid.UUID) (bool, error) {
	friend, err := s.isFriend(ctx, owner, viewer)
	if err != nil || !friend {
		return false, err
	}
	settings, err := s.Store.Settings(ctx, owner)
	if err != nil {
		return false, err
	}
	return settings.ShareLibraryWithFriends, nil
}
