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
	// The realtime socket signs in by bearer token or by a browser's single-use ticket itself.
	"/v1/ws": true,
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
// per-client rate limits count; trustedProxyHops is how many proxies in front of
// the API append to `X-Forwarded-For` (see ClientAddress).
func Auth(sessions Sessions, webClientSecret string, trustedProxyHops int) echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			req := c.Request()
			ctx := reqctx.WithClientAddress(req.Context(), RateLimitAddress(
				req.Header.Get("X-Aaru-Visitor"), req.Header.Get("X-Aaru-Web-Secret"), webClientSecret,
				ClientAddress(req.Header.Values("X-Forwarded-For"), req.RemoteAddr, trustedProxyHops),
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

// ClientAddress is the caller's address as per-address limits count it (HTTP-007).
//
// Each trusted proxy appends the address it was called from to `X-Forwarded-For`, so the
// caller is the entry trustedProxyHops from the right: the right-most one no trusted proxy
// could have been handed by the caller. Anything left of it is what the caller sent and is
// never believed. In production the one proxy is Traefik (platform/infra
// cluster/traefik/helmchartconfig.yaml): api.aaruapp.com is DNS-only at Cloudflare, so nothing
// sits in front of Traefik, and with externalTrafficPolicy Local Traefik sees the real peer
// and appends it. Hence the default of 1 (TRUSTED_PROXY_HOPS). 0 ignores the header and uses
// the socket peer. With fewer entries than hops, the left-most is the closest to the caller.
func ClientAddress(forwarded []string, remoteAddr string, trustedProxyHops int) string {
	if trustedProxyHops > 0 {
		var hops []string
		for _, header := range forwarded {
			for _, hop := range strings.Split(header, ",") {
				if hop = strings.TrimSpace(hop); hop != "" {
					hops = append(hops, hop)
				}
			}
		}
		if len(hops) > 0 {
			return hops[max(0, len(hops)-trustedProxyHops)]
		}
	}
	host, _, err := net.SplitHostPort(remoteAddr)
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
