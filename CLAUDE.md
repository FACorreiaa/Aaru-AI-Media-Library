# Aaru

Aaru is a private-first media library and tracking app for movies, TV shows, anime, manga, books, and music albums. The name comes from the Egyptian Field of Reeds: a calm place where stories live. Social features (friends, activity, encrypted DMs, watch-together), gamification, and scrobbling are planned. They are scheduled in `BACKLOG.md` phases P3–P6 and do not start until the P2 gate ("basics done") is met.

This file is the working contract for anyone — human or agent — changing the repo.

## Product rules

- Aaru is the source of truth after import. Imports and scrobbles are one-way into Aaru. Pushes to Trakt, MAL, and AniList (P3) are one-way out and are never read back as a conflict source. Do not build two-way sync or a conflict engine. The one exception is MyAnimeList (SCR-010, owner 2026-10-23): Aaru reads a connected MAL list back through the import merge (forward only, Aaru wins ties, removals only listed). No conflict engine, and no other provider is read back.
- Private by default. A new account has no visible surface. Social is opt-in per user and friends-only; there is no global feed and no public profile page. Groups are friends-only too: no invite links, no public or discoverable groups.
- Group messages are server-visible and every channel says "not end-to-end". DMs are end-to-end and the server never reads them. Never blur the two.
- Catalog metadata and user library are different layers. Never treat TMDB/Trakt/Open Library/AniList payloads as the user’s library row.
- Every saved title must store external IDs when known: `tmdb`, `imdb`, `trakt`, `tvdb`, `isbn`, `anilist`, `mal`, `anidb`, `musicbrainz`.
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
| Web | `aaru-client/` — SolidJS + TanStack Start on Cloudflare Workers, a pure client of `/v1` with the same functionality as the Apple apps. Landing page + sign-in + the signed-in app in one Worker. API types generated from `openapi.yaml` (`npm run api:generate`). UI from shadcn-solid on Kobalte, every component as source in `src/components/ui` behind the `~/components/ui` barrel, themed on Aaru's tokens; animation through `motion/mini` via `src/lib/motion.ts` (DESIGN.md §17). No DB access, no business logic |
| Browser extension | `aaru-extension/` — WXT, one Manifest V3 source for Chrome and Firefox (SCR-007). Reads the player on Netflix, Disney+ and Prime Video, and YouTube videos for Now playing (SCR-009), and calls `/v1/scrobble/*` with a scrobble-only token. A client like the others: no rules of its own |
| Database | PostgreSQL via Fluent (`hummingbird-fluent`), a StatefulSet on the `maat` cluster |
| Jobs | Hummingbird Jobs (or equivalent queue) for imports and hydration |
| Catalog — video | TMDB (also trending, on the air, new shows, in theaters for Discover) |
| Catalog — anime | AniList GraphQL (with MAL ids); first-class from P1; this season + trending for Discover. While AniList is down, TMDB's Japanese animation stands in for search and Discover (CAT-021). AniDB's daily title dump adds alternate titles for matching only (CAT-022) |
| Catalog — air times | TVmaze (no key, CC BY-SA): exact air times and network for TMDB shows, and the next episode's time on Discover's On air (DISC-003); TMDB stays the episode source |
| Where to watch | TMDB `watch/providers` (JustWatch data, credited): flat-rate services per country on Discover's On air (DISC-003, CAT-014 in part). The country comes from the device language, per request, never stored |
| Catalog — manga | AniList GraphQL, type MANGA (any format: manga, manhwa, manhua, one-shot, light novel), with MAL ids; no fallback while AniList is down (MNG-001, pulled forward 2026-10-23) |
| Catalog — books | Open Library (Google Books only if Open Library is insufficient); weekly trending for Discover |
| Catalog — music | MusicBrainz release groups (albums, EPs) and tracklists, Cover Art Archive covers; no key, 1 req/s with a contact User-Agent (MUS-001). ListenBrainz fresh releases + sitewide stats for Discover's New albums / Coming soon (MUS-002) |
| Catalog — sports | TheSportsDB (`THESPORTSDB_API_KEY`, premium, 100 req/min) behind `SportsListing`: leagues, teams, players, fixtures, 2-minute livescores, TV listings for the Sports tab only; off without the key (SPT-001) |
| Concerts | Ticketmaster Discovery API v2 (`TICKETMASTER_API_KEY`, free, 5,000 calls/day; Aaru stops at 4,500), behind `ConcertListing`; off without the key. Tickets link out (MUS-003) |
| Geocoding | Open-Meteo geocoding (no key, non-commercial) for the "Concerts near" city only (MUS-003) |
| User import — primary | Trakt OAuth; Stremio history by link code (one library read, then logout; key never stored) |
| User import — files | IMDb CSV, Letterboxd CSV, Goodreads CSV, CAT show list / ICS file or iCal link, Netflix viewing activity CSV (one profile), TV Time export (its CSVs one at a time: Export my data or the GDPR export), MAL-format XML, anime or manga (MyAnimeList, Kitsu, AniList exports), AniList anime and manga lists by username, any other CSV read by its column names; `source=auto` detects the format |
| User import — music | Last.fm and ListenBrainz by username, Spotify extended streaming history, Google Takeout's YouTube and YouTube Music history (music only) into the listening log as import jobs undone by job (MUS-004). Never library rows, never in the import order |
| Scrobble — music | ListenBrainz's submit protocol at `/listenbrainz/1/` with music tokens only (MUS-005, owner 2026-10-21): Web Scrobbler, Pano Scrobbler, Navidrome, Jellyfin's plugin. No Spotify OAuth, no native Apple Music path |
| Scrobble (P3) | `POST /v1/scrobble/*` (Trakt-shaped, scrobble tokens only), the browser extension for Netflix / Disney+ / Prime Video (SCR-007, owner exception 2026-10-21), Plex + Jellyfin webhooks, Stremio addon (catalogs + `player`/`library` events, no `stream`; pulled forward 2026-10-19) |
| MyAnimeList sync | OAuth PKCE per user: anime progress pushed out (SCR-005) and the list read back on app open and every 6 h (SCR-010), the one two-way exception |
| Realtime | Hummingbird WebSocket gateway at `/v1/ws` inside `aaru-server`; group envelopes first (GRP-006, pulled forward 2026-10-20), presence and DM delivery in P6. The web connects with a short-lived ticket because its session is cookie-only |
| Groups | Friends-only spaces with channels (`text`, `title`, `watch`, `shelf`) and `#general`. Server-visible messages in Postgres; `@aaru` replies through `ModelProviding` (pulled forward 2026-10-20) |
| Messaging (P6) | libsignal; server is a key directory + ciphertext mailbox only |
| Push | APNSwift, per-device environment; web push (VAPID, `swift-webpush`) to browsers. Airing alerts pulled into P2 (2026-10-15, web 2026-10-20); group mention and invite alerts with groups (GRP-012); the "Now watching" Live Activity pushed from scrobbles (push-to-start, update, end; SCR-008) |
| Deploy | API: GHCR image → promote PR in `~/Work/production/platform/infra` → ArgoCD on `maat` (`horus` namespace). Web: Wrangler to Workers |
| Observability | Grafana Cloud through the cluster's Alloy: Prometheus `/metrics` on an internal port, logs, probes, an "Apps / Aaru" board. Sentry for errors only (server, web, Apple apps, extension; no tracing, no replay, no PII). PostHog for a few server-side product events only; no client analytics SDK. Every claim lives in `docs/privacy.md`, which changes first (owner, 2026-10-21) |
| User import — capture | Pasted text, an image, or a catalog link (TMDB, AniList, Open Library) as an import job (`source=capture`, AG-006, pulled forward 2026-10-22). Text and images are read by one `ModelProviding` call and deleted once read; links are parsed by id and never fetched. Free accounts get 3 a month |
| Agent model | Pluggable `ModelProviding` in `aaru-server` (`Sources/App/Agent`). Anthropic default, user key supported, spend metered daily |
| Billing | Aaru Plus on StoreKit 2, bought in the Apple apps only (BIL-001…004, pulled forward 2026-10-22). The server verifies Apple's signed transactions and notifications itself (`Sources/App/Billing`, against Apple's root) and keeps the entitlement; the web shows it and sells nothing. No Stripe, no web checkout |
| Outbound agent access | App Intents in `aaru-ios`; MCP at `POST /v1/mcp` in `aaru-server/Sources/App/MCP`, with an OAuth front door (`Sources/App/OAuth`) so Claude can add Aaru as a custom connector. Not a second backend |

## Repo layout

```text
aaru/
  aaru-core/             # AaruCore: models, IDs, validation. Shared by server and clients
  aaru-api/              # AaruAPI: generated /v1 client for the Apple apps
  aaru-server/           # Hummingbird API
  aaru-ios/              # SwiftUI iPhone + Mac + widget extension
  aaru-client/           # SolidJS + TanStack Start on Workers: landing + the web app on /v1
  aaru-extension/        # Browser extension (Chrome + Firefox): scrobbles streaming sites
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

Do not invent new root targets without updating this file.

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
cd aaru-client && npm run tokens         # after any design/tokens.json change (web CSS + Apple colour sets)
cd aaru-client && npm run build && npm run size   # JS/CSS budget per route (size-budget.json)

# Browser extension
cd aaru-extension && npm run check && npm run lint && npm run typecheck && npm test
cd aaru-extension && npm run build   # .output/chrome-mv3, .output/firefox-mv3; store submission by hand

# Apple
xcodebuild build -project aaru-ios/Aaru.xcodeproj -scheme Aaru -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
cd aaru-ios && bundle exec fastlane beta   # TestFlight, iOS + macOS

# Format / lint
./scripts/lint.sh   # check only: swiftformat --lint, swiftlint, periphery (core, server, api)
swiftformat .       # rewrites files
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
- **Brand** (owner, 2026-10-22): the owl poster is the standard (DESIGN.md "Brand"). Colours
  come only from `design/tokens.json` through the generated tokens (no hex, no `Color(red:)`), and
  every heading is the system sans (`--font-display`, `Font.aaruDisplay`); no serif or bundled
  faces. On a conflict with main in a brand file, take main's side. `ci-brand.yml` enforces it.
- **Web UI rule** (owner, 2026-10-21): all web UI comes from shadcn-solid in
  `aaru-client/src/components/ui`, always imported through the barrel `~/components/ui`. A
  missing component is added from shadcn-solid's manual install into that folder (and the
  barrel), never hand-rolled and never a raw `button`/`input`/`select`/`textarea`/`dialog`.
  Aaru looks are variants on those components. ESLint enforces it.

## Domain language

Use these words in code, APIs, and UI:

- **Title** — a movie, show, anime, manga, book, or album in the catalog
- **Library item** — a user’s relationship to a title
- **Status** — consumption only: `wishlist` | `in_progress` | `on_hold` | `finished` | `dropped`.
  These stored values never change; UI labels are per kind: films, shows and anime read Plan to
  watch / Watching / Watched / Dropped, books and manga Plan to read / Reading / Read / Dropped, albums
  Plan to listen / Listening / Listened / Dropped, no kind Planned / In progress / Finished /
  Dropped; `on_hold` reads On hold for every kind. On hold is paused on purpose (LIB-007, owner
  2026-10-25): left off Now, Up Next, Tonight, the week and airing alerts, counted in stats and
  status counts, and a new tick or reading position moves it back to `in_progress`
- **Album** — one MusicBrainz release group of type Album or EP: the tracked unit of music.
  Status, rating and notes only; its tracklist is catalog data, never ticked
- **Manga** — one AniList work of type MANGA (manga, manhwa, manhua, one-shot, light novel):
  `MediaType.manga`, never a book and never anime. Progress is the last chapter and volume read.
  MyAnimeList numbers manga apart from anime, so a MAL id is unique per kind
- **Concert** — one music event from the concert provider, near a place or by an artist of the
  user's albums (matched by MusicBrainz artist id, never by name). Catalog data linked out for
  tickets; Aaru sells nothing and stores no event past the cache. A position used to find
  concerts is rounded to two decimals and never stored; the saved "Concerts near" city is the
  only place kept, and the user removes it in Settings
- **Sport follow** — a league (or promotion: UFC, WWE), team or player a user follows in the
  Sports tab, by the provider's id (`sport_follows`). Sports-only: never the social sense of
  follow (there is none), never a Favorite, never shown to friends
- **Sport event** — one match, game or card from the sports provider. Catalog data for the Sports
  tab, kept no longer than the cache: never a Title, never a library item, never journaled
- **Owned** — separate `isOwned` flag; do not overload status
- **Avatar** — a user's own photo, one square JPEG the device made (SOC-001b). It shows wherever
  their name shows to a signed-in account, with the monogram as the fallback; never on a route a
  signed-out caller reads, never across a block. Profile data: not journaled
- **Favorite** — one title in a user's ordered top 10 for a kind (film, show, anime, manga,
  book, album), any catalog title. Profile data shown on the profile: not a library write, not
  journaled, not a List
- **Progress** — episode ticks for TV; page/percentage optional for books
- **List** — user-curated collection of library items, stored as membership rows
- **Shelf** — a *saved query* over library items (`saved_queries`), not membership. Shares a
  renderer with List; never shares a table. Users "pin a shelf" and "add to a list"
- **Anime backlog** — an anime in progress the user never touched in Aaru: status from an
  import (not set by hand) and no live tick. It stays `in_progress` but leaves Now for its
  group page. Derived on the server (`inBacklog`), never stored, never a status (APP-018)
- **Action** — one journaled, undoable library write, whether the user or the agent made it
- **Import job** — one run of Trakt or a CSV/list ingest
- **Capture** — one-shot intake of pasted text, an image, or a URL. It is an *import source*,
  not a subsystem: it produces a `MatchTable` then a `PlanCard`, and never writes unplanned
- **Discover** — provider-curated public rows (DISC-001: trending, on the air, new shows, in
  theaters, this season's anime, trending books; MUS-002: new albums, albums coming soon), the
  same for every user, plus the On air view (DISC-003): the week's airings by channel. Each row
  says its kind (DISC-004): the Discover page shows shows, films and anime; the Books, Manga and
  Music pages show their own rows under the user's shelf, and Music holds Concerts. Home shows
  every row. Catalog data like search, never a recommendation
- **Agent token** — a per-user, scoped, revocable credential an outside agent uses to reach
  Aaru's tool layer. Not an API key for a third-party developer
- **Approval** — the user's yes to a plan an agent proposed. Approval happens inside Aaru; no
  caller approves its own plan
- **Watch event** — one scrobble (start/pause/stop with progress) from a player. It may tick
  progress; it is never library truth on its own
- **Play** — a track (a scrobbler's `playing_now`) or a YouTube video a player reports that is
  not a Title (SCR-009). It lives only while it plays, is never a watch event, and never ticks
  anything. It exists for Now playing. A music video (a `- Topic` channel's) heard past half or
  4 minutes also makes one listen (SCR-011); the play itself is still never stored
- **Listen** — one play of a track a music scrobbler sent (MUS-005) or a history import brought
  in (MUS-004). Append-only and never a library write; the same play sent twice is kept once. An
  imported listen counts on its own day in Insights and the Recap, earns no points, and counts
  toward music badges
- **Friend** — a mutual, accepted connection. There is no one-way follow
- **Invite** — a one-use link (`aaruapp.com/i/{code}`, 14 days) that makes whoever opens it the
  sender's friend, optionally carrying one title to watch together. Friend invites only: groups
  have no invite links
- **Recommendation** — one title a user sends friends, with an optional note; it waits until the
  friend adds it to Plan to watch or dismisses it
- **Reaction** — one of six emoji a friend leaves on an activity row (a person's title on one day)
- **Points event** — one row in the append-only points ledger, idempotent by dedupe key.
  Never a counter
- **Streak** — consecutive local days with at least one live progress write. A day is a
  *streak day* in UI and code; "check-in" stays the Live Activity's word
- **Level** — a pure function of total points (`50·L·(L−1)` to reach L). Never stored as truth
- **Badge** — an award defined in code, tiered 1–4. Milestone badges read library facts (imports
  count); activity badges read points events and streak days (live only). About 15% are hidden
  until earned
- **Recap** — a read-only summary of one month or year (`/v1/me/stats`), played as a story.
  Derived only from the user's own library; imported or restored ticks, and seasons or whole
  shows marked watched, are not activity
- **Group** — a friends-only space a user creates and invites friends into. It holds channels
  and always has `#general`
- **Channel** — one place to talk inside a group. Kind: `text` | `title` (one title, with a
  spoiler guard) | `watch` (a watch-together session) | `shelf` (a list the group edits). The
  UI calls a `shelf` channel a "List" (owner, 2026-10-21: a label only; the stored kind stays)
- **Member** — a user's place in a group. Role: `owner` | `admin` | `member`
- **Group message** — one post in a channel, by a member or by Aaru. Server-visible. Never call
  it a Message, which is the encrypted DM
- **Mention** — `@handle` or `@aaru` inside a group message. Mentioning `@aaru` is the only way
  the agent posts in a group
- **Room** — a watch-together session: invite, countdown, reactions, shared check-off. Aaru
  does not control anyone's player. Since 2026-10-20 it lives in a `watch` channel. The UI
  word is "Watch party" (owner, 2026-10-21: a label only; code keeps Room)
- **Board** — the friends-only stream of posts. A query, not a table. No public page, no global
  feed
- **Post** — one Board entry by a user: free text, or one title with a rating and a spoiler
  stamp. Not a Group message
- **Comment** — a reply on a post, one level of nesting. Can be by Aaru
- **Upvote** — one per user per post
- **Chat** / **Chat turn** — a one-to-one thread with Aaru, and one user or Aaru entry in it.
  Never "Conversation" or "Message": those are the encrypted DM terms
- **Conversation / Message** — an end-to-end encrypted DM thread. The server only ever holds
  ciphertext
- **Device** — one installed client, the unit for push tokens and Signal keys

Do not use “portfolio”, “watchlist-only”, or vendor names as the primary domain terms. Vendor names belong on `ExternalID` and import sources.

## Basics (P0–P2, build this first)

1. Rails: root CI, Xcode project with Beta/Release, fastlane, API on `maat`, Workers beta/prod.
2. Auth: Sign in with Apple + email/password (or magic link). Sessions/JWT as implemented in `aaru-server`.
3. Search titles via TMDB / AniList / Open Library.
4. Add to library, set status, rating, notes.
5. TV and anime progress by season/episode; calendar and Up Next.
6. Manual lists.
7. iOS + Mac clients on the JSON API: home rows, week grid, widgets, Live Activity.
8. Web client (`aaru-client`) on the same API.
9. Trakt OAuth import; Stremio history by link code; CSV import for IMDb, Letterboxd, Goodreads; CAT list + ICS; TV Time export CSVs, MAL, AniList.

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
concerts (MUS-001…003), 2026-10-21; friend invite links, profiles and basic social, 2026-10-21;
profile stats without badges (GAM-006b) and the whole show marked watched (PROG-005), 2026-10-22;
the points ledger, levels, streaks, badges, the friends leaderboard and the streak widget
(GAM-001…005, WID-007) and Boards, 2026-10-22; manga as a sixth kind with MAL and AniList manga
imports (MNG-001…002) and profile favorites (FAV-001), 2026-10-23; the Sports tab (SPT-001…005),
2026-10-24).

## Out of scope (do not add unless asked)

- Two-way sync with any provider, or a conflict engine (MyAnimeList's read-back, SCR-010, is the one exception)
- A documented public API with third-party clients, quotas, and a deprecation policy
- Recommendations engine. Provider-curated public rows on Home and the Discover tab
  (trending, this season, DISC-001) are allowed; anything personalised is not
- A global or public activity feed; public profile pages indexed by search engines
- Serializd / SIMKL integrations
- Comics and games before the P2 gate (they are planned after it; see `BACKLOG.md`
  decisions 2026-10-15). Music albums (MUS-001…003, 2026-10-21) and manga (MNG-001…002,
  2026-10-23) were pulled forward by the owner
- Scraping Pogdesign, IMDb pages, AniDB, or any site without an official export/API. The owner
  exceptions are SCR-007's browser extension reading the player page the user is watching, in
  their own browser (2026-10-21), and the same extension reading `youtube.com/watch` for Now
  playing (SCR-009, 2026-10-22); Aaru's server fetches nothing from those sites
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
Listening-history imports (MUS-004) are not in it either: they fill the listening log, never the
library.

Matching key: external IDs first, then normalized title + year + type. Never merge two titles that only share a similar name.

Merging sources (owner, 2026-10-20): an import fills empty fields and adds missing ticks, and may
move a status forward (`wishlist` → `in_progress` → `finished`). It never moves one backward, never
out of `dropped`, and never past a status the user chose themselves (`library_items.status_by_hand`).
`on_hold` ranks with `in_progress`: a row that says on hold pauses an item in progress, and only a
source that has on hold (MAL, AniList) resumes one (LIB-007).
Anime from MAL or AniList resolves to the TMDB show through `anime_mappings` (by AniList id, else MAL
id); entries for later seasons tick the TMDB season they map to and merge into one row.

## Architecture

Read `ARCHITECTURE.md` before changing boundaries between `AaruCore`, `aaru-server`, and apps.
Read `DESIGN.md` and `VIEWS.md` before adding or changing a client surface. The agent emits
only components from the `VIEWS.md` catalog; it gets no write path a user tap does not have.

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
- Phased work belongs in docs, not unused protocols.
