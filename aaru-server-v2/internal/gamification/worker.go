package gamification

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgtype"
)

// WorkerLease is how long a claimed user stays leased.
const WorkerLease = 120 * time.Second

// Worker evaluates badges the request path did not (GamificationWorker): imports and approved
// plans that failed inline, retries after a failed after-write hook, and the first run over every
// existing user's library (GAM-004). Leased like the import worker, so a crash leaves the user
// re-runnable.
type Worker struct {
	Service *Service
	// Idle is the pause when there is nothing to do (5 s).
	Idle time.Duration
	// Pace is a pause between users, so a deploy's backfill never crowds out request traffic.
	Pace time.Duration
}

// NewWorker is the worker with Swift's timings.
func NewWorker(service *Service) *Worker {
	return &Worker{Service: service, Idle: 5 * time.Second, Pace: 200 * time.Millisecond}
}

// Name is the worker's log name.
func (w *Worker) Name() string { return "gamification" }

// Run loops until ctx is cancelled.
func (w *Worker) Run(ctx context.Context) error {
	for ctx.Err() == nil {
		worked, err := w.Step(ctx)
		switch {
		case err != nil && ctx.Err() != nil:
			return nil
		case err != nil:
			w.Service.log().Error("Gamification worker step failed", "error", err.Error())
		case worked:
			continue
		}
		select {
		case <-ctx.Done():
		case <-time.After(w.Idle):
		}
	}
	return nil
}

// Step seeds progress rows for users who have none, then evaluates one claimed user. It reports
// whether it claimed one.
func (w *Worker) Step(ctx context.Context) (bool, error) {
	st := w.Service.store()
	if _, err := st.q.GamificationSeedProgress(ctx, 100); err != nil {
		return false, fmt.Errorf("seed progress: %w", err)
	}
	claimed, err := st.q.GamificationClaimDirty(ctx, WorkerLease.Seconds())
	if err != nil {
		return false, fmt.Errorf("claim dirty: %w", err)
	}
	if len(claimed) == 0 {
		return false, nil
	}
	row := claimed[0]
	origin := OriginLive
	switch {
	case row.Fresh:
		origin = OriginBackfill
	case row.DirtyOrigin != nil && Origin(*row.DirtyOrigin).valid():
		origin = Origin(*row.DirtyOrigin)
	}
	if err := w.Service.StreakBonuses(ctx, row.UserID); err != nil {
		return false, err
	}
	if _, err := w.Service.Evaluate(ctx, row.UserID, origin, nil); err != nil {
		return false, err
	}
	if w.Pace > 0 {
		select {
		case <-ctx.Done():
			return true, nil
		case <-time.After(w.Pace):
		}
	}
	return true, nil
}

func timestamptz(t time.Time) pgtype.Timestamptz {
	return pgtype.Timestamptz{Time: t, Valid: true}
}
