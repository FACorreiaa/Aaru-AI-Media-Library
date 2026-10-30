// Package migrations holds the schema as goose migrations, embedded in the binary.
//
// Version 1 is the schema the Swift server's 60 Fluent migrations built, dumped
// with pg_dump into baseline.sql. A database those migrations already ran on
// (it has `_fluent_migrations`) adopts it as is; an empty one gets it created.
// Every change after that is a new numbered SQL file here (00002_*.sql, ...).
package migrations

import (
	"context"
	"database/sql"
	"embed"
	"errors"
	"fmt"
)

// FS holds the numbered SQL migrations that follow the baseline.
//
//go:embed *.sql
var FS embed.FS

//go:embed baseline.sql
var baselineSQL string

// UpBaseline creates the schema unless the Swift server already did.
func UpBaseline(ctx context.Context, db *sql.DB) error {
	var adopted bool
	if err := db.QueryRowContext(ctx, `SELECT to_regclass('public._fluent_migrations') IS NOT NULL`).Scan(&adopted); err != nil {
		return fmt.Errorf("look for the Swift server's migrations: %w", err)
	}
	if adopted {
		return checkAdopted(ctx, db)
	}
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin baseline: %w", err)
	}
	if _, err := tx.ExecContext(ctx, baselineSQL); err != nil {
		return errors.Join(fmt.Errorf("create baseline schema: %w", err), tx.Rollback())
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit baseline: %w", err)
	}
	return nil
}

// DownBaseline refuses: nothing drops the whole schema.
func DownBaseline(context.Context, *sql.DB) error {
	return errors.New("the baseline schema is not reversible")
}

// The Swift migrations baseline.sql was dumped after: Migrations.swift's 60, the last CreateShares.
const (
	swiftMigrations    = 60
	lastSwiftMigration = "CreateShares"
)

// checkAdopted refuses a Swift database whose migrations are not exactly the baseline's: one
// behind would lack tables the Go server reads, one ahead has schema the baseline never saw.
func checkAdopted(ctx context.Context, db *sql.DB) error {
	var count int
	var last bool
	err := db.QueryRowContext(ctx, `SELECT count(*), coalesce(bool_or(name = $1 OR name LIKE '%.' || $1), false) FROM _fluent_migrations`,
		lastSwiftMigration).Scan(&count, &last)
	if err != nil {
		return fmt.Errorf("read the Swift server's migrations: %w", err)
	}
	if count != swiftMigrations || !last {
		return fmt.Errorf("the database has %d Swift migrations (want %d, ending with %s): "+
			"bring it to the baseline with the Swift server's --db-migrate first", count, swiftMigrations, lastSwiftMigration)
	}
	return nil
}
