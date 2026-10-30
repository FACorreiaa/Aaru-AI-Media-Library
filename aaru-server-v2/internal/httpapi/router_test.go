package httpapi

import (
	"aaru-go-api/internal/api"
	"net/http"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestHealthAnswersWithoutSession(t *testing.T) {
	h := newHarness(t)
	rec := h.do(http.MethodGet, "/v1/health", "", nil)
	assert.Equal(t, http.StatusOK, rec.Code)
	assert.Equal(t, api.HealthStatusOk, decode[api.Health](t, rec).Status)
}

func TestPrivateRouteNeedsSession(t *testing.T) {
	h := newHarness(t)
	rec := h.do(http.MethodGet, "/v1/library", "", nil)
	assert.Equal(t, http.StatusUnauthorized, rec.Code)
	body := decode[api.ErrorResponse](t, rec)
	assert.Equal(t, "unauthorized", body.Code)
	assert.Equal(t, "Sign in to continue.", body.Message)
}

func TestUnknownRouteIsNotFoundShape(t *testing.T) {
	h := newHarness(t)
	_, bearer := h.signIn()
	rec := h.do(http.MethodGet, "/v1/nope", bearer, nil)
	assert.Equal(t, http.StatusNotFound, rec.Code)
	assert.Equal(t, "not_found", decode[api.ErrorResponse](t, rec).Code)
}

func TestMalformedBodyIsBadRequest(t *testing.T) {
	h := newHarness(t)
	rec := h.do(http.MethodPost, "/v1/auth/apple", "", []byte(`{bad`))
	assert.Equal(t, http.StatusBadRequest, rec.Code)
	body := decode[api.ErrorResponse](t, rec)
	assert.Equal(t, "bad_request", body.Code)
	assert.Equal(t, "The request could not be read.", body.Message)
}

func TestInternalMetricsNeedsSecret(t *testing.T) {
	h := newHarness(t, func(d *Deps) { d.Config.MetricsSecret = "s3cret" })
	assert.Equal(t, http.StatusUnauthorized, h.do(http.MethodGet, "/internal/metrics", "wrong", nil).Code)
	rec := h.do(http.MethodGet, "/internal/metrics", "s3cret", nil)
	assert.Equal(t, http.StatusOK, rec.Code)
	assert.JSONEq(t, `{"users":0}`, rec.Body.String())
}

func TestMissingRequiredFieldIsBadRequest(t *testing.T) {
	h := newHarness(t)
	rec := h.do(http.MethodPost, "/v1/auth/apple", "", []byte(`{"nonce":"n"}`))
	assert.Equal(t, http.StatusBadRequest, rec.Code)
	assert.Equal(t, "bad_request", decode[api.ErrorResponse](t, rec).Code)
}

func TestUnauthenticatedBeatsValidation(t *testing.T) {
	h := newHarness(t)
	rec := h.do(http.MethodPost, "/v1/library", "", []byte(`{}`))
	assert.Equal(t, http.StatusUnauthorized, rec.Code)
}
