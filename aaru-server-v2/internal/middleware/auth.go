package middleware

import (
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/reqctx"
	"aaru-go-api/internal/token"
	"context"
	"crypto/subtle"
	"net"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
)

// Sessions resolves a session token hash to its user.
type Sessions interface {
	UserIDForTokenHash(ctx context.Context, hash string, now time.Time) (uuid.UUID, bool, error)
}

// PublicPaths answer without a session.
var PublicPaths = map[string]bool{
	"/v1/health":            true,
	"/v1/auth/apple":        true,
	"/v1/auth/email/link":   true,
	"/v1/auth/email/verify": true,
	"/v1/auth/google":       true,
	// Trakt's browser redirect: no session; the one-time `state` names the user.
	"/v1/imports/trakt/callback": true,
	// MyAnimeList's browser redirect, the same way (SCR-005).
	"/v1/connections/mal/callback": true,
	// MCP authenticates itself with an agent token, never a session (OUT-004).
	"/v1/mcp": true,
	// Scrobbles authenticate themselves with a scrobble token, never a session (SCR-007).
	"/v1/scrobble/start": true,
	"/v1/scrobble/pause": true,
	"/v1/scrobble/stop":  true,
	// App Store Server Notifications: Apple's signature is the authentication (BIL-003).
	"/v1/billing/apple/notifications": true,
}

// IsPublic is the fixed public routes plus an invite's or a share's preview
// (`/v1/invites/{code}`, `/v1/shares/{code}`), which a signed-out visitor opens.
func IsPublic(path string) bool {
	if PublicPaths[path] {
		return true
	}
	for _, prefix := range []string{"/v1/invites/", "/v1/shares/"} {
		if code, ok := strings.CutPrefix(path, prefix); ok && code != "" && !strings.Contains(code, "/") {
			return true
		}
	}
	return false
}

// Auth resolves `Authorization: Bearer <token>` to a user and refuses every
// `/v1` route but the public ones without one. It also records the address
// per-client rate limits count.
func Auth(sessions Sessions, webClientSecret string) echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			req := c.Request()
			ctx := reqctx.WithClientAddress(req.Context(), RateLimitAddress(
				req.Header.Get("X-Aaru-Visitor"), req.Header.Get("X-Aaru-Web-Secret"), webClientSecret, clientAddress(c),
			))
			signedIn := false
			if bearer := BearerToken(req.Header.Get("Authorization")); bearer != "" {
				hash := token.Hash(bearer)
				userID, ok, err := sessions.UserIDForTokenHash(ctx, hash, time.Now())
				if err != nil {
					return err
				}
				if ok {
					ctx = reqctx.WithUser(ctx, userID, hash)
					signedIn = true
				}
			}
			c.SetRequest(req.WithContext(ctx))
			path := req.URL.Path
			if !signedIn && strings.HasPrefix(path, "/v1/") && !IsPublic(path) {
				return apperr.Unauthorized()
			}
			return next(c)
		}
	}
}

// BearerToken is the token in an `Authorization: Bearer` header, or "".
func BearerToken(header string) string {
	t, ok := strings.CutPrefix(header, "Bearer ")
	if !ok {
		return ""
	}
	return strings.TrimSpace(t)
}

// clientAddress is Traefik's first `X-Forwarded-For` hop, else the socket peer.
func clientAddress(c echo.Context) string {
	if fwd := c.Request().Header.Get("X-Forwarded-For"); fwd != "" {
		first, _, _ := strings.Cut(fwd, ",")
		return strings.TrimSpace(first)
	}
	host, _, err := net.SplitHostPort(c.Request().RemoteAddr)
	if err != nil || host == "" {
		return "unknown"
	}
	return host
}

// RateLimitAddress is the address per-address limits count. The web Worker
// reaches the API from Cloudflare's addresses, so it names the visitor in
// `X-Aaru-Visitor` and proves itself with `X-Aaru-Web-Secret`. Without the
// secret (or with none configured) the header is ignored.
func RateLimitAddress(visitor, presentedSecret, secret, fallback string) string {
	visitor = strings.TrimSpace(visitor)
	if secret == "" || presentedSecret == "" || !ConstantTimeEquals(presentedSecret, secret) || !isAddress(visitor) {
		return fallback
	}
	return visitor
}

// ConstantTimeEquals compares without leaking how much matched.
func ConstantTimeEquals(presented, expected string) bool {
	return subtle.ConstantTimeCompare([]byte(presented), []byte(expected)) == 1
}

// isAddress: one IPv4 or IPv6 address, nothing else (no list, no port, no name).
func isAddress(s string) bool {
	if len(s) < 2 || len(s) > 45 || (!strings.Contains(s, ".") && !strings.Contains(s, ":")) {
		return false
	}
	for _, r := range s {
		isHex := (r >= '0' && r <= '9') || (r >= 'a' && r <= 'f') || (r >= 'A' && r <= 'F')
		if !isHex && r != ':' && r != '.' {
			return false
		}
	}
	return true
}
