package groups

import (
	"aaru-go-api/internal/db"
	"aaru-go-api/internal/db/sqlc"
	"context"
	"fmt"

	"github.com/google/uuid"
)

// Social is the friendship and block reads groups and the Board make (PostgresSocialStore's
// read half). The social area owns writes; these are its reads, kept here so groups and the
// Board do not wait on it.
type Social struct {
	Q *sqlc.Queries
}

// User is someone with a handle, or nil without one.
func (s Social) User(ctx context.Context, id uuid.UUID) (*User, error) {
	row, err := s.Q.GroupSocialUser(ctx, id)
	if db.IsNoRows(err) {
		return nil, nil //nolint:nilnil // no handle, as Swift's optional
	}
	if err != nil {
		return nil, fmt.Errorf("social user: %w", err)
	}
	return &User{ID: row.UserID, Handle: row.Handle, DisplayName: row.DisplayName, AvatarVersion: row.AvatarVersion}, nil
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
	found, err := s.Q.GroupAreFriends(ctx, sqlc.GroupAreFriendsParams{A: a, B: b})
	if err != nil {
		return false, fmt.Errorf("are friends: %w", err)
	}
	return found, nil
}

// IsBlocked reports a block in either direction.
func (s Social) IsBlocked(ctx context.Context, a, b uuid.UUID) (bool, error) {
	found, err := s.Q.GroupIsBlocked(ctx, sqlc.GroupIsBlockedParams{A: a, B: b})
	if err != nil {
		return false, fmt.Errorf("is blocked: %w", err)
	}
	return found, nil
}

// Friends are the user's friends by handle.
func (s Social) Friends(ctx context.Context, user uuid.UUID) ([]User, error) {
	rows, err := s.Q.GroupFriends(ctx, user)
	if err != nil {
		return nil, fmt.Errorf("friends: %w", err)
	}
	users := make([]User, len(rows))
	for i, r := range rows {
		users[i] = User{ID: r.UserID, Handle: r.Handle, DisplayName: r.DisplayName, AvatarVersion: r.AvatarVersion}
	}
	return users, nil
}

// Blocked is everyone the user blocked.
func (s Social) Blocked(ctx context.Context, user uuid.UUID) ([]User, error) {
	rows, err := s.Q.GroupBlockedBy(ctx, user)
	if err != nil {
		return nil, fmt.Errorf("blocked: %w", err)
	}
	users := make([]User, len(rows))
	for i, r := range rows {
		users[i] = User{ID: r.UserID, Handle: r.Handle, DisplayName: r.DisplayName, AvatarVersion: r.AvatarVersion}
	}
	return users, nil
}

// Blockers is everyone who blocked the user.
func (s Social) Blockers(ctx context.Context, user uuid.UUID) (map[uuid.UUID]bool, error) {
	ids, err := s.Q.GroupBlockers(ctx, user)
	if err != nil {
		return nil, fmt.Errorf("blockers: %w", err)
	}
	set := make(map[uuid.UUID]bool, len(ids))
	for _, id := range ids {
		set[id] = true
	}
	return set, nil
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
