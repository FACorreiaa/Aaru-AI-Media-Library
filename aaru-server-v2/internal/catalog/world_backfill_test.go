package catalog

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/testdb"
	"context"
	"os"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Migration 00018 queues every library title that was never looked at, once (GRAPH-007). The
// test database is migrated while empty, so the statement is run here against real rows.
func TestWorldsBackfillQueuesEveryLibraryTitleOnce(t *testing.T) {
	ctx := context.Background()
	store := NewStore(testdb.New(t))
	raw, err := os.ReadFile("../db/migrations/00018_worlds_backfill.sql")
	require.NoError(t, err)
	up, _, found := strings.Cut(string(raw), "-- +goose Down")
	require.True(t, found)
	_, statement, found := strings.Cut(up, "-- +goose Up")
	require.True(t, found)

	title := func(name string) uuid.UUID {
		id := uuid.New()
		_, err := store.pool.Exec(ctx, `INSERT INTO titles (id, type, title) VALUES ($1, $2, $3)`, id, string(core.MediaMovie), name)
		require.NoError(t, err)
		return id
	}
	shared, seen, unowned := title("In two libraries"), title("Looked at already"), title("In no library")
	for range 2 {
		user := uuid.New()
		_, err := store.pool.Exec(ctx, `INSERT INTO users (id) VALUES ($1)`, user)
		require.NoError(t, err)
		for _, id := range []uuid.UUID{shared, seen} {
			_, err := store.pool.Exec(ctx, `INSERT INTO library_items (id, user_id, title_id, status, added_at, updated_at)
				VALUES ($1, $2, $3, 'wishlist', now(), now())`, uuid.New(), user, id)
			require.NoError(t, err)
		}
	}
	_, err = store.pool.Exec(ctx, `INSERT INTO world_builds (title_id, priority, state, attempts, run_after, checked_at, created_at)
		VALUES ($1, 0, 'done', 1, now(), now(), now())`, seen)
	require.NoError(t, err)

	for range 2 {
		_, err = store.pool.Exec(ctx, statement)
		require.NoError(t, err, "running it twice changes nothing")
	}
	queued, err := store.q.WorldBuild(ctx, shared)
	require.NoError(t, err)
	assert.Equal(t, "queued", queued.State)
	assert.Equal(t, WorldPriorityImport, queued.Priority, "behind any title someone opens")
	done, err := store.q.WorldBuild(ctx, seen)
	require.NoError(t, err)
	assert.Equal(t, "done", done.State, "a title already looked at is left alone")
	_, err = store.q.WorldBuild(ctx, unowned)
	require.Error(t, err, "a title in no library is not queued")
	var rows int
	require.NoError(t, store.pool.QueryRow(ctx, `SELECT count(*) FROM world_builds`).Scan(&rows))
	assert.Equal(t, 2, rows)
}
