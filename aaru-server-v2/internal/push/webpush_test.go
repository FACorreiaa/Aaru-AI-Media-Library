package push

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/ecdh"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/hkdf"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"fmt"
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

func TestEndpointAllowlist(t *testing.T) {
	for _, ok := range []string{
		"https://fcm.googleapis.com/fcm/send/abc",
		"https://updates.push.services.mozilla.com/wpush/v2/abc",
		"https://web.push.apple.com/QAbc",
		"https://wns2-par02p.notify.windows.com/w/?token=abc",
	} {
		assert.True(t, EndpointAllowed(ok), ok)
	}
	for _, bad := range []string{
		"https://fcm.googleapis.com.evil.example/x",
		"https://localhost/x",
		"https://user@fcm.googleapis.com/x",
		"http://web.push.apple.com/x",
		"https://evil.example/push",
		"http://fcm.googleapis.com/fcm/send/x",
		"https://fcm.googleapis.com:8443/x",
		"https://fcm.googleapis.com/" + strings.Repeat("a", 2048),
	} {
		assert.False(t, EndpointAllowed(bad), bad)
	}
}

func TestWebPaths(t *testing.T) {
	assert.Equal(t, "/app/groups/g/c", WebPath(map[string]string{"groupId": "g", "channelId": "c"}))
	assert.Equal(t, "/app/groups", WebPath(map[string]string{"groupInvite": "g"}))
	assert.Equal(t, "/app/plans/p", WebPath(map[string]string{"planId": "p", "libraryItemId": "i"}))
	assert.Equal(t, "/app/imports/i", WebPath(map[string]string{"importId": "i"}))
	assert.Equal(t, "/app/title/x", WebPath(map[string]string{"libraryItemId": "x", "titleId": "t"}))
	assert.Equal(t, "/app", WebPath(map[string]string{"groupId": "only"}))
}

func TestAiringMessage(t *testing.T) {
	name := "Episode 2"
	m := AiringMessage(DueAiring{Title: "Severance", Season: 1, Episode: 2, EpisodeName: &name})
	assert.Equal(t, "Severance", m.Title)
	assert.Equal(t, "S1 E2 · “Episode 2” is out", m.Body)
	assert.Equal(t, "S1 E2 is out", AiringMessage(DueAiring{Season: 1, Episode: 2}).Body)
	assert.Equal(t, "2", m.Payload["episode"])
}

// testVAPIDConfig is a swift-webpush configuration with a fresh key, as VAPID_CONFIG holds it.
func testVAPIDConfig(t *testing.T) (string, *ecdsa.PrivateKey) {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	require.NoError(t, err)
	raw, err := key.Bytes()
	require.NoError(t, err)
	cfg := fmt.Sprintf(`{"primaryKey":%q,"contactInformation":"mailto:push@aaruapp.com","expirationDuration":79200,"validityDuration":72000}`,
		base64.StdEncoding.EncodeToString(raw))
	return cfg, key
}

func TestVAPIDConfigFormat(t *testing.T) {
	cfg, key := testVAPIDConfig(t)
	sender, err := NewVAPIDSender(cfg, nil, nil)
	require.NoError(t, err)
	pub, err := key.PublicKey.Bytes()
	require.NoError(t, err)
	assert.Equal(t, base64.RawURLEncoding.EncodeToString(pub), sender.PublicKey(), "the key id is the base64url x963 public key")

	for _, bad := range []string{
		`{}`,
		`{"contactInformation":"mailto:a@b.c","expirationDuration":1,"validityDuration":1}`,
		`{"primaryKey":"bm90IGEga2V5","contactInformation":"mailto:a@b.c","expirationDuration":1,"validityDuration":1}`,
		strings.Replace(cfg, "mailto:push@aaruapp.com", "ftp://x", 1),
		strings.Replace(cfg, "mailto:push@aaruapp.com", "mailto:", 1),
		"not json",
	} {
		_, err := ParseVAPIDConfig(bad)
		assert.Error(t, err, bad)
	}
	// Keys without a primary still configure the sender.
	raw, _ := key.Bytes()
	keysOnly := fmt.Sprintf(`{"keys":[%q],"contactInformation":"https://aaruapp.com","expirationDuration":79200,"validityDuration":72000}`,
		base64.StdEncoding.EncodeToString(raw))
	other, err := NewVAPIDSender(keysOnly, nil, nil)
	require.NoError(t, err)
	assert.Equal(t, sender.PublicKey(), other.PublicKey())
}

// decrypt is the browser's side of RFC 8291, to check what the sender produced.
func decrypt(t *testing.T, body []byte, ua *ecdh.PrivateKey, auth []byte) []byte {
	t.Helper()
	salt := body[:16]
	rs := binary.BigEndian.Uint32(body[16:20])
	idlen := int(body[20])
	asPublic := body[21 : 21+idlen]
	ciphertext := body[21+idlen:]
	assert.Equal(t, int(rs), len(ciphertext))
	as, err := ecdh.P256().NewPublicKey(asPublic)
	require.NoError(t, err)
	shared, err := ua.ECDH(as)
	require.NoError(t, err)
	info := append(append([]byte("WebPush: info\x00"), ua.PublicKey().Bytes()...), asPublic...)
	ikm, err := hkdf.Key(sha256.New, shared, auth, string(info), 32)
	require.NoError(t, err)
	cek, err := hkdf.Key(sha256.New, ikm, salt, "Content-Encoding: aes128gcm\x00", 16)
	require.NoError(t, err)
	nonce, err := hkdf.Key(sha256.New, ikm, salt, "Content-Encoding: nonce\x00", 12)
	require.NoError(t, err)
	block, err := aes.NewCipher(cek)
	require.NoError(t, err)
	gcm, err := cipher.NewGCM(block)
	require.NoError(t, err)
	plain, err := gcm.Open(nil, nonce, ciphertext, nil)
	require.NoError(t, err)
	end := strings.LastIndexByte(string(plain), 0x02)
	require.Positive(t, end)
	for _, b := range plain[end+1:] {
		require.Zero(t, b)
	}
	return plain[:end]
}

func browser(t *testing.T) (*ecdh.PrivateKey, []byte) {
	t.Helper()
	ua, err := ecdh.P256().GenerateKey(rand.Reader)
	require.NoError(t, err)
	auth := make([]byte, 16)
	_, _ = rand.Read(auth)
	return ua, auth
}

func TestWebPushSendsAnEncryptedDeclarativeAlert(t *testing.T) {
	cfg, key := testVAPIDConfig(t)
	ua, auth := browser(t)
	var got *http.Request
	var body []byte
	stub := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		got = r
		body, _ = io.ReadAll(r.Body)
		w.WriteHeader(http.StatusCreated)
	}))
	defer stub.Close()
	sender, err := NewVAPIDSender(cfg, stub.Client(), nil)
	require.NoError(t, err)
	sub := WebSubscription{
		Endpoint: stub.URL + "/push/abc", P256dh: base64.RawURLEncoding.EncodeToString(ua.PublicKey().Bytes()),
		Auth: base64.RawURLEncoding.EncodeToString(auth), VAPIDKeyID: sender.PublicKey(),
	}
	outcome, err := sender.Send(context.Background(), Message{
		Title: "Severance", Body: "S1 E2 is out", Payload: map[string]string{"libraryItemId": "item-1"},
	}, sub)
	require.NoError(t, err)
	assert.Equal(t, Sent, outcome)

	assert.Equal(t, "/push/abc", got.URL.Path)
	assert.Equal(t, "aes128gcm", got.Header.Get("Content-Encoding"))
	assert.Equal(t, "application/octet-stream", got.Header.Get("Content-Type"))
	assert.Equal(t, "2592000", got.Header.Get("TTL"))
	assert.Equal(t, "high", got.Header.Get("Urgency"))
	assert.Len(t, body, 16+4+1+65+maxMessageSize+1+16, "padded so the size does not leak")

	var alert struct {
		WebPush      int `json:"web_push"`
		Notification struct {
			Title, Body, Navigate string
			Timestamp             int64
			Data                  map[string]string
		} `json:"notification"`
	}
	require.NoError(t, json.Unmarshal(decrypt(t, body, ua, auth), &alert))
	assert.Equal(t, 8030, alert.WebPush)
	assert.Equal(t, "Severance", alert.Notification.Title)
	assert.Equal(t, "https://aaruapp.com/app/title/item-1", alert.Notification.Navigate)
	assert.Equal(t, map[string]string{"path": "/app/title/item-1"}, alert.Notification.Data)

	// VAPID: `vapid t=<JWT>, k=<key id>`, signed by the key, for the endpoint's origin.
	authz := got.Header.Get("Authorization")
	require.True(t, strings.HasPrefix(authz, "vapid t="))
	parts := strings.SplitN(strings.TrimPrefix(authz, "vapid t="), ", k=", 2)
	require.Len(t, parts, 2)
	assert.Equal(t, sender.PublicKey(), parts[1])
	jwt := strings.Split(parts[0], ".")
	require.Len(t, jwt, 3)
	header, _ := base64.RawURLEncoding.DecodeString(jwt[0])
	assert.JSONEq(t, `{"typ":"JWT","alg":"ES256"}`, string(header))
	claimsJSON, _ := base64.RawURLEncoding.DecodeString(jwt[1])
	var claims struct {
		Aud string `json:"aud"`
		Exp int64  `json:"exp"`
		Sub string `json:"sub"`
	}
	require.NoError(t, json.Unmarshal(claimsJSON, &claims))
	assert.Equal(t, stub.URL, claims.Aud)
	assert.Equal(t, "mailto:push@aaruapp.com", claims.Sub)
	assert.InDelta(t, time.Now().Add(22*time.Hour).Unix(), claims.Exp, 5)
	sig, _ := base64.RawURLEncoding.DecodeString(jwt[2])
	require.Len(t, sig, 64)
	digest := sha256.Sum256([]byte(jwt[0] + "." + jwt[1]))
	assert.True(t, ecdsa.Verify(&key.PublicKey, digest[:], new(big.Int).SetBytes(sig[:32]), new(big.Int).SetBytes(sig[32:])))
}

func TestWebPushOutcomes(t *testing.T) {
	cfg, _ := testVAPIDConfig(t)
	ua, auth := browser(t)
	cases := []struct {
		status  int
		outcome Outcome
		err     bool
	}{
		{http.StatusGone, DeadToken, false},
		{http.StatusNotFound, DeadToken, false},
		{http.StatusServiceUnavailable, 0, true},
		{http.StatusBadRequest, 0, true},
	}
	for _, c := range cases {
		calls := 0
		stub := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			calls++
			w.WriteHeader(c.status)
		}))
		sender, err := NewVAPIDSender(cfg, stub.Client(), nil)
		require.NoError(t, err)
		sender.Retries = []time.Duration{time.Millisecond}
		sub := WebSubscription{
			Endpoint: stub.URL, P256dh: base64.RawURLEncoding.EncodeToString(ua.PublicKey().Bytes()),
			Auth: base64.RawURLEncoding.EncodeToString(auth), VAPIDKeyID: sender.PublicKey(),
		}
		outcome, err := sender.Send(context.Background(), Message{Title: "x"}, sub)
		assert.Equal(t, c.err, err != nil, c.status)
		assert.Equal(t, c.outcome, outcome, c.status)
		if c.status == http.StatusServiceUnavailable {
			assert.Equal(t, 2, calls, "a 503 is retried")
		}
		stub.Close()
	}
	// A subscription made with a key this server no longer holds is an error, not a dead browser.
	sender, _ := NewVAPIDSender(cfg, nil, nil)
	_, err := sender.Send(context.Background(), Message{}, WebSubscription{
		Endpoint: "https://fcm.googleapis.com/x", P256dh: base64.RawURLEncoding.EncodeToString(ua.PublicKey().Bytes()),
		Auth: base64.RawURLEncoding.EncodeToString(auth), VAPIDKeyID: "other",
	})
	assert.ErrorIs(t, err, ErrNoVAPIDKey)
}
