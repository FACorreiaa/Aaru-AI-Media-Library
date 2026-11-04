package gamification

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// poisonEvaluations makes every evaluation fail at its last write, as a poison row would, until the
// returned func lifts it. Only the evaluation's own stamp trips it: the backoff's update goes through.
func (f *fixture) poisonEvaluations() func() {
	f.exec(`CREATE FUNCTION fail_evaluation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.evaluated_at IS DISTINCT FROM OLD.evaluated_at THEN RAISE EXCEPTION 'poison'; END IF;
    RETURN NEW;
END $$`)
	f.exec(`CREATE TRIGGER fail_evaluation BEFORE UPDATE ON user_progress FOR EACH ROW EXECUTE FUNCTION fail_evaluation()`)
	return func() {
		f.exec(`DROP TRIGGER fail_evaluation ON user_progress`)
		f.exec(`DROP FUNCTION fail_evaluation()`)
	}
}

type evalState struct {
	failures     int
	waits        *time.Duration
	leased       bool
	dirty        bool
	evaluatedNow bool
}

func (f *fixture) evalState(user uuid.UUID) evalState {
	f.t.Helper()
	var s evalState
	var waitSeconds *float64
	require.NoError(f.t, f.pool.QueryRow(f.ctx, `SELECT eval_failures, extract(epoch FROM eval_not_before - now())::float8,
    locked_until IS NOT NULL, dirty_at IS NOT NULL, evaluated_at > now() - interval '1 minute'
FROM user_progress WHERE user_id = $1`, user).Scan(&s.failures, &waitSeconds, &s.leased, &s.dirty, &s.evaluatedNow))
	if waitSeconds != nil {
		d := time.Duration(*waitSeconds * float64(time.Second))
		s.waits = &d
	}
	return s
}

// The wait is over: only the backoff's clock is moved, never the failure count.
func (f *fixture) backoffPassed(user uuid.UUID) {
	f.exec(`UPDATE user_progress SET eval_not_before = now() - interval '1 second' WHERE user_id = $1`, user)
}

// REL-006: a poison user backs off, doubling, and after MaxEvaluationFailures waits for their next
// write instead of being retried forever. That write gives a fresh start.
func TestAFailingEvaluationBacksOffThenGivesUpUntilTheNextWrite(t *testing.T) {
	f := newFixture(t)
	w := &Worker{Service: f.svc}
	f.exec(`UPDATE user_progress SET evaluated_at = now() - interval '1 day' WHERE user_id = $1`, f.user)
	require.NoError(t, f.svc.store().markDirty(f.ctx, f.user, OriginLive))
	lift := f.poisonEvaluations()

	worked, err := w.Step(f.ctx)
	assert.True(t, worked)
	require.Error(t, err)
	first := f.evalState(f.user)
	assert.Equal(t, 1, first.failures)
	assert.False(t, first.leased, "the lease goes: the backoff decides when it runs next")
	assert.True(t, first.dirty)
	require.NotNil(t, first.waits)
	assert.InDelta(t, EvaluationBackoff.Seconds(), first.waits.Seconds(), 5)

	worked, err = w.Step(f.ctx)
	require.NoError(t, err)
	assert.False(t, worked, "it waits out its backoff")

	f.backoffPassed(f.user)
	_, err = w.Step(f.ctx)
	require.Error(t, err)
	second := f.evalState(f.user)
	assert.Equal(t, 2, second.failures)
	require.NotNil(t, second.waits)
	assert.InDelta(t, 2*EvaluationBackoff.Seconds(), second.waits.Seconds(), 5, "the wait doubles")

	for range MaxEvaluationFailures - 2 {
		f.backoffPassed(f.user)
		_, err = w.Step(f.ctx)
		require.Error(t, err)
	}
	assert.Equal(t, MaxEvaluationFailures, f.evalState(f.user).failures)
	f.backoffPassed(f.user)
	worked, err = w.Step(f.ctx)
	require.NoError(t, err)
	assert.False(t, worked, "given up: not claimed even with its wait over")

	lift()
	require.NoError(t, f.svc.store().markDirty(f.ctx, f.user, OriginLive))
	restart := f.evalState(f.user)
	assert.Equal(t, 0, restart.failures, "a new write is a fresh start")
	assert.Nil(t, restart.waits)
	worked, err = w.Step(f.ctx)
	require.NoError(t, err)
	assert.True(t, worked)
	done := f.evalState(f.user)
	assert.False(t, done.dirty)
	assert.True(t, done.evaluatedNow)
	assert.Equal(t, 0, done.failures)
}

// The backoff's bookkeeping outlives the step's cancelled context; a shutdown is not a failure.
func TestACancelledStepIsNotCountedAsAFailure(t *testing.T) {
	f := newFixture(t)
	w := &Worker{Service: f.svc}
	require.NoError(t, f.svc.store().markDirty(f.ctx, f.user, OriginLive))
	ctx, cancel := context.WithCancel(f.ctx)
	cancel()
	_, err := w.Step(ctx)
	require.Error(t, err)
	assert.Equal(t, 0, f.evalState(f.user).failures)
}

// PERF-006: facts keep each item once, in the order first seen.
func TestWriteFactsKeepItemsInFirstSeenOrder(t *testing.T) {
	f := NewWriteFacts("episode")
	a, b := uuid.New(), uuid.New()
	f.see(a)
	f.see(b)
	f.see(a)
	assert.Equal(t, []uuid.UUID{a, b}, f.order)
}
