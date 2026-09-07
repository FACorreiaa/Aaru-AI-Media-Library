# Aaru

Private-first library for the movies, shows, and books you care about.

Aaru is named after the Field of Reeds — a quiet place where stories live. Track what
you want, what you are in the middle of, and what you have finished. Import the history
you already keep on Trakt, IMDb, Letterboxd, Goodreads, or a Pogdesign CAT show list.
Collaboration comes later. The library has to be good alone first.

Native iPhone and Mac clients talk to a Hummingbird API. One Swift package
(`AaruCore`) holds the shared types.

## Status

Early scaffolding. `AaruCore` holds the domain model and its tests. `aaru-server` is a
Hummingbird skeleton — configuration, Postgres, and OpenAPI wiring are in place, but the
only route is the template `getHello`. The clients, the landing page, and the web app
are empty directories.

| Phase | What ships |
| --- | --- |
| 1 — MVP | Auth, search, personal library, TV episode progress, lists, one-way imports, iOS + Mac |
| 2 | Shared lists (explicit, private-by-default) |
| 3 | Realtime collaboration |

## Stack

- **Server**: Hummingbird 2 + PostgreSQL (Fluent) + background import jobs
- **Shared**: `AaruCore` — models, IDs, validation
- **Clients**: SwiftUI on iOS and Mac (prefer one multiplatform target)
- **Web now**: marketing landing page (Hummingbird + Mustache or Elementary, Tailwind)
- **Web later**: logged-in library against the same `/v1` API
- **Catalog**: TMDB (movies, TV), Open Library (books)
- **Imports**: Trakt OAuth, then IMDb / Letterboxd / Goodreads CSV, then CAT list or ICS

Aaru is the source of truth after import. No two-way sync in v1. No scraping.

## Repo layout

```text
aaru/
  aaru-core/       AaruCore package — models, IDs, validation (shared by server and clients)
  aaru-server/     Hummingbird 2 API — auth, library, search, lists, import jobs
  aaru-ios/        SwiftUI client, iPhone + Mac              (not scaffolded)
  aaru-landing/    marketing landing page                     (not scaffolded)
  aaru-site/       logged-in web client on /v1, after native launch (not scaffolded)
  README.md
  CLAUDE.md
  ARCHITECTURE.md
```

## Docs

- [`CLAUDE.md`](CLAUDE.md) — working contract: rules, scope, conventions, commands
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — system design, data model, routes, import pipeline
- [`aaru-core/README.md`](aaru-core/README.md) — the shared types and the conventions they fix
- [`aaru-server/README.md`](aaru-server/README.md) — running the API

Read those before changing boundaries between core, server, and apps.

## Product rules (short)

- Catalog metadata and the user's library are different layers.
- Every saved title stores external IDs when known: `tmdb`, `imdb`, `trakt`, `tvdb`, `isbn`.
- Consumption status is `wishlist` | `in_progress` | `finished` | `dropped`. Ownership is
  a separate `isOwned` flag.
- Pogdesign CAT is a minor on-ramp (names + optional calendar file), not a live sync target.

Import merge order when several sources are connected:
Trakt → IMDb CSV → Letterboxd CSV → Goodreads CSV → CAT.

## Development

```bash
# shared package
swift test --package-path aaru-core

# server (Postgres from docker-compose)
cd aaru-server
docker compose up -d
swift test
swift run
```

You will need:

- Swift 6 (the packages declare `swift-tools-version:6.3`)
- PostgreSQL — `aaru-server/docker-compose.yml` starts one
- TMDB API key
- Trakt API client (for the OAuth importer)
- Xcode for the iOS and Mac apps

Never commit provider secrets. Never run destructive database commands against a
non-local database.

## What v1 will not include

Two-way sync, scrobbling, recommendations, friend feeds, public profiles,
AniList/MAL/SIMKL live integrations, music/comics/games, or a full web clone of the
native apps before those apps ship.

## License

TBD.
