// Package httpapi implements the generated `/v1` strict server (internal/api)
// plus the routes outside openapi.yaml (Stremio, MCP, scrobble, ListenBrainz,
// OAuth, the realtime socket, internal metrics). Handlers translate between the
// API's DTOs and the domain services; rules live in the services.
//
// One file per area, named after the Swift handler file it replaces
// (library.go for LibraryHandlers.swift). An area not yet ported still answers
// from its stub_*.go placeholder.
package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/apperr"
	"aaru-go-api/internal/auth"
	"aaru-go-api/internal/billing"
	"aaru-go-api/internal/config"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/oauth"
	"aaru-go-api/internal/push"
	"aaru-go-api/internal/reqctx"
	"aaru-go-api/internal/telemetry"
	"context"
	"log/slog"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// errNotImplemented answers a route whose handler has not been ported yet.
var errNotImplemented = apperr.New(501, "not_implemented", "This route is not available yet.")

var _ api.StrictServerInterface = (*Server)(nil)

// Deps is what the handlers are built from. Each area adds its services here.
type Deps struct {
	Config *config.App
	Pool   *pgxpool.Pool
	Log    *slog.Logger

	// APNs is nil when APNS_PRIVATE_KEY is unset: devices register, nothing is sent. It also
	// sends Live Activity pushes (push.LiveActivitySender).
	APNs *push.APNSSender
	// WebPush is nil when VAPID_CONFIG is unset: the web push routes answer 503.
	WebPush push.WebSender
	// Push fans one alert out to a user's devices and browsers (never nil once built by app).
	Push *push.UserPush
	// Apple verifies App Store signed data; nil answers billing routes with 503.
	Apple billing.AppleVerifier
	// ProductEvents is nil when POSTHOG_PROJECT_TOKEN is unset; it runs as a worker to flush.
	ProductEvents *telemetry.PostHog
	// Auth is sign-in, sign-out and account deletion (auth.FromConfig).
	Auth *auth.Service
	// AgentTokens mints agent, scrobble and music tokens and authenticates them
	// for the MCP, Stremio, scrobble and ListenBrainz transports.
	AgentTokens *auth.AgentTokenService
	// OAuth is the front door for Claude's connector (oauth.FromConfig).
	OAuth *oauth.Service
}

// Server implements api.StrictServerInterface.
type Server struct {
	Deps
	q *sqlc.Queries
}

// New builds the handlers.
func New(deps Deps) *Server {
	return &Server{Deps: deps, q: sqlc.New(deps.Pool)}
}

// currentUser is the signed-in user. The auth middleware already refused
// anonymous requests to non-public routes; this guards a route that forgot to be listed.
func currentUser(ctx context.Context) (uuid.UUID, error) {
	id, ok := reqctx.UserID(ctx)
	if !ok {
		return uuid.Nil, apperr.Unauthorized()
	}
	return id, nil
}
