package push

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"io"
	"math/big"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type apnsCall struct {
	proto   int
	path    string
	headers http.Header
	body    map[string]any
}

// stubAPNs is an HTTP/2 TLS server answering every push with status and reason.
func stubAPNs(t *testing.T, status int, reason string) (*httptest.Server, *[]apnsCall) {
	t.Helper()
	var calls []apnsCall
	srv := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		data, _ := io.ReadAll(r.Body)
		var body map[string]any
		_ = json.Unmarshal(data, &body)
		calls = append(calls, apnsCall{proto: r.ProtoMajor, path: r.URL.Path, headers: r.Header.Clone(), body: body})
		if status != http.StatusOK {
			w.WriteHeader(status)
			_, _ = w.Write([]byte(`{"reason":"` + reason + `"}`))
		}
	}))
	srv.EnableHTTP2 = true
	srv.StartTLS()
	t.Cleanup(srv.Close)
	return srv, &calls
}

func testSender(t *testing.T, srv *httptest.Server) (*APNSSender, *ecdsa.PrivateKey) {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	require.NoError(t, err)
	der, err := x509.MarshalPKCS8PrivateKey(key)
	require.NoError(t, err)
	p8 := string(pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der}))
	s, err := NewAPNSSender(APNSSettings{KeyID: "KEY123", TeamID: "TEAM456", PrivateKeyPEM: p8}, srv.Client())
	require.NoError(t, err)
	s.Sandbox = srv.URL + "/sandbox"
	s.Production = srv.URL + "/production"
	return s, key
}

func TestAPNsAlertOverHTTP2(t *testing.T) {
	srv, calls := stubAPNs(t, http.StatusOK, "")
	sender, key := testSender(t, srv)
	outcome, err := sender.Send(context.Background(), Message{
		Title: "Severance", Body: "S1 E2 is out", Payload: map[string]string{"titleId": "t1"},
	}, Device{Token: "abcd", Environment: Production, Topic: "com.fernandocorreia.aaru.beta"})
	require.NoError(t, err)
	assert.Equal(t, Sent, outcome)
	require.Len(t, *calls, 1)
	call := (*calls)[0]
	assert.Equal(t, 2, call.proto)
	assert.Equal(t, "/production/3/device/abcd", call.path)
	assert.Equal(t, "alert", call.headers.Get("apns-push-type"))
	assert.Equal(t, "10", call.headers.Get("apns-priority"))
	assert.Equal(t, "com.fernandocorreia.aaru.beta", call.headers.Get("apns-topic"))
	assert.Empty(t, call.headers.Get("apns-expiration"))
	assert.Equal(t, "t1", call.body["titleId"])
	assert.Equal(t, map[string]any{"alert": map[string]any{"title": "Severance", "body": "S1 E2 is out", "sound": "default"}}, call.body["aps"])

	// The provider token is ES256 by the team's key, and reused.
	authz := call.headers.Get("authorization")
	require.True(t, strings.HasPrefix(authz, "bearer "))
	jwt := strings.Split(strings.TrimPrefix(authz, "bearer "), ".")
	require.Len(t, jwt, 3)
	header, _ := base64.RawURLEncoding.DecodeString(jwt[0])
	assert.JSONEq(t, `{"alg":"ES256","kid":"KEY123","typ":"JWT"}`, string(header))
	claims, _ := base64.RawURLEncoding.DecodeString(jwt[1])
	assert.Contains(t, string(claims), `"iss":"TEAM456"`)
	sig, _ := base64.RawURLEncoding.DecodeString(jwt[2])
	digest := sha256.Sum256([]byte(jwt[0] + "." + jwt[1]))
	assert.True(t, ecdsa.Verify(&key.PublicKey, digest[:], new(big.Int).SetBytes(sig[:32]), new(big.Int).SetBytes(sig[32:])))

	_, err = sender.Send(context.Background(), Message{}, Device{Token: "efgh", Environment: Sandbox, Topic: "t"})
	require.NoError(t, err)
	assert.Equal(t, "/sandbox/3/device/efgh", (*calls)[1].path)
	assert.Equal(t, authz, (*calls)[1].headers.Get("authorization"))
}

func TestAPNsDeadTokens(t *testing.T) {
	for reason, dead := range map[string]bool{
		"BadDeviceToken": true, "Unregistered": true, "DeviceTokenNotForTopic": true,
		"ExpiredToken": false, "TooManyRequests": false,
	} {
		srv, _ := stubAPNs(t, http.StatusGone, reason)
		sender, _ := testSender(t, srv)
		outcome, err := sender.Send(context.Background(), Message{}, Device{Token: "a", Environment: Sandbox, Topic: "t"})
		if dead {
			require.NoError(t, err, reason)
			assert.Equal(t, DeadToken, outcome, reason)
		} else {
			var apnsErr *Error
			require.ErrorAs(t, err, &apnsErr, reason)
			assert.Equal(t, reason, apnsErr.Reason)
		}
		// An ended activity's token answers ExpiredToken: dead for Live Activities.
		outcome, err = sender.SendLiveActivity(context.Background(), LiveActivityPush{Event: LiveActivityUpdate, Timestamp: time.Now()},
			LiveActivityToken{Token: "a", Environment: Sandbox, Topic: "t"})
		if dead || reason == "ExpiredToken" {
			require.NoError(t, err, reason)
			assert.Equal(t, DeadToken, outcome, reason)
		} else {
			require.Error(t, err, reason)
		}
	}
}

func TestNewAPNSSenderRefusesABadKey(t *testing.T) {
	_, err := NewAPNSSender(APNSSettings{PrivateKeyPEM: "not a key"}, nil)
	require.Error(t, err)
}

func TestLiveActivityPushes(t *testing.T) {
	srv, calls := stubAPNs(t, http.StatusOK, "")
	sender, _ := testSender(t, srv)
	now := time.Unix(1_800_000_000, 0)
	stale := now.Add(time.Hour)
	content := map[string]any{"items": []any{}, "showsEndTime": false}
	token := LiveActivityToken{Token: "start-token", Kind: LiveActivityTokenStart, Environment: Production, Topic: "com.fernandocorreia.aaru"}

	_, err := sender.SendLiveActivity(context.Background(), LiveActivityPush{
		Event: LiveActivityStart, AlertTitle: "Now playing", AlertBody: "Severance", Content: content,
		StaleDate: &stale, Timestamp: now,
	}, token)
	require.NoError(t, err)
	_, err = sender.SendLiveActivity(context.Background(), LiveActivityPush{
		Event: LiveActivityUpdate, Content: content, StaleDate: &stale, Timestamp: now, Considerate: true,
	}, token)
	require.NoError(t, err)
	_, err = sender.SendLiveActivity(context.Background(), LiveActivityPush{
		Event: LiveActivityEnd, Content: content, StaleDate: &stale, Timestamp: now, Dismissal: now.Add(time.Minute),
	}, token)
	require.NoError(t, err)

	require.Len(t, *calls, 3)
	for _, c := range *calls {
		assert.Equal(t, "liveactivity", c.headers.Get("apns-push-type"))
		assert.Equal(t, "com.fernandocorreia.aaru.push-type.liveactivity", c.headers.Get("apns-topic"))
		assert.Equal(t, "/production/3/device/start-token", c.path)
	}
	start := (*calls)[0].body["aps"].(map[string]any)
	assert.Equal(t, map[string]any{
		"timestamp": float64(now.Unix()), "event": "start", "content-state": content, "stale-date": float64(stale.Unix()),
		"alert": map[string]any{"title": "Now playing", "body": "Severance"}, "attributes": map[string]any{},
		"attributes-type": "NowPlayingActivityAttributes",
	}, start)
	assert.Equal(t, "10", (*calls)[0].headers.Get("apns-priority"))

	update := (*calls)[1].body["aps"].(map[string]any)
	assert.Equal(t, map[string]any{
		"timestamp": float64(now.Unix()), "event": "update", "content-state": content, "stale-date": float64(stale.Unix()),
	}, update)
	assert.Equal(t, "5", (*calls)[1].headers.Get("apns-priority"))

	end := (*calls)[2].body["aps"].(map[string]any)
	assert.Equal(t, map[string]any{
		"timestamp": float64(now.Unix()), "event": "end", "content-state": content,
		"dismissal-date": float64(now.Add(time.Minute).Unix()),
	}, end)
}
