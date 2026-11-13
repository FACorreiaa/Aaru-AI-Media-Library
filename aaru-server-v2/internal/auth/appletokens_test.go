package auth

import (
	"aaru-go-api/internal/crypto"
	"aaru-go-api/internal/testdb"
	"aaru-go-api/internal/token"
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"log/slog"
	"math/big"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Sign in with Apple token revocation (AUTH-006) against a stub of Apple's token and revoke
// endpoints, with a key made in the test. Never reaches Apple, never a real key.

const (
	appClientID = "com.fernandocorreia.aaru"
	webClientID = "com.aaruapp.web"
	appleTeam   = "TEAM123456"
	appleKeyID  = "KEY1234567"
)

// stubApple verifies any identity token as one subject signing in to one client.
type stubApple struct{ subject, audience string }

func (s stubApple) Verify(context.Context, string, string) (AppleIdentity, error) {
	return AppleIdentity{Subject: s.subject, Audience: s.audience}, nil
}

// appleCall is one form Apple's stub received.
type appleCall struct {
	path string
	form url.Values
}

// appleStub is Apple's `/auth/token` and `/auth/revoke`.
type appleStub struct {
	t      *testing.T
	server *httptest.Server
	mu     sync.Mutex
	calls  []appleCall
	// tokenStatus and revokeStatus are what the endpoints answer (200 unless set).
	tokenStatus, revokeStatus int
	// subject is the `sub` of the id_token the token endpoint returns.
	subject string
	// refresh is the refresh token it hands out.
	refresh string
}

func newAppleStub(t *testing.T, subject string) *appleStub {
	t.Helper()
	stub := &appleStub{t: t, subject: subject, refresh: "r." + uuid.NewString()}
	stub.server = httptest.NewServer(http.HandlerFunc(stub.serve))
	t.Cleanup(stub.server.Close)
	return stub
}

func (a *appleStub) serve(w http.ResponseWriter, r *http.Request) {
	if !assert.NoError(a.t, r.ParseForm()) {
		return
	}
	assert.Equal(a.t, http.MethodPost, r.Method)
	assert.Equal(a.t, "application/x-www-form-urlencoded", r.Header.Get("Content-Type"))
	a.mu.Lock()
	a.calls = append(a.calls, appleCall{path: r.URL.Path, form: r.PostForm})
	tokenStatus, revokeStatus := a.tokenStatus, a.revokeStatus
	a.mu.Unlock()
	w.Header().Set("Content-Type", "application/json")
	switch r.URL.Path {
	case "/auth/token":
		if tokenStatus != 0 && tokenStatus != http.StatusOK {
			w.WriteHeader(tokenStatus)
			_, _ = w.Write([]byte(`{"error":"invalid_grant"}`))
			return
		}
		claims, _ := json.Marshal(map[string]string{"sub": a.subject})
		idToken := "e30." + base64.RawURLEncoding.EncodeToString(claims) + ".sig"
		_ = json.NewEncoder(w).Encode(map[string]any{
			"access_token": "a", "token_type": "Bearer", "expires_in": 3600,
			"refresh_token": a.refresh, "id_token": idToken,
		})
	case "/auth/revoke":
		if revokeStatus != 0 && revokeStatus != http.StatusOK {
			w.WriteHeader(revokeStatus)
			_, _ = w.Write([]byte(`{"error":"invalid_client"}`))
		}
	default:
		w.WriteHeader(http.StatusNotFound)
	}
}

func (a *appleStub) received() []appleCall {
	a.mu.Lock()
	defer a.mu.Unlock()
	return append([]appleCall(nil), a.calls...)
}

// appleFixture is a Service whose Apple verifier and Apple endpoints are stubs.
type appleFixture struct {
	t       *testing.T
	pool    *pgxpool.Pool
	service *Service
	stub    *appleStub
	key     *ecdsa.PrivateKey
	logs    *bytes.Buffer
}

func newAppleFixture(t *testing.T, audience string) *appleFixture {
	t.Helper()
	pool := testdb.New(t)
	subject := "apple." + uuid.NewString()
	stub := newAppleStub(t, subject)
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	require.NoError(t, err)
	cipher, err := crypto.NewTokenCipherFromKey(bytes.Repeat([]byte{7}, 32))
	require.NoError(t, err)
	service := NewService(NewStore(pool), stubApple{subject: subject, audience: audience}, nil, nil)
	service.AppleTokens = &AppleTokens{
		Client: stub.server.Client(), TokenURL: stub.server.URL + "/auth/token", RevokeURL: stub.server.URL + "/auth/revoke",
		KeyID: appleKeyID, TeamID: appleTeam, Key: key, ClientIDs: []string{appClientID, webClientID},
		Cipher: cipher, Now: time.Now,
	}
	// What the service logs is read back: a token, a code or an email must never be in it.
	logs := &bytes.Buffer{}
	previous := slog.Default()
	slog.SetDefault(slog.New(slog.NewTextHandler(logs, nil)))
	t.Cleanup(func() { slog.SetDefault(previous) })
	return &appleFixture{t: t, pool: pool, service: service, stub: stub, key: key, logs: logs}
}

func (f *appleFixture) signIn(code, redirectURI string) NewSession {
	f.t.Helper()
	session, err := f.service.SignInWithApple(context.Background(), AppleSignIn{
		IdentityToken: "identity", Nonce: "nonce", AuthorizationCode: code, RedirectURI: redirectURI,
	})
	require.NoError(f.t, err)
	return session
}

// stored is the user's kept tokens, opened: client id → refresh token. The stored value is
// checked not to be the token itself.
func (f *appleFixture) stored(userID uuid.UUID) map[string]string {
	f.t.Helper()
	rows, err := f.pool.Query(context.Background(),
		`SELECT client_id, refresh_token FROM apple_refresh_tokens WHERE user_id = $1`, userID)
	require.NoError(f.t, err)
	defer rows.Close()
	out := map[string]string{}
	for rows.Next() {
		var clientID, sealed string
		require.NoError(f.t, rows.Scan(&clientID, &sealed))
		plain, err := f.service.AppleTokens.Cipher.Open(sealed)
		require.NoError(f.t, err, "the stored value opens with the token key")
		assert.NotContains(f.t, sealed, plain, "the token is stored sealed, never plain")
		out[clientID] = plain
	}
	require.NoError(f.t, rows.Err())
	return out
}

func (f *appleFixture) userExists(userID uuid.UUID) bool {
	f.t.Helper()
	var n int
	require.NoError(f.t, f.pool.QueryRow(context.Background(), `SELECT count(*) FROM users WHERE id = $1`, userID).Scan(&n))
	return n == 1
}

// checkClientSecret verifies the client secret as Apple would: ES256 by the configured key,
// issued by the team, about the client, for Apple, and short-lived.
func (f *appleFixture) checkClientSecret(secret, clientID string) {
	f.t.Helper()
	parts := strings.Split(secret, ".")
	require.Len(f.t, parts, 3)
	var header struct{ Alg, Kid string }
	raw, err := base64.RawURLEncoding.DecodeString(parts[0])
	require.NoError(f.t, err)
	require.NoError(f.t, json.Unmarshal(raw, &header))
	assert.Equal(f.t, "ES256", header.Alg)
	assert.Equal(f.t, appleKeyID, header.Kid)

	sig, err := base64.RawURLEncoding.DecodeString(parts[2])
	require.NoError(f.t, err)
	require.Len(f.t, sig, 64)
	digest := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	r, s := new(big.Int).SetBytes(sig[:32]), new(big.Int).SetBytes(sig[32:])
	assert.True(f.t, ecdsa.Verify(&f.key.PublicKey, digest[:], r, s), "signed by the Sign in with Apple key")

	var claims struct {
		Iss, Sub, Aud string
		Iat, Exp      int64
	}
	raw, err = base64.RawURLEncoding.DecodeString(parts[1])
	require.NoError(f.t, err)
	require.NoError(f.t, json.Unmarshal(raw, &claims))
	assert.Equal(f.t, appleTeam, claims.Iss)
	assert.Equal(f.t, clientID, claims.Sub)
	assert.Equal(f.t, "https://appleid.apple.com", claims.Aud)
	assert.WithinDuration(f.t, time.Now(), time.Unix(claims.Iat, 0), time.Minute)
	assert.Equal(f.t, int64(appleSecretLifetime/time.Second), claims.Exp-claims.Iat, "short-lived")
}

func TestAppleCodeIsExchangedAndTheTokenStoredSealed(t *testing.T) {
	f := newAppleFixture(t, appClientID)
	session := f.signIn("code-1", "")

	calls := f.stub.received()
	require.Len(t, calls, 1)
	assert.Equal(t, "/auth/token", calls[0].path)
	form := calls[0].form
	assert.Equal(t, "authorization_code", form.Get("grant_type"))
	assert.Equal(t, "code-1", form.Get("code"))
	assert.Equal(t, appClientID, form.Get("client_id"))
	assert.False(t, form.Has("redirect_uri"), "an app's code has no redirect URI")
	f.checkClientSecret(form.Get("client_secret"), appClientID)
	assert.Equal(t, map[string]string{appClientID: f.stub.refresh}, f.stored(session.UserID))

	// Signing in again replaces the token kept for that client.
	first := f.stub.refresh
	f.stub.mu.Lock()
	f.stub.refresh = "r.second"
	f.stub.mu.Unlock()
	again := f.signIn("code-2", "")
	assert.Equal(t, session.UserID, again.UserID)
	assert.Equal(t, map[string]string{appClientID: "r.second"}, f.stored(session.UserID))
	assert.NotContains(t, f.logs.String(), first)
}

func TestAppleWebCodeIsExchangedAsTheServicesIDWithItsRedirect(t *testing.T) {
	f := newAppleFixture(t, webClientID)
	session := f.signIn("web-code", "https://aaruapp.com/sign-in")

	calls := f.stub.received()
	require.Len(t, calls, 1)
	assert.Equal(t, webClientID, calls[0].form.Get("client_id"))
	assert.Equal(t, "https://aaruapp.com/sign-in", calls[0].form.Get("redirect_uri"))
	f.checkClientSecret(calls[0].form.Get("client_secret"), webClientID)
	assert.Equal(t, map[string]string{webClientID: f.stub.refresh}, f.stored(session.UserID))
}

func TestAppleSignInWithoutACodeStoresNothing(t *testing.T) {
	f := newAppleFixture(t, appClientID)
	session := f.signIn("", "")
	assert.Empty(t, f.stub.received(), "an older app sends no code: Apple is not called")
	assert.Empty(t, f.stored(session.UserID))

	// Deleting that account has nothing to revoke, and still deletes.
	require.NoError(t, f.service.DeleteAccount(context.Background(), session.UserID, token.Hash(session.Token)))
	assert.Empty(t, f.stub.received())
	assert.False(t, f.userExists(session.UserID))
}

func TestAppleExchangeFailureDoesNotFailTheSignIn(t *testing.T) {
	f := newAppleFixture(t, appClientID)
	f.stub.tokenStatus = http.StatusBadRequest
	session := f.signIn("used-code", "")
	assert.NotEmpty(t, session.Token, "signed in all the same")
	assert.Len(t, f.stub.received(), 1)
	assert.Empty(t, f.stored(session.UserID))
	logs := f.logs.String()
	assert.Contains(t, logs, "status=400")
	assert.Contains(t, logs, "reason=invalid_grant")
	assert.NotContains(t, logs, "used-code")

	// Apple unreachable is no different.
	f.stub.server.Close()
	again := f.signIn("code-2", "")
	assert.Equal(t, session.UserID, again.UserID)
	assert.Empty(t, f.stored(session.UserID))
	assert.NotContains(t, f.logs.String(), "code-2")
}

func TestAppleCodeOfAnotherUserIsNotKept(t *testing.T) {
	f := newAppleFixture(t, appClientID)
	f.stub.subject = "apple.someone-else"
	session := f.signIn("their-code", "")
	assert.Len(t, f.stub.received(), 1)
	assert.Empty(t, f.stored(session.UserID), "a token for a different Apple user is dropped")
	assert.Contains(t, f.logs.String(), "subject_mismatch")
}

func TestAppleCodeForAClientTheKeyDoesNotSignForIsNotExchanged(t *testing.T) {
	f := newAppleFixture(t, "com.fernandocorreia.aaru.beta")
	session := f.signIn("code", "")
	assert.Empty(t, f.stub.received())
	assert.Empty(t, f.stored(session.UserID))
}

func TestDeletingTheAccountRevokesTheAppleToken(t *testing.T) {
	f := newAppleFixture(t, appClientID)
	session := f.signIn("code-1", "")
	require.NoError(t, f.service.DeleteAccount(context.Background(), session.UserID, token.Hash(session.Token)))

	calls := f.stub.received()
	require.Len(t, calls, 2)
	revoke := calls[1]
	assert.Equal(t, "/auth/revoke", revoke.path)
	assert.Equal(t, f.stub.refresh, revoke.form.Get("token"))
	assert.Equal(t, "refresh_token", revoke.form.Get("token_type_hint"))
	assert.Equal(t, appClientID, revoke.form.Get("client_id"))
	f.checkClientSecret(revoke.form.Get("client_secret"), appClientID)
	assert.False(t, f.userExists(session.UserID))
	assert.Empty(t, f.stored(session.UserID), "the sealed token goes with the account")
	assert.NotContains(t, f.logs.String(), f.stub.refresh)
}

func TestDeletingTheAccountRevokesEveryClientsToken(t *testing.T) {
	f := newAppleFixture(t, appClientID)
	session := f.signIn("app-code", "")
	// The same Apple user then signs in on the web: a second token, for the Services ID.
	f.stub.mu.Lock()
	f.stub.refresh = "r.web"
	f.stub.mu.Unlock()
	f.service.Apple = stubApple{subject: f.stub.subject, audience: webClientID}
	web := f.signIn("web-code", "https://aaruapp.com/sign-in")
	require.Equal(t, session.UserID, web.UserID)
	require.Len(t, f.stored(session.UserID), 2)

	require.NoError(t, f.service.DeleteAccount(context.Background(), web.UserID, token.Hash(web.Token)))
	revoked := map[string]string{}
	for _, call := range f.stub.received() {
		if call.path == "/auth/revoke" {
			revoked[call.form.Get("client_id")] = call.form.Get("token")
			f.checkClientSecret(call.form.Get("client_secret"), call.form.Get("client_id"))
		}
	}
	assert.Len(t, revoked, 2, "each token is revoked as the client it was issued to")
	assert.Equal(t, "r.web", revoked[webClientID])
	assert.NotEmpty(t, revoked[appClientID])
}

func TestARevokeFailureStillDeletesTheAccount(t *testing.T) {
	f := newAppleFixture(t, appClientID)
	session := f.signIn("code-1", "")
	f.stub.revokeStatus = http.StatusBadRequest
	require.NoError(t, f.service.DeleteAccount(context.Background(), session.UserID, token.Hash(session.Token)))
	assert.Len(t, f.stub.received(), 2, "the revoke was tried")
	assert.False(t, f.userExists(session.UserID), "the right to delete wins")
	logs := f.logs.String()
	assert.Contains(t, logs, "level=WARN")
	assert.Contains(t, logs, "status=400")
	assert.Contains(t, logs, "reason=invalid_client")
	assert.NotContains(t, logs, f.stub.refresh)

	// Apple unreachable: the same.
	other := newAppleFixture(t, appClientID)
	session = other.signIn("code-1", "")
	other.stub.server.Close()
	require.NoError(t, other.service.DeleteAccount(context.Background(), session.UserID, token.Hash(session.Token)))
	assert.False(t, other.userExists(session.UserID))
	assert.NotContains(t, other.logs.String(), other.stub.refresh)
}

func TestAStaleSessionRevokesNothing(t *testing.T) {
	f := newAppleFixture(t, appClientID)
	session := f.signIn("code-1", "")
	f.service.Now = func() time.Time { return time.Now().Add(ReauthWindow + time.Minute) }
	err := f.service.DeleteAccount(context.Background(), session.UserID, token.Hash(session.Token))
	require.Error(t, err, "reauth_required")
	assert.Len(t, f.stub.received(), 1, "only the exchange: a refused deletion revokes nothing")
	assert.True(t, f.userExists(session.UserID))
}

func TestWithoutTheAppleKeyNothingIsExchangedOrRevoked(t *testing.T) {
	f := newAppleFixture(t, appClientID)
	f.service.AppleTokens = nil
	session, err := f.service.SignInWithApple(context.Background(), AppleSignIn{
		IdentityToken: "identity", Nonce: "nonce", AuthorizationCode: "code-1",
	})
	require.NoError(t, err)
	var n int
	require.NoError(t, f.pool.QueryRow(context.Background(), `SELECT count(*) FROM apple_refresh_tokens`).Scan(&n))
	assert.Zero(t, n)
	require.NoError(t, f.service.DeleteAccount(context.Background(), session.UserID, token.Hash(session.Token)))
	assert.Empty(t, f.stub.received(), "feature off: Apple is never called")
	assert.False(t, f.userExists(session.UserID))
}
