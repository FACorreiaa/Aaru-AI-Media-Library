package middleware

import (
	"aaru-go-api/internal/provider"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/labstack/echo/v4"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type recordingReporter struct{ failures []Failure }

func (r *recordingReporter) Report(f Failure) { r.failures = append(r.failures, f) }

func TestFailureCarriesOperationAndProvider(t *testing.T) {
	tests := []struct {
		name         string
		err          error
		wantStatus   int
		wantProvider string
	}{
		{"internal", errors.New("boom"), http.StatusInternalServerError, ""},
		{"provider", fmt.Errorf("search: %w", provider.NewError("tmdb", provider.KindUnavailable)), http.StatusBadGateway, "tmdb"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			reporter := &recordingReporter{}
			e := echo.New()
			e.Use(Errors(slog.New(slog.NewTextHandler(io.Discard, nil)), reporter))
			handler := Operation(func(echo.Context, any) (any, error) { return nil, tt.err }, "GetTitle")
			e.GET("/v1/titles/:id", func(c echo.Context) error {
				_, err := handler(c, nil)
				return err
			})
			rec := httptest.NewRecorder()
			e.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/v1/titles/42", nil))

			assert.Equal(t, tt.wantStatus, rec.Code)
			require.Len(t, reporter.failures, 1)
			f := reporter.failures[0]
			assert.Equal(t, "getTitle", f.Operation)
			assert.Equal(t, tt.wantProvider, f.Provider)
			assert.Equal(t, "/v1/titles/{id}", f.Route)
		})
	}
}

func TestProviderFailureNamesTheSwiftCase(t *testing.T) {
	assert.Equal(t, "unavailable", providerFailure(provider.NewError("tmdb", provider.KindUnavailable)))
	refused := provider.NewError("trakt", provider.KindRefused)
	refused.Status = 420
	assert.Equal(t, "refused(420)", providerFailure(refused))
}
