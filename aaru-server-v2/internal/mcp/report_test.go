package mcp

import (
	"aaru-go-api/internal/auth"
	"aaru-go-api/internal/middleware"
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/labstack/echo/v4"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type failingTokens struct{ err error }

func (f failingTokens) Authenticate(context.Context, string, auth.TokenGroup) (auth.AgentCaller, bool, error) {
	return auth.AgentCaller{}, false, f.err
}

func (failingTokens) Allow(auth.AgentCaller) bool { return true }

type noTools struct{}

func (noTools) Call(context.Context, string, json.RawMessage, auth.AgentCaller) (any, error) {
	return nil, nil // never called
}

type reports struct{ failures []middleware.Failure }

func (r *reports) Report(f middleware.Failure) { r.failures = append(r.failures, f) }

// HTTP-006: MCP writes its own 500, and it reaches the reporter like any `/v1` 500.
func TestAnMCP500IsReported(t *testing.T) {
	r := &reports{}
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	e := echo.New()
	e.Use(middleware.Errors(log, r))
	(&Handler{Tokens: failingTokens{errors.New("db down")}, Tools: noTools{}, Log: log}).Register(e)

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, Path, strings.NewReader(`{"jsonrpc":"2.0","id":1,"method":"ping"}`))
	req.Header.Set("Authorization", "Bearer aaru_mcp_x")
	e.ServeHTTP(rec, req)

	assert.Equal(t, http.StatusInternalServerError, rec.Code)
	assert.Equal(t, "Something went wrong.", rec.Body.String())
	require.Len(t, r.failures, 1)
	assert.Equal(t, "/v1/mcp", r.failures[0].Route)
	assert.Equal(t, "internal", r.failures[0].Code)
}
