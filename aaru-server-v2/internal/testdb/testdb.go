// Package testdb gives each test its own migrated Postgres database, cloned
// from a template migrated once per schema version. Tests can run in parallel.
//
// It reaches Postgres with the POSTGRES_* variables, defaulting to the
// aaru-server docker-compose database (hb / testing123 on 127.0.0.1:5432).
// Without a reachable Postgres every test that asks for one is skipped,
// unless AARU_REQUIRE_DB=1 (CI), which fails them instead.
package testdb

import (
	"aaru-go-api/internal/config"
	"aaru-go-api/internal/db"
	"aaru-go-api/internal/db/migrations"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io/fs"
	"net/url"
	"os"
	"sort"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

func env(key, def string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return def
}

func settings(database string) config.Postgres {
	var port int
	_, _ = fmt.Sscanf(env("POSTGRES_PORT", "5432"), "%d", &port)
	return config.Postgres{
		Host:               env("POSTGRES_HOST", "127.0.0.1"),
		Port:               port,
		User:               env("POSTGRES_USER", "hb"),
		Password:           env("POSTGRES_PASSWORD", "testing123"),
		Database:           database,
		PoolSize:           8,
		PoolTimeoutSeconds: 10,
	}
}

func connString(database string) string {
	s := settings(database)
	u := url.URL{
		Scheme: "postgres",
		User:   url.UserPassword(s.User, s.Password),
		Host:   fmt.Sprintf("%s:%d", s.Host, s.Port),
		Path:   "/" + database,
	}
	q := u.Query()
	q.Set("sslmode", "disable")
	u.RawQuery = q.Encode()
	return u.String()
}

var (
	templateOnce sync.Once
	templateName string
	templateErr  error
)

// schemaVersion hashes the migrations, so a changed schema gets a new template.
func schemaVersion() string {
	h := sha256.New()
	names, _ := fs.Glob(migrations.FS, "*.sql")
	sort.Strings(names)
	for _, n := range names {
		b, _ := fs.ReadFile(migrations.FS, n)
		h.Write([]byte(n))
		h.Write(b)
	}
	return hex.EncodeToString(h.Sum(nil))[:12]
}

func adminDB() string { return env("POSTGRES_DATABASE", "hb") }

func ensureTemplate(ctx context.Context) (string, error) {
	templateOnce.Do(func() {
		templateName = "aaru_tmpl_" + schemaVersion()
		admin, err := pgx.Connect(ctx, connString(adminDB()))
		if err != nil {
			templateErr = fmt.Errorf("connect to test Postgres: %w", err)
			return
		}
		defer func() { _ = admin.Close(ctx) }()
		// Test packages run as parallel processes: one builds the template, the rest wait.
		if _, err := admin.Exec(ctx, `SELECT pg_advisory_lock(727274)`); err != nil {
			templateErr = err
			return
		}
		defer func() { _, _ = admin.Exec(ctx, `SELECT pg_advisory_unlock(727274)`) }()
		var exists bool
		if err := admin.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM pg_database WHERE datname = $1)`, templateName).Scan(&exists); err != nil {
			templateErr = err
			return
		}
		if exists {
			return
		}
		building := templateName + "_building"
		_, _ = admin.Exec(ctx, `DROP DATABASE IF EXISTS `+building)
		if _, err := admin.Exec(ctx, `CREATE DATABASE `+building); err != nil {
			templateErr = err
			return
		}
		pool, err := db.Open(ctx, settings(building))
		if err != nil {
			templateErr = err
			return
		}
		if err := db.Migrate(ctx, pool); err != nil {
			pool.Close()
			templateErr = err
			return
		}
		pool.Close()
		if _, err := admin.Exec(ctx, `ALTER DATABASE `+building+` RENAME TO `+templateName); err != nil {
			templateErr = err
		}
	})
	return templateName, templateErr
}

// New returns a pool on a fresh, migrated database that is dropped when the test ends.
func New(t testing.TB) *pgxpool.Pool {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	tmpl, err := ensureTemplate(ctx)
	if err != nil {
		if os.Getenv("AARU_REQUIRE_DB") == "1" {
			t.Fatalf("test database: %v", err)
		}
		t.Skipf("no test database: %v", err)
	}
	b := make([]byte, 6)
	_, _ = rand.Read(b)
	name := "aaru_t_" + hex.EncodeToString(b)
	admin, err := pgx.Connect(ctx, connString(adminDB()))
	if err != nil {
		t.Fatalf("connect: %v", err)
	}
	defer func() { _ = admin.Close(context.Background()) }()
	if _, err := admin.Exec(ctx, `CREATE DATABASE `+name+` TEMPLATE `+tmpl); err != nil {
		t.Fatalf("create test database: %v", err)
	}
	pool, err := db.Open(ctx, settings(name))
	if err != nil {
		t.Fatalf("open test database: %v", err)
	}
	t.Cleanup(func() {
		pool.Close()
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		if admin, err := pgx.Connect(ctx, connString(adminDB())); err == nil {
			_, _ = admin.Exec(ctx, `DROP DATABASE IF EXISTS `+name+` WITH (FORCE)`)
			_ = admin.Close(ctx)
		}
	})
	return pool
}
