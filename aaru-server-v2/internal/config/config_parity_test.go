package config

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// APITests.missingTMDBKey: serving without TMDB_API_KEY fails naming the key.
func TestServingWithoutTheTMDBKeyFailsNamingIt(t *testing.T) {
	_, err := Load(NewReaderFrom(map[string]string{
		"postgres.user": "u", "postgres.password": "p", "postgres.database": "d",
	}))
	var missing MissingError
	require.ErrorAs(t, err, &missing)
	assert.Equal(t, "TMDB_API_KEY", missing.Env)
	assert.Contains(t, err.Error(), "TMDB_API_KEY")
}

// DB-001, HTTP-007: the timeouts and the proxy hops the port adds, their defaults and overrides.
func TestTimeoutsAndProxyHopsDefaultAndOverride(t *testing.T) {
	base := map[string]string{"postgres.user": "u", "postgres.password": "p", "postgres.database": "d", "tmdb.api.key": "k"}
	cfg, err := Load(NewReaderFrom(base))
	require.NoError(t, err)
	assert.Equal(t, 10, cfg.Postgres.PoolTimeoutSeconds)
	assert.Equal(t, 30, cfg.Postgres.StatementTimeoutSeconds)
	assert.Equal(t, 60, cfg.Postgres.IdleInTransactionTimeoutSeconds)
	assert.Equal(t, 30, cfg.HTTP.RequestTimeoutSeconds)
	assert.Equal(t, 1, cfg.HTTP.TrustedProxyHops)

	base["postgres.statement.timeout"] = "0"
	base["postgres.idle.transaction.timeout"] = "5"
	base["http.request.timeout"] = "0"
	base["trusted.proxy.hops"] = "2"
	cfg, err = Load(NewReaderFrom(base))
	require.NoError(t, err)
	assert.Equal(t, 0, cfg.Postgres.StatementTimeoutSeconds)
	assert.Equal(t, 5, cfg.Postgres.IdleInTransactionTimeoutSeconds)
	assert.Equal(t, 0, cfg.HTTP.RequestTimeoutSeconds)
	assert.Equal(t, 2, cfg.HTTP.TrustedProxyHops)

	maintenance := cfg.Postgres.WithoutSessionTimeouts()
	assert.Zero(t, maintenance.StatementTimeoutSeconds)
	assert.Zero(t, maintenance.IdleInTransactionTimeoutSeconds)
	assert.Equal(t, cfg.Postgres.PoolTimeoutSeconds, maintenance.PoolTimeoutSeconds)
}
