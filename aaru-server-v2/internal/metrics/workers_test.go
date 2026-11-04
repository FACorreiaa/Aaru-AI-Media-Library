package metrics

import (
	"aaru-go-api/internal/safe"
	"context"
	"errors"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestWorkerPassesCountByResult(t *testing.T) {
	Reset()
	WorkerPass("imports", nil)
	WorkerPass("imports", nil)
	WorkerPass("imports", errors.New("db down"))
	WorkerPass("imports", safe.Step(func() error { panic("bug") }))
	text := render(t)
	assert.Contains(t, text, `aaru_worker_passes_total{result="ok",worker="imports"} 2`+"\n")
	assert.Contains(t, text, `aaru_worker_passes_total{result="error",worker="imports"} 1`+"\n")
	assert.Contains(t, text, `aaru_worker_passes_total{result="panic",worker="imports"} 1`+"\n")
	assert.Contains(t, text, `aaru_worker_last_success_timestamp_seconds{worker="imports"}`)
}

func TestRefreshFailuresCountByStep(t *testing.T) {
	Reset()
	RefreshFailed("episodes")
	assert.Contains(t, render(t), `aaru_catalog_refresh_failures_total{step="episodes"} 1`+"\n")
}

func TestQueueGaugesReadTheSourceAtScrapeTime(t *testing.T) {
	Reset()
	t.Cleanup(func() { SetQueueSource(nil) })
	SetQueueSource(func(context.Context) ([]QueueStat, error) {
		return []QueueStat{{Queue: "import_jobs", Depth: 4, OldestAge: 90 * time.Second}}, nil
	})
	text := render(t)
	assert.Contains(t, text, `aaru_queue_depth{queue="import_jobs"} 4`+"\n")
	assert.Contains(t, text, `aaru_queue_oldest_age_seconds{queue="import_jobs"} 90`+"\n")

	SetQueueSource(func(context.Context) ([]QueueStat, error) { return nil, errors.New("db down") })
	assert.NotContains(t, render(t), "aaru_queue_depth{", "a failed read leaves the gauges out")
}

func TestPoolStatsRender(t *testing.T) {
	Reset()
	cfg, err := pgxpool.ParseConfig("postgres://u:p@127.0.0.1:1/db")
	require.NoError(t, err)
	cfg.MaxConns = 7
	pool, err := pgxpool.NewWithConfig(context.Background(), cfg) // does not connect
	require.NoError(t, err)
	t.Cleanup(pool.Close)
	require.NoError(t, RegisterPool(pool))
	text := render(t)
	assert.Contains(t, text, "aaru_db_pool_max_connections 7\n")
	assert.Contains(t, text, "aaru_db_pool_acquired_connections 0\n")
	assert.Contains(t, text, "# TYPE aaru_db_pool_empty_acquires_total counter\n")
	assert.Contains(t, text, "aaru_db_pool_canceled_acquires_total 0\n")
	assert.Contains(t, text, "aaru_db_pool_acquire_duration_seconds_total 0\n")
}
