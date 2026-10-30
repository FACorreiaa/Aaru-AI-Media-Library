package app

import (
	"aaru-go-api/internal/catalog"
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
	svc.CATFeed = imports.NewCATCalendarFeed(provider.NewHTTPTransport())
	if anilist, ok := deps.Catalog.Providers.AniList.(*catalog.AniList); ok {
		svc.AniListLists = imports.AniListRows{AniList: anilist}
	}

	// Trakt.

	// Stremio.

	// Capture.

	// Listening history.

	deps.Imports = svc
}
