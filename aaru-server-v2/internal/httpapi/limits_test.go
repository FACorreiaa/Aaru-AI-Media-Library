package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/config"
	"aaru-go-api/internal/db"
	"aaru-go-api/internal/middleware"
	"bytes"
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// sendBytes posts body with a content type; chunked leaves the length undeclared.
func (h *harness) sendBytes(method, path, bearer, contentType string, body []byte, chunked bool) *httptest.ResponseRecorder {
	h.t.Helper()
	var reader io.Reader = bytes.NewReader(body)
	if chunked {
		reader = io.MultiReader(reader)
	}
	req := httptest.NewRequest(method, path, reader)
	if chunked {
		req.ContentLength = -1
	}
	req.Header.Set("Content-Type", contentType)
	if bearer != "" {
		req.Header.Set("Authorization", "Bearer "+bearer)
	}
	rec := httptest.NewRecorder()
	h.echo.ServeHTTP(rec, req)
	return rec
}

// bigJSON is a JSON object of about n bytes.
func bigJSON(n int) []byte {
	return []byte(`{"email":"a@example.com","pad":"` + strings.Repeat("a", n) + `"}`)
}

// HTTP-001: a public route takes at most 1 MiB, refused with 413 before the validator reads it,
// declared or not.
func TestAPublicRouteRefusesA2MiBBody(t *testing.T) {
	h := newHarness(t)
	for _, chunked := range []bool{false, true} {
		rec := h.sendBytes(http.MethodPost, "/v1/auth/email/link", "", "application/json", bigJSON(2<<20), chunked)
		assert.Equal(t, http.StatusRequestEntityTooLarge, rec.Code, "chunked=%v", chunked)
		assert.Equal(t, "payload_too_large", decode[api.ErrorResponse](t, rec).Code)
		assert.Len(t, rec.Header().Get(middleware.RequestIDHeader), 16)
	}
}

// HTTP-001: the upload routes keep their own limits and their own messages.
func TestUploadsKeepTheirOwnLimitsAndMessages(t *testing.T) {
	h := newHarness(t)
	_, bearer := h.signIn()

	// A CSV export: 5 MB.
	rec := h.sendBytes(http.MethodPost, "/v1/imports/csv?source=imdb", bearer, "text/csv", bytes.Repeat([]byte("a,b\n"), 6<<18), false)
	assert.Equal(t, http.StatusRequestEntityTooLarge, rec.Code)
	assert.Equal(t, "file_too_large", decode[api.ErrorResponse](t, rec).Code)

	// Listening history: up to 24 MB passes the body limit; past it, its own message.
	rec = h.sendBytes(http.MethodPost, "/v1/imports/csv?source=spotify", bearer, "application/octet-stream", bytes.Repeat([]byte(" "), 2<<20), false)
	assert.NotEqual(t, http.StatusRequestEntityTooLarge, rec.Code, rec.Body.String())
	rec = h.sendBytes(http.MethodPost, "/v1/imports/csv?source=spotify", bearer, "application/octet-stream", make([]byte, 25<<20), true)
	assert.Equal(t, http.StatusRequestEntityTooLarge, rec.Code)
	body := decode[api.ErrorResponse](t, rec)
	assert.Equal(t, "file_too_large", body.Code)
	assert.Contains(t, body.Message, "24 MB")

	// An avatar: 1 MB, its own message even for a larger declared length.
	rec = h.sendBytes(http.MethodPut, "/v1/me/avatar", bearer, "image/jpeg", make([]byte, 3<<20), false)
	assert.Equal(t, http.StatusRequestEntityTooLarge, rec.Code)
	assert.Equal(t, "That photo is larger than 1 MB.", decode[api.ErrorResponse](t, rec).Message)

	// A capture image: 5 MB.
	rec = h.sendBytes(http.MethodPost, "/v1/imports/capture", bearer, "image/png", make([]byte, 6<<20), false)
	assert.Equal(t, http.StatusRequestEntityTooLarge, rec.Code)
	assert.Equal(t, "file_too_large", decode[api.ErrorResponse](t, rec).Code)
}

// HTTP-001: capture's JSON body is at most 512 KiB, answered as text over capture's limit.
func TestCaptureJSONIsAtMost512KiB(t *testing.T) {
	h := newHarness(t)
	_, bearer := h.signIn()
	text := []byte(`{"text":"` + strings.Repeat("a", 600<<10) + `"}`)
	for _, chunked := range []bool{false, true} {
		rec := h.sendBytes(http.MethodPost, "/v1/imports/capture", bearer, "application/json", text, chunked)
		assert.Equal(t, http.StatusRequestEntityTooLarge, rec.Code, "chunked=%v", chunked)
		assert.Equal(t, "capture_too_large", decode[api.ErrorResponse](t, rec).Code)
	}
}

// DB-001: with the pool's only connection held, a request answers 503 within
// POSTGRES_POOL_TIMEOUT instead of waiting for the client to give up.
func TestASaturatedPoolAnswers503WithinThePoolTimeout(t *testing.T) {
	ctx := context.Background()
	h := newHarness(t)
	_, bearer := h.signIn()
	c := h.pool.Config().ConnConfig
	small, err := db.Open(ctx, config.Postgres{
		Host: c.Host, Port: int(c.Port), User: c.User, Password: c.Password, Database: c.Database,
		PoolSize: 1, PoolTimeoutSeconds: 1,
	})
	require.NoError(t, err)
	t.Cleanup(small.Close)
	saturated := newHarness(t, func(d *Deps) { d.Pool = small })
	held, err := small.Acquire(ctx)
	require.NoError(t, err)
	defer held.Release()

	started := time.Now()
	rec := saturated.do(http.MethodGet, "/v1/me", bearer, nil)
	assert.Equal(t, http.StatusServiceUnavailable, rec.Code, rec.Body.String())
	assert.Equal(t, "timeout", decode[api.ErrorResponse](t, rec).Code)
	assert.Less(t, time.Since(started), 3*time.Second)
}

// A route named in these tables that no longer exists under that exact spelling would silently
// lose its limit or its exemption from the deadline, cutting an upload or a socket off at 30 s.
func TestBodyLimitAndDeadlineTablesNameRealRoutes(t *testing.T) {
	h := newHarness(t)
	routes := map[string]bool{}
	for _, r := range h.echo.Routes() {
		routes[r.Method+" "+r.Path] = true
	}
	for key := range ownBodyLimits {
		assert.True(t, routes[key], "ownBodyLimits: %s", key)
	}
	for key := range noDeadline {
		assert.True(t, routes[key], "noDeadline: %s", key)
	}
}
