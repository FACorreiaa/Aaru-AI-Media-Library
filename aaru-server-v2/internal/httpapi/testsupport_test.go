package httpapi

import (
	"aaru-go-api/internal/config"
	"aaru-go-api/internal/testdb"
	"aaru-go-api/internal/token"
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/labstack/echo/v4"
	"github.com/stretchr/testify/require"
)

// harness is a router over a fresh database, for HTTP tests.
type harness struct {
	t      *testing.T
	pool   *pgxpool.Pool
	server *Server
	echo   *echo.Echo
}

func testConfig() *config.App {
	cfg, err := config.Load(config.NewReaderFrom(map[string]string{
		"postgres.user": "u", "postgres.password": "p", "postgres.database": "d", "tmdb.api.key": "test",
	}))
	if err != nil {
		panic(err)
	}
	return cfg
}

// newHarness builds the server; tweak lets a test change Deps before the router is built.
func newHarness(t *testing.T, tweak ...func(*Deps)) *harness {
	t.Helper()
	pool := testdb.New(t)
	deps := Deps{Config: testConfig(), Pool: pool, Log: slog.New(slog.NewTextHandler(io.Discard, nil))}
	withAuthDefaults(&deps)
	for _, f := range tweak {
		f(&deps)
	}
	s := New(deps)
	return &harness{t: t, pool: pool, server: s, echo: s.Router(nil)}
}

// signIn makes a user with a live session and returns its id and bearer token.
func (h *harness) signIn() (uuid.UUID, string) {
	h.t.Helper()
	ctx := context.Background()
	id := uuid.New()
	_, err := h.pool.Exec(ctx, `INSERT INTO users (id) VALUES ($1)`, id)
	require.NoError(h.t, err)
	bearer := token.Generate()
	_, err = h.pool.Exec(ctx, `INSERT INTO sessions (id, user_id, token_hash, expires_at) VALUES ($1, $2, $3, $4)`,
		uuid.New(), id, token.Hash(bearer), time.Now().Add(time.Hour))
	require.NoError(h.t, err)
	return id, bearer
}

// do sends a request; body may be nil, a []byte, or a value encoded as JSON.
func (h *harness) do(method, path, bearer string, body any) *httptest.ResponseRecorder {
	h.t.Helper()
	var reader io.Reader
	contentType := ""
	switch b := body.(type) {
	case nil:
	case []byte:
		reader = bytes.NewReader(b)
		contentType = "application/json"
	default:
		data, err := json.Marshal(b)
		require.NoError(h.t, err)
		reader = bytes.NewReader(data)
		contentType = "application/json"
	}
	req := httptest.NewRequest(method, path, reader)
	if contentType != "" {
		req.Header.Set("Content-Type", contentType)
	}
	if bearer != "" {
		req.Header.Set("Authorization", "Bearer "+bearer)
	}
	rec := httptest.NewRecorder()
	h.echo.ServeHTTP(rec, req)
	return rec
}

// decode reads a JSON response body into v.
func decode[T any](t *testing.T, rec *httptest.ResponseRecorder) T {
	t.Helper()
	var v T
	require.NoError(t, json.Unmarshal(rec.Body.Bytes(), &v), rec.Body.String())
	return v
}

var _ = http.MethodGet
