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

// A Swift database is adopted only at the baseline's migrations: not one behind, not one ahead.
func TestAdoptingASwiftDatabaseNeedsTheBaselinesMigrations(t *testing.T) {
	ctx := context.Background()
	pool := testdb.New(t)
	sqlDB := stdlib.OpenDBFromPool(pool)
	t.Cleanup(func() { _ = sqlDB.Close() })
	_, err := pool.Exec(ctx, `CREATE TABLE _fluent_migrations (id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
		name text NOT NULL UNIQUE, batch int NOT NULL DEFAULT 1)`)
	require.NoError(t, err)
	record := func(names ...string) {
		for _, n := range names {
			_, err := pool.Exec(ctx, `INSERT INTO _fluent_migrations (name) VALUES ($1)`, n)
			require.NoError(t, err)
		}
	}

	record("App.CreateUsers")
	assert.ErrorContains(t, migrations.UpBaseline(ctx, sqlDB), "has 1 Swift migrations")

	for i := 2; i < 60; i++ {
		record(fmt.Sprintf("App.Migration%d", i))
	}
	assert.Error(t, migrations.UpBaseline(ctx, sqlDB), "59: one behind")

	record("App.CreateShares")
	assert.NoError(t, migrations.UpBaseline(ctx, sqlDB))

	record("App.AddSomethingNew")
	assert.ErrorContains(t, migrations.UpBaseline(ctx, sqlDB), "has 61 Swift migrations")
}
