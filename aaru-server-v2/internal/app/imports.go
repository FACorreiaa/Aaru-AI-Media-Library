package app

import (
	"aaru-go-api/internal/config"
	"aaru-go-api/internal/httpapi"
	"aaru-go-api/internal/imports"
	"aaru-go-api/internal/provider"
	"log/slog"

	"github.com/jackc/pgx/v5/pgxpool"
)

// buildImports makes the import service with every provider it reads (App+build.swift's
// ImportService): parsers' CAT feed and AniList lists, Trakt, Stremio, capture and listening
// history. Each is left nil when it is not configured, as in Swift.
func buildImports(cfg *config.App, pool *pgxpool.Pool, log *slog.Logger, deps *httpapi.Deps) {
	svc := imports.NewService(imports.NewStore(pool), deps.Catalog, deps.Library.Store, deps.Gamification, log)
	if deps.Push != nil {
		svc.Push = deps.Push
	}
	_ = cfg
	// Parsers: CAT feed, AniList lists.

	// Trakt.

	// Stremio.

	// Capture.

	// Listening history (MUS-004): ListenBrainz on the Discover rows' client; Last.fm only with
	// LASTFM_API_KEY (without it, its import answers 503).
	var listenBrainz *provider.Client
	if deps.Catalog != nil {
		listenBrainz = deps.Catalog.ListenBrainzClient
	}
	svc.ListenHistory = imports.NewListenHistory(cfg.LastFMAPIKey, cfg.ProviderUserAgent, listenBrainz, provider.NewHTTPTransport())

	deps.Imports = svc
	// MCP's plan_import hands list exports to the same service (AgentTools+Import).
	deps.AgentImports = imports.AgentImporter{Service: svc}
}
