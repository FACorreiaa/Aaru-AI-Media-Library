package db_test

import (
	"aaru-go-api/internal/config"
	"aaru-go-api/internal/db"
	"aaru-go-api/internal/testdb"
	"context"
	"io"
	"log/slog"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// DatabaseTests.migrationsRerun (SRV-004): everything is applied; running again is a clean no-op.
func TestMigrationsAreReRunnable(t *testing.T) {
	pool := testdb.New(t)
	ctx := context.Background()
	require.NoError(t, db.Migrate(ctx, pool))
	require.NoError(t, db.Migrate(ctx, pool))
}

// DatabaseTests.waitForDatabaseReturns: one-shot modes go ahead once the database answers.
func TestWaitForGoesAheadOnceTheDatabaseAnswers(t *testing.T) {
	pool := testdb.New(t)
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	assert.NoError(t, db.WaitFor(context.Background(), pool, 1, time.Millisecond, log))
}

// DatabaseTests.waitForDatabaseGivesUp: one-shot modes give up and fail when it never answers.
func TestWaitForGivesUpWhenTheDatabaseNeverAnswers(t *testing.T) {
	ctx := context.Background()
	pool, err := db.Open(ctx, config.Postgres{
		Host: "127.0.0.1", Port: 1, User: "u", Password: "p", Database: "d", PoolSize: 1, PoolTimeoutSeconds: 1,
	})
	require.NoError(t, err)
	t.Cleanup(pool.Close)
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	assert.Error(t, db.WaitFor(ctx, pool, 2, 10*time.Millisecond, log))
}
