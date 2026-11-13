package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/auth"
	"aaru-go-api/internal/crypto"
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// AUTH-006 over HTTP: `POST /v1/auth/apple` carries the authorization code to Apple's token
// endpoint, and `DELETE /v1/me` revokes what came back. Apple is a stub; the key is made here.
func TestAppleCodeSentOnSignInIsRevokedOnAccountDelete(t *testing.T) {
	subject := "apple." + uuid.NewString()
	var mu sync.Mutex
	forms := map[string]url.Values{}
	apple := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !assert.NoError(t, r.ParseForm()) {
			return
		}
		mu.Lock()
		forms[r.URL.Path] = r.PostForm
		mu.Unlock()
		if r.URL.Path == "/auth/token" {
			claims, _ := json.Marshal(map[string]string{"sub": subject})
			_ = json.NewEncoder(w).Encode(map[string]string{
				"refresh_token": "r.kept", "id_token": "e30." + base64.RawURLEncoding.EncodeToString(claims) + ".sig",
			})
		}
	}))
	t.Cleanup(apple.Close)
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	require.NoError(t, err)
	cipher, err := crypto.NewTokenCipherFromKey(bytes.Repeat([]byte{3}, 32))
	require.NoError(t, err)

	h := authHarness(t, nil, nil, func(d *Deps) {
		d.Auth.Apple = fixedApple{subject: subject}
		d.Auth.AppleTokens = &auth.AppleTokens{
			Client: apple.Client(), TokenURL: apple.URL + "/auth/token", RevokeURL: apple.URL + "/auth/revoke",
			KeyID: "KEY1234567", TeamID: "TEAM123456", Key: key, ClientIDs: []string{fixedAppleAudience},
			Cipher: cipher, Now: time.Now,
		}
	})
	rec := h.do(http.MethodPost, "/v1/auth/apple", "", map[string]any{
		"identityToken": "good", "nonce": "n", "authorizationCode": "code-1", "redirectUri": "https://aaruapp.com/sign-in",
	})
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	session := decode[api.Session](t, rec)

	mu.Lock()
	exchange := forms["/auth/token"]
	mu.Unlock()
	require.NotNil(t, exchange, "the code went to Apple")
	assert.Equal(t, "code-1", exchange.Get("code"))
	assert.Equal(t, fixedAppleAudience, exchange.Get("client_id"))
	assert.Equal(t, "https://aaruapp.com/sign-in", exchange.Get("redirect_uri"))
	var sealed string
	require.NoError(t, h.pool.QueryRow(context.Background(),
		`SELECT refresh_token FROM apple_refresh_tokens WHERE user_id = $1 AND client_id = $2`,
		session.UserId.ID(), fixedAppleAudience).Scan(&sealed))
	assert.NotContains(t, sealed, "r.kept", "sealed at rest")

	assert.Equal(t, http.StatusNoContent, h.do(http.MethodDelete, "/v1/me", session.Token, nil).Code)
	mu.Lock()
	revoke := forms["/auth/revoke"]
	mu.Unlock()
	require.NotNil(t, revoke, "deleting the account revoked the token")
	assert.Equal(t, "r.kept", revoke.Get("token"))
	assert.Equal(t, "refresh_token", revoke.Get("token_type_hint"))
	assert.Equal(t, http.StatusUnauthorized, h.do(http.MethodGet, "/v1/me", session.Token, nil).Code)
}
