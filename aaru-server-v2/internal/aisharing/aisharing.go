// Package aisharing is AI sharing (PRV-002): a user's yes or no to Aaru sending their data to its
// AI provider. Unanswered counts as no. Every path that hands a user's data to a model.Provider
// calls Require first, so the rule holds whatever a client shows.
package aisharing

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/db"
	"aaru-go-api/internal/db/sqlc"
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
)

// State is where a user stands.
type State string

// The three states. Unanswered and Declined both send nothing; only Unanswered is asked again.
const (
	Unanswered State = "unanswered"
	Allowed    State = "allowed"
	Declined   State = "declined"
)

// Answer is a user's state and when they last answered (nil while unanswered).
type Answer struct {
	State     State
	DecidedAt *time.Time
}

// Code is the error code every gated route answers with.
const Code = "ai_sharing_required"

// ErrRequired is the 403 a gated path returns for a user who has not allowed. Nothing was sent.
var ErrRequired = apperr.New(http.StatusForbidden, Code,
	"Aaru asks before it sends anything of yours to its AI provider. Allow AI data sharing in Settings to use this.")

// From reads an answer out of the two stored columns.
func From(allowed *bool, decidedAt pgtype.Timestamptz) Answer {
	a := Answer{State: Unanswered}
	if allowed == nil {
		return a
	}
	a.State = Declined
	if *allowed {
		a.State = Allowed
	}
	if decidedAt.Valid {
		at := decidedAt.Time
		a.DecidedAt = &at
	}
	return a
}

// Get is the user's answer. A user who no longer exists is unanswered.
func Get(ctx context.Context, q *sqlc.Queries, user uuid.UUID) (Answer, error) {
	row, err := q.AISharing(ctx, user)
	if err != nil {
		if db.IsNoRows(err) {
			return Answer{State: Unanswered}, nil
		}
		return Answer{}, fmt.Errorf("ai sharing: %w", err)
	}
	return From(row.AiSharingAllowed, row.AiSharingDecidedAt), nil
}

// Set stores the user's answer; the latest one holds.
func Set(ctx context.Context, q *sqlc.Queries, user uuid.UUID, allowed bool, now time.Time) (Answer, error) {
	row, err := q.SetAISharing(ctx, sqlc.SetAISharingParams{
		ID: user, Allowed: allowed, DecidedAt: pgtype.Timestamptz{Time: now, Valid: true},
	})
	if err != nil {
		if db.IsNoRows(err) {
			return Answer{}, apperr.Unauthorized()
		}
		return Answer{}, fmt.Errorf("set ai sharing: %w", err)
	}
	return From(row.AiSharingAllowed, row.AiSharingDecidedAt), nil
}

// Require is nil when the user allowed, ErrRequired when they have not. It fails closed: an error
// reading the answer is returned, never treated as a yes.
func Require(ctx context.Context, q *sqlc.Queries, user uuid.UUID) error {
	answer, err := Get(ctx, q, user)
	if err != nil {
		return err
	}
	if answer.State != Allowed {
		return ErrRequired
	}
	return nil
}

// AllowedAmong is which of these users allowed, for the group rule: only their messages go out.
func AllowedAmong(ctx context.Context, q *sqlc.Queries, users []uuid.UUID) (map[uuid.UUID]bool, error) {
	out := make(map[uuid.UUID]bool, len(users))
	if len(users) == 0 {
		return out, nil
	}
	ids, err := q.UsersAllowingAI(ctx, users)
	if err != nil {
		return nil, fmt.Errorf("users allowing ai: %w", err)
	}
	for _, id := range ids {
		out[id] = true
	}
	return out, nil
}
