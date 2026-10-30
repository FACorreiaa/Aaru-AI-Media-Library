package app

import (
	"aaru-go-api/internal/config"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestInternalMuxServesProfilesWhenEnabled(t *testing.T) {
	for _, path := range []string{"/debug/pprof/", "/debug/pprof/heap", "/debug/pprof/goroutine?debug=1", "/metrics"} {
		rec := httptest.NewRecorder()
		internalMux(&config.App{Pprof: config.Pprof{Enabled: true}}).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
		assert.Equal(t, http.StatusOK, rec.Code, path)
	}
}

func TestInternalMuxHidesProfilesWhenDisabled(t *testing.T) {
	rec := httptest.NewRecorder()
	internalMux(&config.App{}).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/debug/pprof/", nil))
	assert.Equal(t, http.StatusNotFound, rec.Code)
}

// MetricsTests.swift off: port 0 turns the listener off.
func TestMetricsPortZeroTurnsTheListenerOff(t *testing.T) {
	assert.Nil(t, newMetricsServer(&config.App{MetricsPort: 0}))
	server := newMetricsServer(&config.App{MetricsPort: 9090})
	if assert.NotNil(t, server) {
		assert.Equal(t, "0.0.0.0:9090", server.Addr)
	}
}

// TelemetryTests.swift unconfigured: nothing is sent without configuration.
func TestNothingIsSentWithoutConfiguration(t *testing.T) {
	quiet := slog.New(slog.NewTextHandler(io.Discard, nil))
	assert.Nil(t, makeSentry(nil, quiet))
	assert.Nil(t, makePostHog(nil, quiet))
	assert.Nil(t, makeSentry(&config.Sentry{DSN: "not a dsn"}, quiet))
}
