# Aaru architecture

Aaru is a private-first media library for movies, TV, anime, and books. Native clients are Swift; the web client is SolidJS + TanStack Start. The server is Hummingbird. Social, gamification, tracking integrations, and realtime are later phases (see "Phasing"). They must not leak into Phase 0–2 data-model or API design beyond nullable hooks that already exist (e.g. a `visibility` field defaulting to private).

## Goals

- One language on the wire and in the apps: Swift models in `AaruCore`.
- Catalog providers are replaceable; the library schema is not.
- Imports are asynchronous, idempotent, and one-way.
- iOS and Mac ship first. The web app is a second client of the same API, not a second product.

## System context

```text
                ┌──────┐  ┌────────────┐  ┌─────────┐
                │ TMDB │  │Open Library│  │ AniList │
                └──┬───┘  └─────┬──────┘  └────┬────┘
                   │ metadata   │              │
┌────────────┐ JSON┌▼───────────▼──────────────▼┐     ┌──────────┐
│ iOS / Mac  │────▶│      Hummingbird API       │────▶│ Postgres │
│ + widgets  │     │  auth · library · search   │     └──────────┘
└────────────┘     │  lists · calendar · jobs   │
┌────────────┐     │                            │     ┌─────────┐
│ aaru-client│────▶│                            │     │  Trakt  │
│ (Workers)  │     └─────────────┬──────────────┘     └────┬────┘
└────────────┘                   │ enqueue                 │ OAuth
                                 ▼                         │ + history
                       ┌─────────────────────┐             │
                       │ Import workers      │◀────────────┘
                       │ Trakt / CSV / CAT   │
                       └─────────────────────┘
```

The web client (`aaru-client/`) is SolidJS + TanStack Start on Cloudflare Workers. It holds the
landing page and the signed-in app on `/v1`, mirroring the Apple apps. It never touches Postgres.

## Process boundaries

| Component | Responsibility | Must not do |
| --- | --- | --- |
| `aaru-core` (`AaruCore`) | Shared DTOs, identifiers, status enums, title matching, lightweight validation | Persistence, HTTP server, TMDB secret handling |
| `aaru-server` | HTTP, auth, Postgres, jobs, provider adapters | SwiftUI, store-kit, vendor JSON leaked to clients |
| `aaru-api` (`AaruAPI`) | The `/v1` client for the Apple apps, generated from the server's `openapi.yaml` (committed, checked fresh in CI); bearer-token session middleware that reports a rejected session once | Hand-written DTOs, retries of a 401, business logic |
| `aaru-ios` | iOS + macOS app, widget extension, Live Activity, App Intents, local cache, Sign in with Apple | Direct TMDB/Trakt/AniList calls (go through Aaru API) |
| `aaru-client` | SolidJS + TanStack Start on Cloudflare Workers: landing page + the web app on `/v1`, at parity with the Apple apps. Holds the session in an HttpOnly cookie and forwards `/v1` calls with it | Database access, business logic, forking DTO meaning from the native clients |

All clients talk only to Aaru. That keeps API keys, rate limits, and ID mapping on the server.

## AaruCore model

These types are the contract. Persistence tables map to them; they do not have to be 1:1.

### Media type and external IDs

```swift
enum MediaType: String, Codable, Sendable {
    case movie, show, book
}

struct ExternalIDs: Codable, Hashable, Sendable {
    var tmdb: String?
    var imdb: String?
    var trakt: String?
    var tvdb: String?
    var isbn: String?
    var openLibrary: String?
    var anilist: String?   // CAT-008
    var mal: String?       // CAT-008
    var anidb: String?     // CAT-008
}
```

Anime is not a fourth `MediaType`. See "Anime catalog" under provider adapters.

### Title (catalog)

A canonical work Aaru knows about. Created on first add or during import hydration.

- `id` — Aaru UUID
- `type` — `MediaType`
- `title`, `originalTitle`, `year`
- `synopsis` (optional, from catalog)
- `posterURL` (catalog URL, not hosted)
- `ids` — `ExternalIDs`
- `seasons` — only for shows; episode lists may be lazy-loaded
- `genres` (server-only, CAT-018) — the provider's genre names, stored at hydration (TMDB,
  AniList; books none) and backfilled by the catalog refresher. Not on the `Title` DTO; the
  stats read them

Titles are shared across users. Do not put ratings or status on `Title`.

### Library item (user data)

- `id` — Aaru UUID
- `userId`
- `titleId`
- `status` — `wishlist` | `in_progress` | `finished` | `dropped` (consumption only)
- `rating` — optional. Scale is fixed: 1–10 in 0.5 steps, enforced by `AaruCore.Rating`
- `notes`
- `isOwned: Bool` — ownership, independent of consumption. A wishlist item can be owned.
- `progress` — see below
- `addedAt`, `updatedAt`, `finishedAt`

Recommended: `status` is consumption only; ownership is `isOwned: Bool`.

### Progress

- Show: map of watched episode ids or `(season, episode)` pairs; plus optional `currentSeason` / `currentEpisode`
- Movie: watched boolean is implied by `finished`; optional rewatch count later
- Book: optional `page` / `percent`

Phases 0–2 do not need continuous scrobble positions. Scrobbles arrive in Phase 3 as
`watch_events` that write into this same progress; they do not replace it.

### List

- `id`, `userId`, `name`, `createdAt`
- items reference `libraryItemId` or `titleId` (prefer `titleId` so a list can include titles not yet in a status)

### Import job

- `id`, `userId`
- `source` — `trakt` | `imdb_csv` | `letterboxd_csv` | `goodreads_csv` | `cat_list` | `cat_ics`
- `state` — `queued` | `running` | `planned` | `succeeded` | `failed` | `partial` (`planned` waits
  for the user's approval; nothing is written before it)
- `stats` — created / updated / skipped / unmatched
- `errorSummary`

## Persistence

PostgreSQL. Suggested tables:

- `users`
- `auth_identities` (Apple, email)
- `titles` (unique indexes on each external id where not null)
- `show_episodes` (title_id, season, episode, optional air time + `airs_at_exact`, optional overview, optional still URL (TMDB, referenced), optional tmdb episode id). Title detail returns all of them per episode
- `library_items` (unique `(user_id, title_id)`)
- `episode_progress` (unique `(library_item_id, season, episode)`; `watched_at_known` is false
  for ticks an import or an undo wrote, whose `watched_at` is the write, not the watch)
- `lists`, `list_items`
- `saved_queries` (shelves — a stored filter, never membership rows)
- `import_jobs`, `import_job_events` (optional log lines)
- `actions` (action journal: one row per mutating library write, with its inverse)
- `match_aliases` (match ledger: aggregate crosswalk from a source row key to an external id)
- `watch_events` (one playback session per user, source and player id: state, position, longest known duration, `title_id` null when unmatched; built 2026-10-20 for Stremio)
- `agent_plans` (an outside agent's change waiting for approval: the op, its basis, status, the token)
- `agent_tokens` (per-user agent access: `kind` (`stremio`, or an MCP client: `claude_code`, `codex`, `hermes`, `gemini`, `other`), hashed secret, scopes, `lastUsedAt`, revocation)
- `agent_usage` (model spend per user per day: tokens in and out, cost in cents)

Later-phase tables, listed so nobody invents a parallel shape. None is created before its
phase:

| Phase | Tables |
| --- | --- |
| 3 | `watch_events`, `outbound_connections` (Trakt / MAL / AniList tokens, encrypted) |
| 4 | `social_friend_requests`, `social_friendships`, `social_blocks`, `social_reports`, `social_invites`, `social_settings`, `apns_devices` |
| 5 | `points_events`, `user_progress`, `check_ins`, `user_badges` |
| 6 | `devices`, `signal_identity_keys`, `signal_signed_prekeys`, `signal_onetime_prekeys`, `conversations`, `conversation_members`, `message_envelopes`, `rooms`, `room_members` |

Do not store raw provider dumps long-term. Store the job result and the normalized rows.

`saved_queries` and `lists` are different objects and must not be merged. A list stores
membership; a shelf stores a query and recomputes. See `VIEWS.md`.

`actions` is user data, not observability output — it backs the undo ribbon, which is a
first-class view. Each row carries enough inverse payload to revert the write. One user
instruction is one row even when it touches many episodes.

Each row also records **who**: `actor` is `user`, `agent` (Aaru's own agent) or
`external_agent`, and a nullable `agentTokenId` names the `agent_tokens` row that made the
write. Revoking a token leaves its history readable, so the ribbon can always answer which
agent did it. See "Outbound agent surfaces" below and X-009 in `BACKLOG.md`.

### Match ledger (`match_aliases`)

The match ledger is the one table in Aaru that compounds across users. It records that a
row from a given import source resolves to a given external id, so the next import of the
same row — by anyone — skips the fuzzy title-plus-year path. It is catalog-layer data, not
library data, and the rules below exist so that it can never become a side channel for
what any user watched or read.

Shape:

- `source` — import source (`trakt`, `imdb_csv`, `letterboxd_csv`, `goodreads_csv`, `cat`)
- `source_key` — the normalized row identity from that source (Letterboxd URI, Goodreads
  book id, normalized title + year for sources with no stable id)
- `external_id` — the resolved `ExternalID` (`tmdb`, `imdb`, `trakt`, `tvdb`, `isbn`)
- `media_type`
- `confirmations` — count of independent confirmations
- `first_seen_day`, `last_seen_day` — day granularity, never finer

Rules:

- **No user identity.** No `user_id`, no `library_item_id`, no `import_job_id`, no foreign key
  to any user-owned table. A ledger row must be meaningful with every user table dropped.
- **No user rows.** The ledger stores the mapping, never the imported row: no rating, no
  status, no watched date, no notes. `source_key` is the identity of the *title* in that
  source, not the identity of the user's entry.
- **Day granularity.** Timestamps on the ledger are dates. A row's existence must not let
  anyone infer when a particular person imported.
- **Two independent confirmations, or one plus a provider id.** A human correction in the
  unmatched-row triage becomes a ledger row only when a second account makes the same
  correction independently, or when the corrected target is confirmed by an exact provider
  id already present on the row. A single account's correction is applied to that account's
  import and held in a pending state; it does not influence other users' matches.
- **Read at step 2, write after step 6.** The import worker consults the ledger when mapping
  a row to `MediaRef`, before any fuzzy matching. Ledger writes happen only after a job has
  finished and only from the confirmed-correction path above. Ledger lookups are a hint to
  the matcher, not an override: an exact external id present on the incoming row always wins.
- **Exportable in full.** The ledger is published as open data (see `MARKETING.md` §5.3). Any
  column that would be uncomfortable to publish does not belong in the table.
- **Deleting a user deletes nothing here.** Because nothing here belongs to a user. If that
  sentence ever becomes false, the table design is wrong.

The pre-launch converter tools on the landing pages (`aaru-client` route group) write to the same ledger through the
same confirmation rule; a correction made by an anonymous web visitor counts as one
confirmation from one account.

## API

JSON over HTTPS. Version prefix: `/v1`.

Auth: bearer session or JWT issued after Sign in with Apple / email. All library routes require a user.

### Core routes

```text
POST   /v1/auth/apple
POST   /v1/auth/email/...
DELETE /v1/auth/session

GET    /v1/search?q=&type=all|movie|show|anime|book   # all: CAT-019
GET    /v1/titles/{id}

GET    /v1/calendar?from=&to=             # CAL-001
GET    /v1/up-next                        # UPN-001; counts + unfinished UPN-002
GET    /v1/discover                       # DISC-001

GET    /v1/library/items
POST   /v1/library/items
GET    /v1/library/items/{id}
PATCH  /v1/library/items/{id}
DELETE /v1/library/items/{id}

PUT    /v1/library/items/{id}/episodes/{season}/{episode}   # watched true/false
POST   /v1/library/items/{id}/seasons/{season}/watched      # bulk

GET    /v1/lists
POST   /v1/lists
POST   /v1/lists/{id}/items
DELETE /v1/lists/{id}/items/{itemId}

GET    /v1/shelves                        # saved queries
POST   /v1/shelves
PATCH  /v1/shelves/{id}
DELETE /v1/shelves/{id}
GET    /v1/shelves/{id}/items             # same DTO as GET /v1/library/items

GET    /v1/actions?limit=                 # action journal, newest first
POST   /v1/actions/{id}/undo

GET    /v1/me/stats?year=&month=&span=&tz=  # GAM-006a/c: a year, a month or span=all, in the user's time zone

GET    /v1/imports
POST   /v1/imports/trakt/connect          # start OAuth
GET    /v1/imports/trakt/callback
POST   /v1/imports/stremio/link           # IMP-016: a code to approve on stremio.com
POST   /v1/imports/stremio/link/{code}    # 204 pending | 202 queued import | 410 expired
POST   /v1/imports/csv                    # text/csv body; ?source=imdb|letterboxd|goodreads&filename=
POST   /v1/imports/{id}/apply             # approve the plan: one journaled, undoable action
DELETE /v1/imports/{id}                   # discard
POST   /v1/imports/cat                    # text list or ics
POST   /v1/imports/capture                # one-shot capture: text | image | url
GET    /v1/imports/{id}

GET    /v1/settings
PATCH  /v1/settings                       # autonomy dial, model provider, own model key

GET    /v1/agent/tokens
POST   /v1/agent/tokens                   # secret returned once, never again
DELETE /v1/agent/tokens/{id}              # revoke

POST   /v1/plans/{id}/approve             # in-app approval of a proposed plan
POST   /v1/plans/{id}/deny

GET    /v1/context                        # compact library digest for read-only agents
POST   /v1/mcp                            # streamable HTTP, exposes the tool layer only
```

Search hits are catalog projections, not library items. The client calls `POST /library/items` with a `MediaRef` (Aaru title id or provider id + type).

`type=all` (CAT-019, the clients' default) runs TMDB `search/multi` (films and shows; people
and adult titles dropped) and AniList in parallel, AniList on a short deadline. Books are never
in All: Open Library is the slowest and noisiest provider, so clients end the list with a
"Search Books for 'x'" row. One provider failing returns the other's hits with
`incomplete: true`; both failing is a 502. The only dedupe is `anime_mappings`, and only for
shows: a TMDB show is dropped when an AniList hit in the same results maps to its tmdb id, and
that hit gains `ids.tmdb`. Nothing is merged on a name. Hits carry an optional `releaseDate`.

Later-phase route groups, each added with its phase and never before:
`/v1/scrobble/*` and `/v1/webhooks/{plex|jellyfin}` (3), `/v1/agent/tokens` and the Stremio
addon at `/stremio/{token}/*` (3, pulled forward 2026-10-19; outside `/v1` because the Stremio
protocol fixes the paths), `/v1/social/*`
and `/v1/devices` (airing push, pulled into 2 on 2026-10-15), `/v1/me/points|badges|streak` (5; `/v1/me/stats` shipped early
with GAM-006a and grew with GAM-006c, 2026-10-20), `/v1/ws`,
`/v1/keys/*`, `/v1/conversations/*`, `/v1/rooms/*` (6).

### Recap stats (GAM-006a)

`/v1/me/stats` is a derived read with no table of its own (`StatsService` over `StatsStore`, the
same shape as Calendar). One query unions episode ticks whose `watched_at_known` is true with
finished items that have a `finished_at`, buckets them by local day in the caller's `tz`, and
the service derives totals, buckets, the longest run and the top titles in Swift. The journal is
not a source: it stores inverses, collapses an import into one row, and is pruned.

An import's ticks are marked in the same transaction (`now()` is the transaction's start, so
`watched_at = now()` picks out exactly the rows it wrote); a snapshot insert (undoing a delete)
writes them unknown. A finish at exactly 00:00 UTC is a date-only import and keeps its UTC day
in every time zone.

Insights (GAM-006c) reads the same rows. `year` is optional; `span=all` runs from the first
active year to the end of the current one with one bucket per year (422 with `year` or `month`;
a request with neither `year` nor `span` is a 422 too), so all-time totals equal the years summed. The
response adds `span` (`month` | `year` | `all`), `byKind` (`movie` | `show` | `anime` | `book`:
episodes, minutes, finished) and `ratings.distribution`: ten bins, index `ceil(rating) - 1`,
so a 7.5 counts as an 8. No new query and no table.

### Calendar and Up Next

Both are derived reads over the user's library. Neither has its own table.

- **CAL-001 `GET /v1/calendar?from=&to=`** joins tracked shows (`in_progress` or `wishlist`)
  to `show_episodes` air times. Episodes come from TMDB for shows (dates only), refined to the
  exact broadcast instant and network by TVmaze (CAT-011) when it knows the show by TVDB or
  IMDb id and its date agrees within two days; anime comes from AniList `airingSchedule`
  (exact). `airTimeKnown` tells clients which. Where both exist for one title, AniList wins for
  anime episodes.
  Returns episodes with watched state, so the `WeekGrid` checkbox and the week widget read one
  DTO. Times are UTC on the wire; clients localize.
- **UPN-001 `GET /v1/up-next`** returns, per `in_progress` show, the next unwatched aired
  episode, runtime, episodes left and time left ("10 left · 8h 40m"), and a finale flag
  (last episode of the season). Ordered by last activity. It feeds `ContinueRow`, the Up Next
  widget, and the Live Activity.
- **UPN-002** adds two optional fields. `counts` is items per status (`wishlist`,
  `inProgress`, `finished`, `dropped`) for Home's chips. `unfinished` feeds `UnfinishedRow`:
  every `dropped` item and every `in_progress` item whose `updated_at` is at least 30 days old
  (`reason` `dropped` | `stalled`, `since`, and `next` for a show's next aired episode), never
  one already in Continue watching, newest first, at most 20. Stalled reads `updated_at`, so a
  rating edit or an import makes an item fresh again.

`list_airs` in the tool layer wraps CAL-001.

### Discover (DISC-001)

`GET /v1/discover` is the one catalog read that is not a search: provider-curated public lists
for Home, the same for every user. `DiscoverService` (`Catalog/DiscoverService.swift`) asks each
adapter that conforms to `DiscoverListing` for its lists — TMDB `trending/tv/week`,
`tv/on_the_air`, `discover/tv` (premiered in the last 90 days), `trending/movie/week`,
`movie/now_playing`; AniList `Page.media` by `season`/`seasonYear` (popularity) and
`RELEASING` (trending); Open Library `trending/weekly.json`. A `DiscoverCache` actor holds them
in memory for 6 h, coalesces concurrent fetches into one, and serves the stale copy (then backs
off 5 min) when a refresh fails; a provider that fails drops only its rows. The API runs one
replica, so memory is enough; a second replica would hold its own copy (Valkey if that ever
matters). After the cache read, one `LibraryStore.itemIDs` query (type + tmdb/anilist/Open
Library id) sets `libraryItemId` on hits the caller already has. Nothing is personalised and
nothing is stored.

### MediaRef

```swift
struct MediaRef: Codable, Sendable {
    var titleId: UUID?
    var type: MediaType
    var ids: ExternalIDs
    var title: String?
    var year: Int?
}
```

Server resolves `MediaRef` → `Title` (find or hydrate) → `LibraryItem`.

## Provider adapters

Each adapter lives in `Server` (`Sources/App/Catalog`) and implements a narrow protocol. All
outbound calls go through one `ProviderClient` per provider (X-002): a token-bucket pacer
shared by every caller (TMDB 40/s, AniList 1.5/s, Open Library 3/s, TVmaze 1.8/s), retries with backoff on
429/5xx and network errors, and cancellation from the calling task. Failures surface as 502
`provider_unavailable`. Tests use a stub `HTTPTransport`; no test reaches a provider.

```swift
protocol CatalogSearching: Sendable {
    func search(query: String, type: MediaType) async throws -> [CatalogHit]
    func hydrate(ids: ExternalIDs, type: MediaType) async throws -> CatalogTitle
}

protocol MultiSearching: Sendable {        // TMDB search/multi, for type=all
    func searchMulti(query: String) async throws -> [CatalogHit]
}

protocol DiscoverListing: Sendable {       // DISC-001: public lists (TMDB, AniList, Open Library)
    var discoverLists: Set<DiscoverList> { get }
    func list(_ list: DiscoverList, now: Date) async throws -> [CatalogHit]
}

protocol UserLibraryImporting: Sendable {
    func importLibrary(userId: UUID, credential: ImportCredential) async throws -> ImportResult
}
```

### TMDB

- Search and detail for `movie` and `show`; `search/multi` for All
- Discover lists (DISC-001): `trending/tv/week`, `tv/on_the_air`, `discover/tv` (premiered in
  the last 90 days, at least 10 votes), `trending/movie/week`, `movie/now_playing`. Show rows
  drop anime (AniList serves those) and news, soap and talk genres; no IMDb lookups
- Season/episode lists when a show is added or when the user opens progress
- Map `imdb_id` from TMDB external IDs onto `titles.ids`

### Open Library

- Search and detail for `book`
- ISBN and cover URL
- Discover's books row: `trending/weekly.json` (DISC-001)

### Anime catalog (AniList)

Anime is first-class from Phase 1 (CAT-007…009).

- AniList GraphQL is the anime catalog. Reads need no key. Jikan is not used (it scrapes MAL);
  missing MAL ids stay missing until the anime mapping fills them.
- Discover's anime rows (DISC-001) are one `Page { media(type: ANIME, isAdult: false, ...) }`
  each: this season by `season`/`seasonYear` and `POPULARITY_DESC` (seasons by calendar
  quarter, UTC), and `status: RELEASING` by `TRENDING_DESC`. Search hits carry `startDate` as
  `releaseDate`.
- Every anime title stores `anilist`, `mal`, and `anidb` ids when known, plus `tmdb` when a
  cross-id exists.
- Matching: exact AniList↔TMDB cross-ids first. Never merge an AniList entry and a TMDB entry
  on name alone. An AniList season that TMDB folds into one show stays a separate `Title`
  unless a cross-id says otherwise.
- **Decided 2026-10-09:** anime is an `isAnime` facet on `show`/`movie`, not a fourth
  `MediaType`. Progress, calendar, Up Next, and widgets share one code path, and an anime film
  is still a movie. TMDB hits are flagged when they are Japanese animation.
- Community AniList → TMDB mappings live in `anime_mappings` (CAT-009/010). A mapped AniList
  entry resolves to the TMDB show; an unmapped one stays its own AniList-backed title, whose
  episodes come from AniList's airing schedule (one season per entry), named from AniList's
  streaming links ("Episode 3 - Name") when it has them, and "Episode N" otherwise.
- The mappings come from Fribb/anime-lists (MIT), loaded by `aaru --anime-mappings
  <path|url|default>` (CAT-010) and refreshed monthly by a CronJob. Only a TMDB **TV** id is
  kept: a film's TMDB movie id would attach it to whichever show shares the number. Anime
  titles created before a mapping existed keep their AniList episodes; they are found by their
  AniList id first and are never merged into the TMDB show.

### Trakt

- PKCE only: Trakt issues this app no client secret. The server holds the verifier; the browser
  carries a one-time `state` and the `code`. Redirect URI `https://api.<domain>/v1/imports/trakt/callback`
- OAuth user token stored encrypted at rest (AES-GCM, `TRAKT_TOKEN_KEY`), refreshed before expiry
- Pull watched history, watchlist, ratings, lists
- Map Trakt ids → TMDB/IMDb → `Title`
- First importer in the merge order

### Stremio history (IMP-016)

- Stremio's own device-link flow: `link.stremio.com/api/v2/create` gives a code, the user approves
  it on stremio.com (no password reaches Aaru), `read` then returns a session key. The client polls
  `POST /v1/imports/stremio/link/{code}`; Aaru keeps only the code, its owner and a 5-minute expiry
  (`stremio_link_requests`), because Stremio answers pending and expired codes the same way.
- On approval, one `api.strem.io/api/datastoreGet` reads every library item, then `api/logout`
  ends the session. The key lives in that request's local variables only: never stored, never
  logged. Unofficial API (what Stremio's apps call); used once per import.
- `StremioLibraryMapper`: `movie`/`series` only; removed-by-hand items are skipped, played-but-never-
  added (`temp`) ones come in if they were played. Watched film → finished (`lastWatched` as the
  finish date), started → in progress, otherwise wishlist. Only `tt…` ids match; add-on ids
  (`kitsu:`…) are listed unmatched.
- A show's `state.watched` is a bitfield over its Cinemeta episode list
  (`{anchorId}:{anchorLength}:{base64 zlib}`, LSB first, list sorted by season, episode, release).
  The worker fetches `v3-cinemeta.strem.io/meta/series/{tt}.json` once per show, lines the bits up
  by the anchor (stremio-core's rules), and ticks the episodes. Specials are left out; Cinemeta's
  numbering that disagrees with TMDB stays unticked rather than guessed.
- Second in the merge order, after Trakt. Then the normal plan → approve flow.

### CSV importers

Parse known column layouts:

- IMDb: title, year, title type, IMDb id (`tconst`), rating, date
- Letterboxd: Name, Year, Letterboxd URI, Rating, Watched Date (URI may yield a slug; resolve via TMDB search + year)
- Goodreads: Title, Author, ISBN, My Rating, Exclusive Shelf, Date Read

Unmatched rows are counted and listed on the job; they are not silently dropped without stats.

### CAT

- Text list of show names → TMDB search, first high-confidence hit
- ICS: extract show titles from event names; treat as tracked series (`wishlist` or `in_progress` if currently airing is knowable, else `wishlist`)
- No watched-episode import from CAT in v1
- No HTTP scraping of pogdesign.co.uk

## Import pipeline

```text
POST /imports/*  →  parse the file (bounded, 5 MB) into import_rows; the file is not kept
                 →  row in import_jobs (queued)
                 →  worker (leased: a job whose worker died runs again when the lease ends;
                    3 attempts with backoff, then failed with an errorSummary)
                      1. map each row to MediaRef (exact ids → title+year+type; match_aliases later)
                      2. hydrate Title (IDs + TMDB/Open Library)
                      3. merge rows that matched one title (anime seasons tick their TMDB
                         season), then decide: create / update (fill-empty, status forward
                         only, never past one the user chose) / skip / unmatched
                      4. job → planned (nothing written yet)
POST /imports/{id}/apply  →  decide again against the current library, then write every
                    create, update and list membership as ONE journaled batch action, so the
                    whole import undoes in one tap → succeeded / partial
```

File imports are a raw `text/csv` body rather than multipart: one file per request, and the
`filename` query parameter is all the extra the parsers need (Letterboxd's watchlist and watched
exports share columns). IMDb episode rows are listed as unmatched with a reason rather than
rolled up to their show (decided for IMP-006).

Merge when the same user imports several sources, in order:

1. Trakt  
2. Stremio history  
3. IMDb CSV  
4. Letterboxd CSV  
5. Goodreads CSV  
6. CAT  

Later sources fill empty fields; they do not overwrite a non-empty rating, status, or progress from an earlier source unless the incoming event is newer *and* the source is explicitly marked authoritative. v1 can skip “newer” and use fill-empty-only. That is enough.

Idempotency: re-running the same Trakt import updates in place via `(user_id, title_id)` and does not duplicate items.

## Agent tools

`DESIGN.md` makes the agent the way the user speaks to Aaru; `VIEWS.md` fixes what it may
render. This section fixes what it may call.

Tools are thin, typed wrappers over routes that already exist. No tool reaches Fluent or a
provider directly, and no tool returns vendor JSON.

| Tool | Wraps | Surface it feeds |
| --- | --- | --- |
| `search_titles` | `GET /v1/search`, `GET /v1/titles/{id}` | `TitleCard` |
| `plan_import` | dry run over `POST /v1/imports/*` | `PlanCard`, `MatchTable` |
| `apply_library_patch` | `PATCH /v1/library/items/{id}`, episode and season writes | `SeasonMap`, `TitleCard` |
| `list_airs` | library items joined to `show_episodes` air dates | `CalendarMonth` |
| `read_library` | `GET /v1/library/items`, `GET /v1/shelves/{id}/items` | `Shelf`, `TonightStrip` |

Rules:

- **Removing the tool layer must leave every feature reachable through the plain API.** The
  agent is a caller, never a privileged path.
- Argument validation is the same code the route uses. A tool cannot accept what a route
  rejects.
- Any mutation crossing more than one library item goes through a plan: a dry run returns a
  `PlanCard` payload, and apply names that plan id. A plan whose underlying library changed
  is rejected, not silently re-planned. First-run imports always plan.
- Autonomy — `ask me` / `fill empty only` / `overwrite if newer` — is stored user config read
  by the server. The model does not choose it.
- Every tool write goes through the same data layer as a user tap, so it lands in `actions`
  and is undoable. There is no agent-only write path.

The agent layer is Phase 7 (formerly "phase 1.5"). It is built after the native client, on
components that already work by direct touch. See M13 in `BACKLOG.md`.

## Outbound agent surfaces

The tool layer above has two transports besides Aaru's own composer. Both are **skins over
the same tools**. Neither adds a capability, a route behind the tools, or a write path.

| Transport | Where it lives | Notes |
| --- | --- | --- |
| App Intents / Shortcuts | `aaru-ios` | Each tool is an App Intent. `TitleCard` and `TonightStrip` serve as snippet views. No server work |
| MCP | `aaru-server/Sources/App/MCP`, `POST /v1/mcp` | Streamable HTTP, stateless, hand-rolled JSON-RPC. In the existing server — MCP is a transport, not a second backend. A folder, not a SwiftPM target (`aaru` is an executable target); it is registered by one line in `buildRouter` |

**This is not a public API.** Access is per-user and token-scoped: the user generates a token
in settings for their own agents. A documented third-party platform with quotas and
deprecation policy remains out of scope until there are real users. See `MARKETING.md` §3.4.

`agent_tokens` scopes, defaulting to read-only:

| Scope | Grants |
| --- | --- |
| `library:read` | `read_library`, `search_titles`, `list_airs` |
| `library:write` | `apply_library_patch` for a single item; plan proposal for anything larger |
| `imports:write` | `plan_import`, including capture. Never an apply |
| `scrobble:write` | `/v1/scrobble/*`, webhooks, and the Stremio addon's `player` events and `watched` marks (Phase 3). Never an untick, add, or remove |

A Stremio token (`kind = stremio`) gets `library:read` (its catalogs) and `scrobble:write` by
default. `library:write` is an opt-in at connect time and only lets Stremio's `unwatched` and
`libraryAdd` events through.

An MCP token (`kind` = `claude_code`, `codex`, `hermes`, `gemini` or `other`) gets
`library:read`, plus `library:write` when the user allows changes and `imports:write` when the
user allows imports at connect time; never `scrobble:write`. The kind only picks the setup Settings shows (`GET /v1/agent/setup/{kind}`,
written once on the server for web and Apple). Secrets carry a per-surface prefix
(`aaru_st_`, `aaru_mcp_`) and a token authenticates only on its own surface. The tools live in
`aaru-server/Sources/App/Agent/AgentTools.swift`, transport-neutral, and answer the `/v1` DTOs.

### Remote approval

An external caller holding `library:write` cannot write more than one item directly. It gets
a plan id, and the plan waits for the user **in Aaru**:

1. The caller calls a `plan_*` tool; the server returns a plan id and a human summary.
2. Aaru renders it as a `PlanCard` labelled with the calling token's name, and pushes a
   notification. Until The Field exists, pending plans pin to the top of Home.
3. The user approves or denies via `POST /v1/plans/{id}/approve` or `/deny`. There is no
   route by which a caller approves its own plan, and no scope grants it.
4. Apply runs through the same data layer as a tap: one `actions` row, `actor =
   external_agent`, `agentTokenId` set, inverse recorded, undoable.
5. Denials are recorded too, on the `agent_plans` row (`status = denied`), so the ledger
   answers what a token tried to do. The `actions` journal keeps only undoable writes.

Plans are stored as the exact `LibraryOp` batch worked out at proposal time
(`LibraryService+Prepare.swift`) plus a basis: each touched item's `updated_at` and the titles
being added. Approval re-checks status, expiry (24 h) and basis inside one transaction, then
runs the op and journals it (`PostgresPlanStore.approve`). A token has at most 20 plans
waiting; revoking it expires them.

Rules:

- A single-item write within scope may skip the plan, because that is what a user tap does.
  An external caller gets a tap's power, never more.
- Plans expire, and a plan whose library changed since the dry run is rejected rather than
  re-planned. Unchanged from the agent-tools rules above.
- Agent tokens go through the central rate limiter (X-002). A token is not a bypass.
- Every rule in "Agent tools" applies unchanged. In particular: deleting `App/MCP` must leave
  every feature reachable through `/v1`.

### OAuth front door (Claude's connector)

Claude (claude.ai, Desktop, mobile) adds a remote MCP server as a custom connector, and a
connector authenticates with OAuth per the MCP authorization spec. `aaru-server/Sources/App/OAuth`
is that front door, hand-written like the MCP route:

| Endpoint | Role |
| --- | --- |
| `GET /.well-known/oauth-protected-resource[/v1/mcp]` | RFC 9728: the resource is `/v1/mcp`, the issuer is the API |
| `GET /.well-known/oauth-authorization-server` | RFC 8414 metadata |
| `POST /oauth/register` | RFC 7591. Every client is public (`none`); https or loopback redirects |
| `GET /oauth/authorize` | S256 PKCE only. Sets the `aaru_oauth` binding cookie, sends the browser to the web consent page |
| `POST /oauth/token` | Code (60 s, once) or refresh token (30 days, rotated) for an access token (one hour) |
| `POST /oauth/revoke` | RFC 7009 |
| `GET/POST /v1/oauth/requests/{id}[/approve, /deny]` | The consent page's answer: session plus binding |

The consent page lives in `aaru-client` (`/oauth/consent`) and holds no rules: it forwards the
session and the binding cookie, which the API sets on `OAUTH_COOKIE_DOMAIN` (the parent of the
API and web hosts). Tokens are `agent_tokens` rows (`issuance = oauth`), so an OAuth client gets
exactly an MCP token's scopes, lists in Settings, and is revoked the same way. A reused code or a
replayed refresh token revokes the connection.

### Model provider

The agent's model is pluggable, in the same narrow-protocol style as the catalog adapters.

```swift
protocol ModelProviding: Sendable {
    func complete(_ request: ModelRequest) async throws -> ModelResponse
}
```

- Anthropic adapter is the default. Keys live in environment config.
- A user may supply their own encrypted key, which lifts the fair-use cap.
- `agent_usage` meters spend per user per day from the first call, not later.

## Auth

- Sign in with Apple is the primary native path. The server verifies the identity token
  against Apple's JWKS (signature, `iss`, `aud` ∈ `APPLE_AUDIENCES`, `exp`, and the nonce:
  the client sends Apple `sha256(rawNonce)` and sends us `rawNonce`). Accounts are keyed on
  Apple's `sub`, never on email. An unknown `kid` refreshes the key set once, then fails
  closed — checked by Aaru, because jwt-kit silently falls back to its default key.
- Sign in with Google (AUTH-005) verifies Google ID tokens the same way, against Google's JWKS
  through the same cache: `iss` is `accounts.google.com`, `aud` ∈ `GOOGLE_CLIENT_IDS` (the iOS
  and web OAuth client ids, public), `exp`, and the nonce when the client sent one. Accounts are
  keyed on Google's `sub`; an email is stored only when Google says it is verified. A signed-in
  user links Google with `POST /v1/me/identities/google`. Two accounts are never merged on a
  shared email; a Google account already on another user is a 409. The Apple apps get the ID
  token with the OAuth code flow + PKCE in `ASWebAuthenticationSession` (an iOS-type client has
  no secret); the web uses Google Identity Services. Both pass a nonce Aaru checks.
- Email is a **magic link** (decided 2026-10-09): `POST /v1/auth/email/link` emails a one-time
  link via Resend; `POST /v1/auth/email/verify` exchanges it. No passwords are stored. Links
  live 15 minutes, are single-use (consumed in one `UPDATE … RETURNING`), and are rate-limited
  per address (5/h) and per client (20/h). Without `RESEND_API_KEY` the route answers 503.
- Sessions are **opaque bearer tokens** (decided 2026-10-09): 32 random bytes, shown once;
  Postgres stores only the SHA-256 in `sessions`. 90-day lifetime. Revocation is a row delete.
  `AuthMiddleware` resolves the token and refuses every `/v1` route except health and auth.
- Provider tokens (Trakt) are stored separately and never sent to the client.

## Clients

### Native (MVP)

SwiftUI, `AaruCore` client, URLSession.

Minimum screens:

- Sign in
- Home / library (filter by type and status)
- Search and add
- Discover (DISC-001's rows as a tab/page, APP-012) and Insights (stats), pulled forward 2026-10-20
- Title detail (status, rating, notes, TV episodes)
- Lists and shelves
- Undo ribbon over the last write
- Settings → connected sources, autonomy setting, and import status

Local cache: display last successful library fetch offline. No offline write queue in v1 unless it falls out naturally.

Prefer a single multiplatform target for iPhone and Mac.

Screens are composed from the `VIEWS.md` component catalog. Every component must be usable
by direct touch before the agent is allowed to emit it — a failed model call should degrade
to a working screen, never a blank one.

### Widgets and Live Activity

The widget extension lives in the same `aaru-ios` project and serves iOS and macOS.

- **Data path:** the app writes a JSON snapshot (Up Next, today's airings, the week, and later
  the streak) to the App Group container after every successful library fetch or write, then
  calls `WidgetCenter.reloadAllTimelines()`. The widget reads only the snapshot. This is the
  LuminaVault `WidgetSnapshotStore` pattern. A widget never holds a session or calls the API
  on its own.
- **Interactive:** "mark watched" on the Up Next widget is an App Intent that performs the same
  `PUT …/episodes/{s}/{e}` a tap does, through the shared API client, then refreshes the
  snapshot. This follows Khepri's `LogWaterIntent`. It is journaled in `actions` like any tap.
- **Live Activity:** "now watching" shows the episode, progress, and an Ends-at / time-left
  toggle. The app starts it on check-in; scrobbles (Phase 3) can update it.
- **macOS widgets** come from the same extension and the same snapshot. No second widget
  codebase.

App Group id: `group.$(PRODUCT_BUNDLE_IDENTIFIER)`, so beta and prod builds never share a
snapshot.

### Web (`aaru-client`)

SolidJS + TanStack Start on Cloudflare Workers, Tailwind 4. Decided 2026-10-14 (replaces the
SvelteKit scaffold). Same screens as the Apple apps, in the same order they ship.

- Session: the token lives in an HttpOnly, Secure, SameSite=Lax cookie. Server functions send
  `/v1` calls with it; page scripts never see the token. A 401 clears the cookie once.
- API types come from the same `openapi.yaml` as the Apple apps' `AaruAPI` (`openapi-typescript`,
  committed, checked fresh in CI).

- The landing pages (product, waitlist, legal) are a route group in the same app, so there is no
  separate marketing site.
- The logged-in library uses the same `/v1` API as native, with the same screens where they make
  sense: home rows, `WeekGrid`, Title room, lists, settings.
- It is a pure client: no database binding, no business logic, no vendor calls. A rule that
  matters lives on the server.
- Do not fork DTO meaning for the web.

## Tracking integrations (Phase 3)

### Scrobble ingest

- `POST /v1/scrobble/{start|pause|stop}` takes a Trakt-compatible body: movie or episode ids
  plus `progress` as a percent. A client or bridge that already speaks Trakt's scrobble shape
  only needs a base URL change.
- Each call writes a `watch_events` row (user, title, episode, progress, source, timestamp).
  A `stop` at **≥ 80%** marks the episode or movie watched through the same data layer as a tap,
  so it lands in `actions` and is undoable. 80% is Aaru's own documented threshold.
- `start` and `pause` feed the "now watching" Live Activity and, later, room drift
  (ROOM-004). They never change progress.
- Auth is a scoped per-user token on the `agent_tokens` model with a `scrobble:write` scope. A
  scrobbler gets no more than that scope.
- **Webhooks:** `POST /v1/webhooks/plex` (`media.play`, `media.stop`, `media.scrobble`) and
  `/v1/webhooks/jellyfin` translate into the same scrobble calls. Jellyfin `PlaybackStop`
  counts only past the threshold, never on its played flag.
- **Stremio:** an addon served by `aaru-server` under `/stremio/{token}/manifest.json`, outside
  `/v1` because the protocol fixes the paths. It exposes catalogs (Continue watching, Next 7 days,
  Plan to watch; ids unchanged since 2026-10-20's relabel), `meta` for titles without an IMDb id, and receives Stremio's `player` and `library`
  events (stremio-core PR #1070, core-web v0.64, Stremio Web and Stremio 5 desktop). Player events
  feed the scrobble service; `library` `watched` marks tick episodes; `libraryRemove` is always
  ignored. The token is minted in Settings. It serves no streams, ever. No subtitles-request
  inference.

### Outbound sync

Trakt history push (SCR-004) and MAL / AniList progress push (SCR-005) are **one-way out**.

- Aaru writes to them after its own write commits.
- What it pushed is never read back as a conflict source, and a remote change never overwrites
  Aaru. Imports stay one-way in.
- Tokens live in `outbound_connections`, encrypted at rest.
- MAL uses OAuth with PKCE. AniList uses `SaveMediaListEntry`.

## Social (Phase 4)

Modelled on Norviq's `social_*` design (`norviq-backend/.../Social`, `CreateSocialTables`).

| Table | Shape |
| --- | --- |
| `social_friend_requests` | from, to, status `pending` / `accepted` / `declined` / `cancelled` |
| `social_friendships` | one row per pair, ordered ids, `created_at` |
| `social_blocks` | blocker, blocked |
| `social_reports` | reporter, target, reason |
| `social_invites` | code, inviter, redeemed_by, expiry |
| `social_settings` | `profile_visibility` (default `private`), `show_points`, `show_streaks`, `leaderboard_opt_in` |

Rules:

- **Private by default.** A new account is invisible until the user changes
  `profile_visibility`. Friend-only is the most open default Aaru ever offers. There are no
  public profile pages indexed by search engines.
- **A block is invisible.** A blocked user gets `404` for everything about the blocker, the
  same response as for a user who does not exist. Blocks apply both ways in feeds,
  leaderboards, rooms, and DMs.
- Friend activity and "Today" stories read `watch_events` and journaled progress, filtered by
  friendship and settings at query time. There is no fan-out table.

## Gamification (Phase 5)

Modelled on Norviq `gamification_xp_events` and Loci `points_events`.

- **Ledger, not counter:** `points_events(user_id, kind, points, dedupe_key, created_at)`,
  unique on `(user_id, dedupe_key)`.
  - Every award goes through one idempotent `award` that inserts and ignores duplicates. A
    re-ticked episode or a replayed scrobble earns nothing twice.
  - `user_progress` (total, level, current and longest streak) is a cache rebuilt from the
    ledger, never the source.
- **Kinds:** episode watched, movie or book finished, scrobbled stream, friend added, room
  joined, import completed.
  - Daily caps per kind.
  - Un-checking does not earn points; it writes a negative event with the same dedupe root.
- **Friend added** counts only when the friendship is mutual. It is reversed if the friendship
  ends within N days.
- **Levels:** `50·L·(L−1)` XP to reach level L.
- **Streaks:** daily `check_ins(user_id, local_date, time_zone)`, with the time zone from the
  client's `X-Timezone` header.
- **Badges:** `user_badges(user_id, badge, tier)`. Definitions live in code, not the DB.
- **Leaderboards** are friends-only, weekly, and opt-in.

## Realtime, messaging, and watch together (Phase 6)

### Realtime gateway

- `GET /v1/ws` behind the same JWT as `/v1`.
- One in-process `ConnectionManager` actor keyed by user, as in LuminaVaultServer. It carries
  presence, room events, and message-arrival notices.
- **Single replica** is assumed and documented. Cross-pod fan-out (Valkey pub/sub) is added
  when a second replica is needed, not before.
- The template `/ws` echo is deleted in SRV-001; this is a fresh gateway.

### Messaging (libsignal)

DMs are Signal-grade: `libsignal` on the clients, with forward secrecy and multi-device. The
server never sees plaintext.

- **Key directory per device:** identity key, signed prekey, and a pool of one-time prekeys in
  `devices` / `signal_*`. Clients replenish one-time prekeys when the pool runs low. A user has
  a device list; a sender encrypts once per recipient device.
- **Message store:** `message_envelopes` holds ciphertext addressed to one device, deleted after
  delivery is acknowledged. Delivery goes over `/v1/ws` when online and APNs when not.
  Attachments are out of the first cut.
- **iOS/macOS:** `LibSignalClient` (Swift). Keys stay in the Keychain. Safety numbers are
  shown for verification.
- **OPEN (DM-004):** web DMs. libsignal's TypeScript package is Node-native and does not run in
  a browser or a Worker. Options are a WASM build, or native-only DMs with the web showing
  "open on your device".
- **OPEN (licence, before DM-003):** libsignal is AGPL-3.0. Shipping it in a closed-source App
  Store app likely obliges publishing the app's source. Decide before any client code links it.

### Watch together

- Rooms (`rooms`, `room_members`) are created from a title or episode. Members are invited from
  friends.
- A room runs over `/v1/ws`: a countdown to "press play", reactions, and a shared check-off at
  the end that writes each member's own progress through the normal data layer.
- Aaru owns no player, so it does not sync playback. It can show drift from scrobbles ("Ana is
  2 min ahead").
- SharePlay (`GroupActivity` with `.generic` metadata + `GroupSessionMessenger`) is a layer on
  top of rooms for Apple users. It does not replace them.

## Push

- APNSwift in `aaru-server`.
- `apns_devices(user_id, token, environment, bundle_id)` stores the APNs environment per
  token, so the TestFlight `.beta` app and the App Store app share one API.
- Notification categories (requests, messages, rooms, airing) have per-user preferences.
- Airing alerts shipped early (2026-10-15): an in-process job every 10 minutes, each episode
  claimed in `notifications_sent` before it goes out. The payload carries `libraryItemId`, which a
  tap opens. The other categories arrive in Phase 4; until then remote approval stays a pinned
  artifact in The Field.
- Web push (2026-10-20): browsers subscribe with the VAPID public key (`GET /v1/web-push/key`)
  and save the subscription (`PUT /v1/web-push/subscriptions`, one row per endpoint in
  `web_push_subscriptions`). Only the browsers' own push services are accepted as endpoints, so
  the server never POSTs anywhere else. The same airing job fans out to APNs devices and browser
  subscriptions behind `WebPushSending` (named for the wire format). The web's `public/sw.js` has
  no fetch handler: it shows the alert and opens the same-origin path the alert carries.

## Phasing

`BACKLOG.md` holds the tickets. This is the shape and the gates.

| Phase | Scope | Exit gate |
| --- | --- | --- |
| 0 — Rails | Root CI, Xcode project (iOS + macOS + widget extension, Beta config), fastlane, server image → infra, Workers deploy, SRV foundation | Empty app ships to TestFlight beta; API health live on the cluster; web beta Worker live |
| 1 — Basics | Auth, catalog (TMDB, Open Library, AniList), library, action journal, TV/anime progress, lists, shelves, calendar, Up Next | API complete for a personal tracker |
| 2 — Clients, widgets, imports | iOS + Mac app, widgets + Live Activity, web client, Trakt/CSV/CAT/TV Time/MAL/AniList imports | **Basics done:** beta app and beta web usable end to end, widgets work |
| 3 — Tracking integrations | Scrobble ingest, Plex/Jellyfin webhooks, Stremio addon, outbound Trakt/MAL/AniList | Scrobble from at least one player lands as journaled progress |
| 4 — Social | Profiles, friends, blocks, invites, friend activity, push | Two accounts can friend, see each other's activity, and block cleanly |
| 5 — Gamification | Points ledger, levels, streaks, badges, friend leaderboards, stats | Replaying any event earns nothing twice |
| 6 — Realtime, DMs, rooms | WebSocket gateway, libsignal DMs, watch-together rooms, SharePlay | Server stores only ciphertext; a room can count down and check off together |
| 7 — Agent surfaces | Composer, The Field, tool layer, capture, App Intents, MCP, remote approval (M13, M14) | See M13/M14 in `BACKLOG.md` |

Phase 7 keeps its existing scope and spec
(`docs/superpowers/specs/2026-09-07-agentic-surfaces-design.md`). It needs only the action
journal and saved queries from Phase 1, so it may be pulled forward after the Phase 2 gate.

**Gate rule:** no social, gamification, realtime, messaging, or scrobble code is written
before the Phase 2 gate. That includes WebSocket handlers, follow graphs, and points tables
added "to save time later". Nullable hooks that already exist (such as `visibility`) are
the only allowance. Exception by the owner's call (2026-10-19): agent tokens for Stremio, the
scrobble service, and the Stremio addon. And (2026-10-20): Discover rows (DISC-001) and the Discover
tab/page on them, Insights (GAM-006c, part of P5's stats) and Home's stats strip, with no new
tables. And (2026-10-20): agent connections, MCP with its OAuth front door, and remote
plans/approvals (OUT-001/002/004, AG-001's tools, AG-003's remote-plan slice).

## Deployment

One backend. API and workers run as one binary at first (`Application` + job consumer
in-process); split the workers when imports block request latency. Background services in the
same process: `ImportWorker`, the airing notifier (every 10 minutes) and `CatalogRefreshService`
(every 5 minutes: up to 40 tracked shows per pass, never-loaded first, then past their CAT-006
window; an attempt is stamped on `titles.episodes_attempted_at` and not retried for an hour).

### Infra

- **Host:** the `maat` k3s cluster (node `lumina-green`), sourced from
  `~/Work/production/platform/infra` (`LuminaVault/LuminaVaultInfra`). ArgoCD auto-syncs
  `argocd/apps`, so merging to `main` deploys.
- **Edit only that repo.** An app-local `*-infra/` copy deploys nothing.
- **Namespace:** `horus`. It is default-deny ingress, so `aaru-api` needs an allow rule in
  `cluster/network-policies/horus.yaml`, and so does anything that calls it in-cluster.
- **Postgres:** one StatefulSet for Aaru with a backup CronJob, the same shape as
  `apps/norviq/data/postgres.yaml`.
- **Apps:** `argocd/apps/aaru-api-production.yaml` and `aaru-data` on `charts/norviq-app`, with
  `apps/aaru/{api,data}/values-production.yaml`. Public ingress through Traefik +
  cert-manager.
- **Secrets:** sealed-secrets. A blob is bound to **both** namespace and secret name; seal for
  `horus` and the exact name, or the key silently never appears. TMDB, Trakt, Anthropic, APNs,
  and JWT keys are environment variables from sealed secrets.
- **Transcription,** if capture ever needs it, uses the in-cluster `whisper.horus` service and
  never a paid speech API.
- Rate-limit provider adapters centrally so two users importing Trakt cannot stampede TMDB.

### Release channels

| Channel | Native | Web | API |
| --- | --- | --- | --- |
| Beta | TestFlight, `.beta` bundle id suffix, `Beta` build config, own App Group | staging Worker (`env.staging` in `wrangler.jsonc`) | **prod** |
| Prod | App Store | prod Worker (`wrangler.jsonc`) | prod |

- Beta is client-side only. There is no staging backend.
- **Server:** CI builds `ghcr.io/…/aaru-server:<sha>`, then opens a promote PR in the infra repo
  that bumps `values-production.yaml`. Merging that PR is the deploy (Khepri pattern).
- **Native:** fastlane lanes `beta`, `release`, `hotfix`, `seed_signing`, with `release.yml` on
  `workflow_run` after CI passes on `main` (Khepri pattern).
- Because beta clients hit prod, API changes must stay backward-compatible with the App Store
  build that is live.

## Decisions already made

| Topic | Decision |
| --- | --- |
| Product | One app: library + tracking. Social, gamification, realtime after the Phase 2 gate (2026-10-09). |
| Source of truth | Aaru after import |
| Video catalog | TMDB |
| Book catalog | Open Library |
| Primary user import | Trakt |
| CAT | Manual list / ICS only |
| Scraping | Forbidden |
| Backend | Hummingbird only |
| First clients | iOS and Mac, with widgets and a Live Activity |
| Web | `aaru-client`: SolidJS + TanStack Start on Cloudflare Workers, pure `/v1` client at parity with the Apple apps (2026-10-14; SvelteKit 2026-10-09 to 10-14) |
| Beta | Client-side only: TestFlight `.beta` + staging Worker, both on the prod API. One backend (2026-10-09) |
| Anime | First-class from Phase 1: AniList catalog, `anilist`/`mal`/`anidb` ids (2026-10-09) |
| DMs | Signal-grade via libsignal; server stores ciphertext only. Licence and web are OPEN (2026-10-09) |
| Social | Opt-in, private by default, friends-only; built after the Phase 2 gate (2026-10-09) |
| Points | Append-only ledger with dedupe keys; totals are a cache (2026-10-09) |
| Host | `maat` cluster, `horus` namespace, via `platform/infra` only |
| Ownership vs status | Prefer `isOwned` + consumption `status` |
| Status labels | Stored values fixed; UI labels per kind (Plan to watch / Watching / Watched; Plan to read / Reading / Read) (2026-10-20) |
| Discover | DISC-001: provider-curated public rows, the same for every user. The cache holds no user data; `libraryItemId` is marked per caller after it. Not a recommendations engine (2026-10-20) |
| Shelf vs list | Shelf is a saved query, list is membership. Never merged. |
| Agent writes | Journaled in `actions` and undoable. No agent-only write path. |
| Agent UI | Native component catalog only. No model-authored layout. |
| Third-party agent access | Per-user, token-scoped, over the same tool layer. Not a public API. |
| External agent writes | Single item like a tap; anything larger proposes a plan the user approves in Aaru. |
| Agent model | Pluggable `ModelProviding`. Anthropic default, own key supported, spend metered per day. |
| Capture | An import source, not a subsystem. Renders `MatchTable` then `PlanCard`. Never writes unplanned. |
| Match ledger | `match_aliases` is aggregate catalog data: no user ids, no user rows, day-granular dates, two confirmations to promote, published in full. |

If a change violates a row in that table, update this file in the same PR.
