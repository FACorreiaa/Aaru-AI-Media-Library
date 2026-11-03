package db_test

import (
	"aaru-go-api/internal/config"
	"aaru-go-api/internal/db"
	"aaru-go-api/internal/testdb"
	"context"
	"errors"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// settingsOf is the Postgres settings of a test database, for a second pool on it.
func settingsOf(pool *pgxpool.Pool) config.Postgres {
	c := pool.Config().ConnConfig
	return config.Postgres{
		Host: c.Host, Port: int(c.Port), User: c.User, Password: c.Password, Database: c.Database,
		PoolSize: 1, PoolTimeoutSeconds: 1,
	}
}

// DB-001: POSTGRES_POOL_TIMEOUT is how long a query waits for a free connection, as in Swift.
// With the only connection held, a query gives up within the bound instead of queueing.
func TestAQueryWaitsForAFreeConnectionAtMostThePoolTimeout(t *testing.T) {
	ctx := context.Background()
	pool, err := db.Open(ctx, settingsOf(testdb.New(t)))
	require.NoError(t, err)
	t.Cleanup(pool.Close)
	held, err := pool.Acquire(ctx)
	require.NoError(t, err)

	started := time.Now()
	_, err = pool.Exec(ctx, `SELECT 1`)
	require.Error(t, err)
	assert.True(t, errors.Is(err, context.DeadlineExceeded), err)
	assert.Less(t, time.Since(started), 3*time.Second)

	held.Release()
	_, err = pool.Exec(ctx, `SELECT 1`)
	assert.NoError(t, err, "a free connection is handed out again")
}

// DB-001: the API's connections carry statement_timeout and idle_in_transaction_session_timeout;
// the one-shot modes' do not.
func TestTheAPIsConnectionsCarryStatementTimeouts(t *testing.T) {
	ctx := context.Background()
	settings := settingsOf(testdb.New(t))
	settings.StatementTimeoutSeconds, settings.IdleInTransactionTimeoutSeconds = 1, 7

	pool, err := db.Open(ctx, settings)
	require.NoError(t, err)
	t.Cleanup(pool.Close)
	var statement, idle string
	require.NoError(t, pool.QueryRow(ctx, `SELECT current_setting('statement_timeout'), current_setting('idle_in_transaction_session_timeout')`).Scan(&statement, &idle))
	assert.Equal(t, "1s", statement)
	assert.Equal(t, "7s", idle)
	_, err = pool.Exec(ctx, `SELECT pg_sleep(3)`)
	var pgErr *pgconn.PgError
	require.ErrorAs(t, err, &pgErr)
	assert.Equal(t, "57014", pgErr.Code)
	pool.Close()

	maintenance, err := db.Open(ctx, settings.WithoutSessionTimeouts())
	require.NoError(t, err)
	t.Cleanup(maintenance.Close)
	require.NoError(t, maintenance.QueryRow(ctx, `SELECT current_setting('statement_timeout')`).Scan(&statement))
	assert.Equal(t, "0", statement)
}
