// Package db owns the Postgres pool and the schema migrations. Queries are
// written in internal/db/queries and generated into internal/db/sqlc by sqlc;
// no handler writes SQL of its own.
package db

import (
	"aaru-go-api/internal/config"
	"aaru-go-api/internal/db/migrations"
	"context"
	"database/sql"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jackc/pgx/v5/stdlib"
	"github.com/pressly/goose/v3"
)

// Open builds the pool from the POSTGRES_* settings. It does not connect.
func Open(ctx context.Context, settings config.Postgres) (*pgxpool.Pool, error) {
	cfg, err := pgxpool.ParseConfig("")
	if err != nil {
		return nil, fmt.Errorf("pool config: %w", err)
	}
	cfg.ConnConfig.Host = settings.Host
	cfg.ConnConfig.Port = uint16(settings.Port) //nolint:gosec // a port from config
	cfg.ConnConfig.User = settings.User
	cfg.ConnConfig.Password = settings.Password
	cfg.ConnConfig.Database = settings.Database
	cfg.ConnConfig.TLSConfig = nil
	cfg.MaxConns = int32(settings.PoolSize) //nolint:gosec // clamped in config
	cfg.ConnConfig.ConnectTimeout = time.Duration(settings.PoolTimeoutSeconds) * time.Second
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, fmt.Errorf("open pool: %w", err)
	}
	return pool, nil
}

// WaitFor pings until Postgres answers. A fresh pod can be refused for its first
// seconds while the network policy that admits it is still being programmed.
func WaitFor(ctx context.Context, pool *pgxpool.Pool, attempts int, delay time.Duration, log *slog.Logger) error {
	var err error
	for attempt := 1; attempt <= attempts; attempt++ {
		if err = pool.Ping(ctx); err == nil {
			return nil
		}
		if attempt < attempts {
			log.Info("Database not reachable yet, retrying", "attempt", attempt)
			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-time.After(delay):
			}
		}
	}
	return fmt.Errorf("database not reachable: %w", err)
}

// Migrate applies every pending goose migration.
func Migrate(ctx context.Context, pool *pgxpool.Pool) error {
	sqlDB := stdlib.OpenDBFromPool(pool)
	defer func() { _ = sqlDB.Close() }()
	return migrate(ctx, sqlDB)
}

func migrate(ctx context.Context, sqlDB *sql.DB) error {
	provider, err := goose.NewProvider(goose.DialectPostgres, sqlDB, migrations.FS,
		goose.WithGoMigrations(goose.NewGoMigration(1,
			&goose.GoFunc{RunDB: migrations.UpBaseline, Mode: goose.TransactionDisabled},
			&goose.GoFunc{RunDB: migrations.DownBaseline, Mode: goose.TransactionDisabled},
		)),
	)
	if err != nil {
		return fmt.Errorf("goose provider: %w", err)
	}
	if _, err := provider.Up(ctx); err != nil {
		return fmt.Errorf("migrate: %w", err)
	}
	return nil
}

// IsUniqueViolation reports a unique-constraint failure, optionally on one constraint.
func IsUniqueViolation(err error, constraint string) bool {
	var pgErr *pgconn.PgError
	if !errors.As(err, &pgErr) || pgErr.Code != "23505" {
		return false
	}
	return constraint == "" || pgErr.ConstraintName == constraint
}

// IsNoRows reports pgx's no-rows error.
func IsNoRows(err error) bool {
	return errors.Is(err, pgx.ErrNoRows)
}
