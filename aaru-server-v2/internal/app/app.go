// Package app wires the server: config, database, handlers, background
// workers, and the one-shot modes (`--db-migrate`, `--anime-mappings`).
package app

import (
	"aaru-go-api/internal/auth"
	"aaru-go-api/internal/billing"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/concerts"
	"aaru-go-api/internal/config"
	"aaru-go-api/internal/db"
	"aaru-go-api/internal/db/sqlc"
	"aaru-go-api/internal/gamification"
	"aaru-go-api/internal/httpapi"
	"aaru-go-api/internal/metrics"
	"aaru-go-api/internal/middleware"
	"aaru-go-api/internal/oauth"
	"aaru-go-api/internal/provider"
	"aaru-go-api/internal/push"
	"aaru-go-api/internal/sports"
	"aaru-go-api/internal/telemetry"
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/sync/errgroup"
)

// Run is the process: a one-shot mode, or serve until ctx is cancelled.
func Run(ctx context.Context, args []string) error {
	reader := config.NewReader(args)
	log := NewLogger(reader.String("log.level", "info"))
	slog.SetDefault(log)

	if reader.Bool("db.migrate") {
		return migrate(ctx, reader, log)
	}
	if source, ok := reader.Lookup("anime.mappings"); ok {
		return loadAnimeMappings(ctx, reader, source, log)
	}
	return serve(ctx, reader, log)
}

func migrate(ctx context.Context, reader *config.Reader, log *slog.Logger) error {
	settings, err := config.LoadPostgres(reader)
	if err != nil {
		return err
	}
	pool, err := db.Open(ctx, settings)
	if err != nil {
		return err
	}
	defer pool.Close()
	if err := db.WaitFor(ctx, pool, 10, 3*time.Second, log); err != nil {
		return err
	}
	log.Info("Running database migrations")
	return db.Migrate(ctx, pool)
}

// loadAnimeMappings is CAT-010's `aaru --anime-mappings <path|url|default>`: loads
// Fribb's anime list into `anime_mappings` and exits. Needs only Postgres settings,
// like `--db-migrate`.
func loadAnimeMappings(ctx context.Context, reader *config.Reader, source string, log *slog.Logger) error {
	settings, err := config.LoadPostgres(reader)
	if err != nil {
		return err
	}
	pool, err := db.Open(ctx, settings)
	if err != nil {
		return err
	}
	defer pool.Close()
	if err := db.WaitFor(ctx, pool, 10, 3*time.Second, log); err != nil {
		return err
	}
	if source == "" || source == "default" {
		source = catalog.DefaultAnimeMappingsSource
	}
	data, err := catalog.LoadAnimeMappings(ctx, source, catalog.NewAnimeMappingsTransport())
	if err != nil {
		return err
	}
	mappings, err := catalog.ParseAnimeMappings(data)
	if err != nil {
		return err
	}
	if err := catalog.NewStore(pool).UpsertMappings(ctx, mappings); err != nil {
		return err
	}
	withTMDB := 0
	for _, m := range mappings {
		if m.TMDB != nil {
			withTMDB++
		}
	}
	log.Info("Anime mappings loaded", "count", len(mappings), "withTMDB", withTMDB)
	return nil
}

func serve(ctx context.Context, reader *config.Reader, log *slog.Logger) error {
	cfg, err := config.Load(reader)
	if err != nil {
		return err
	}
	pool, err := db.Open(ctx, cfg.Postgres)
	if err != nil {
		return err
	}
	defer pool.Close()

	deps := httpapi.Deps{Config: cfg, Pool: pool, Log: log}
	if err := buildPushAndBilling(cfg, pool, log, &deps); err != nil {
		return err
	}
	sentry := makeSentry(cfg.Sentry, log)
	var reporter middleware.Reporter
	if sentry != nil {
		reporter = sentry
	}
	deps.ProductEvents = makePostHog(cfg.PostHog, log)
	if deps.ProductEvents != nil {
		telemetry.Install(deps.ProductEvents)
	}
	outbound := &http.Client{Timeout: 15 * time.Second}
	deps.Auth, deps.AgentTokens = auth.FromConfig(cfg, pool, outbound)
	deps.OAuth = oauth.FromConfig(cfg, pool)
	deps.Catalog = catalog.NewKit(pool,
		catalog.NewProviders(cfg.TMDBAPIKey, cfg.ProviderUserAgent, provider.NewHTTPTransport()), log)
	if deps.Catalog.MusicBrainz != nil {
		deps.ConcertArtists = concertArtists{deps.Catalog.MusicBrainz}
	}
	deps.Gamification = gamification.New(pool, log)
	deps.Concerts, deps.Sports = buildConcertsAndSports(cfg, pool, provider.NewHTTPTransport())
	server := httpapi.New(deps)
	router := server.Router(reporter)

	api := &http.Server{
		Addr:              net.JoinHostPort(cfg.HTTP.Host, strconv.Itoa(cfg.HTTP.Port)),
		Handler:           router,
		ReadHeaderTimeout: 10 * time.Second,
	}
	group, ctx := errgroup.WithContext(ctx)
	group.Go(func() error {
		log.Info("Server started and listening", "address", api.Addr)
		if err := api.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			return fmt.Errorf("api server: %w", err)
		}
		return nil
	})
	var metricsServer *http.Server
	if cfg.MetricsPort > 0 {
		mux := http.NewServeMux()
		mux.Handle("GET /metrics", metrics.Handler())
		metricsServer = &http.Server{Addr: net.JoinHostPort("0.0.0.0", strconv.Itoa(cfg.MetricsPort)), Handler: mux, ReadHeaderTimeout: 5 * time.Second}
		group.Go(func() error {
			if err := metricsServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
				return fmt.Errorf("metrics server: %w", err)
			}
			return nil
		})
	}
	for _, w := range server.Workers() {
		group.Go(func() error {
			log.Info("Worker started", "worker", w.Name())
			if err := w.Run(ctx); err != nil && !errors.Is(err, context.Canceled) {
				return fmt.Errorf("worker %s: %w", w.Name(), err)
			}
			return nil
		})
	}
	group.Go(func() error {
		<-ctx.Done()
		shutdown, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		defer cancel()
		errs := []error{api.Shutdown(shutdown)}
		if metricsServer != nil {
			errs = append(errs, metricsServer.Shutdown(shutdown))
		}
		sentry.Wait()
		return errors.Join(errs...)
	})
	return group.Wait()
}

// buildPushAndBilling makes the APNs and web push senders (each nil, with a notice, when not
// configured or not parseable), the fan-out, and the App Store verifier (App+build.swift).
func buildPushAndBilling(cfg *config.App, pool *pgxpool.Pool, log *slog.Logger, deps *httpapi.Deps) error {
	fanout := &push.UserPush{Q: sqlc.New(pool), Log: log}
	if cfg.Push == nil {
		log.Info("Push disabled: APNS_PRIVATE_KEY is not set")
	} else {
		sender, err := push.NewAPNSSender(push.APNSSettings{KeyID: cfg.Push.KeyID, TeamID: cfg.Push.TeamID, PrivateKeyPEM: cfg.Push.PrivateKeyPEM}, nil)
		if err != nil {
			log.Error("Push disabled: APNS_PRIVATE_KEY is not a valid .p8 key")
		} else {
			deps.APNs = sender
			fanout.APNs = sender
		}
	}
	if cfg.VAPIDConfigJSON == nil {
		log.Info("Web push disabled: VAPID_CONFIG is not set")
	} else {
		sender, err := push.NewVAPIDSender(*cfg.VAPIDConfigJSON, nil, log)
		if err != nil {
			log.Error("Web push disabled: VAPID_CONFIG is not a valid VAPID configuration")
		} else {
			deps.WebPush = sender
			fanout.Web = sender
		}
	}
	deps.Push = fanout
	apple, err := billing.NewAppleSignedData(cfg.AppleAudiences)
	if err != nil {
		return fmt.Errorf("apple root certificate: %w", err)
	}
	deps.Apple = apple
	return nil
}

// buildConcertsAndSports makes MUS-003's concerts (Ticketmaster with TICKETMASTER_API_KEY, the
// Open-Meteo city search always) and SPT-001's sports (TheSportsDB with THESPORTSDB_API_KEY).
// Without a key the area is off and answers unavailable.
func buildConcertsAndSports(cfg *config.App, pool *pgxpool.Pool, transport provider.Transport) (*concerts.Service, *sports.Service) {
	q := sqlc.New(pool)
	var listing concerts.Listing
	if cfg.TicketmasterAPIKey != nil {
		listing = concerts.NewTicketmaster(*cfg.TicketmasterAPIKey, transport)
	}
	concertService := concerts.NewService(&concerts.Store{Q: q, Pool: pool}, listing, concerts.NewOpenMeteo(transport))
	var sportsListing sports.Listing
	if cfg.TheSportsDBAPIKey != nil {
		sportsListing = sports.NewTheSportsDB(*cfg.TheSportsDBAPIKey, transport)
	}
	return concertService, sports.NewService(&sports.Store{Q: q, Pool: pool}, sportsListing)
}

// makeSentry is the error reporter, or nil (with a notice) when SENTRY_DSN is unset or not a DSN.
func makeSentry(settings *config.Sentry, log *slog.Logger) *telemetry.Sentry {
	if settings == nil {
		log.Info("Error reports disabled: SENTRY_DSN is not set")
		return nil
	}
	reporter := telemetry.NewSentry(settings.DSN, settings.Environment, settings.Release, nil, log)
	if reporter == nil {
		log.Error("Error reports disabled: SENTRY_DSN is not a Sentry DSN")
	}
	return reporter
}

// makePostHog is the product events client, or nil (with a notice) when POSTHOG_PROJECT_TOKEN is unset.
func makePostHog(settings *config.PostHog, log *slog.Logger) *telemetry.PostHog {
	if settings == nil {
		log.Info("Product events disabled: POSTHOG_PROJECT_TOKEN is not set")
		return nil
	}
	return telemetry.NewPostHog(settings.ProjectToken, settings.Host, nil, log)
}

// NewLogger maps LOG_LEVEL's swift-log names onto slog.
func NewLogger(level string) *slog.Logger {
	var l slog.Level
	switch strings.ToLower(level) {
	case "trace", "debug":
		l = slog.LevelDebug
	case "warning", "warn":
		l = slog.LevelWarn
	case "error", "critical":
		l = slog.LevelError
	default:
		l = slog.LevelInfo
	}
	return slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: l}))
}
