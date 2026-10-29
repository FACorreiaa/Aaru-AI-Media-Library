// Package reqctx carries what the middleware learned about a request to the
// handlers: the signed-in user, the session they presented, the address
// rate limits count, and the caller's time zone.
package reqctx

import (
	"context"
	"time"

	"github.com/google/uuid"
)

type key int

const (
	userKey key = iota
	sessionKey
	addressKey
	zoneKey
)

// WithUser records the signed-in user and the hash of the session token they presented.
func WithUser(ctx context.Context, userID uuid.UUID, sessionTokenHash string) context.Context {
	ctx = context.WithValue(ctx, userKey, userID)
	return context.WithValue(ctx, sessionKey, sessionTokenHash)
}

// UserID is the signed-in user, if any.
func UserID(ctx context.Context) (uuid.UUID, bool) {
	id, ok := ctx.Value(userKey).(uuid.UUID)
	return id, ok
}

// SessionTokenHash is the hash of the presented session token, so sign-out deletes exactly that session.
func SessionTokenHash(ctx context.Context) string {
	h, _ := ctx.Value(sessionKey).(string)
	return h
}

// WithClientAddress records the address per-client limits count.
func WithClientAddress(ctx context.Context, address string) context.Context {
	return context.WithValue(ctx, addressKey, address)
}

// ClientAddress is the address per-client rate limits count; never an authorization input.
func ClientAddress(ctx context.Context) string {
	if a, ok := ctx.Value(addressKey).(string); ok && a != "" {
		return a
	}
	return "unknown"
}

// WithTimeZone records the caller's zone from `X-Timezone`.
func WithTimeZone(ctx context.Context, loc *time.Location) context.Context {
	return context.WithValue(ctx, zoneKey, loc)
}

// TimeZone is the caller's zone from `X-Timezone` (GAM-003), or nil when the
// request sent none: callers fall back to the user's stored zone, then UTC.
func TimeZone(ctx context.Context) *time.Location {
	loc, _ := ctx.Value(zoneKey).(*time.Location)
	return loc
}
