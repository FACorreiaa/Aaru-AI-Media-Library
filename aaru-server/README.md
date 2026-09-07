# aaru-server

The Aaru API. Hummingbird 2, Swift 6, PostgreSQL. It owns auth, the user's library,
catalog search, lists, and import jobs — everything the iOS and Mac clients are not
allowed to do themselves.

Native apps talk only to this server. TMDB and Trakt keys, rate limits, and provider ID
mapping stay here.

See [`../ARCHITECTURE.md`](../ARCHITECTURE.md) for the data model and the import
pipeline, and [`../aaru-core/README.md`](../aaru-core/README.md) for the shared types.

## Status

Skeleton. Configuration, logging, Postgres, OpenAPI wiring, and the test harness work.
The only implemented route is the template `getHello`. Nothing in `ARCHITECTURE.md`'s
route map is built yet.

## Running it

```bash
docker compose up -d          # Postgres on 5432
swift run                     # serves on the configured host/port
swift test                    # needs the database up
```

Migrations run as a separate invocation and exit — see `Sources/App/App+build.swift`:

```bash
swift run aaru --db.migrate true
```

There are no migrations registered yet, so today this is a no-op that exits 0.

Docker build for deployment:

```bash
docker build -t aaru-server .
```

## Configuration

`Sources/App/App.swift` reads settings in this order, first hit wins:

1. Command line arguments — `--postgres.host 10.0.0.2`
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
| `log.level` | `LOG_LEVEL` | `info` |
| `http.serverName` | — | `aaru-server` |
| `db.migrate` | `DB_MIGRATE` | unset |

The checked-in `.env` holds the local docker-compose credentials only. Real provider
secrets — TMDB, Trakt — belong in the environment and must never be committed.

## Layout

```text
Sources/App/         executable target `aaru`
  App.swift                     entry point, configuration reader
  App+build.swift               application, router, WebSocket router, Fluent setup
  APIImplementation.swift       conformance to the generated APIProtocol
  OpenAPIRequestContextMiddleware.swift   puts the request context in a TaskLocal
Sources/AppAPI/      target `aaruAPI`
  openapi.yaml                  the API contract — routes start here
  openapi-generator-config.yaml types + server, package access
Tests/AppTests/      swift-testing suite
```

## How a route gets added

Routes are generated from the OpenAPI document, not hand-registered.

1. Describe the operation in `Sources/AppAPI/openapi.yaml`.
2. Build — the generator plugin adds the requirement to `APIProtocol`.
3. Implement it in `APIImplementation.swift`; the compiler tells you what is missing.
4. Data access goes through the Fluent layer, never ad-hoc SQL in the handler.

Generated types are `package`-access and cannot leave `aaruAPI`. Anything a client also
needs is a hand-written type in `AaruCore`.

## Dependencies

| Package | Why |
| --- | --- |
| hummingbird 2.25 | HTTP server, routing, middleware |
| hummingbird-fluent, fluent-kit, fluent-postgres-driver | Postgres access and migrations |
| swift-configuration | Layered config (CLI → env → `.env` → defaults) |
| swift-openapi-generator / -runtime / swift-openapi-hummingbird | Routes and DTOs from `openapi.yaml` |
| hummingbird-websocket | Phase 3 only; currently template scaffolding |
| `../aaru-core` | Shared domain types |

`AaruCore` is a relative path dependency, so `aaru-core/` must stay a sibling of this
directory. If this ever becomes a standalone git repository, `.github/workflows/ci.yml`
will fail until AaruCore is published as a git dependency instead.

## Template leftovers

Scaffolding from the Hummingbird template, kept only until real routes land. Delete
them then; do not build on them.

- `getHello` — `GET /` returning `Hello!`, in `openapi.yaml` and `APIImplementation.swift`.
- The `/ws` echo endpoint in `buildWebSocketRouter`. `ARCHITECTURE.md` puts WebSockets in
  Phase 3, after shared lists are actually used.

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
