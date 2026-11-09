package migrations_test

import (
	"aaru-go-api/internal/db/migrations"
	"aaru-go-api/internal/testdb"
	"context"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/stdlib"
	"github.com/pressly/goose/v3"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// ONB-001: an account made before onboarding shipped is backfilled as onboarded at its creation and
// never sees the flow; an account made after starts pending.
func TestOnboardingBackfillsAccountsThatAlreadyExist(t *testing.T) {
	ctx := context.Background()
	pool := testdb.New(t)
	sqlDB := stdlib.OpenDBFromPool(pool)
	t.Cleanup(func() { _ = sqlDB.Close() })
	provider, err := goose.NewProvider(goose.DialectPostgres, sqlDB, migrations.FS,
		goose.WithGoMigrations(goose.NewGoMigration(1,
			&goose.GoFunc{RunDB: migrations.UpBaseline, Mode: goose.TransactionDisabled},
			&goose.GoFunc{RunDB: migrations.DownBaseline, Mode: goose.TransactionDisabled},
		)),
	)
	require.NoError(t, err)
	_, err = provider.DownTo(ctx, 8)
	require.NoError(t, err)

	before := uuid.New()
	_, err = pool.Exec(ctx, `INSERT INTO users (id, created_at) VALUES ($1, '2026-01-02T03:04:05Z')`, before)
	require.NoError(t, err)
	_, err = provider.UpTo(ctx, 9)
	require.NoError(t, err)
	after := uuid.New()
	_, err = pool.Exec(ctx, `INSERT INTO users (id) VALUES ($1)`, after)
	require.NoError(t, err)

	var onboarded, created any
	var skipped bool
	require.NoError(t, pool.QueryRow(ctx, `SELECT onboarded_at, created_at, onboarding_skipped FROM users WHERE id = $1`, before).
		Scan(&onboarded, &created, &skipped))
	assert.Equal(t, created, onboarded, "onboarded when it was made")
	assert.False(t, skipped)

	var pending bool
	require.NoError(t, pool.QueryRow(ctx, `SELECT onboarded_at IS NULL, onboarding_skipped FROM users WHERE id = $1`, after).
		Scan(&pending, &skipped))
	assert.True(t, pending, "a new account sees the flow")
	assert.False(t, skipped)
}
