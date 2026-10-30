// Package metrics is the Prometheus registry served on METRICS_PORT.
//
// Every label value comes from a small fixed set: a route template, a source, a
// result. Never a path with an id in it, a user, or a title. Names match the
// Swift server's, so the "Apps / Aaru" board keeps working.
package metrics

import (
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// Registry holds the app's metrics; the Go runtime's are left out.
var Registry = prometheus.NewRegistry()

var (
	httpRequests = counter("aaru_http_requests_total", "HTTP requests by method, route template and status code.", "method", "route", "code")
	// Imports finished, by source and result (planned or failed).
	Imports = counter("aaru_imports_total", "Import jobs that finished, by source and result (planned or failed).", "source", "result")
	// Scrobbles are playback reports and plays received, by source and action (Swift's labels).
	Scrobbles = counter("aaru_scrobbles_total", "Playback reports received, by player.", "source", "action")
	// Push sends by channel (apns, web, live_activity) and result.
	Push = counter("aaru_push_total", "Push sends by channel (apns, web, live_activity) and result.", "channel", "result")
	// LLMCalls are model calls by provider and result.
	LLMCalls = counter("aaru_llm_calls_total", "Model calls by provider and result.", "provider", "result")

	inFlight = prometheus.NewGauge(prometheus.GaugeOpts{Name: "aaru_http_in_flight", Help: "HTTP requests being handled now."})
	duration = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "aaru_http_request_duration_seconds",
		Help:    "Time spent handling a request, by route group.",
		Buckets: prometheus.DefBuckets,
	}, []string{"group"})
)

func init() {
	Registry.MustRegister(inFlight, duration)
}

func counter(name, help string, labels ...string) *prometheus.CounterVec {
	c := prometheus.NewCounterVec(prometheus.CounterOpts{Name: name, Help: help}, labels)
	Registry.MustRegister(c)
	return c
}

// RequestStarted counts a request in flight.
func RequestStarted() { inFlight.Inc() }

// RequestFinished records one request. route is the matched template, "" when none matched.
func RequestFinished(method, route string, status int, took time.Duration) {
	inFlight.Dec()
	if route == "" {
		route = "unmatched"
	}
	httpRequests.WithLabelValues(method, route, strconv.Itoa(status)).Inc()
	duration.WithLabelValues(Group(route)).Observe(took.Seconds())
}

// Group is the first segment after `/v1`, or the first segment of a path outside it.
func Group(route string) string {
	if route == "unmatched" {
		return route
	}
	var segments []string
	for _, s := range strings.Split(route, "/") {
		if s != "" {
			segments = append(segments, s)
		}
	}
	if len(segments) > 0 && segments[0] == "v1" {
		segments = segments[1:]
	}
	if len(segments) == 0 {
		return "root"
	}
	return segments[0]
}

// Handler serves `GET /metrics`.
func Handler() http.Handler {
	return promhttp.HandlerFor(Registry, promhttp.HandlerOpts{})
}
