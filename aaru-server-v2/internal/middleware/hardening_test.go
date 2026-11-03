package middleware

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/metrics"
	"aaru-go-api/internal/reqctx"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgconn"
	"github.com/labstack/echo/v4"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func discard() *slog.Logger { return slog.New(slog.NewTextHandler(io.Discard, nil)) }

func metricsText(t *testing.T) string {
	t.Helper()
	rec := httptest.NewRecorder()
	metrics.Handler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/metrics", nil))
	require.Equal(t, http.StatusOK, rec.Code)
	return rec.Body.String()
}

// REL-001: a panicking handler is the JSON 500, reported once, with the stack in the log, and
// the in-flight gauge is back to 0.
func TestAPanickingHandlerIsAReportedJSON500(t *testing.T) {
	metrics.Reset()
	logs := &recordedLogParity{}
	reporter := &recordingReporter{}
	e := echo.New()
	e.Use(Metrics(), Errors(slog.New(logs), reporter), Recover())
	e.GET("/v1/boom/:id", func(echo.Context) error { panic("kaboom") })

	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/v1/boom/1", nil))

	assert.Equal(t, http.StatusInternalServerError, rec.Code)
	assert.JSONEq(t, `{"code":"internal","message":"Something went wrong."}`, rec.Body.String())
	require.Len(t, reporter.failures, 1)
	assert.Equal(t, "/v1/boom/{id}", reporter.failures[0].Route)
	assert.Equal(t, "*middleware.PanicError", reporter.failures[0].ErrorType)
	require.NotEmpty(t, logs.records)
	stack := ""
	logs.records[len(logs.records)-1].Attrs(func(a slog.Attr) bool {
		if a.Key == "stack" {
			stack = a.Value.String()
		}
		return true
	})
	assert.Contains(t, stack, "goroutine")
	text := metricsText(t)
	assert.Contains(t, text, "aaru_http_in_flight 0\n")
	assert.Contains(t, text, `aaru_http_requests_total{code="500",method="GET",route="/v1/boom/{id}"} 1`)
}

// REL-001: even a panic nothing recovers (outside Recover) leaves the in-flight gauge at 0.
func TestMetricsFinishesWhenAPanicPassesThrough(t *testing.T) {
	metrics.Reset()
	e := echo.New()
	e.Use(Metrics())
	e.GET("/v1/boom", func(echo.Context) error { panic("kaboom") })
	func() {
		defer func() { _ = recover() }()
		e.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/v1/boom", nil))
	}()
	assert.Contains(t, metricsText(t), "aaru_http_in_flight 0\n")
}

// REL-001: net/http's deliberate abort is not turned into a 500.
func TestRecoverPassesHTTPAbortOn(t *testing.T) {
	e := echo.New()
	e.Use(Recover())
	e.GET("/v1/abort", func(echo.Context) error { panic(http.ErrAbortHandler) })
	assert.PanicsWithError(t, http.ErrAbortHandler.Error(), func() {
		e.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/v1/abort", nil))
	})
}

// HTTP-002: a cancellation from a client that went away is a 499, logged at Info, never reported.
func TestAClientThatWentAwayIsA499NeverReported(t *testing.T) {
	metrics.Reset()
	logs := &recordedLogParity{}
	reporter := &recordingReporter{}
	e := echo.New()
	e.Use(Metrics(), Errors(slog.New(logs), reporter))
	e.GET("/v1/search", func(c echo.Context) error {
		<-c.Request().Context().Done()
		return fmt.Errorf("search: %w", c.Request().Context().Err())
	})
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/v1/search", nil).WithContext(ctx))

	assert.Empty(t, reporter.failures)
	assert.Equal(t, StatusClientClosedRequest, rec.Code)
	for _, r := range logs.records {
		assert.Less(t, r.Level, slog.LevelWarn, r.Message)
	}
	assert.Contains(t, metricsText(t), `aaru_http_requests_total{code="499",method="GET",route="/v1/search"} 1`)
}

// HTTP-002: a cancellation while the client is still there is still a reported 500.
func TestACancellationWithTheClientStillThereIsA500(t *testing.T) {
	reporter := &recordingReporter{}
	e := echo.New()
	e.Use(Errors(discard(), reporter))
	e.GET("/v1/x", func(echo.Context) error { return context.Canceled })
	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/v1/x", nil))
	assert.Equal(t, http.StatusInternalServerError, rec.Code)
	assert.Len(t, reporter.failures, 1)
}

// HTTP-003: a method that is not a standard one is labelled OTHER.
func TestANonStandardMethodIsLabelledOther(t *testing.T) {
	metrics.Reset()
	e := echo.New()
	e.Use(Metrics(), Errors(discard(), nil))
	e.Any("/v1/thing", func(c echo.Context) error { return c.NoContent(http.StatusNoContent) })
	for _, m := range []string{"FOO", "RANDOM1", http.MethodGet} {
		e.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(m, "/v1/thing", nil))
	}
	text := metricsText(t)
	assert.Contains(t, text, `aaru_http_requests_total{code="405",method="OTHER",route="/v1/thing"} 2`)
	assert.Contains(t, text, `aaru_http_requests_total{code="204",method="GET",route="/v1/thing"} 1`)
	assert.NotContains(t, text, "FOO")
	assert.Equal(t, "OTHER", MethodLabel("RANDOM9"))
	assert.Equal(t, http.MethodPatch, MethodLabel(http.MethodPatch))
}

// DB-001: running out of time (the deadline, the pool's wait, statement_timeout) is a 503.
func TestRunningOutOfTimeIsA503(t *testing.T) {
	for name, err := range map[string]error{
		"deadline":          fmt.Errorf("acquire: %w", context.DeadlineExceeded),
		"statement_timeout": fmt.Errorf("query: %w", &pgconn.PgError{Code: "57014"}),
	} {
		t.Run(name, func(t *testing.T) {
			e := Map(err)
			assert.Equal(t, http.StatusServiceUnavailable, e.Status)
			assert.Equal(t, "timeout", e.Code)
		})
	}
	assert.Equal(t, http.StatusInternalServerError, Map(&pgconn.PgError{Code: "23505"}).Status)
}

// DB-001: a request is cut at its deadline and answers 503 within it; an exempt route is not.
func TestTheRequestDeadlineCutsALongRequest(t *testing.T) {
	e := echo.New()
	e.Use(Errors(discard(), nil), Deadline(50*time.Millisecond, func(c echo.Context) bool { return c.Path() == "/v1/ws" }))
	wait := func(c echo.Context) error {
		select {
		case <-c.Request().Context().Done():
			return c.Request().Context().Err()
		case <-time.After(300 * time.Millisecond):
			return c.NoContent(http.StatusNoContent)
		}
	}
	e.GET("/v1/slow", wait)
	e.GET("/v1/ws", wait)

	started := time.Now()
	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/v1/slow", nil))
	assert.Equal(t, http.StatusServiceUnavailable, rec.Code)
	assert.Less(t, time.Since(started), 250*time.Millisecond)

	rec = httptest.NewRecorder()
	e.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/v1/ws", nil))
	assert.Equal(t, http.StatusNoContent, rec.Code)
}

// HTTP-001: a body over its route's limit is refused with 413 before the validator or the
// handler reads it, whether it declares its length or not.
func TestABodyOverItsLimitIs413BeforeTheHandler(t *testing.T) {
	read := false
	e := echo.New()
	e.Use(Errors(discard(), nil), BodyLimit(func(echo.Context) BodyRule { return BodyRule{Limit: 1024} }))
	e.POST("/v1/x", func(c echo.Context) error {
		read = true
		if _, err := io.ReadAll(c.Request().Body); err != nil {
			if tooLarge := bodyTooLarge(c, err); tooLarge != nil {
				return tooLarge
			}
			return err
		}
		return c.NoContent(http.StatusNoContent)
	})
	big := bytes.Repeat([]byte("a"), 2048)

	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/v1/x", bytes.NewReader(big)))
	assert.Equal(t, http.StatusRequestEntityTooLarge, rec.Code)
	assert.False(t, read, "refused from its declared length")

	req := httptest.NewRequest(http.MethodPost, "/v1/x", io.MultiReader(bytes.NewReader(big)))
	req.ContentLength = -1
	rec = httptest.NewRecorder()
	e.ServeHTTP(rec, req)
	assert.Equal(t, http.StatusRequestEntityTooLarge, rec.Code)
	assert.Equal(t, "payload_too_large", decodeCode(t, rec))
}

// HTTP-001: a route with its own bound answers with its own message, not the shared 413.
func TestARouteWithItsOwnBoundSpeaks(t *testing.T) {
	own := apperr.New(http.StatusRequestEntityTooLarge, "file_too_large", "That file is too large.")
	e := echo.New()
	e.Use(Errors(discard(), nil), BodyLimit(func(echo.Context) BodyRule { return BodyRule{Limit: 1024, OwnBound: true} }))
	e.POST("/v1/upload", func(c echo.Context) error {
		if c.Request().ContentLength > 512 {
			return own
		}
		return c.NoContent(http.StatusNoContent)
	})
	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/v1/upload", bytes.NewReader(make([]byte, 4096))))
	assert.Equal(t, http.StatusRequestEntityTooLarge, rec.Code)
	assert.Equal(t, "file_too_large", decodeCode(t, rec))
}

func decodeCode(t *testing.T, rec *httptest.ResponseRecorder) string {
	t.Helper()
	var b struct{ Code string }
	require.NoError(t, json.Unmarshal(rec.Body.Bytes(), &b), rec.Body.String())
	return b.Code
}

// HTTP-006: a transport that answers its own 500 reports it through the reporter Errors holds,
// and a client that went away is not reported.
func TestATransportsOwn500IsReported(t *testing.T) {
	reporter := &recordingReporter{}
	e := echo.New()
	e.Use(Errors(discard(), reporter))
	e.POST("/v1/mcp", func(c echo.Context) error {
		ReportFailure(c, errors.New("db down"), "internal", http.StatusInternalServerError)
		return c.String(http.StatusInternalServerError, "Something went wrong.")
	})
	e.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodPost, "/v1/mcp", nil))
	require.Len(t, reporter.failures, 1)
	assert.Equal(t, Failure{ErrorType: "*errors.errorString", Code: "internal", Status: 500, Method: "POST", Route: "/v1/mcp"}, reporter.failures[0])

	e.POST("/v1/mcp-cancelled", func(c echo.Context) error {
		ReportFailure(c, fmt.Errorf("tool: %w", context.Canceled), "internal", http.StatusInternalServerError)
		return c.String(http.StatusInternalServerError, "Something went wrong.")
	})
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	e.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodPost, "/v1/mcp-cancelled", nil).WithContext(ctx))
	// Outside Errors there is no reporter: nothing to do.
	ReportFailure(echo.New().NewContext(httptest.NewRequest(http.MethodGet, "/", nil), httptest.NewRecorder()),
		errors.New("x"), "internal", http.StatusInternalServerError)
	assert.Len(t, reporter.failures, 1)
}

// HTTP-007: the caller is the right-most hop no trusted proxy could have been handed.
func TestTheClientAddressIsTheRightMostUntrustedHop(t *testing.T) {
	tests := []struct {
		name      string
		forwarded []string
		hops      int
		want      string
	}{
		{"traefik's own entry", []string{"203.0.113.9"}, 1, "203.0.113.9"},
		{"a forged entry before it", []string{"1.2.3.4, 203.0.113.9"}, 1, "203.0.113.9"},
		{"split across headers", []string{"1.2.3.4", "203.0.113.9"}, 1, "203.0.113.9"},
		{"two trusted proxies", []string{"1.2.3.4, 203.0.113.9, 10.0.0.1"}, 2, "203.0.113.9"},
		{"fewer entries than hops", []string{"203.0.113.9"}, 3, "203.0.113.9"},
		{"no header", nil, 1, "192.0.2.1"},
		{"hops 0 ignores the header", []string{"1.2.3.4"}, 0, "192.0.2.1"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, ClientAddress(tt.forwarded, "192.0.2.1:1234", tt.hops))
		})
	}
	assert.Equal(t, "unknown", ClientAddress(nil, "", 1))
}

// HLT-005: every line logged with a request's context carries its id, which the response names.
func TestEveryRequestLineCarriesTheRequestID(t *testing.T) {
	var buf bytes.Buffer
	log := slog.New(NewContextHandler(slog.NewJSONHandler(&buf, &slog.HandlerOptions{Level: slog.LevelInfo})))
	e := echo.New()
	e.Use(RequestID(), RequestLog(log))
	e.GET("/v1/x", func(c echo.Context) error {
		log.InfoContext(c.Request().Context(), "Inside")
		return c.NoContent(http.StatusNoContent)
	})
	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/v1/x", nil))
	id := rec.Header().Get(RequestIDHeader)
	require.Len(t, id, 16)

	lines := strings.Split(strings.TrimSpace(buf.String()), "\n")
	require.Len(t, lines, 2, "the Debug arrival line is off at Info: one line per request plus the handler's")
	for _, line := range lines {
		var rec map[string]any
		require.NoError(t, json.Unmarshal([]byte(line), &rec))
		assert.Equal(t, id, rec["requestId"], line)
	}
	assert.Empty(t, reqctx.RequestID(context.Background()))
}

// HLT-005: the arrival line is Debug, the answer Info.
func TestTheArrivalLineIsDebug(t *testing.T) {
	logs := &recordedLogParity{}
	e := echo.New()
	e.Use(RequestLog(slog.New(logs)))
	e.GET("/v1/x", func(c echo.Context) error { return c.NoContent(http.StatusNoContent) })
	e.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/v1/x", nil))
	require.Len(t, logs.records, 2)
	assert.Equal(t, slog.LevelDebug, logs.records[0].Level)
	assert.Equal(t, slog.LevelInfo, logs.records[1].Level)
}
