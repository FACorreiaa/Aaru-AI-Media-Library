package migrations_test

import (
	"aaru-go-api/internal/db/migrations"
	"aaru-go-api/internal/testdb"
	"context"
	"fmt"
	"testing"

	"github.com/jackc/pgx/v5/stdlib"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// MALPullTests.onHoldBackfill (LIB-007) ran the Swift migration AddOnHold's one-time backfill.
// Go carries no backfill: an empty database has no rows to fill, and a Swift database is adopted
// only once AddOnHold (Fluent's 57th, before CreateShares) has run. A database at CreateShares
// that skipped AddOnHold is refused, and the adopted schema takes on_hold.
func TestAdoptionNeedsAddOnHoldsBackfillToHaveRun(t *testing.T) {
	ctx := context.Background()
	pool := testdb.New(t)
	sqlDB := stdlib.OpenDBFromPool(pool)
	t.Cleanup(func() { _ = sqlDB.Close() })
	_, err := pool.Exec(ctx, `CREATE TABLE _fluent_migrations (id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
		name text NOT NULL UNIQUE, batch int NOT NULL DEFAULT 1)`)
	require.NoError(t, err)
	record := func(name string) {
		_, err := pool.Exec(ctx, `INSERT INTO _fluent_migrations (name) VALUES ($1)`, name)
		require.NoError(t, err)
	}
	for i := 1; i < 59; i++ {
		record(fmt.Sprintf("App.Migration%d", i))
	}
	record("App.CreateShares")
	assert.ErrorContains(t, migrations.UpBaseline(ctx, sqlDB), "has 59 Swift migrations", "AddOnHold never ran")

	record("App.AddOnHold")
	require.NoError(t, migrations.UpBaseline(ctx, sqlDB))
}

// On an empty database the baseline creates the schema with on_hold allowed, and there is nothing
// to backfill.
func TestAFreshBaselineTakesOnHold(t *testing.T) {
	ctx := context.Background()
	pool := testdb.New(t)
	var check string
	require.NoError(t, pool.QueryRow(ctx, `SELECT pg_get_constraintdef(oid) FROM pg_constraint
		WHERE conname = 'library_items_status_check'`).Scan(&check))
	assert.Contains(t, check, "'on_hold'::text")
	var items int
	require.NoError(t, pool.QueryRow(ctx, `SELECT count(*) FROM library_items`).Scan(&items))
	assert.Zero(t, items)
}
