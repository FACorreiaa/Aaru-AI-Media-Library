# Aaru

Aaru is a private-first media library and tracking app for movies, TV shows, anime, and books. The name comes from the Egyptian Field of Reeds: a calm place where stories live. Social features (friends, activity, encrypted DMs, watch-together), gamification, and scrobbling are planned. They are scheduled in `BACKLOG.md` phases P3–P6 and do not start until the P2 gate ("basics done") is met.

This file is the working contract for anyone — human or agent — changing the repo.

## Product rules

- Aaru is the source of truth after import. Imports and scrobbles are one-way into Aaru. Pushes to Trakt, MAL, and AniList (P3) are one-way out and are never read back as a conflict source. Do not build two-way sync or a conflict engine.
- Private by default. A new account has no visible surface. Social is opt-in per user and friends-only; there is no global feed and no public profile page. Groups are friends-only too: no invite links, no public or discoverable groups.
- Group messages are server-visible and every channel says "not end-to-end". DMs are end-to-end and the server never reads them. Never blur the two.
- Catalog metadata and user library are different layers. Never treat TMDB/Trakt/Open Library/AniList payloads as the user’s library row.
- Every saved title must store external IDs when known: `tmdb`, `imdb`, `trakt`, `tvdb`, `isbn`, `anilist`, `mal`, `anidb`.
- Pogdesign CAT is a minor on-ramp (show list + optional ICS), not a first-class sync target. No CAT scraping:
  the one request Aaru makes to pogdesign.co.uk is reading the user's own iCal export link, once, when they
  paste it (owner, 2026-10-21). Every CAT show is planned as `wishlist`; CAT's watched episodes do not come across.
- Do not mention or implement the tattoo-artist product in this repo.

## Stack

| Layer | Choice |
| --- | --- |
| API server | Hummingbird 2 (Swift, structured concurrency); routes generated from `aaru-server/Sources/AppAPI/openapi.yaml` |
| Shared code | `AaruCore` Swift package in `aaru-core/` (models, IDs, validation). No HTTP client in it |
| API client (Apple) | `AaruAPI` Swift package in `aaru-api/`: the `/v1` client generated from the server's `openapi.yaml` and committed, plus session middleware. Regenerate with `scripts/generate-api-client.sh`; CI fails if stale |
| iOS + Mac | SwiftUI, one multiplatform target in `aaru-ios/`, plus one widget extension (iOS + macOS widgets, Live Activity, App Intents) |
| Web | `aaru-client/` — SolidJS + TanStack Start on Cloudflare Workers, a pure client of `/v1` with the same functionality as the Apple apps. Landing page + sign-in + the signed-in app in one Worker. API types generated from `openapi.yaml` (`npm run api:generate`). UI primitives in `src/components/ui` (solid-ui's shapes on native elements, no Kobalte), animation through `motion/mini` (DESIGN.md §17). No DB access, no business logic |
| Database | PostgreSQL via Fluent (`hummingbird-fluent`), a StatefulSet on the `maat` cluster |
| Jobs | Hummingbird Jobs (or equivalent queue) for imports and hydration |
| Catalog — video | TMDB (also trending, on the air, new shows, in theaters for Discover) |
| Catalog — anime | AniList GraphQL (with MAL ids); first-class from P1; this season + trending for Discover |
| Catalog — air times | TVmaze (no key, CC BY-SA): exact air times and network for TMDB shows; TMDB stays the episode source |
| Catalog — books | Open Library (Google Books only if Open Library is insufficient); weekly trending for Discover |
| User import — primary | Trakt OAuth; Stremio history by link code (one library read, then logout; key never stored) |
| User import — files | IMDb CSV, Letterboxd CSV, Goodreads CSV, CAT show list / ICS file or iCal link, Netflix viewing activity CSV (one profile), TV Time export, MAL-format XML (MyAnimeList, Kitsu, AniList exports), AniList list by username, any other CSV read by its column names; `source=auto` detects the format |
| Scrobble (P3) | `POST /v1/scrobble/*` (Trakt-shaped), Plex + Jellyfin webhooks, Stremio addon (catalogs + `player`/`library` events, no `stream`; pulled forward 2026-10-19) |
| Realtime | Hummingbird WebSocket gateway at `/v1/ws` inside `aaru-server`; group envelopes first (GRP-006, pulled forward 2026-10-20), presence and DM delivery in P6. The web connects with a short-lived ticket because its session is cookie-only |
| Groups | Friends-only spaces with channels (`text`, `title`, `watch`, `shelf`) and `#general`. Server-visible messages in Postgres; `@aaru` replies through `ModelProviding` (pulled forward 2026-10-20) |
| Messaging (P6) | libsignal; server is a key directory + ciphertext mailbox only |
| Push | APNSwift, per-device environment; web push (VAPID, `swift-webpush`) to browsers. Airing alerts pulled into P2 (2026-10-15, web 2026-10-20); group mention and invite alerts with groups (GRP-012) |
| Deploy | API: GHCR image → promote PR in `~/Work/production/platform/infra` → ArgoCD on `maat` (`horus` namespace). Web: Wrangler to Workers |
| User import — capture | Pasted text, image, or URL. One-shot, out-of-band, P7 |
| Agent model | Pluggable `ModelProviding` in `Server`. Anthropic default, user key supported, spend metered daily |
| Outbound agent access | App Intents in `aaru-ios`; MCP at `POST /v1/mcp` in `aaru-server/Sources/App/MCP`, with an OAuth front door (`Sources/App/OAuth`) so Claude can add Aaru as a custom connector. Not a second backend |

## Repo layout

```text
aaru/
  aaru-core/             # AaruCore: models, IDs, validation. Shared by server and clients
  aaru-api/              # AaruAPI: generated /v1 client for the Apple apps
  aaru-server/           # Hummingbird API
  aaru-ios/              # SwiftUI iPhone + Mac + widget extension (not scaffolded)
  aaru-client/           # SolidJS + TanStack Start on Workers: landing + the web app on /v1
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

# Apple API client (after any openapi.yaml change)
./scripts/generate-api-client.sh
swift test --package-path aaru-api

# Server (needs Postgres: cd aaru-server && docker compose up -d)
cd aaru-server && swift run
cd aaru-server && swift test
cd aaru-server && swift run aaru --db-migrate
docker build -f aaru-server/Dockerfile -t aaru-server .   # from the repo root: needs aaru-core

# Web
cd aaru-client && npm run dev
cd aaru-client && npm run check && npm run lint && npm run typecheck
cd aaru-client && npm test
cd aaru-client && npm run api:generate   # after any openapi.yaml change
cd aaru-client && npm run build && npm run size   # JS/CSS budget per route (size-budget.json)

# Apple
xcodebuild build -project aaru-ios/Aaru.xcodeproj -scheme Aaru -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
cd aaru-ios && bundle exec fastlane beta   # TestFlight, iOS + macOS

# Format / lint (use whatever the repo actually configures)
swiftformat .
swiftlint
```

Never run destructive DB commands against a non-local database.

## Release channels

One backend. **Beta is client-side only**, as in the other apps:

| Channel | Apple | Web | API |
| --- | --- | --- | --- |
| Beta | TestFlight, bundle id + `.beta`, scheme "Aaru Beta", fastlane `beta` on every merge to `main` | `env.staging` Worker in `wrangler.jsonc`, deployed on every merge to `main` | production |
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
- **Status** — consumption only: `wishlist` | `in_progress` | `finished` | `dropped`. These
  stored values never change; UI labels are per kind: films, shows and anime read Plan to
  watch / Watching / Watched / Dropped, books Plan to read / Reading / Read / Dropped, no kind
  Planned / In progress / Finished / Dropped
- **Owned** — separate `isOwned` flag; do not overload status
- **Progress** — episode ticks for TV; page/percentage optional for books
- **List** — user-curated collection of library items, stored as membership rows
- **Shelf** — a *saved query* over library items (`saved_queries`), not membership. Shares a
  renderer with List; never shares a table. Users "pin a shelf" and "add to a list"
- **Action** — one journaled, undoable library write, whether the user or the agent made it
- **Import job** — one run of Trakt or a CSV/list ingest
- **Capture** — one-shot intake of pasted text, an image, or a URL. It is an *import source*,
  not a subsystem: it produces a `MatchTable` then a `PlanCard`, and never writes unplanned
- **Discover** — provider-curated public rows (DISC-001: trending, on the air, new shows, in
  theaters, this season's anime, trending books), the same for every user. Shown on Home and
  as the Discover tab/page. Catalog data like search, never a recommendation
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
- **Recap** — a read-only summary of one month or year (`/v1/me/stats`), played as a story.
  Derived only from the user's own library; imported or restored ticks are not activity
- **Group** — a friends-only space a user creates and invites friends into. It holds channels
  and always has `#general`
- **Channel** — one place to talk inside a group. Kind: `text` | `title` (one title, with a
  spoiler guard) | `watch` (a watch-together session) | `shelf` (a list the group edits)
- **Member** — a user's place in a group. Role: `owner` | `admin` | `member`
- **Group message** — one post in a channel, by a member or by Aaru. Server-visible. Never call
  it a Message, which is the encrypted DM
- **Mention** — `@handle` or `@aaru` inside a group message. Mentioning `@aaru` is the only way
  the agent posts in a group
- **Room** — a watch-together session: invite, countdown, reactions, shared check-off. Aaru
  does not control anyone's player. Since 2026-10-20 it lives in a `watch` channel
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
9. Trakt OAuth import; Stremio history by link code; CSV import for IMDb, Letterboxd, Goodreads; CAT list + ICS; TV Time, MAL, AniList.

## Later phases (after the P2 gate, see `BACKLOG.md`)

- P3 Tracking: scrobble ingest, Plex/Jellyfin webhooks, Stremio addon (catalogs + `player`/`library` events), one-way push to Trakt/MAL/AniList
- P4 Social: profiles, friends, blocks, invites, friend activity and "Today" stories, push, shared lists, groups
- P5 Gamification: points ledger, levels, streaks, badges, friends-only leaderboard, stats
- P6 Realtime: presence, libsignal DMs, SharePlay (the gateway and watch channels ship with groups)
- P7 Agent surfaces (M13/M14)

Do not write code for a later phase before the P2 gate, and do not add empty abstractions for it.
Owner's exceptions are recorded in `BACKLOG.md` decisions (Recap 2026-10-16; Stremio tokens,
scrobble service and addon 2026-10-19; Discover rows (DISC-001), the Discover tab, Insights
and Home stats 2026-10-20; agent connections, MCP, the Claude connector and remote approval
2026-10-20; groups, with minimal friends, the groups gateway and a minimal model provider,
2026-10-20; Seasons on Discover (DISC-002) and music as a fifth kind with new albums and
concerts (MUS-001…003), 2026-10-21).

## Out of scope (do not add unless asked)

- Two-way sync with any provider, or a conflict engine
- A documented public API with third-party clients, quotas, and a deprecation policy
- Recommendations engine. Provider-curated public rows on Home and the Discover tab
  (trending, this season, DISC-001) are allowed; anything personalised is not
- A global or public activity feed; public profile pages indexed by search engines
- Serializd / SIMKL integrations
- Music, manga, comics, games before the P2 gate (they are planned after it; see `BACKLOG.md`
  decisions 2026-10-15)
- Scraping Pogdesign, IMDb pages, AniDB, or any site without an official export/API. The one owner
  exception (2026-10-21) is SCR-007's browser extension reading the player page the user is
  watching, in their own browser; Aaru's server fetches nothing from those sites
- Any Stremio `stream` resource or stream source

## Import order (product + matching code)

When implementing multi-source import for one account, apply in this order and skip sources the user did not connect:

1. Trakt
2. Stremio history (link code)
3. IMDb CSV
4. Letterboxd CSV
5. Goodreads CSV
6. CAT show list / ICS
7. Netflix viewing activity
8. TV Time export
9. MyAnimeList XML
10. AniList list
11. Any other CSV (generic, by column names): fills gaps only

Capture is **not** in this order. It is a user-triggered one-shot, applied when the user asks
and never as part of reconciling an account's connected sources.

Scrobbles are not in this order either: they are live events, applied as they arrive.

Matching key: external IDs first, then normalized title + year + type. Never merge two titles that only share a similar name.

Merging sources (owner, 2026-10-20): an import fills empty fields and adds missing ticks, and may
move a status forward (`wishlist` → `in_progress` → `finished`). It never moves one backward, never
out of `dropped`, and never past a status the user chose themselves (`library_items.status_by_hand`).
Anime from MAL or AniList resolves to the TMDB show through `anime_mappings` (by AniList id, else MAL
id); entries for later seasons tick the TMDB season they map to and merge into one row.

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
  web Worker is a client: it holds the session in an HttpOnly cookie and forwards `/v1` calls
  with it, nothing else. Every rule lives in `aaru-server`.
- Third-party agent access is per-user and token-scoped, over the same tool layer a tap uses.
  An outside caller gets no capability a signed-in session lacks: single-item writes behave
  like a tap, anything larger becomes a plan the user approves inside Aaru. See X-009 in
  `BACKLOG.md` and `ARCHITECTURE.md` §"Outbound agent surfaces".
- Do not add features “for later” as empty abstractions. Phased work belongs in docs, not unused protocols.
