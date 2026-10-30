//go:build parity_g1

package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/config"
	"aaru-go-api/internal/db"
	"context"
	"net/http"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// APITests.healthUnavailable: GET /v1/health is 503 with no database detail when the database is down.
func TestHealthIs503WithNoDetailWhenTheDatabaseIsDown(t *testing.T) {
	down, err := db.Open(context.Background(), config.Postgres{
		Host: "127.0.0.1", Port: 1, User: "u", Password: "p", Database: "d", PoolSize: 1, PoolTimeoutSeconds: 1,
	})
	require.NoError(t, err)
	t.Cleanup(down.Close)
	h := newHarness(t, func(d *Deps) { d.Pool = down })
	rec := h.do(http.MethodGet, "/v1/health", "", nil)
	assert.Equal(t, http.StatusServiceUnavailable, rec.Code)
	assert.Equal(t, api.HealthStatusUnavailable, decode[api.Health](t, rec).Status)
	assert.Less(t, len(rec.Body.String()), 40, "no database detail in the body")
}

// APITests.notFoundShape: an unknown route outside /v1 is 404 in the shared shape.
func TestAnUnknownRouteIs404InTheSharedShape(t *testing.T) {
	h := newHarness(t)
	rec := h.do(http.MethodGet, "/does-not-exist", "", nil)
	assert.Equal(t, http.StatusNotFound, rec.Code)
	body := decode[api.ErrorResponse](t, rec)
	assert.Equal(t, "not_found", body.Code)
	assert.NotEmpty(t, body.Message)
}

// APITests.anonymousIsUnauthorized: without a session a /v1 route is 401, and an unknown one is too.
func TestAnonymousV1IsUnauthorizedWhetherOrNotTheRouteExists(t *testing.T) {
	h := newHarness(t)
	for _, path := range []string{"/v1/me", "/v1/does-not-exist"} {
		rec := h.do(http.MethodGet, path, "", nil)
		assert.Equal(t, http.StatusUnauthorized, rec.Code, path)
		assert.Equal(t, "unauthorized", decode[api.ErrorResponse](t, rec).Code, path)
	}
}
