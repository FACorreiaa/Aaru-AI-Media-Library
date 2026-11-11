package metrics

import (
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// MetricsTests.swift: `GET /metrics` on the internal port, what Alloy scrapes into Grafana Cloud.
// Labels come out in name order (the Prometheus client sorts them); the scrape reads them by name.

func render(t *testing.T) string {
	t.Helper()
	rec := httptest.NewRecorder()
	Handler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/metrics", nil))
	require.Equal(t, http.StatusOK, rec.Code)
	body, err := io.ReadAll(rec.Body)
	require.NoError(t, err)
	return string(body)
}

func TestCountersGaugeAndHistogramRenderInTheTextFormat(t *testing.T) {
	Reset()
	Imports.WithLabelValues("trakt", "planned").Inc()
	Imports.WithLabelValues("trakt", "planned").Inc()
	RequestStarted()
	RequestFinished(http.MethodGet, "/v1/library", 200, 30*time.Millisecond)
	text := render(t)
	assert.Contains(t, text, "# TYPE aaru_imports_total counter\n")
	assert.Contains(t, text, "aaru_imports_total{result=\"planned\",source=\"trakt\"} 2\n")
	assert.Contains(t, text, "aaru_http_requests_total{code=\"200\",method=\"GET\",route=\"/v1/library\"} 1\n")
	assert.Contains(t, text, "aaru_http_in_flight 0\n")
	assert.Contains(t, text, "aaru_http_request_duration_seconds_bucket{group=\"library\",le=\"0.025\"} 0\n")
	assert.Contains(t, text, "aaru_http_request_duration_seconds_bucket{group=\"library\",le=\"0.05\"} 1\n")
	assert.Contains(t, text, "aaru_http_request_duration_seconds_bucket{group=\"library\",le=\"+Inf\"} 1\n")
	assert.Contains(t, text, "aaru_http_request_duration_seconds_count{group=\"library\"} 1\n")
}

func TestALabelValueCannotBreakOutOfItsQuotes(t *testing.T) {
	Reset()
	Scrobbles.WithLabelValues("a\"b\\c\nd", "start").Inc()
	assert.Contains(t, render(t), `aaru_scrobbles_total{action="start",source="a\"b\\c\nd"} 1`+"\n")
}

func TestRoutesGroupByTheirFirstSegmentAfterV1(t *testing.T) {
	for route, group := range map[string]string{
		"/v1/titles/{id}": "titles", "/v1/library": "library", "/stremio/{token}/manifest.json": "stremio",
		"/": "root", "unmatched": "unmatched",
	} {
		assert.Equal(t, group, Group(route), route)
	}
}

func TestTheMetricsHandlerServesTheTextFormat(t *testing.T) {
	Reset()
	Push.WithLabelValues("apns", "sent").Inc()
	rec := httptest.NewRecorder()
	Handler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/metrics", nil))
	assert.Equal(t, http.StatusOK, rec.Code)
	assert.Contains(t, rec.Header().Get("Content-Type"), "text/plain; version=0.0.4; charset=utf-8")
	assert.Contains(t, rec.Body.String(), "aaru_push_total{channel=\"apns\",result=\"sent\"} 1\n")
}

// A counter series that first appears at 1 has no increase() in Prometheus, so the
// report alert would miss the first report after a restart. Every reason starts at 0.
func TestSocialReportsStartAtZeroForEveryReason(t *testing.T) {
	Reset()
	text := render(t)
	for _, reason := range []string{"spam", "harassment", "impersonation", "other"} {
		assert.Contains(t, text, "aaru_social_reports_total{reason=\""+reason+"\"} 0\n")
	}
}
