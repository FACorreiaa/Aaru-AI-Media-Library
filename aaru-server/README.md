# aaru-server

The Aaru API. Hummingbird 2, Swift 6, PostgreSQL. It owns auth, the user's library,
catalog search, lists, and import jobs — everything the iOS and Mac clients are not
allowed to do themselves.

Native apps talk only to this server. TMDB and Trakt keys, rate limits, and provider ID
mapping stay here.

See [`../ARCHITECTURE.md`](../ARCHITECTURE.md) for the data model and the import
pipeline, and [`../aaru-core/README.md`](../aaru-core/README.md) for the shared types.

## Status

M1 foundation (`BACKLOG.md` SRV-001…SRV-009). The `/v1` spec skeleton with the shared
`ErrorResponse` shape, the data layer (`Sources/App/Data`), migrations for users, titles,
library, lists, and import jobs, fail-fast config, and `GET /v1/health`. No business routes
yet — those start with M2 auth.

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
| `tmdb.api.key` | `TMDB_API_KEY` | required to serve |
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
  API/                          handlers (APIImplementation), AppError, ErrorMiddleware
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

## Planned routes

From `ARCHITECTURE.md`. None are implemented yet; the prefix is `/v1`.

```text
POST   /v1/auth/apple                 POST   /v1/library/items
POST   /v1/auth/email/...             GET    /v1/library/items/{id}
DELETE /v1/auth/session               PATCH  /v1/library/items/{id}
                                      DELETE /v1/library/items/{id}
GET    /v1/search?q=&type=            PUT    /v1/library/items/{id}/episodes/{season}/{episode}
GET    /v1/titles/{id}                POST   /v1/library/items/{id}/seasons/{season}/watched
GET    /v1/library/items

GET    /v1/lists                      GET    /v1/imports
POST   /v1/lists                      POST   /v1/imports/trakt/connect
POST   /v1/lists/{id}/items           GET    /v1/imports/trakt/callback
DELETE /v1/lists/{id}/items/{itemId}  POST   /v1/imports/csv
                                      POST   /v1/imports/cat
                                      GET    /v1/imports/{id}
```

Imports are jobs. An import endpoint enqueues work and returns a job id; it never parses
a CSV on the request path.
