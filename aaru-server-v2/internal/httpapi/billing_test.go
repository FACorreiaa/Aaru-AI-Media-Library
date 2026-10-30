package httpapi

import (
	"aaru-go-api/internal/billing"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type stubApple struct {
	txs map[string]billing.Transaction
}

func (s stubApple) Transaction(jws string) (billing.Transaction, error) {
	t, ok := s.txs[jws]
	if !ok {
		return billing.Transaction{}, billing.ErrInvalid
	}
	return t, nil
}

func (stubApple) Notification(string) (billing.Notification, error) {
	return billing.Notification{}, billing.ErrInvalid
}

func TestAppleReachesTheNotificationRouteWithoutASession(t *testing.T) {
	h := newHarness(t)
	rec := h.do(http.MethodPost, "/v1/billing/apple/notifications", "not-a-session", map[string]string{"signedPayload": "x"})
	// No verifier configured in this harness: 503, not 401.
	assert.Equal(t, http.StatusServiceUnavailable, rec.Code)
	assert.Equal(t, "billing_unavailable", decode[map[string]any](t, rec)["code"])
}

func TestEntitlementReportsPlusAndCaptures(t *testing.T) {
	var apple stubApple
	h := newHarness(t, func(d *Deps) { d.Apple = &apple })
	user, bearer := h.signIn()
	expires := time.Now().Add(24 * time.Hour)
	apple.txs = map[string]billing.Transaction{"mine": {
		OriginalTransactionID: uuid.NewString(), ProductID: "aaru_plus_monthly", Environment: "Sandbox",
		AppAccountToken: &user, ExpiresAt: &expires, SignedAt: time.Now(),
	}}

	free := decode[map[string]any](t, h.do(http.MethodGet, "/v1/me/entitlement", bearer, nil))
	assert.Equal(t, false, free["plus"])
	assert.Equal(t, strings.ToUpper(user.String()), free["appAccountToken"])
	assert.InDelta(t, 3, free["capture"].(map[string]any)["limit"], 0)

	bad := h.do(http.MethodPost, "/v1/billing/apple/transactions", bearer, map[string]string{"signedTransaction": "garbage"})
	assert.Equal(t, http.StatusUnprocessableEntity, bad.Code)
	assert.JSONEq(t, `{"code":"invalid_transaction","message":"Aaru could not confirm that purchase with the App Store."}`, bad.Body.String())

	rec := h.do(http.MethodPost, "/v1/billing/apple/transactions", bearer, map[string]string{"signedTransaction": "mine"})
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	plus := decode[map[string]any](t, rec)
	assert.Equal(t, true, plus["plus"])
	assert.Equal(t, "aaru_plus_monthly", plus["productId"])
	assert.Equal(t, true, plus["sandbox"])
	assert.NotEmpty(t, plus["expiresAt"])
	_, hasLimit := plus["capture"].(map[string]any)["limit"]
	assert.False(t, hasLimit, "Plus has no monthly limit")
}
