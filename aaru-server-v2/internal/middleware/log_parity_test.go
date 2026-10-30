package middleware

import (
	"context"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/labstack/echo/v4"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// AgentTokenTests.redaction: request logs never carry a Stremio token or Trakt's callback secrets.
func TestRequestLogsNeverCarryAStremioTokenOrCallbackSecrets(t *testing.T) {
	assert.Equal(t, "/stremio/[token]/manifest.json", Redacted("/stremio/aaru_st_SECRET/manifest.json", ""))
	assert.Equal(t, "/stremio/[token]/catalog/series/up-next/skip=100.json",
		Redacted("/stremio/aaru_st_SECRET/catalog/series/up-next/skip=100.json", "x=1"))
	assert.Equal(t, "/stremio/[token]", Redacted("/stremio/aaru_st_SECRET", ""))
	assert.Equal(t, "/v1/imports/trakt/callback", Redacted("/v1/imports/trakt/callback", "code=abc&state=def"))
	assert.Equal(t, "/v1/connections/mal/callback", Redacted("/v1/connections/mal/callback", "code=abc&state=def"))
	assert.Equal(t, "/v1/calendar?from=a", Redacted("/v1/calendar", "from=a"))
}

// recordedLogParity keeps every record a handler sees.
type recordedLogParity struct {
	mu      sync.Mutex
	records []slog.Record
}

func (r *recordedLogParity) Enabled(context.Context, slog.Level) bool { return true }

func (r *recordedLogParity) Handle(_ context.Context, rec slog.Record) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.records = append(r.records, rec)
	return nil
}

func (r *recordedLogParity) WithAttrs([]slog.Attr) slog.Handler { return r }
func (r *recordedLogParity) WithGroup(string) slog.Handler      { return r }

// AgentTokenTests.responseMilliseconds: response logs give the time in whole milliseconds,
// and the logged path is the redacted one.
func TestResponseLogsGiveWholeMilliseconds(t *testing.T) {
	logs := &recordedLogParity{}
	e := echo.New()
	e.Use(RequestLog(slog.New(logs)))
	e.GET("/stremio/:token/manifest.json", func(c echo.Context) error {
		time.Sleep(1200 * time.Microsecond)
		return c.NoContent(http.StatusNoContent)
	})
	e.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/stremio/aaru_st_SECRET/manifest.json", nil))

	require.Len(t, logs.records, 2)
	attrs := map[string]slog.Value{}
	logs.records[1].Attrs(func(a slog.Attr) bool {
		attrs[a.Key] = a.Value
		return true
	})
	assert.Equal(t, "Response", logs.records[1].Message)
	ms := attrs["hb.response.ms"]
	require.Equal(t, slog.KindInt64, ms.Kind(), "a whole number of milliseconds")
	assert.GreaterOrEqual(t, ms.Int64(), int64(1))
	assert.Equal(t, "/stremio/[token]/manifest.json", attrs["hb.request.path"].String())
	assert.EqualValues(t, http.StatusNoContent, attrs["hb.response.status"].Any())
}
