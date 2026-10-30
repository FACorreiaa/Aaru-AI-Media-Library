package groups

import (
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/social"
	"context"
	"fmt"

	"github.com/google/uuid"
)

// Social is the friendship and block reads groups and the Board make, through the social area's
// store (PostgresSocialStore's read half): one copy of who is a friend and who blocked whom.
type Social struct {
	Store *social.Store
}

// NewSocial reads the social graph over q.
func NewSocial(q *sqlc.Queries) Social { return Social{Store: &social.Store{Q: q}} }

// User is someone with a handle, or nil without one.
func (s Social) User(ctx context.Context, id uuid.UUID) (*User, error) {
	return s.Store.User(ctx, id) //nolint:wrapcheck // the store wraps its own errors
}

// RequireHandle is the viewer with their handle, or 422 `handle_required`.
func (s Social) RequireHandle(ctx context.Context, viewer uuid.UUID) (User, error) {
	u, err := s.User(ctx, viewer)
	if err != nil {
		return User{}, err
	}
	if u == nil {
		return User{}, ErrHandleRequired
	}
	return *u, nil
}

// AreFriends reports a mutual friendship.
func (s Social) AreFriends(ctx context.Context, a, b uuid.UUID) (bool, error) {
	return s.Store.AreFriends(ctx, a, b) //nolint:wrapcheck // the store wraps its own errors
}

// IsBlocked reports a block in either direction.
func (s Social) IsBlocked(ctx context.Context, a, b uuid.UUID) (bool, error) {
	return s.Store.IsBlocked(ctx, a, b) //nolint:wrapcheck // the store wraps its own errors
}

// Friends are the user's friends by handle.
func (s Social) Friends(ctx context.Context, user uuid.UUID) ([]User, error) {
	return s.Store.Friends(ctx, user) //nolint:wrapcheck // the store wraps its own errors
}

// Blocked is everyone the user blocked.
func (s Social) Blocked(ctx context.Context, user uuid.UUID) ([]User, error) {
	return s.Store.Blocked(ctx, user) //nolint:wrapcheck // the store wraps its own errors
}

// Blockers is everyone who blocked the user.
func (s Social) Blockers(ctx context.Context, user uuid.UUID) (map[uuid.UUID]bool, error) {
	return s.Store.Blockers(ctx, user) //nolint:wrapcheck // the store wraps its own errors
}

// BlockedEitherWay is everyone the user blocked plus everyone who blocked the user.
func (s Social) BlockedEitherWay(ctx context.Context, user uuid.UUID) (map[uuid.UUID]bool, error) {
	blocked, err := s.Blocked(ctx, user)
	if err != nil {
		return nil, err
	}
	set, err := s.Blockers(ctx, user)
	if err != nil {
		return nil, err
	}
	for _, u := range blocked {
		set[u.ID] = true
	}
	return set, nil
}

// Progress is each user's progress in a title; users without it in their library are absent.
func Progress(ctx context.Context, q *sqlc.Queries, title uuid.UUID, users []uuid.UUID) (map[uuid.UUID]TitleProgress, error) {
	rows, err := q.GroupTitleProgress(ctx, sqlc.GroupTitleProgressParams{TitleID: title, Users: users})
	if err != nil {
		return nil, fmt.Errorf("title progress: %w", err)
	}
	progress := make(map[uuid.UUID]TitleProgress, len(rows))
	for _, r := range rows {
		status := coreStatus(r.Status)
		if status == nil {
			continue
		}
		p := TitleProgress{Status: *status}
		if r.Season != nil && r.Episode != nil {
			p.Furthest = &EpisodePoint{Season: int(*r.Season), Episode: int(*r.Episode)}
		}
		progress[r.UserID] = p
	}
	return progress, nil
}

// ProgressOf is one user's progress in a title, or nil.
func ProgressOf(ctx context.Context, q *sqlc.Queries, title, user uuid.UUID) (*TitleProgress, error) {
	all, err := Progress(ctx, q, title, []uuid.UUID{user})
	if err != nil {
		return nil, err
	}
	return progressOf(all, user), nil
}
