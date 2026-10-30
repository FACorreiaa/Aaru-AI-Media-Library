package auth

import (
	"aaru-go-api/internal/apperr"
	"context"
	"crypto"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"strings"
	"sync"
	"time"
)

// errInvalidToken is any signature, issuer, audience, expiry or nonce failure.
var errInvalidToken = errors.New("invalid identity token")

// errUnknownKid is a kid the provider's set does not hold, even after a refresh: fail closed.
var errUnknownKid = errors.New("unknown signing key")

// errProviderUnavailable is the key set not answering 200.
var errProviderUnavailable = apperr.New(http.StatusBadGateway, "provider_unavailable", "This sign-in provider is unavailable right now.")

// JWKSCache is a provider's signing keys, cached (Swift's AppleJWKSCache, shared
// by Apple and Google). An unknown `kid` refreshes the set at most once per
// MinimumRefreshInterval and then fails closed. Concurrent callers share one fetch.
type JWKSCache struct {
	client                 *http.Client
	url                    string
	ttl                    time.Duration
	minimumRefreshInterval time.Duration
	now                    func() time.Time

	mu        sync.Mutex
	keys      map[string]crypto.PublicKey
	loaded    bool
	fetchedAt time.Time
	inFlight  *fetchCall
}

type fetchCall struct {
	done chan struct{}
	err  error
}

// NewJWKSCache caches the key set at url for 12 hours, refreshing for an unknown kid at most once a minute.
func NewJWKSCache(client *http.Client, url string) *JWKSCache {
	return NewJWKSCacheWith(client, url, 12*time.Hour, time.Minute)
}

// NewJWKSCacheWith sets the TTL and the minimum refresh interval (tests use 0).
func NewJWKSCacheWith(client *http.Client, url string, ttl, minimumRefreshInterval time.Duration) *JWKSCache {
	if client == nil {
		client = &http.Client{Timeout: 15 * time.Second}
	}
	return &JWKSCache{client: client, url: url, ttl: ttl, minimumRefreshInterval: minimumRefreshInterval, now: time.Now}
}

// key is the public key for kid, refreshing once if it is unknown. errUnknownKid means fail closed.
func (c *JWKSCache) key(ctx context.Context, kid string) (crypto.PublicKey, error) {
	now := c.now()
	c.mu.Lock()
	stale := !c.loaded || now.Sub(c.fetchedAt) >= c.ttl
	hadKeys := c.loaded
	c.mu.Unlock()
	if stale {
		// The provider is down at the TTL: keep verifying with the keys we hold.
		if err := c.fetch(ctx, now); err != nil && !hadKeys {
			return nil, err
		}
	}
	c.mu.Lock()
	if k, ok := c.keys[kid]; ok {
		c.mu.Unlock()
		return k, nil
	}
	// Unknown kid: refresh at most once per interval, so a flood of bad kids cannot hammer the provider.
	recent := c.loaded && now.Sub(c.fetchedAt) < c.minimumRefreshInterval
	c.mu.Unlock()
	if recent {
		return nil, errUnknownKid
	}
	if err := c.fetch(ctx, now); err != nil {
		return nil, err
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if k, ok := c.keys[kid]; ok {
		return k, nil
	}
	return nil, errUnknownKid
}

// fetch joins the fetch already running, if any.
func (c *JWKSCache) fetch(ctx context.Context, now time.Time) error {
	c.mu.Lock()
	if call := c.inFlight; call != nil {
		c.mu.Unlock()
		select {
		case <-call.done:
			return call.err
		case <-ctx.Done():
			return ctx.Err()
		}
	}
	call := &fetchCall{done: make(chan struct{})}
	c.inFlight = call
	c.mu.Unlock()

	keys, err := c.load(ctx)
	c.mu.Lock()
	if err == nil {
		c.keys = keys
		c.loaded = true
		c.fetchedAt = now
	}
	c.inFlight = nil
	call.err = err
	c.mu.Unlock()
	close(call.done)
	return err
}

type jwk struct {
	Kid string `json:"kid"`
	Kty string `json:"kty"`
	Crv string `json:"crv"`
	N   string `json:"n"`
	E   string `json:"e"`
	X   string `json:"x"`
	Y   string `json:"y"`
}

func (c *JWKSCache) load(ctx context.Context) (map[string]crypto.PublicKey, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.url, nil)
	if err != nil {
		return nil, fmt.Errorf("jwks request: %w", err)
	}
	resp, err := c.client.Do(req)
	if err != nil {
		return nil, errProviderUnavailable
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		return nil, errProviderUnavailable
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return nil, errProviderUnavailable
	}
	var set struct {
		Keys []jwk `json:"keys"`
	}
	if err := json.Unmarshal(body, &set); err != nil {
		return nil, fmt.Errorf("jwks: %w", err)
	}
	keys := map[string]crypto.PublicKey{}
	for _, k := range set.Keys {
		if k.Kid == "" {
			continue
		}
		if pub := k.publicKey(); pub != nil {
			keys[k.Kid] = pub
		}
	}
	return keys, nil
}

func (k jwk) publicKey() crypto.PublicKey {
	switch k.Kty {
	case "RSA":
		n, err1 := b64(k.N)
		e, err2 := b64(k.E)
		if err1 != nil || err2 != nil || len(e) == 0 || len(e) > 4 {
			return nil
		}
		exp := 0
		for _, b := range e {
			exp = exp<<8 | int(b)
		}
		return &rsa.PublicKey{N: new(big.Int).SetBytes(n), E: exp}
	case "EC":
		if k.Crv != "P-256" {
			return nil
		}
		x, err1 := b64(k.X)
		y, err2 := b64(k.Y)
		if err1 != nil || err2 != nil {
			return nil
		}
		// Build the uncompressed point so the curve check runs.
		point := append([]byte{4}, append(pad32(x), pad32(y)...)...)
		pub, err := ecdsa.ParseUncompressedPublicKey(elliptic.P256(), point)
		if err != nil {
			return nil
		}
		return pub
	}
	return nil
}

func pad32(b []byte) []byte {
	if len(b) >= 32 {
		return b
	}
	return append(make([]byte, 32-len(b)), b...)
}

func b64(s string) ([]byte, error) {
	return base64.RawURLEncoding.DecodeString(strings.TrimRight(s, "="))
}

// KeyID is the `kid` from a token's (unverified) header. Used only to pick a key.
func KeyID(token string) string {
	part, _, _ := strings.Cut(token, ".")
	data, err := b64(part)
	if err != nil {
		return ""
	}
	var header struct {
		Kid string `json:"kid"`
	}
	if json.Unmarshal(data, &header) != nil {
		return ""
	}
	return header.Kid
}

// verifyJWT checks the signature (RS256 or ES256, matching the key) and expiry,
// then decodes the claims into v.
func (c *JWKSCache) verifyJWT(ctx context.Context, token string, v any, exp func() float64) error {
	kid := KeyID(token)
	if kid == "" {
		return errInvalidToken
	}
	key, err := c.key(ctx, kid)
	if errors.Is(err, errUnknownKid) {
		return errInvalidToken
	}
	if err != nil {
		return err
	}
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return errInvalidToken
	}
	headerJSON, err := b64(parts[0])
	if err != nil {
		return errInvalidToken
	}
	var header struct {
		Alg string `json:"alg"`
	}
	if json.Unmarshal(headerJSON, &header) != nil {
		return errInvalidToken
	}
	sig, err := b64(parts[2])
	if err != nil {
		return errInvalidToken
	}
	digest := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	switch pub := key.(type) {
	case *rsa.PublicKey:
		if header.Alg != "RS256" || rsa.VerifyPKCS1v15(pub, crypto.SHA256, digest[:], sig) != nil {
			return errInvalidToken
		}
	case *ecdsa.PublicKey:
		if header.Alg != "ES256" || len(sig) != 64 {
			return errInvalidToken
		}
		r, s := new(big.Int).SetBytes(sig[:32]), new(big.Int).SetBytes(sig[32:])
		if !ecdsa.Verify(pub, digest[:], r, s) {
			return errInvalidToken
		}
	default:
		return errInvalidToken
	}
	payload, err := b64(parts[1])
	if err != nil || json.Unmarshal(payload, v) != nil {
		return errInvalidToken
	}
	if float64(c.now().UnixNano())/1e9 >= exp() {
		return errInvalidToken
	}
	return nil
}

// audience is `aud` as a string or an array of strings.
type audience []string

func (a *audience) UnmarshalJSON(data []byte) error {
	var one string
	if err := json.Unmarshal(data, &one); err == nil {
		*a = audience{one}
		return nil
	}
	var many []string
	if err := json.Unmarshal(data, &many); err != nil {
		return fmt.Errorf("aud: %w", err)
	}
	*a = many
	return nil
}

func (a audience) any(allowed map[string]bool) bool {
	for _, v := range a {
		if allowed[v] {
			return true
		}
	}
	return false
}

// registeredClaims are the claims both providers must send.
type registeredClaims struct {
	Sub *string  `json:"sub"`
	Aud audience `json:"aud"`
	Iss *string  `json:"iss"`
	Exp *float64 `json:"exp"`
}

func (r registeredClaims) complete() bool {
	return r.Sub != nil && r.Iss != nil && r.Exp != nil && r.Aud != nil
}

func (r registeredClaims) expiry() float64 {
	if r.Exp == nil {
		return 0
	}
	return *r.Exp
}

func set(values []string) map[string]bool {
	m := make(map[string]bool, len(values))
	for _, v := range values {
		m[v] = true
	}
	return m
}
