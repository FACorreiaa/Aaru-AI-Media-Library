package app

import (
	"aaru-go-api/internal/config"
	"aaru-go-api/internal/httpapi"
	"aaru-go-api/internal/imports"
	"aaru-go-api/internal/mal"
	"aaru-go-api/internal/provider"
	"aaru-go-api/internal/trakt"
	"log/slog"

	"github.com/jackc/pgx/v5/pgxpool"
)

// buildConnections sets up Trakt and MyAnimeList connect (App+build.swift's makeTraktAPI and
// makeMALAPI). Without TRAKT_CLIENT_ID connect answers 503 and Trakt imports answer 409; without
// MAL_CLIENT_ID connect answers 503 and the sync worker does not run.
func buildConnections(cfg *config.App, pool *pgxpool.Pool, log *slog.Logger, deps *httpapi.Deps, svc *imports.Service) {
	traktConnect := &trakt.ConnectService{Store: trakt.NewStore(pool)}
	if settings, err := trakt.NewSettings(cfg.Trakt); err != nil {
		log.Error("Trakt is off", "error", err.Error())
	} else if settings != nil {
		api := trakt.NewAPI(*settings, provider.NewHTTPTransport())
		traktConnect.Settings, traktConnect.API = settings, api
		svc.Trakt = &trakt.Source{Connect: traktConnect, Importer: &trakt.Importer{API: api}}
	}
	deps.TraktConnect = traktConnect

	malConnect := &mal.ConnectService{Store: mal.NewStore(pool)}
	if settings, err := mal.NewSettings(cfg.MAL); err != nil {
		log.Error("MyAnimeList is off", "error", err.Error())
	} else if settings != nil {
		malConnect.Settings, malConnect.API = settings, mal.NewAPI(*settings, provider.NewHTTPTransport())
	}
	deps.MALConnect = malConnect
}
