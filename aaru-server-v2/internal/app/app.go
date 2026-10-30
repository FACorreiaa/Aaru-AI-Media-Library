// Package app wires the server: config, database, handlers, background
// workers, and the one-shot modes (`--db-migrate`, `--anime-mappings`).
package app

import (
	"aaru-go-api/internal/auth"
	"aaru-go-api/internal/config"
	"aaru-go-api/internal/db"
	"aaru-go-api/internal/httpapi"
	"aaru-go-api/internal/metrics"
	"aaru-go-api/internal/oauth"
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

// loadAnimeMappings is CAT-010's `aaru --anime-mappings <path|url|default>`.
var loadAnimeMappings = func(context.Context, *config.Reader, string, *slog.Logger) error {
	return errors.New("--anime-mappings is not ported yet")
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
	outbound := &http.Client{Timeout: 15 * time.Second}
	deps.Auth, deps.AgentTokens = auth.FromConfig(cfg, pool, outbound)
	deps.OAuth = oauth.FromConfig(cfg, pool)
	server := httpapi.New(deps)
	router := server.Router(nil)

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
		return errors.Join(errs...)
	})
	return group.Wait()
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
