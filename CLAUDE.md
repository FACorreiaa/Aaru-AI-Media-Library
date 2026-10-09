# Aaru

Aaru is a private-first media library and tracking app for movies, TV shows, anime, and books. The name comes from the Egyptian Field of Reeds: a calm place where stories live. Social features (friends, activity, encrypted DMs, watch-together), gamification, and scrobbling are planned. They are scheduled in `BACKLOG.md` phases P3–P6 and do not start until the P2 gate ("basics done") is met.

This file is the working contract for anyone — human or agent — changing the repo.

## Product rules

- Aaru is the source of truth after import. Imports and scrobbles are one-way into Aaru. Pushes to Trakt, MAL, and AniList (P3) are one-way out and are never read back as a conflict source. Do not build two-way sync or a conflict engine.
- Private by default. A new account has no visible surface. Social is opt-in per user and friends-only; there is no global feed and no public profile page.
- Catalog metadata and user library are different layers. Never treat TMDB/Trakt/Open Library/AniList payloads as the user’s library row.
- Every saved title must store external IDs when known: `tmdb`, `imdb`, `trakt`, `tvdb`, `isbn`, `anilist`, `mal`, `anidb`.
- Pogdesign CAT is a minor on-ramp (show list + optional ICS), not a first-class sync target. No CAT scraping.
- Do not mention or implement the tattoo-artist product in this repo.

## Stack

| Layer | Choice |
| --- | --- |
| API server | Hummingbird 2 (Swift, structured concurrency); routes generated from `aaru-server/Sources/AppAPI/openapi.yaml` |
| Shared code | `AaruCore` Swift package in `aaru-core/` (models, IDs, validation). No HTTP client yet |
| iOS + Mac | SwiftUI, one multiplatform target in `aaru-ios/`, plus one widget extension (iOS + macOS widgets, Live Activity, App Intents) |
| Web | `aaru-client/` — SvelteKit (Svelte 5) on Cloudflare Workers, a pure client of `/v1`. Landing pages are a route group in the same app. No DB access, no business logic |
| Database | PostgreSQL via Fluent (`hummingbird-fluent`), a StatefulSet on the `maat` cluster |
| Jobs | Hummingbird Jobs (or equivalent queue) for imports and hydration |
| Catalog — video | TMDB |
| Catalog — anime | AniList GraphQL (with MAL ids); first-class from P1 |
| Catalog — books | Open Library (Google Books only if Open Library is insufficient) |
| User import — primary | Trakt OAuth |
| User import — files | IMDb CSV, Letterboxd CSV, Goodreads CSV, CAT show list / ICS, TV Time export, MAL XML, AniList list |
| Scrobble (P3) | `POST /v1/scrobble/*` (Trakt-shaped), Plex + Jellyfin webhooks, Stremio addon (catalogs only) |
| Realtime (P6) | Hummingbird WebSocket gateway at `/v1/ws` inside `aaru-server` |
| Messaging (P6) | libsignal; server is a key directory + ciphertext mailbox only |
| Push (P4) | APNSwift, per-device environment |
| Deploy | API: GHCR image → promote PR in `~/Work/production/platform/infra` → ArgoCD on `maat` (`horus` namespace). Web: Wrangler to Workers |
| User import — capture | Pasted text, image, or URL. One-shot, out-of-band, P7 |
| Agent model | Pluggable `ModelProviding` in `Server`. Anthropic default, user key supported, spend metered daily |
| Outbound agent access | App Intents in `aaru-ios`; MCP at `POST /v1/mcp` in `aaru-server/Sources/AppMCP`. Not a second backend |

## Repo layout

```text
aaru/
  aaru-core/             # AaruCore: models, IDs, validation. Shared by server and clients
  aaru-server/           # Hummingbird API
  aaru-ios/              # SwiftUI iPhone + Mac + widget extension (not scaffolded)
  aaru-client/           # SvelteKit web on Cloudflare Workers: landing + logged-in client on /v1
  README.md
  ARCHITECTURE.md
  DESIGN.md              # what Aaru feels like: surfaces, agentic rules
  VIEWS.md               # surfaces + component catalog the agent may emit
  BACKLOG.md
  BUSINESS.md            # moat + monetisation thinking. Notes, not a plan of record
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
cd aaru-server && swift run aaru --db-migrate

# Web
cd aaru-client && npm run dev
cd aaru-client && npm run check && npm run lint
cd aaru-client && npm run test:unit -- --run

# Format / lint (use whatever the repo actually configures)
swiftformat .
swiftlint
```

Never run destructive DB commands against a non-local database.

## Release channels

One backend. **Beta is client-side only**, as in the other apps:

| Channel | Apple | Web | API |
| --- | --- | --- | --- |
| Beta | TestFlight, bundle id + `.beta`, scheme "Aaru Beta", fastlane `beta` on every merge to `main` | `wrangler.staging.jsonc` Worker, deployed on every merge to `main` | production |
| Prod | App Store, fastlane `release` on manual dispatch | `wrangler.jsonc` Worker, manual dispatch | production |

The API ships only through a merged promote PR in `~/Work/production/platform/infra`. Never
edit an app-local `*-infra/` copy. Push tokens carry their APNs environment so Beta and Prod
apps share one API. See `BACKLOG.md` REL-001…REL-006.

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

- **Title** — a movie, show, anime, or book in the catalog
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
- **Watch event** — one scrobble (start/pause/stop with progress) from a player. It may tick
  progress; it is never library truth on its own
- **Friend** — a mutual, accepted connection. There is no one-way follow
- **Points event** — one row in the append-only points ledger, idempotent by dedupe key.
  Never a counter
- **Streak** — consecutive local days with at least one progress write
- **Badge** — an award derived from points events, defined in code
- **Room** — a watch-together session: invite, countdown, reactions, shared check-off. Aaru
  does not control anyone's player
- **Conversation / Message** — an end-to-end encrypted DM thread. The server only ever holds
  ciphertext
- **Device** — one installed client, the unit for push tokens and Signal keys

Do not use “portfolio”, “watchlist-only”, or vendor names as the primary domain terms. Vendor names belong on `ExternalID` and import sources.

## Basics (P0–P2, build this first)

1. Rails: root CI, Xcode project with Beta/Release, fastlane, API on `maat`, Workers beta/prod.
2. Auth: Sign in with Apple + email/password (or magic link). Sessions/JWT as implemented in `Server`.
3. Search titles via TMDB / AniList / Open Library.
4. Add to library, set status, rating, notes.
5. TV and anime progress by season/episode; calendar and Up Next.
6. Manual lists.
7. iOS + Mac clients on the JSON API: home rows, week grid, widgets, Live Activity.
8. Web client (`aaru-client`) on the same API.
9. Trakt OAuth import; CSV import for IMDb, Letterboxd, Goodreads; CAT list + ICS; TV Time, MAL, AniList.

## Later phases (after the P2 gate, see `BACKLOG.md`)

- P3 Tracking: scrobble ingest, Plex/Jellyfin webhooks, Stremio addon (catalogs only), one-way push to Trakt/MAL/AniList
- P4 Social: profiles, friends, blocks, invites, friend activity and "Today" stories, push, shared lists
- P5 Gamification: points ledger, levels, streaks, badges, friends-only leaderboard, stats
- P6 Realtime: WebSocket gateway, libsignal DMs, watch-together rooms, SharePlay
- P7 Agent surfaces (M13/M14)

Do not write code for a later phase before the P2 gate, and do not add empty abstractions for it.

## Out of scope (do not add unless asked)

- Two-way sync with any provider, or a conflict engine
- A documented public API with third-party clients, quotas, and a deprecation policy
- Recommendations engine
- A global or public activity feed; public profile pages indexed by search engines
- Serializd / SIMKL integrations
- Music, comics, games
- Scraping Pogdesign, IMDb pages, AniDB, or any site without an official export/API
- Any Stremio `stream` resource or stream source

## Import order (product + matching code)

When implementing multi-source import for one account, apply in this order and skip sources the user did not connect:

1. Trakt
2. IMDb CSV
3. Letterboxd CSV
4. Goodreads CSV
5. CAT show list / ICS
6. TV Time export
7. MyAnimeList XML
8. AniList list

Capture is **not** in this order. It is a user-triggered one-shot, applied when the user asks
and never as part of reconciling an account's connected sources.

Scrobbles are not in this order either: they are live events, applied as they arrive.

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
- Do not introduce Vapor, a Node server, or a second backend. MCP, the Stremio addon, scrobble
  webhooks, and the WebSocket gateway are transports inside `aaru-server`, not services. The
  SvelteKit Worker is a client: it may proxy the session cookie exchange, nothing else.
- Third-party agent access is per-user and token-scoped, over the same tool layer a tap uses.
  An outside caller gets no capability a signed-in session lacks: single-item writes behave
  like a tap, anything larger becomes a plan the user approves inside Aaru. See X-009 in
  `BACKLOG.md` and `ARCHITECTURE.md` §"Outbound agent surfaces".
- Do not add features “for later” as empty abstractions. Phased work belongs in docs, not unused protocols.
