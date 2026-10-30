// Package trakt is Trakt connect and import (Trakt/*.swift, IMP-002/003): PKCE sign-in with the
// tokens sealed at rest, and the user's Trakt library read into import rows.
//
// The API other areas call:
//
//   - ConnectService: Start / Callback / Status / Disconnect / AccessToken (the handlers).
//   - Source: imports.TraktSource for the import worker.
//   - PKCEVerifier / PKCEChallenge / QueryString / Returning: shared with MyAnimeList connect.
package trakt

import (
	"aaru-go-api/internal/config"
	"aaru-go-api/internal/crypto"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"math/big"
	"strings"
)

// The hosts Trakt answers on (TraktSettings).
const (
	AuthorizeURL = "https://auth.trakt.tv/oauth/authorize"
	// AuthURL is token exchange, refresh and revoke. Trakt requires this host for OAuth from 2027-02-01.
	AuthURL = "https://auth.trakt.tv"
	APIURL  = "https://api.trakt.tv"
	// UserAgent: Trakt may block requests that do not identify the app.
	UserAgent = "Aaru/1.0 (+https://aaruapp.com)"
)

// Settings is IMP-002's configuration. Trakt issues no client secret to this app: sign-in is PKCE
// only, and the client id is public.
type Settings struct {
	ClientID string
	// RedirectURI must be registered on the Trakt app exactly. `https://` on Aaru's own API host.
	RedirectURI string
	// ReturnPrefixes are where a finished connect may send the browser: the apps' URL scheme and
	// the web origin.
	ReturnPrefixes []string
	Cipher         *crypto.TokenCipher
}

// NewSettings builds the settings from config (nil when Trakt is not configured).
func NewSettings(p *config.OAuthProvider) (*Settings, error) {
	if p == nil {
		return nil, nil //nolint:nilnil // unset turns Trakt off
	}
	cipher, err := crypto.NewTokenCipherFromKey(p.TokenKey)
	if err != nil {
		return nil, fmt.Errorf("trakt token key: %w", err)
	}
	return &Settings{ClientID: p.ClientID, RedirectURI: p.RedirectURI.String(), ReturnPrefixes: p.ReturnPrefixes, Cipher: cipher}, nil
}

// AllowsReturn is whether a finished connect may send the browser to url.
func AllowsReturn(prefixes []string, url string) bool {
	for _, p := range prefixes {
		if strings.HasPrefix(url, p) {
			return true
		}
	}
	return false
}

// MARK: PKCE (RFC 7636)

const verifierAlphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"

// PKCEVerifier is 64 characters from the unreserved set.
func PKCEVerifier() string {
	out := make([]byte, 64)
	limit := big.NewInt(int64(len(verifierAlphabet)))
	for i := range out {
		n, err := rand.Int(rand.Reader, limit)
		if err != nil {
			panic(fmt.Sprintf("crypto/rand: %v", err))
		}
		out[i] = verifierAlphabet[n.Int64()]
	}
	return string(out)
}

// PKCEChallenge is the S256 challenge (Trakt requires S256): base64url of SHA-256, unpadded.
func PKCEChallenge(verifier string) string {
	sum := sha256.Sum256([]byte(verifier))
	return base64.RawURLEncoding.EncodeToString(sum[:])
}

// MARK: URLs as Foundation's URLComponents wrote them

// queryAllowed is Foundation's urlQueryAllowed less `&` and `=`, which a query item's name or
// value must not carry unescaped.
func queryAllowed(c byte) bool {
	switch {
	case c >= 'a' && c <= 'z', c >= 'A' && c <= 'Z', c >= '0' && c <= '9':
		return true
	}
	return strings.IndexByte("-._~!$'()*+,;:@/?", c) >= 0
}

func queryEscape(s string) string {
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		c := s[i]
		if queryAllowed(c) {
			b.WriteByte(c)
			continue
		}
		fmt.Fprintf(&b, "%%%02X", c)
	}
	return b.String()
}

// QueryString encodes query items in order, as URLComponents.queryItems did.
func QueryString(items [][2]string) string {
	parts := make([]string, len(items))
	for i, item := range items {
		parts[i] = queryEscape(item[0]) + "=" + queryEscape(item[1])
	}
	return strings.Join(parts, "&")
}

// Returning is base with one more query item (`trakt=connected`), telling the app how a connect
// went (TraktConnectService.returning).
func Returning(base, name, value string) string {
	rest, fragment, hasFragment := strings.Cut(base, "#")
	prefix, query, _ := strings.Cut(rest, "?")
	var items [][2]string
	if query != "" {
		for _, pair := range strings.Split(query, "&") {
			k, v, _ := strings.Cut(pair, "=")
			items = append(items, [2]string{unescape(k), unescape(v)})
		}
	}
	items = append(items, [2]string{name, value})
	out := prefix + "?" + QueryString(items)
	if hasFragment {
		out += "#" + fragment
	}
	return out
}

// unescape decodes percent escapes, leaving a malformed one as it is.
func unescape(s string) string {
	if !strings.Contains(s, "%") {
		return s
	}
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		if s[i] == '%' && i+2 < len(s) && isHex(s[i+1]) && isHex(s[i+2]) {
			b.WriteByte(unhex(s[i+1])<<4 | unhex(s[i+2]))
			i += 2
			continue
		}
		b.WriteByte(s[i])
	}
	return b.String()
}

func isHex(c byte) bool {
	return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

func unhex(c byte) byte {
	switch {
	case c >= '0' && c <= '9':
		return c - '0'
	case c >= 'a' && c <= 'f':
		return c - 'a' + 10
	default:
		return c - 'A' + 10
	}
}
