# aaru-server (archived)

> **Archived.** The Aaru API is now [`aaru-server-v2`](../aaru-server-v2) (Go: echo, pgx, sqlc,
> goose), a 1:1 port of this server. Add no code here. This package is kept for two things only:
> `Sources/AppAPI/openapi.yaml`, the one spec every client and the Go server generate from, and
> the `swift-openapi-generator` that `scripts/generate-api-client.sh` runs for `aaru-api`. Its
> Swift sources stay as the reference the port was made from; CI no longer builds or tests them.

The Aaru API. Hummingbird 2, Swift 6, PostgreSQL. It owns every rule: auth, the user's
library and progress, catalog search, lists and shelves, imports, the calendar and Up Next,
stats, and the action journal with undo.

The iOS and Mac apps and the web Worker (`aaru-client`) talk only to this server, through the
same `/v1` routes. The Worker's `createServerFn` functions are adapters that attach the session
and call `/v1`; they hold no business logic. TMDB, AniList, Open Library, TVmaze and Trakt keys,
rate limits, and provider ID mapping stay here.

See [`../ARCHITECTURE.md`](../ARCHITECTURE.md) for the data model and the import
pipeline, and [`../aaru-core/README.md`](../aaru-core/README.md) for the shared types.

## Status

In production at `api.aaruapp.com` (deployed through `platform/infra`, see `../CLAUDE.md`).
52 operations in `Sources/AppAPI/openapi.yaml`, listed under [Routes](#routes); `BACKLOG.md`
tracks what each ticket added.

## Running it

```bash
docker compose up -d          # Postgres on 5432
swift run                     # serves on the configured host/port
swift test                    # needs the database up
```

Migrations run as a separate invocation and exit — see `Sources/App/App+build.swift`:

```bash
swift run aaru --db-migrate
```

It is re-runnable: applied migrations are recorded in `_fluent_migrations`. It needs only
the Postgres settings, not `TMDB_API_KEY`.

Docker build for deployment. The build context is the **repo root**, because the server
depends on `../aaru-core`:

```bash
docker build -f aaru-server/Dockerfile -t aaru-server .
```

## Configuration

`Sources/App/App.swift` reads settings in this order, first hit wins:

1. Command line arguments — `--postgres-host 10.0.0.2` (dots become dashes)
2. Environment variables — `POSTGRES_HOST`
3. `.env` in the working directory (optional)
4. In-memory defaults

| Key | Env | Default |
| --- | --- | --- |
| `postgres.host` | `POSTGRES_HOST` | `127.0.0.1` |
| `postgres.port` | `POSTGRES_PORT` | `5432` |
| `postgres.user` | `POSTGRES_USER` | required |
| `postgres.password` | `POSTGRES_PASSWORD` | required |
| `postgres.database` | `POSTGRES_DATABASE` | required |
| `postgres.pool.size` | `POSTGRES_POOL_SIZE` | `10` connections per process (keep size × replicas under `max_connections`) |
| `postgres.pool.timeout` | `POSTGRES_POOL_TIMEOUT` | `10` seconds a query waits for a free connection |
| `imports.workers` | `IMPORTS_WORKERS` | `1` concurrent import jobs per process (1–8) |
| `agent.reply.workers` | `AGENT_REPLY_WORKERS` | `1` concurrent `@aaru` replies per process (1–8) |
| `tmdb.api.key` | `TMDB_API_KEY` | required to serve |
| `apple.audiences` | `APPLE_AUDIENCES` | `com.fernandocorreia.aaru,com.fernandocorreia.aaru.beta` (add the web Services ID) |
| `resend.api.key` | `RESEND_API_KEY` | unset → email sign-in answers 503 |
| `email.from` | `EMAIL_FROM` | `Aaru <signin@aaruapp.com>` |
| `magic.link.base.url` | `MAGIC_LINK_BASE_URL` | `https://aaruapp.com/auth/verify` |
| `google.client.ids` | `GOOGLE_CLIENT_IDS` | empty → Google sign-in refused (comma-separated OAuth client ids) |
| `apns.private.key` | `APNS_PRIVATE_KEY` | unset → no pushes |
| `apns.key.id` | `APNS_KEY_ID` | required when the private key is set |
| `apns.team.id` | `APNS_TEAM_ID` | `84X9WYBF36` |
| `vapid.config` | `VAPID_CONFIG` | unset → no browser alerts (`/v1/web-push/key` answers 503). swift-webpush's VAPID JSON; generate once, a new key drops every subscription |
| `trakt.client.id` | `TRAKT_CLIENT_ID` | unset → Trakt connect answers 503 |
| `trakt.token.key` | `TRAKT_TOKEN_KEY` | required with Trakt: 32 bytes, base64, encrypts tokens at rest |
| `trakt.redirect.uri` | `TRAKT_REDIRECT_URI` | `https://api.aaruapp.com/v1/imports/trakt/callback` |
| `open.library.user.agent` | `OPEN_LIBRARY_USER_AGENT` | `Aaru/0.1 (media library; contact: signin@aaruapp.com)` |
| `metrics.secret` | `METRICS_SECRET` | empty → `GET /internal/metrics` answers 404. The bearer facorreia.com/apps sends for the user count |
| `metrics.port` | `METRICS_PORT` | 9090. `GET /metrics` (Prometheus text) on its own listener, for the cluster's Alloy only: not in the Service or the Ingress. 0 turns it off |
| `sentry.dsn` | `SENTRY_DSN` | empty → server errors are only logged. Set: each 5xx goes to Sentry with its route template, status and error type; never the path, query, headers, body or user |
| `sentry.environment` | `SENTRY_ENVIRONMENT` | `production` |
| `aaru.release` | `AARU_RELEASE` | the image's commit (Docker build arg, set by `server-deploy.yml`) |
| `posthog.project.token` | `POSTHOG_PROJECT_TOKEN` | empty → no product events. Set: the events in `ProductEvent`, by account id, with no person profiles |
| `posthog.host` | `POSTHOG_HOST` | `https://eu.i.posthog.com` |
| `log.level` | `LOG_LEVEL` | `info` |
| `http.serverName` | — | `aaru-server` |
| `db.migrate` | `DB_MIGRATE` (`--db-migrate`) | unset |

A missing required key stops boot with `MissingConfigError` naming the environment
variable. Keys are added with the ticket that reads them (Trakt with IMP-002, session
signing with AUTH-001). `.env` is git-ignored and holds local docker-compose credentials
only; real provider secrets live in the environment and are never committed.

## Layout

```text
Sources/App/         executable target `aaru`
  App.swift                     entry point, configuration reader
  App+build.swift               application, router, Fluent setup, migrate mode
  API/                          handlers (APIImplementation + one *Handlers.swift per area)
  Auth/                         Apple, Google, email sign-in; sessions
  Catalog/                      TMDB, AniList, Open Library, TVmaze; title resolution
  Library/                      library and list services; LibraryOp, the journaled write
  Schedule/                     calendar and Up Next
  Stats/                        period stats for the Recap
  Imports/, Trakt/              import parsing, plans, jobs; Trakt OAuth
  Export/, Push/, HTTP/         account export; APNs; outbound HTTP
  Config/AppConfig.swift        typed config, fail-fast on missing keys
  Data/Stores.swift             the data layer boundary: store protocols handlers depend on
  Data/Fluent/                  Postgres implementations (the only SQL outside migrations)
  Data/Migrations/              schema, raw SQL, in apply order
Sources/AppAPI/      target `aaruAPI`
  openapi.yaml                  the API contract — routes start here
  openapi-generator-config.yaml types + server, package access
Tests/AppTests/      swift-testing suite (API contract with fake stores; Postgres-backed store tests)
```

## How a route gets added

Routes are generated from the OpenAPI document, not hand-registered.

1. Describe the operation in `Sources/AppAPI/openapi.yaml`.
2. Build — the generator plugin adds the requirement to `APIProtocol`.
3. Implement it in `APIImplementation.swift`; the compiler tells you what is missing.
4. Data access goes through a protocol in `Data/Stores.swift`. No `Fluent`, `SQLKit`, or
   `Database` symbol appears in a handler file. Throw `AppError` or an `AaruCore`
   `ValidationError`; `ErrorMiddleware` renders the shared error shape.

Generated types are `package`-access and cannot leave `aaruAPI`. Anything a client also
needs is a hand-written type in `AaruCore`.

## Dependencies

| Package | Why |
| --- | --- |
| hummingbird 2.25 | HTTP server, routing, middleware |
| hummingbird-fluent, fluent-kit, fluent-postgres-driver | Postgres access and migrations |
| swift-configuration | Layered config (CLI → env → `.env` → defaults) |
| swift-openapi-generator / -runtime / swift-openapi-hummingbird | Routes and DTOs from `openapi.yaml` |
| `../aaru-core` | Shared domain types |

`AaruCore` is a relative path dependency, so `aaru-core/` must stay a sibling of this
directory. CI lives at the repo root (`.github/workflows/ci.yml`).

## Routes

`Sources/AppAPI/openapi.yaml` is the source of truth; this list is a map of it.

```text
GET    /v1/health
GET    /internal/metrics                    # plain router, not OpenAPI: {"users":N}, METRICS_SECRET bearer
GET    /metrics                             # METRICS_PORT only (9090), never the API port: Prometheus text

POST   /v1/auth/apple                       GET    /v1/me
POST   /v1/auth/google                      DELETE /v1/me
POST   /v1/auth/email/link                  GET    /v1/me/export          # JSON or CSV
POST   /v1/auth/email/verify                GET    /v1/me/stats           # Recap: ?year=&month=&tz=
DELETE /v1/auth/session                     GET    /v1/me/notifications
POST   /v1/me/identities/google             PUT    /v1/me/notifications
PUT    /v1/devices                          DELETE /v1/devices/{token}

GET    /v1/search?q=&type=                  GET    /v1/titles/{id}

GET    /v1/library/items                    PUT    /v1/library/items/{id}/episodes/{season}/{episode}
POST   /v1/library/items                    POST   /v1/library/items/{id}/seasons/{season}/watched
GET    /v1/library/items/{id}               GET    /v1/library/sync
PATCH  /v1/library/items/{id}               GET    /v1/actions
DELETE /v1/library/items/{id}               POST   /v1/actions/{id}/undo

GET    /v1/lists                            POST   /v1/lists/{id}/items
POST   /v1/lists                            DELETE /v1/lists/{id}/items/{titleId}
GET    /v1/lists/{id}                       PUT    /v1/lists/{id}/order
PATCH  /v1/lists/{id}                       DELETE /v1/lists/{id}

GET    /v1/shelves                          DELETE /v1/shelves/{id}
POST   /v1/shelves                          GET    /v1/shelves/{id}/items
PATCH  /v1/shelves/{id}

GET    /v1/imports                          POST   /v1/imports/trakt
POST   /v1/imports/csv                      POST   /v1/imports/trakt/connect
POST   /v1/imports/anilist                  GET    /v1/imports/trakt/connection
GET    /v1/imports/{id}                     DELETE /v1/imports/trakt/connection
DELETE /v1/imports/{id}                     GET    /v1/imports/trakt/callback  # plain router, not OpenAPI
POST   /v1/imports/{id}/apply

GET    /v1/calendar?from=&to=               GET    /v1/up-next
```

Imports are jobs. An import endpoint enqueues work and returns a job id; it never parses
a file on the request path. Applying a plan is one journaled, undoable action.
