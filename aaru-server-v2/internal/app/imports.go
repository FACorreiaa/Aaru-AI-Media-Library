package app

import (
	"aaru-go-api/internal/agent"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/config"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/httpapi"
	"aaru-go-api/internal/imports"
	"aaru-go-api/internal/provider"
	"aaru-go-api/internal/stremioapi"
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
	// Parsers: CAT feed, AniList lists.
	svc.CATFeed = imports.NewCATCalendarFeed(provider.NewHTTPTransport())
	if anilist, ok := deps.Catalog.Providers.AniList.(*catalog.AniList); ok {
		svc.AniListLists = imports.AniListRows{AniList: anilist}
	}

	// Trakt (IMP-002/003) and MyAnimeList (SCR-005/SCR-010): off without their client ids.
	buildConnections(cfg, pool, log, deps, svc)

	// Stremio: its account API and Cinemeta (makeStremioAccount), always on as in Swift.
	// The addon's episode map reads Cinemeta through the same account.
	stremio := stremioapi.NewAccount(provider.NewHTTPTransport())
	svc.Stremio = stremio
	deps.StremioSeries = stremio

	// Capture: text and images need the model; links work without it. Every model call is
	// metered in agent_usage.
	svc.Capture = imports.CaptureDeps{Model: deps.Model, Usage: agent.UsageStore{Q: sqlc.New(pool)}}

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
