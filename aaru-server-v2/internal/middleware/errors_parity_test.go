package middleware

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"bytes"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/labstack/echo/v4"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// errorsRouterParity is an echo router behind the error middleware, logging into logs.
func errorsRouterParity(logs *bytes.Buffer) *echo.Echo {
	e := echo.New()
	e.Use(Errors(slog.New(slog.NewTextHandler(logs, nil)), nil))
	return e
}

// APITests.validationShape: a validation failure returns 422 naming the field.
func TestAValidationFailureIs422NamingTheField(t *testing.T) {
	e := errorsRouterParity(&bytes.Buffer{})
	e.GET("/test/rating", func(echo.Context) error {
		_, err := core.NewRating(11)
		return err
	})
	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/test/rating", nil))
	assert.Equal(t, http.StatusUnprocessableEntity, rec.Code)
	var body struct {
		Code    string            `json:"code"`
		Details map[string]string `json:"details"`
	}
	require.NoError(t, json.Unmarshal(rec.Body.Bytes(), &body))
	assert.Equal(t, "validation_failed", body.Code)
	assert.Contains(t, body.Details, "rating")
}

type secretErrorParity struct{}

func (secretErrorParity) Error() string { return "Secret" }

// APITests.internalErrorIsOpaque: an unexpected error is an opaque 500.
func TestAnUnexpectedErrorIsAnOpaque500(t *testing.T) {
	e := errorsRouterParity(&bytes.Buffer{})
	e.GET("/test/boom", func(echo.Context) error { return secretErrorParity{} })
	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/test/boom", nil))
	assert.Equal(t, http.StatusInternalServerError, rec.Code)
	assert.Contains(t, rec.Body.String(), `"code":"internal"`)
	assert.NotContains(t, rec.Body.String(), "Secret")
}

// ErrorLoggingTests.noRequestInLogs: a 5xx log line carries the failure, never the request or its
// Authorization header.
func TestA5xxLogLineNeverCarriesTheRequest(t *testing.T) {
	var logs bytes.Buffer
	e := errorsRouterParity(&logs)
	e.POST("/v1/search", func(echo.Context) error {
		return provider.NewError("tmdb", provider.KindUnavailable)
	})
	req := httptest.NewRequest(http.MethodPost, "/v1/search?q=private-query", strings.NewReader(`{"secret":"body-secret"}`))
	req.Header.Set("Authorization", "Bearer token-secret")
	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, req)
	assert.Equal(t, http.StatusBadGateway, rec.Code)
	line := logs.String()
	for _, want := range []string{"code=provider_unavailable", "provider=tmdb", "providerFailure=unavailable", "errorType="} {
		assert.Contains(t, line, want)
	}
	for _, secret := range []string{"token-secret", "Bearer", "Authorization", "private-query", "body-secret"} {
		assert.NotContains(t, line, secret)
	}
}
