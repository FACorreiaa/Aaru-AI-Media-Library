//go:build parity_g1

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
