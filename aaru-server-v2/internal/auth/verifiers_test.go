package auth

import (
	"aaru-go-api/internal/token"
	"context"
	"crypto"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"math/big"
	"net/http"
	"net/http/httptest"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Sign in with Apple and Google verification against a stub JWKS. Never reaches Apple or Google.

const (
	appleAudience  = "com.fernandocorreia.aaru.beta"
	rawNonce       = "raw-nonce-123"
	googleAudience = "1234-ios.apps.googleusercontent.com"
)

func rsaKey(t *testing.T) *rsa.PrivateKey {
	t.Helper()
	k, err := rsa.GenerateKey(rand.Reader, 2048)
	require.NoError(t, err)
	return k
}

func enc(b []byte) string { return base64.RawURLEncoding.EncodeToString(b) }

func jwkFor(t *testing.T, kid string, key crypto.Signer) map[string]string {
	t.Helper()
	switch k := key.(type) {
	case *rsa.PrivateKey:
		return map[string]string{
			"kty": "RSA", "alg": "RS256", "use": "sig", "kid": kid,
			"n": enc(k.N.Bytes()), "e": enc(big.NewInt(int64(k.E)).Bytes()),
		}
	case *ecdsa.PrivateKey:
		point, err := k.PublicKey.Bytes()
		require.NoError(t, err)
		x, y := point[1:33], point[33:]
		return map[string]string{"kty": "EC", "crv": "P-256", "alg": "ES256", "use": "sig", "kid": kid, "x": enc(x), "y": enc(y)}
	}
	t.Fatalf("unsupported key %T", key)
	return nil
}

func signJWT(t *testing.T, kid string, key crypto.Signer, claims map[string]any) string {
	t.Helper()
	alg := "RS256"
	if _, ok := key.(*ecdsa.PrivateKey); ok {
		alg = "ES256"
	}
	header, err := json.Marshal(map[string]string{"alg": alg, "kid": kid, "typ": "JWT"})
	require.NoError(t, err)
	payload, err := json.Marshal(claims)
	require.NoError(t, err)
	input := enc(header) + "." + enc(payload)
	digest := sha256.Sum256([]byte(input))
	var sig []byte
	switch k := key.(type) {
	case *rsa.PrivateKey:
		sig, err = rsa.SignPKCS1v15(rand.Reader, k, crypto.SHA256, digest[:])
		require.NoError(t, err)
	case *ecdsa.PrivateKey:
		r, s, err := ecdsa.Sign(rand.Reader, k, digest[:])
		require.NoError(t, err)
		sig = make([]byte, 64)
		r.FillBytes(sig[:32])
		s.FillBytes(sig[32:])
	}
	return input + "." + enc(sig)
}

// stubJWKS serves a key set that a test can swap, counting requests.
type stubJWKS struct {
	mu       sync.Mutex
	body     []byte
	status   int
	requests atomic.Int32
	server   *httptest.Server
}

func newStubJWKS(t *testing.T, keys ...map[string]string) *stubJWKS {
	t.Helper()
	s := &stubJWKS{status: http.StatusOK}
	s.publish(t, keys...)
	s.server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		s.requests.Add(1)
		s.mu.Lock()
		defer s.mu.Unlock()
		w.WriteHeader(s.status)
		_, _ = w.Write(s.body)
	}))
	t.Cleanup(s.server.Close)
	return s
}

func (s *stubJWKS) publish(t *testing.T, keys ...map[string]string) {
	t.Helper()
	body, err := json.Marshal(map[string]any{"keys": keys})
	require.NoError(t, err)
	s.mu.Lock()
	s.body = body
	s.mu.Unlock()
}

func (s *stubJWKS) setStatus(status int) {
	s.mu.Lock()
	s.status = status
	s.mu.Unlock()
}

func (s *stubJWKS) cache() *JWKSCache {
	return NewJWKSCacheWith(s.server.Client(), s.server.URL, 12*time.Hour, 0)
}

func appleClaimsFor(audience string, nonce *string, expires time.Time) map[string]any {
	claims := map[string]any{
		"sub": "001234.apple-user", "aud": audience, "iss": AppleIssuer, "exp": expires.Unix(),
		"email": "Relay@PrivateRelay.AppleID.com", "is_private_email": "true",
	}
	if nonce != nil {
		claims["nonce"] = *nonce
	}
	return claims
}

func hashedNonce() *string {
	n := token.SHA256Hex(rawNonce)
	return &n
}

func TestAppleValidTokenYieldsSubjectLowercasedEmailAndRelayFlag(t *testing.T) {
	key := rsaKey(t)
	jwks := newStubJWKS(t, jwkFor(t, "test-kid", key))
	v := AppleVerifier{Audiences: []string{appleAudience}, JWKS: jwks.cache()}
	identity, err := v.Verify(context.Background(), signJWT(t, "test-kid", key, appleClaimsFor(appleAudience, hashedNonce(), time.Now().Add(10*time.Minute))), rawNonce)
	require.NoError(t, err)
	email := "relay@privaterelay.appleid.com"
	assert.Equal(t, AppleIdentity{Subject: "001234.apple-user", Email: &email, IsPrivateRelay: true}, identity)
}

func TestAppleAcceptsAnAudienceArrayAndES256(t *testing.T) {
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	require.NoError(t, err)
	jwks := newStubJWKS(t, jwkFor(t, "ec-kid", key))
	v := AppleVerifier{Audiences: []string{appleAudience}, JWKS: jwks.cache()}
	claims := appleClaimsFor(appleAudience, hashedNonce(), time.Now().Add(10*time.Minute))
	claims["aud"] = []string{"other", appleAudience}
	claims["is_private_email"] = false
	identity, err := v.Verify(context.Background(), signJWT(t, "ec-kid", key, claims), rawNonce)
	require.NoError(t, err)
	assert.False(t, identity.IsPrivateRelay)
}

func TestAppleExpiredTokenIsRejected(t *testing.T) {
	key := rsaKey(t)
	jwks := newStubJWKS(t, jwkFor(t, "test-kid", key))
	v := AppleVerifier{Audiences: []string{appleAudience}, JWKS: jwks.cache()}
	_, err := v.Verify(context.Background(), signJWT(t, "test-kid", key, appleClaimsFor(appleAudience, hashedNonce(), time.Now().Add(-time.Minute))), rawNonce)
	require.ErrorIs(t, err, ErrInvalidToken)
}

func TestAppleRotatedKeyIsPickedUpByOneRefresh(t *testing.T) {
	old := rsaKey(t)
	jwks := newStubJWKS(t, jwkFor(t, "test-kid", old))
	cache := jwks.cache()
	_, err := cache.key(context.Background(), "test-kid") // fills the cache with the old set
	require.NoError(t, err)
	assert.EqualValues(t, 1, jwks.requests.Load())

	rotated := rsaKey(t)
	jwks.publish(t, jwkFor(t, "new-kid", rotated))
	v := AppleVerifier{Audiences: []string{appleAudience}, JWKS: cache}
	identity, err := v.Verify(context.Background(), signJWT(t, "new-kid", rotated, appleClaimsFor(appleAudience, hashedNonce(), time.Now().Add(10*time.Minute))), rawNonce)
	require.NoError(t, err)
	assert.Equal(t, "001234.apple-user", identity.Subject)
	assert.EqualValues(t, 2, jwks.requests.Load(), "one refresh for the new kid")
}

func TestAppleOtherAudienceOrWrongNonceIsRejected(t *testing.T) {
	key := rsaKey(t)
	jwks := newStubJWKS(t, jwkFor(t, "test-kid", key))
	v := AppleVerifier{Audiences: []string{appleAudience}, JWKS: jwks.cache()}
	ctx := context.Background()
	soon := time.Now().Add(10 * time.Minute)

	_, err := v.Verify(ctx, signJWT(t, "test-kid", key, appleClaimsFor("com.example.other", hashedNonce(), soon)), rawNonce)
	require.ErrorIs(t, err, ErrInvalidToken)
	good := signJWT(t, "test-kid", key, appleClaimsFor(appleAudience, hashedNonce(), soon))
	_, err = v.Verify(ctx, good, "a-different-nonce")
	require.ErrorIs(t, err, ErrInvalidToken)
	_, err = v.Verify(ctx, good, "")
	require.ErrorIs(t, err, ErrInvalidToken)
	_, err = v.Verify(ctx, signJWT(t, "test-kid", key, appleClaimsFor(appleAudience, nil, soon)), rawNonce)
	require.ErrorIs(t, err, ErrInvalidToken)

	issuer := appleClaimsFor(appleAudience, hashedNonce(), soon)
	issuer["iss"] = "https://evil.example.com"
	_, err = v.Verify(ctx, signJWT(t, "test-kid", key, issuer), rawNonce)
	require.ErrorIs(t, err, ErrInvalidToken)

	forged := signJWT(t, "test-kid", rsaKey(t), appleClaimsFor(appleAudience, hashedNonce(), soon))
	_, err = v.Verify(ctx, forged, rawNonce)
	require.ErrorIs(t, err, ErrInvalidToken, "signed by a key the set does not hold")
	_, err = v.Verify(ctx, "not-a-jwt", rawNonce)
	require.ErrorIs(t, err, ErrInvalidToken)
}

func TestAppleUnknownKidRefreshesOnceThenFailsClosed(t *testing.T) {
	jwks := newStubJWKS(t, jwkFor(t, "published-kid", rsaKey(t)))
	v := AppleVerifier{Audiences: []string{appleAudience}, JWKS: jwks.cache()}
	other := rsaKey(t)
	_, err := v.Verify(context.Background(), signJWT(t, "rotated-kid", other, appleClaimsFor(appleAudience, hashedNonce(), time.Now().Add(10*time.Minute))), rawNonce)
	require.ErrorIs(t, err, ErrInvalidToken)
	assert.EqualValues(t, 2, jwks.requests.Load(), "initial fetch + one refresh")
}

func TestJWKSUnknownKidWithinTheIntervalDoesNotRefetch(t *testing.T) {
	jwks := newStubJWKS(t, jwkFor(t, "published-kid", rsaKey(t)))
	cache := NewJWKSCacheWith(jwks.server.Client(), jwks.server.URL, 12*time.Hour, time.Minute)
	for range 3 {
		k, err := cache.key(context.Background(), "unknown")
		require.ErrorIs(t, err, errUnknownKid)
		assert.Nil(t, k)
	}
	assert.EqualValues(t, 1, jwks.requests.Load())
}

func TestJWKSDownIs502UntilKeysAreHeldThenKeepsThem(t *testing.T) {
	key := rsaKey(t)
	jwks := newStubJWKS(t, jwkFor(t, "kid", key))
	jwks.setStatus(http.StatusServiceUnavailable)
	clock := time.Now()
	cache := NewJWKSCacheWith(jwks.server.Client(), jwks.server.URL, time.Hour, 0)
	cache.now = func() time.Time { return clock }
	_, err := cache.key(context.Background(), "kid")
	require.ErrorIs(t, err, errProviderUnavailable)

	jwks.setStatus(http.StatusOK)
	k, err := cache.key(context.Background(), "kid")
	require.NoError(t, err)
	require.NotNil(t, k)

	jwks.setStatus(http.StatusServiceUnavailable)
	clock = clock.Add(2 * time.Hour) // past the TTL, the provider is down
	k, err = cache.key(context.Background(), "kid")
	require.NoError(t, err)
	assert.NotNil(t, k, "keeps verifying with the keys it holds")
}

func TestJWKSConcurrentColdCallersShareOneFetch(t *testing.T) {
	jwks := newStubJWKS(t, jwkFor(t, "kid", rsaKey(t)))
	cache := NewJWKSCacheWith(jwks.server.Client(), jwks.server.URL, 12*time.Hour, time.Minute)
	var wg sync.WaitGroup
	for range 20 {
		wg.Go(func() {
			k, err := cache.key(context.Background(), "kid")
			assert.NoError(t, err)
			assert.NotNil(t, k)
		})
	}
	wg.Wait()
	assert.LessOrEqual(t, jwks.requests.Load(), int32(2))
}

func googleClaimsFor(issuer, audience string, nonce *string, verified bool, expires time.Time) map[string]any {
	claims := map[string]any{
		"sub": "google-sub-1", "aud": audience, "iss": issuer, "exp": expires.Unix(),
		"email": "Ana@Example.com", "email_verified": verified, "name": "Ana",
	}
	if nonce != nil {
		claims["nonce"] = *nonce
	}
	return claims
}

func TestGoogleValidTokenYieldsSubjectNameAndOnlyAVerifiedEmail(t *testing.T) {
	key := rsaKey(t)
	jwks := newStubJWKS(t, jwkFor(t, "google-kid", key))
	v := GoogleVerifier{Audiences: []string{googleAudience}, JWKS: jwks.cache()}
	ctx := context.Background()
	soon := time.Now().Add(10 * time.Minute)
	nonce := "n-1"

	identity, err := v.Verify(ctx, signJWT(t, "google-kid", key, googleClaimsFor("https://accounts.google.com", googleAudience, &nonce, true, soon)), &nonce)
	require.NoError(t, err)
	email, name := "ana@example.com", "Ana"
	assert.Equal(t, GoogleIdentity{Subject: "google-sub-1", Email: &email, Name: &name}, identity)

	unverified, err := v.Verify(ctx, signJWT(t, "google-kid", key, googleClaimsFor("https://accounts.google.com", googleAudience, &nonce, false, soon)), nil)
	require.NoError(t, err)
	assert.Nil(t, unverified.Email)

	bare, err := v.Verify(ctx, signJWT(t, "google-kid", key, googleClaimsFor("accounts.google.com", googleAudience, &nonce, true, soon)), nil)
	require.NoError(t, err)
	assert.Equal(t, "google-sub-1", bare.Subject)
}

func TestGoogleRejectsWrongAudienceIssuerNonceOrExpiry(t *testing.T) {
	key := rsaKey(t)
	jwks := newStubJWKS(t, jwkFor(t, "google-kid", key))
	v := GoogleVerifier{Audiences: []string{googleAudience}, JWKS: jwks.cache()}
	ctx := context.Background()
	soon := time.Now().Add(10 * time.Minute)
	nonce := "n-1"
	for _, bad := range []map[string]any{
		googleClaimsFor("https://accounts.google.com", "someone-else.apps.googleusercontent.com", &nonce, true, soon),
		googleClaimsFor("https://evil.example.com", googleAudience, &nonce, true, soon),
		googleClaimsFor("https://accounts.google.com", googleAudience, &nonce, true, time.Now().Add(-time.Minute)),
	} {
		_, err := v.Verify(ctx, signJWT(t, "google-kid", key, bad), nil)
		require.ErrorIs(t, err, ErrInvalidToken)
	}
	other := "a-different-nonce"
	_, err := v.Verify(ctx, signJWT(t, "google-kid", key, googleClaimsFor("https://accounts.google.com", googleAudience, &nonce, true, soon)), &other)
	require.ErrorIs(t, err, ErrInvalidToken)
}

func TestResendSenderPostsTheCodeAndLink(t *testing.T) {
	var got map[string]any
	var auth string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		auth = r.Header.Get("Authorization")
		assert.Equal(t, "application/json", r.Header.Get("Content-Type"))
		assert.NoError(t, json.NewDecoder(r.Body).Decode(&got))
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()
	sender := NewResendSender(server.Client(), "re_key", "Aaru <signin@aaruapp.com>")
	sender.Endpoint = server.URL
	require.NoError(t, sender.Send(context.Background(), "a@b.test", "https://aaruapp.com/auth/verify?token=t", "123456"))
	assert.Equal(t, "Bearer re_key", auth)
	assert.Equal(t, "Your Aaru sign-in code: 123 456", got["subject"])
	assert.Equal(t, []any{"a@b.test"}, got["to"])
	assert.Equal(t, "Your Aaru sign-in code is 123 456\n\nOr open this link:\n\nhttps://aaruapp.com/auth/verify?token=t\n\n"+
		"Either works once and expires in 15 minutes. If you did not ask for it, ignore this email.", got["text"])

	failing := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusUnprocessableEntity) }))
	defer failing.Close()
	sender.Endpoint = failing.URL
	require.ErrorIs(t, sender.Send(context.Background(), "a@b.test", "https://x", "123456"), errEmailNotSent)
}
