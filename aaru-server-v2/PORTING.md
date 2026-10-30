# Porting aaru-server (Swift) to aaru-server-v2 (Go)

aaru-server-v2 is a 1:1 port of `aaru-server`: same routes, same JSON, same
status codes and error codes, same database, same environment variables, same
background work. A client must not be able to tell which one answered. Once the
port is complete the Swift server is archived and **all new server code goes
here**.

## Ground rules

- **Behaviour comes from the Swift source.** Read the Swift files for your area
  (handlers in `aaru-server/Sources/App/API/*Handlers.swift`, services in
  `Sources/App/<Area>/`, stores in `Sources/App/Data/Fluent/Postgres*Store*.swift`,
  shared models in `aaru-core/Sources/AaruCore/`) and port the rules, limits,
  messages and edge cases exactly. Error messages are user-visible: copy them.
- **Tests come from the Swift tests.** `aaru-server/Tests/AppTests/<Area>Tests*.swift`
  describe the behaviour; port them to Go (`testify`, table-driven where it
  fits). Tests run against a real Postgres via `internal/testdb` (no fake stores).
- **Do not edit**: `aaru-server/` (Swift), `openapi.yaml`, generated code
  (`internal/api/api.gen.go`, `internal/db/sqlc/*`), the baseline schema.
- **Product rules in the repo root `CLAUDE.md` still apply** (domain language,
  import merge rules, privacy rules, the Haiku trial rules for model calls).

## Layout

| Path | What |
| --- | --- |
| `cmd/aaru` | the binary; `--db-migrate`, `--anime-mappings`, else serve |
| `internal/app` | wiring: config → pool → services → router → workers |
| `internal/config` | every env var the Swift `AppConfig` read, same names |
| `internal/api` | **generated** types + echo strict server from `openapi.yaml` (`make api`) |
| `internal/httpapi` | handlers: `Server` implements `api.StrictServerInterface`; one file per Swift handler file (`library.go` ← `LibraryHandlers.swift`) |
| `internal/httpapi/stub_*.go` | 501 placeholders. **Delete a method when you implement it; delete the file when empty** |
| `internal/httpapi/raw_routes.go` | routes outside the strict server (Stremio, MCP, scrobble, ListenBrainz, OAuth, ws, the three multi-type imports) |
| `internal/middleware` | log, metrics, error shape, auth, time zone, avatar cache |
| `internal/apperr` | the `ErrorResponse` error type |
| `internal/apitime` | the `date-time` wire type (whole seconds, UTC) |
| `internal/reqctx` | user id, session hash, client address, time zone from the request |
| `internal/token` | opaque tokens and their hashes |
| `internal/db` | pool, goose migrations (`migrations/`), sqlc queries (`queries/`) → `sqlc/` |
| `internal/testdb` | a fresh migrated database per test |
| `internal/core` | AaruCore's models and rules (media types, statuses, external ids, ratings, matching) |
| `internal/<area>` | a domain service per Swift area (`library`, `catalog`, `imports`, `social`, …) |

## Conventions

- **Handlers are thin.** Decode the request object, call a service, map to the
  generated response type. Rules live in `internal/<area>`, never in handlers.
- **Services** are structs built from their dependencies (`*sqlc.Queries`,
  `*pgxpool.Pool` for transactions, other services, provider clients); no globals.
  Add the service to `httpapi.Deps` and build it in `internal/app/app.go`.
- **SQL** lives in `internal/db/queries/<area>.sql` and is generated with
  `go tool sqlc generate`. Use `sqlc.narg`/`sqlc.slice` for optional filters.
  Only when sqlc truly cannot express a query (a dynamic ORDER BY, a bulk
  `unnest` it rejects), write it with pgx in `internal/<area>/store.go`, with a
  comment saying why. Transactions: `pgx.BeginFunc(ctx, pool, func(tx pgx.Tx) error { q := queries.WithTx(tx) ... })`.
- **Errors**: return `*apperr.Error` (or a type implementing `apperr.Convertible`)
  for anything a client should see; wrap everything else with
  `fmt.Errorf("...: %w", err)`. Never swallow an error.
- **Dates** in DTOs are `apitime.Time` (generated). Use `apitime.From(t)`.
- **Ids** in DTOs are `apiid.UUID` (generated): written uppercase like Swift's
  `uuidString`, read leniently (malformed → `uuid.Nil` → the route's 404). Use
  `apiid.From`, `.ID()`, `apiid.Slice`/`IDs`/`PtrOrNil`. Never hand an
  `apiid.UUID` to pgx. An id you format into a string (a path, a URL) is uppercase.
- **Text length** is Swift's `String.count`: grapheme clusters. Count with `core.Length`
  and cut with `core.Prefix`, never `len`, `utf8.RuneCountInString` or `[]rune`.
- **Request shape** is checked by `middleware.Validate` before handlers run
  (required fields, types, enums → 400 `bad_request`); length/range limits are
  not, so handlers enforce those with the Swift messages.
- **The signed-in user**: `currentUser(ctx)` in handlers; services take a
  `uuid.UUID` user id. Client time zone: `reqctx.TimeZone(ctx)`.
- **Outbound HTTP** (catalogs, Trakt, MAL, Anthropic, APNs, …) goes through the
  shared provider client (`internal/provider`): per-provider pacing, typed
  `ProviderError` that maps to 502 `provider_unavailable`. Tests use
  `httptest.Server` stubs, never a real key or a real network call.
- **Model calls** (Anthropic): never send `temperature`, `top_p`, `top_k` or an
  assistant prefill (Haiku 5.5 rejects them; see the root `CLAUDE.md`).
- **Background work** implements `httpapi.Worker` (`Name()`, `Run(ctx)`) and is
  appended in `internal/httpapi/workers.go`. Leasing jobs uses
  `FOR UPDATE SKIP LOCKED`, as the Swift workers did.
- **Metrics**: `internal/metrics` counters keep the Swift names and labels.
- **Profiling**: Go's pprof is on the internal port next to `/metrics` (`METRICS_PORT`, 9090),
  never on the API port. Flame graph: `kubectl port-forward <pod> 9090`, then
  `go tool pprof -http=:0 http://localhost:9090/debug/pprof/profile?seconds=30` (or `/heap`,
  `/goroutine`, `/trace`). `PPROF_ENABLED=false` turns it off; `PPROF_BLOCK_RATE` and
  `PPROF_MUTEX_FRACTION` sample contention.
- **Concurrency**: `errgroup` for independent calls; respect `ctx` cancellation.
- Format with `gofumpt`; `go vet ./...` and `golangci-lint run` must be clean.

## Running

```bash
docker compose up -d                 # Postgres for tests (hb/testing123 on 5432)
make generate                        # after an openapi.yaml or query change
make test                            # AARU_REQUIRE_DB=1 to fail instead of skip without Postgres
POSTGRES_USER=hb POSTGRES_PASSWORD=testing123 POSTGRES_DATABASE=hb TMDB_API_KEY=x go run ./cmd/aaru
```

## Database

`internal/db/migrations/baseline.sql` is the schema the Swift server's 60 Fluent
migrations built (pg_dump). Migration 1 adopts an existing Swift database as is
(it has `_fluent_migrations`) and creates the schema on an empty one. New schema
changes are new goose files: `internal/db/migrations/00002_<what>.sql` with
`-- +goose Up` / `-- +goose Down`.
