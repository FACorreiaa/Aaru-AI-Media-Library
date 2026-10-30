package app

import (
	"aaru-go-api/internal/config"
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
