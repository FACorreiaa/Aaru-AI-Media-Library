package middleware

import (
	"aaru-go-api/internal/metrics"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/labstack/echo/v4"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// MetricsTests.swift routeTemplate: the route label is the matched template, never the path with its id.
func TestTheRouteLabelIsTheMatchedTemplateNeverThePath(t *testing.T) {
	e := echo.New()
	e.Use(Metrics(), Errors(slog.New(slog.NewTextHandler(io.Discard, nil)), nil))
	e.GET("/v1/metric-titles/:id", func(c echo.Context) error { return c.String(http.StatusOK, "ok") })
	e.GET("/v1/metric-fails", func(echo.Context) error { return echo.ErrBadRequest })
	for path, status := range map[string]int{
		"/v1/metric-titles/0b6a2f63-secret-id": http.StatusOK,
		"/v1/metric-fails":                     http.StatusBadRequest,
		"/nowhere/abc":                         http.StatusNotFound,
	} {
		rec := httptest.NewRecorder()
		e.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
		assert.Equal(t, status, rec.Code, path)
	}

	rec := httptest.NewRecorder()
	metrics.Handler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/metrics", nil))
	require.Equal(t, http.StatusOK, rec.Code)
	text := rec.Body.String()
	assert.NotContains(t, text, "0b6a2f63")
	assert.NotContains(t, text, "nowhere")
	assert.Contains(t, text, `route="/v1/metric-titles/{id}"} 1`)
	assert.Contains(t, text, `aaru_http_requests_total{code="200",method="GET",route="/v1/metric-titles/{id}"} 1`)
	assert.Contains(t, text, `aaru_http_requests_total{code="400",method="GET",route="/v1/metric-fails"} 1`)
	assert.Contains(t, text, `aaru_http_requests_total{code="404",method="GET",route="unmatched"} 1`)
	assert.Contains(t, text, "aaru_http_in_flight 0\n")
}
