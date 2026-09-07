# Aaru

Aaru is a private-first media library and tracking app for movies, TV shows, and books. The name comes from the Egyptian Field of Reeds: a calm place where stories live. Collaboration (shared lists, activity, live updates) is planned, but it is not part of v1.

This file is the working contract for anyone — human or agent — changing the repo.

## Product rules

- Aaru is the source of truth after import. Imports are one-way into Aaru. Do not build two-way sync or a conflict engine in v1.
- Private by default. No public profiles, friend feeds, or collaborative lists in MVP.
- Catalog metadata and user library are different layers. Never treat TMDB/Trakt/Open Library payloads as the user’s library row.
- Every saved title must store external IDs when known: `tmdb`, `imdb`, `trakt`, `tvdb`, `isbn`.
- Pogdesign CAT is a minor on-ramp (show list + optional ICS), not a first-class sync target. No CAT scraping.
- Do not mention or implement the tattoo-artist product in this repo.

## Stack

| Layer | Choice |
| --- | --- |
| API server | Hummingbird 2 (Swift, structured concurrency); routes generated from `aaru-server/Sources/AppAPI/openapi.yaml` |
| Shared code | `AaruCore` Swift package in `aaru-core/` (models, IDs, validation). No HTTP client yet |
| iOS | SwiftUI |
| Mac | SwiftUI, same app target if possible |
| Web (now) | `aaru-landing/` — marketing landing page only (Hummingbird + Mustache or Elementary, Tailwind) |
| Web (after native launch) | `aaru-site/` — logged-in library client against the same API |
| Database | PostgreSQL via Fluent (`hummingbird-fluent`) |
| Jobs | Hummingbird Jobs (or equivalent queue) for imports and hydration |
| Catalog — video | TMDB |
| Catalog — books | Open Library (Google Books only if Open Library is insufficient) |
| User import — primary | Trakt OAuth |
| User import — files | IMDb CSV, Letterboxd CSV, Goodreads CSV, CAT show list / ICS |
| User import — capture | Pasted text, image, or URL. One-shot, out-of-band, phase 1.5 |
| Agent model | Pluggable `ModelProviding` in `Server`. Anthropic default, user key supported, spend metered daily |
| Outbound agent access | App Intents in `aaru-ios`; MCP at `POST /v1/mcp` in `aaru-server/Sources/AppMCP`. Not a second backend |

## Repo layout

```text
aaru/
  aaru-core/             # AaruCore: models, IDs, validation. Shared by server and clients
  aaru-server/           # Hummingbird API
  aaru-ios/              # SwiftUI iPhone + Mac (not scaffolded)
  aaru-landing/          # marketing landing page (not scaffolded)
  aaru-site/             # logged-in web client on /v1, after native launch (not scaffolded)
  README.md
  ARCHITECTURE.md
  DESIGN.md              # what Aaru feels like: surfaces, agentic rules
  VIEWS.md               # surfaces + component catalog the agent may emit
  BACKLOG.md
  CLAUDE.md
```

Directory names are flat and lowercase. The Swift package inside `aaru-core/` is named
`AaruCore`; the directory is not.

Prefer one multiplatform SwiftUI app over two divergent clients. If split, they must share views through `AaruCore` + a thin UI module, not copy-paste.

## Commands

Adjust names if Package.swift targets differ. Do not invent new root targets without updating this file.

```bash
# Shared package
swift test --package-path aaru-core

# Server (needs Postgres: cd aaru-server && docker compose up -d)
cd aaru-server && swift run
cd aaru-server && swift test
cd aaru-server && swift run aaru --db.migrate true

# Format / lint (use whatever the repo actually configures)
swiftformat .
swiftlint
```

Never run destructive DB commands against a non-local database.

## Coding conventions

- Swift 6 / strict concurrency. No unannotated escaping of `Sendable` boundaries.
- Models that cross server and client live in `AaruCore` only. Server persistence models may wrap them; they must not diverge in meaning.
- API types are explicit `Codable` DTOs. Do not return raw TMDB/Trakt JSON to clients.
- Use structured concurrency (`async let`, task groups). Cancel in-flight work when the client disconnects.
- PostgreSQL access goes through one data layer. No ad-hoc SQL in route handlers.
- Imports are jobs, not request-path work. An import endpoint enqueues and returns a job id.
- Image posters are referenced by catalog URLs. Do not download and host TMDB/Open Library artwork in MVP unless a legal/technical need appears.
- Secrets stay in environment / server config. Never commit API keys.

## Domain language

Use these words in code, APIs, and UI:

- **Title** — a movie, show, or book in the catalog
- **Library item** — a user’s relationship to a title
- **Status** — consumption only: `wishlist` | `in_progress` | `finished` | `dropped`
- **Owned** — separate `isOwned` flag; do not overload status
- **Progress** — episode ticks for TV; page/percentage optional for books
- **List** — user-curated collection of library items, stored as membership rows
- **Shelf** — a *saved query* over library items (`saved_queries`), not membership. Shares a
  renderer with List; never shares a table. Users "pin a shelf" and "add to a list"
- **Action** — one journaled, undoable library write, whether the user or the agent made it
- **Import job** — one run of Trakt or a CSV/list ingest
- **Capture** — one-shot intake of pasted text, an image, or a URL. It is an *import source*,
  not a subsystem: it produces a `MatchTable` then a `PlanCard`, and never writes unplanned
- **Agent token** — a per-user, scoped, revocable credential an outside agent uses to reach
  Aaru's tool layer. Not an API key for a third-party developer
- **Approval** — the user's yes to a plan an agent proposed. Approval happens inside Aaru; no
  caller approves its own plan

Do not use “portfolio”, “watchlist-only”, or vendor names as the primary domain terms. Vendor names belong on `ExternalID` and import sources.

## MVP scope (build this)

1. Auth: Sign in with Apple + email/password (or magic link). Sessions/JWT as implemented in `Server`.
2. Search titles via TMDB / Open Library.
3. Add to library, set status, rating, notes.
4. TV progress by season/episode.
5. Manual lists.
6. Trakt OAuth import.
7. CSV import for IMDb, Letterboxd, Goodreads.
8. Optional CAT show-name list + ICS parse (tracked series only).
9. iOS + Mac clients on the JSON API.

## Out of scope (do not add unless asked)

- Two-way sync with Trakt/IMDb/Letterboxd
- A documented public API with third-party clients, quotas, and a deprecation policy
- Scrobbling
- Recommendations engine
- Friend graph, activity feed, collaborative lists, WebSocket presence
- Public profile pages
- AniList / MyAnimeList / Serializd / SIMKL live integrations
- Music, comics, games
- Scraping Pogdesign, IMDb pages, or any site without an official export/API
- Rebuilding the full native app as SSR before native launch

## Import order (product + matching code)

When implementing multi-source import for one account, apply in this order and skip sources the user did not connect:

1. Trakt
2. IMDb CSV
3. Letterboxd CSV
4. Goodreads CSV
5. CAT show list / ICS

Capture is **not** in this order. It is a user-triggered one-shot, applied when the user asks
and never as part of reconciling an account's connected sources.

Matching key: external IDs first, then normalized title + year + type. Never merge two titles that only share a similar name.

## Architecture

Read `ARCHITECTURE.md` before changing boundaries between `AaruCore`, `Server`, and apps.
Read `DESIGN.md` and `VIEWS.md` before adding or changing a client surface. The agent emits
only components from the `VIEWS.md` catalog; it gets no write path a user tap does not have.

When you add a source, status, or client, update this file and `ARCHITECTURE.md`.

## Agent working style

- Change the smallest surface that implements the request.
- If a task needs a new table, DTO, and client screen, do them in that order so the API stays the source of behavior.
- Update this file and `ARCHITECTURE.md` when you add a source, status, or client. Adding or
  renaming a surface or component updates `DESIGN.md` and `VIEWS.md` too.
- Do not introduce Vapor, Node, or a second backend. MCP is a transport inside `aaru-server`,
  not a service.
- Third-party agent access is per-user and token-scoped, over the same tool layer a tap uses.
  An outside caller gets no capability a signed-in session lacks: single-item writes behave
  like a tap, anything larger becomes a plan the user approves inside Aaru. See X-009 in
  `BACKLOG.md` and `ARCHITECTURE.md` §"Outbound agent surfaces".
- Do not add features “for later” as empty abstractions. Phased work belongs in docs, not unused protocols.
