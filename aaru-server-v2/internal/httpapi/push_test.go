package httpapi

import (
	"aaru-go-api/internal/push"
	"context"
	"crypto/rand"
	"encoding/hex"
	"net/http"
	"net/url"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type stubWebPush struct{}

func (stubWebPush) PublicKey() string { return "BPublicKeyForTests_abcdefghijklmnop" }

func (stubWebPush) Send(context.Context, push.Message, push.WebSubscription) (push.Outcome, error) {
	return push.Sent, nil
}

func apnsToken() string {
	b := make([]byte, 32)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func TestDevicesRegisterPerUserAndEnvironment(t *testing.T) {
	h := newHarness(t)
	user, bearer := h.signIn()
	svc := &push.Service{Q: h.server.q}
	register := func(token, env, bundle string) int {
		return h.do(http.MethodPut, "/v1/devices", bearer, map[string]string{"token": token, "environment": env, "bundleId": bundle}).Code
	}
	token := apnsToken()
	assert.Equal(t, http.StatusNoContent, register(token, "production", "com.fernandocorreia.aaru.beta"))
	devices, err := svc.Devices(context.Background(), user)
	require.NoError(t, err)
	assert.Equal(t, []push.Device{{Token: token, Environment: push.Production, Topic: "com.fernandocorreia.aaru.beta"}}, devices)

	rec := h.do(http.MethodPut, "/v1/devices", bearer, map[string]string{"token": "not-a-token", "environment": "production", "bundleId": "com.fernandocorreia.aaru"})
	assert.Equal(t, http.StatusUnprocessableEntity, rec.Code)
	assert.JSONEq(t, `{"code":"validation_failed","message":"That is not an APNs device token.","details":{"token":"Hex, as the device gave it."}}`, rec.Body.String())
	assert.Equal(t, http.StatusUnprocessableEntity, register(apnsToken(), "sandbox", "com.example.other"))
	assert.Equal(t, http.StatusBadRequest, register(apnsToken(), "staging", "com.fernandocorreia.aaru"))

	assert.Equal(t, http.StatusNoContent, h.do(http.MethodDelete, "/v1/devices/"+token, bearer, nil).Code)
	devices, err = svc.Devices(context.Background(), user)
	require.NoError(t, err)
	assert.Empty(t, devices)
}

func TestNotificationSwitchesStartOffAndChangeOneByOne(t *testing.T) {
	h := newHarness(t)
	_, bearer := h.signIn()
	type settings struct{ Airing, GroupMentions, GroupInvites bool }
	initial := decode[settings](t, h.do(http.MethodGet, "/v1/me/notifications", bearer, nil))
	assert.Equal(t, settings{}, initial)
	mentions := decode[settings](t, h.do(http.MethodPut, "/v1/me/notifications", bearer, map[string]bool{"groupMentions": true}))
	assert.Equal(t, settings{GroupMentions: true}, mentions)
	airing := decode[settings](t, h.do(http.MethodPut, "/v1/me/notifications", bearer, map[string]bool{"airing": true}))
	assert.Equal(t, settings{Airing: true, GroupMentions: true}, airing)
}

func TestWebPushKeyIs503WithoutVAPID(t *testing.T) {
	h := newHarness(t)
	_, bearer := h.signIn()
	rec := h.do(http.MethodGet, "/v1/web-push/key", bearer, nil)
	assert.Equal(t, http.StatusServiceUnavailable, rec.Code)
	assert.Equal(t, "push_unavailable", decode[map[string]any](t, rec)["code"])
}

func TestBrowserSubscribes(t *testing.T) {
	h := newHarness(t, func(d *Deps) { d.WebPush = stubWebPush{} })
	user, bearer := h.signIn()
	key := decode[map[string]string](t, h.do(http.MethodGet, "/v1/web-push/key", bearer, nil))
	assert.Equal(t, stubWebPush{}.PublicKey(), key["publicKey"])

	subscribe := func(endpoint string) int {
		return h.do(http.MethodPut, "/v1/web-push/subscriptions", bearer, map[string]any{
			"endpoint": endpoint,
			"keys": map[string]string{
				"p256dh": "BNcRdreALRFXTkOOUHK1EtK2wtaz5Ry4YfYCA_0QTpQtUbVlUls0VJXg7A8u-Ts1XbjhazAkj7I99e8QcYP7DkM",
				"auth":   "tBHItJI5svbpez7KI4CCXg",
			},
		}).Code
	}
	for _, bad := range []string{"https://evil.example/push", "http://fcm.googleapis.com/fcm/send/x", "https://fcm.googleapis.com:8443/x"} {
		assert.Equal(t, http.StatusUnprocessableEntity, subscribe(bad), bad)
	}
	badKeys := h.do(http.MethodPut, "/v1/web-push/subscriptions", bearer, map[string]any{
		"endpoint": "https://fcm.googleapis.com/fcm/send/x", "keys": map[string]string{"p256dh": "short", "auth": "tBHItJI5svbpez7KI4CCXg"},
	})
	assert.Equal(t, http.StatusUnprocessableEntity, badKeys.Code)
	assert.Contains(t, badKeys.Body.String(), "Those subscription keys are not valid.")

	endpoint := "https://fcm.googleapis.com/fcm/send/" + uuid.NewString()
	assert.Equal(t, http.StatusNoContent, subscribe(endpoint))
	assert.Equal(t, http.StatusNoContent, subscribe(endpoint), "saving again is idempotent")
	svc := &push.Service{Q: h.server.q}
	saved, err := svc.WebSubscriptions(context.Background(), user)
	require.NoError(t, err)
	require.Len(t, saved, 1)
	assert.Equal(t, endpoint, saved[0].Endpoint)
	assert.Equal(t, stubWebPush{}.PublicKey(), saved[0].VAPIDKeyID)

	assert.Equal(t, http.StatusNoContent, h.do(http.MethodDelete, "/v1/web-push/subscriptions?endpoint="+url.QueryEscape(endpoint), bearer, nil).Code)
	saved, err = svc.WebSubscriptions(context.Background(), user)
	require.NoError(t, err)
	assert.Empty(t, saved)
}
