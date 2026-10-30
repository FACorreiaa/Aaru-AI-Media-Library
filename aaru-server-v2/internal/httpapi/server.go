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
	"aaru-go-api/internal/config"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/oauth"
	"aaru-go-api/internal/reqctx"
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
