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
| `cmd/aaru` | the binary; `--db-migrate`, `--anime-mappings`, `--seed-review` (REL-008), else serve |
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
- **Concurrency**: `safe.WithContext` for independent calls (`errgroup` whose goroutines turn a panic into the group's error; depguard refuses a raw `errgroup`); respect `ctx` cancellation.
- **Request limits**: `ownBodyLimits` in `internal/httpapi/router.go` caps each route's body, and a body that stalls is cut off after `bodyReadTimeout` (`uploadReadTimeout` for uploads). `noDeadline` lists routes that may outlast the normal request deadline: the socket, uploads, the export, MCP calls, and one-transaction writes over a whole library (import or plan approval, undo, account deletion).
- **Long statements**: Postgres ends a statement at the pool's `statement_timeout` and an idle transaction at `idle_in_transaction_session_timeout`. Work known to run longer says so inside its transaction: `db.AllowLongStatements`, or `db.AllowIdleInTransaction` for a transaction held across an outbound call.
- **Paging**: never `arg IS NULL OR col < arg` on a large table. Under a generic plan the index cannot use that bound and each page walks from the first row; use `col < coalesce(arg, 'infinity')`.
- Format with `gofumpt`; `go vet ./...` and `golangci-lint run` must be clean.

## Settings

Every Swift setting keeps its name and meaning (`aaru-server/README.md` has the table).
`POSTGRES_POOL_TIMEOUT` is, as in Swift, the seconds a query waits for a free connection: the
pool's acquire is bounded by it (and dialing a new connection too); a request that waits longer
answers 503 `timeout`. The port adds these, each env-driven so it can be relaxed without code:

| Key | Env | Default |
| --- | --- | --- |
| `postgres.statement.timeout` | `POSTGRES_STATEMENT_TIMEOUT` | `30` seconds, Postgres' `statement_timeout` on the API's connections; `0` leaves the server's. `--db-migrate` and `--anime-mappings` never set it |
| `postgres.idle.transaction.timeout` | `POSTGRES_IDLE_TRANSACTION_TIMEOUT` | `60` seconds, `idle_in_transaction_session_timeout`; `0` leaves the server's. Not set by the one-shot modes |
| `http.request.timeout` | `HTTP_REQUEST_TIMEOUT` | `30` seconds a request may run (503 `timeout` after); `0` turns it off. Not applied to `/v1/ws`, the uploads (`/v1/imports/csv`, `cat`, `capture`, `PUT /v1/me/avatar`, ListenBrainz `submit-listens`), `GET /v1/me/export`, `/v1/mcp`, an import's apply and undo, and `DELETE /v1/me` |
| `apple.signin.private.key`, `apple.signin.key.id`, `apple.signin.token.key` | `APPLE_SIGNIN_PRIVATE_KEY`, `APPLE_SIGNIN_KEY_ID`, `APPLE_SIGNIN_TOKEN_KEY` | unset: Sign in with Apple tokens are neither kept nor revoked (AUTH-006). All three or none, else boot is refused: the .p8 of a key with Sign in with Apple enabled, its key id, and 32 bytes of base64 that seal the refresh tokens |
| `apple.signin.team.id` | `APPLE_SIGNIN_TEAM_ID` | `APNS_TEAM_ID`, else `84X9WYBF36` |
| `apple.signin.client.ids` | `APPLE_SIGNIN_CLIENT_IDS` | `APPLE_AUDIENCES`: the bundle ids and Services IDs the key signs for. A sign-in for any other is not exchanged |
| `trusted.proxy.hops` | `TRUSTED_PROXY_HOPS` | `1`: proxies in front of the API that append to `X-Forwarded-For` (Traefik). The caller is that many entries from the right; `0` uses the socket peer |

Request bodies are at most 1 MiB, except the routes in `ownBodyLimits`
(`internal/httpapi/router.go`), which read with their own bound and message, and capture's JSON,
128 KiB. Every response carries `X-Request-Id`, and every log line written with a request's
context carries it as `requestId`; a request is logged once, when answered (`Request` at
arrival is Debug). A request the client abandoned is logged at Info as a 499 and not reported.

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
