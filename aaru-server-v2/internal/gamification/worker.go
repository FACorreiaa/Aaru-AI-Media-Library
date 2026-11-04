package gamification

import (
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/metrics"
	"aaru-go-api/internal/safe"
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
)

// WorkerLease is how long a claimed user stays leased.
const WorkerLease = 120 * time.Second

// A user whose evaluation fails waits EvaluationBackoff, doubling each time up to
// EvaluationBackoffMax; after MaxEvaluationFailures the worker gives up on them until they are
// marked dirty again or an inline evaluation succeeds (Go audit REL-006: a poison user no longer
// retries forever).
const (
	EvaluationBackoff     = time.Minute
	EvaluationBackoffMax  = time.Hour
	MaxEvaluationFailures = 5
)

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
		worked, err := safe.Value(func() (bool, error) { return w.Step(ctx) })
		if ctx.Err() == nil {
			metrics.WorkerPass(w.Name(), err)
		}
		switch {
		case err != nil && ctx.Err() != nil:
			return nil
		case err != nil:
			w.Service.log().Error("Gamification worker step failed", "error", err.Error(), "stack", string(safe.Stack(err)))
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

// Step seeds progress rows for users who have none, then evaluates one claimed user: a dirty one,
// else one never evaluated. It reports whether it claimed one. A failed evaluation backs the user
// off before it returns the error.
func (w *Worker) Step(ctx context.Context) (bool, error) {
	st := w.Service.store()
	if _, err := st.q.GamificationSeedProgress(ctx, 100); err != nil {
		return false, fmt.Errorf("seed progress: %w", err)
	}
	row, ok, err := w.claim(ctx, st)
	if err != nil || !ok {
		return false, err
	}
	origin := OriginLive
	switch {
	case row.Fresh:
		origin = OriginBackfill
	case row.DirtyOrigin != nil && Origin(*row.DirtyOrigin).valid():
		origin = Origin(*row.DirtyOrigin)
	}
	err = safe.Step(func() error {
		if err := w.Service.StreakBonuses(ctx, row.UserID); err != nil {
			return err
		}
		_, err := w.Service.Evaluate(ctx, row.UserID, origin, nil)
		return err
	})
	if err != nil {
		if ctx.Err() == nil {
			w.backOff(ctx, st, row.UserID)
		}
		return true, err
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

func (w *Worker) claim(ctx context.Context, st store) (sqlc.GamificationClaimDirtyRow, bool, error) {
	dirty, err := st.q.GamificationClaimDirty(ctx, sqlc.GamificationClaimDirtyParams{
		LeaseSeconds: WorkerLease.Seconds(), MaxFailures: MaxEvaluationFailures,
	})
	if err != nil {
		return sqlc.GamificationClaimDirtyRow{}, false, fmt.Errorf("claim dirty: %w", err)
	}
	if len(dirty) > 0 {
		return dirty[0], true, nil
	}
	fresh, err := st.q.GamificationClaimFresh(ctx, sqlc.GamificationClaimFreshParams{
		LeaseSeconds: WorkerLease.Seconds(), MaxFailures: MaxEvaluationFailures,
	})
	if err != nil {
		return sqlc.GamificationClaimDirtyRow{}, false, fmt.Errorf("claim fresh: %w", err)
	}
	if len(fresh) == 0 {
		return sqlc.GamificationClaimDirtyRow{}, false, nil
	}
	return sqlc.GamificationClaimDirtyRow(fresh[0]), true, nil
}

// backOff records a failed evaluation; the bookkeeping outlives a cancelled step.
func (w *Worker) backOff(ctx context.Context, st store, user uuid.UUID) {
	failures, err := st.q.GamificationEvaluationFailed(context.WithoutCancel(ctx), sqlc.GamificationEvaluationFailedParams{
		BaseSeconds: EvaluationBackoff.Seconds(), MaxSeconds: EvaluationBackoffMax.Seconds(), UserID: user,
	})
	switch {
	case err != nil:
		w.Service.log().Error("Gamification backoff failed", "error", err.Error())
	case failures >= MaxEvaluationFailures:
		w.Service.log().Error("Gamification worker gave up on a user until they are marked dirty again",
			"user", user, "failures", failures)
	}
}

func timestamptz(t time.Time) pgtype.Timestamptz {
	return pgtype.Timestamptz{Time: t, Valid: true}
}
