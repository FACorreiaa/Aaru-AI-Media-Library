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
    case movie, show, book, album, manga   // album: MUS-001, manga: MNG-001
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
    var musicbrainz: String? // MUS-001: an album's release-group MBID
}
```

Anime is not a fourth `MediaType`. See "Anime catalog" under provider adapters. Manga is its
own kind (MNG-001, 2026-10-23): AniList serves it, but it reads like a book, not like anime.

MyAnimeList numbers anime and manga separately, so `titles.mal` is unique per list: one partial
index over manga and one over everything else. AniList ids share one space and stay globally
unique.

### Title (catalog)

A canonical work Aaru knows about. Created on first add or during import hydration.

- `id` — Aaru UUID
- `type` — `MediaType`
- `title`, `originalTitle`, `year`
- `synopsis` (optional, from catalog)
- `posterURL` (catalog URL, not hosted)
- `ids` — `ExternalIDs`
- `byline` — authors for books, the story and art credits for manga, the artist credit for albums
- `chapterCount`, `volumeCount` — manga only, when AniList knows them
- `seasons` — only for shows; episode lists may be lazy-loaded
- tracklist (server-only, MUS-001) — `album_tracks`, an album's earliest official release,
  stored the first time its page opens (`tracks_hydrated_at`, refreshed after 30 days) and
  returned on `TitleDetail.tracks`. Never ticked
- `genres` (server-only, CAT-018) — the provider's genre names, stored at hydration (TMDB,
  AniList; books none) and backfilled by the catalog refresher. Not on the `Title` DTO; the
  stats read them

Titles are shared across users. Do not put ratings or status on `Title`.

### Library item (user data)

- `id` — Aaru UUID
- `userId`
- `titleId`
- `status` — `wishlist` | `in_progress` | `on_hold` | `finished` | `dropped` (consumption only).
  `on_hold` (LIB-007) is paused on purpose: no calendar, Up Next, Tonight or airing alert reads
  it, stats and counts do, and a new episode tick or reading position moves it to `in_progress`
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
- Manga: optional `chapter` / `volume` (MNG-001), the last ones read. An import moves them forward only

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
- `live_activity_tokens` (ActivityKit push tokens: a device's push-to-start token, or its running activity's own; SCR-008, per user since SCR-009)
- `live_plays` (SCR-009: what plays that is not a Title, a `playing_now` track or a YouTube video; one row per connection and kind, replaced by the next report, deleted once `expires_at` passes)
- `live_activity_states` (SCR-009: per user, what the "Now playing" activity last showed, the "Watched" rows lingering, a `version` for compare-and-swap, and `next_check_at` for the sweep)
- `agent_plans` (an outside agent's change waiting for approval: the op, its basis, status, the token)
- `agent_tokens` (per-user agent access: `kind` (`stremio`, or an MCP client: `claude_code`, `codex`, `hermes`, `gemini`, `other`), hashed secret, scopes, `lastUsedAt`, revocation)
- `agent_usage` (model spend per user per day: tokens in and out, cost in cents)

Later-phase tables, listed so nobody invents a parallel shape. None is created before its
phase:

| Phase | Tables |
| --- | --- |
| 3 | `watch_events`, `outbound_connections` (Trakt / MAL / AniList tokens, encrypted) |
| 4 | `social_friend_requests`, `social_friendships`, `social_blocks`, `social_reports`, `social_invites`, `social_settings`, `apns_devices` |
| 5 | `points_events`, `user_progress`, `check_ins`, `user_badges` (pulled forward 2026-10-22) |
| 6 | `devices`, `signal_identity_keys`, `signal_signed_prekeys`, `signal_onetime_prekeys`, `conversations`, `conversation_members`, `message_envelopes` |

Groups (pulled forward 2026-10-20) bring `profiles`, `social_friend_requests`,
`social_friendships`, `social_blocks`, `social_reports` and the `group_*`, `watch_sessions` and
`agent_replies` tables early; see §Groups. Rooms are `watch` channels, so there is no `rooms`
table.

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

- `source` — import source (`trakt`, `imdb_csv`, `letterboxd_csv`, `goodreads_csv`, `cat_list`, `cat_ics`)
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
POST   /v1/titles/resolve                 # LIB-006: a MediaRef's page; catalog only, never the library

GET    /v1/calendar?from=&to=             # CAL-001
GET    /v1/up-next                        # UPN-001; counts + unfinished UPN-002
GET    /v1/discover                       # DISC-001
GET    /v1/discover/on-air?region=        # DISC-003

GET    /v1/library/items
GET    /v1/library/watching           # in-progress films/shows/anime + airing, next episode, time left (APP-018)
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
POST   /v1/imports/cat                    # text/plain list or text/calendar ics (IMP-009/010)
POST   /v1/imports/cat/feed               # {url}: the user's CAT iCal link, read once, not kept
POST   /v1/imports/capture                # AG-006: JSON {text} | {url}, or an image body; 402 past the free quota
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
`/v1/keys/*`, `/v1/conversations/*` (6). Pulled forward with groups (2026-10-20):
`/v1/me/profile`, `/v1/social/*` (friends, requests, blocks, reports, invite links), the public
invite preview `/v1/invites/{code}`, `/v1/groups/*`,
`/v1/group-invites/*`, `/v1/me/group-invites`, `/v1/realtime/ticket` and `/v1/ws`.

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
response adds `span` (`month` | `year` | `all`), `byKind` (`movie` | `show` | `anime` | `book`,
then `album` only when the period finished one, so pre-MUS-001 clients keep decoding:
episodes, minutes, finished; albums never have minutes) and `ratings.distribution`: ten bins, index `ceil(rating) - 1`,
so a 7.5 counts as an 8. No new query and no table.

The last 7 and 30 days (GAM-006d) are `span=last7|last30`: the local days ending today in `tz`,
one bucket per day, `from`/`until` inclusive. The service reads the window and the equal-length
window before it in one `activity` call, splits the rows at the window's first day, and digests
each; the earlier one returns only as `prior` totals, for the clients' deltas. Same rows, same
rule on imported ticks, no new query and no table.

The Year in Review (GAM-006e) reads `titles.genres` (CAT-018) in the same query and derives
`topGenres`, `biggestDay` and `persona` in `StatsDigest`. The persona rule lives in the server;
clients only map its key to words.

The whole show marked watched (PROG-005) journals as kind `show`, and its ticks are marked
unknown the same way an import's are (`PostgresLibraryStore.undatedKinds`), so a 60-episode mark
never lands on today. `PATCH status: finished` on a show and adding a show as finished go through
the same rule in `LibraryService`.

The profile (GAM-006b, `GET /v1/me/profile/stats`) is the other read: `StatsStore.library` returns
one row per library item with all its ticks, dated or not, and `ProfileDigest` derives the
all-time numbers. It is the library's state, not activity, so it may exceed `span=all`. No table.

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
  CAL-004: neither read calls a provider. `CatalogRefresher` loads episodes in the background
  (every minute, back to back while a pass is full). `pendingShows` counts tracked shows never
  attempted, so a client waiting on an import asks again until it reaches 0.
- **UPN-001 `GET /v1/up-next`** returns, per `in_progress` show, the next unwatched aired
  episode, runtime, episodes left and time left ("10 left · 8h 40m"), and a finale flag
  (last episode of the season). Ordered by last activity. It feeds `ContinueRow`, the Up Next
  widget, and the Live Activity.
- **UPN-002** adds two optional fields. `counts` is items per status (`wishlist`,
  `inProgress`, `onHold`, `finished`, `dropped`) for Home's chips. An `on_hold` item is never
  in Continue watching, the calendar or Unfinished (LIB-007). `unfinished` feeds `UnfinishedRow`:
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

**Seasons (DISC-002).** `GET /v1/discover/season` lists one season of one kind a page at a time.
`SeasonKey` (`Catalog/DiscoverSeasons.swift`) is a calendar quarter in UTC, the same for every
kind. Adapters conforming to `SeasonBrowsing` serve it: AniList `Page(page:, perPage: 50)` by
`season`/`seasonYear` with GraphQL variables; TMDB `discover/tv` by `first_air_date` (new) or
`air_date` with `first_air_date` before the season (returning), and `discover/movie` by
`primary_release_date`. A `SeasonCache` actor holds pages by kind, season and page (LRU, 200
entries; 6 h, or 7 days for a season that has ended), coalesces fetches and serves stale on
failure; nothing cached and the provider down returns `unavailable: true`. Marking against the
library is the same `DiscoverService.mark` the rows use.

**On air (DISC-003).** `GET /v1/discover/on-air` is the week's airings by channel. `TMDBCatalog`
(`Catalog/TMDBCatalog+OnAir.swift`, as `OnAirListing`) reads `tv/on_the_air` pages 1–2 through the
TV row filter, then one `tv/{id}?append_to_response=external_ids,watch/providers` per show (40 at
most): its first network (name and logo), `next_episode_to_air` (kept within a day back and
eight ahead) and every country's flat-rate services. An `OnAirCache` actor
(`Catalog/OnAirGuide.swift`) holds the guide for 6 h and serves a stale copy while it refetches.
It publishes the guide with dates first, then refines the times in a second, unstructured pass:
`TVmazeAirTimes.nextAirTime` (as `NextEpisodeTiming`, two calls per show through TVmaze's
1.8/s pacer) gives the exact instant, kept only within CAT-011's two-day tolerance. No viewer
waits on that pass. Per request, `DiscoverService.onAir` marks hits with `mark`, picks the
caller's `region` (two letters, from the device language, never stored; else 422), and drops
from "streams on" the channel itself and JustWatch's resellers ("… Amazon Channel", "… with
Ads"), keeping three at most. Channels are ordered by show count, then by name, with "Other"
last, and each channel's shows by next air time.

**Album rows (MUS-002).** `ListenBrainzReleases` (`Catalog/ListenBrainzReleases.swift`, no key,
1 req/s with a contact User-Agent) serves `music_new` and `music_upcoming` through the same
`DiscoverListing` and cache. Each list is two calls: `explore/fresh-releases` (30 days back, or
30 days ahead) and a sitewide stat for this month (`stats/sitewide/release-groups` for New
albums, `stats/sitewide/artists` for Coming soon), because fresh releases carry no listens of
their own. Hits are `album`s keyed by the release-group MBID, so marking works; covers are Cover
Art Archive release URLs. `CatalogProviders.releases` is optional: without it the rows are absent.

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

### MusicBrainz (MUS-001)

- Search, hydrate and tracklist for `album`: release groups of type Album or EP
  (`ws/2/release-group`, Lucene query with the user's punctuation escaped), lookup with
  `inc=artist-credits+genres` (top five genres by count), and `ws/2/release?release-group=`
  for the earliest dated official release's tracks
- One `ProviderClient` paced at 1 request/s, `User-Agent` with a contact, as MusicBrainz asks
- Covers are Cover Art Archive URLs (`release-group/{mbid}/front-250`), square, never hosted
- `CatalogProviders.music` is optional; without it album search is `incomplete` and album pages
  show no tracklist
- Listens (MUS-006): `ListenResolver` runs every minute and asks `ws/2/recording` once per track
  and album (`rid:` when the scrobbler sent a recording id, else `isrc:`, else the exact artist
  and title). Only a score-100 recording with the same folded title and artist counts; the album
  is the release group named like the listen's album, or the only Album/EP when none was sent.
  Answers, misses included, live in `music_lookups` (shared, keyed by track and album) and fill
  new listens as they are stored; a miss is asked again after 30 days. It uses the same
  `MusicBrainzCatalog`, so album search and lookups share the one-a-second pacer. A listen's
  `albumRef` points at the album by MusicBrainz id, and by Aaru's title id once it is in the catalog
- `artists(releaseGroup:)` (MUS-003) gives an album's credited artists by MBID for concerts

### Concerts (MUS-003)

`Sources/App/Concerts/`, behind `ConcertListing` (named for the job). `TicketmasterConcerts`
calls Discovery v2 with `TICKETMASTER_API_KEY`; without the key `CatalogProviders.concerts` is
nil and every concert answer is `unavailable` (`GET /v1/me/concert-place` says `available: false`
and clients hide the view). Paced at 4/s; a `CallBudget` stops at 4,500 calls a UTC day.

- **Near a place.** `POST /v1/concerts/near` (POST so a position never sits in a URL). A one-off
  position is rounded to two decimals (`GeoPoint`) and used once; otherwise the saved city
  (`concert_places`, one row a user, rounded, deleted with the account); neither is 409
  `no_place`. Ticketmaster gets only the 5-character geohash cell (~5 km) plus the radius
  (25/50/100 km); the cell also keys `ConcertCache` (6 h, stale served on failure, 500 entries).
  Nothing logs the point; the cache's failure log names only the kind of query.
- **Your artists on tour.** `album_artists` links albums to `music_artists` (MBID, name,
  `performer_id`). `ConcertRefreshService` runs `ConcertRefresher` every 30 minutes: albums in
  someone's library without artists get them from MusicBrainz (stamped `titles.artists_checked_at`
  even when empty), then up to 20 artists are matched by searching Ticketmaster performers by name
  and keeping only one whose `externalLinks.musicbrainz` carries the same MBID; rechecked after 30
  days. `GET /v1/concerts/artists` asks for the user's matched performers 20 ids a call, cached.
- **Search by artist (MUS-010).** `POST /v1/concerts/search` (POST so the typed name never sits
  in a URL): Ticketmaster's `keyword` on music events, free text, searched on submit only.
  `scope: near` adds the same cell and radius as `/near` (no centre is 409 `no_place`);
  `scope: anywhere` sends the keyword alone, and the server adds `distanceKm` from the point or
  saved city to the venue's own position (haversine) after the cache, so results are shared by
  everyone. Cache key `search:<lowercased name>:<cell|*>:<radius|*>:<page>`. Picking a performer
  first (2026-10-25): `POST /v1/concerts/performers` returns Ticketmaster's attractions for the
  name (`attractions(named:)`, the same call the artist matcher uses; up to eight, cached by the
  lowercased name in its own `ConcertCache`), and `performerId` on the search switches
  `ConcertMatch` from `.keyword` to `.performer`, sent as `attractionId`; its cache key is
  `search:performer=<id>:…`.
- **City picker.** `GET /v1/concerts/places?q=` → `OpenMeteoPlaces` (no key). The request log
  drops this route's query. `PUT`/`DELETE /v1/me/concert-place` save and forget the city.

### Discover rows by kind (DISC-004)

`DiscoverList.kind` gives every row a `DiscoverRowKind` (`film | show | anime | manga | book |
album`), sent as `DiscoverRow.kind`. Clients filter on it: Discover shows film, show and anime
rows, and the Books, Manga and Music pages show their own, all from the one cached
`GET /v1/discover`. AniList serves the two manga rows (type MANGA, `status: RELEASING`, trending
or popular). Only anime rows fall back to TMDB while AniList is down.

### Sports (SPT-001…005)

`Sources/App/Sports/`, behind `SportsListing` (named for the job). `TheSportsDBSports` calls
TheSportsDB v2 with `THESPORTSDB_API_KEY` in `X-API-KEY`, and v1 (key in the path) for the two
calls v2 lacks: a league's events on one day and an event's TV listings. Without the key
`CatalogProviders.sports` is nil and every Sports answer is `unavailable` (`GET
/v1/me/sport-settings` says `available: false`; clients hide the tab).

- **Follows.** `sport_follows` (league, team or player by provider id, with a name, sport, badge,
  league and team snapshot; at most 100) and `sport_settings` (the "Where to watch" country).
  Following looks the entity up first; a player's league comes from their team, so a fighter's
  fixtures are the promotion's cards, by id and never by name.
- **Cache.** `SportsCache` holds every answer by key with its own freshness (livescores 90 s,
  event 5 min, league day 15 min, schedules 30 min, TV 6 h, entities 24 h), shared by all users,
  stale on failure and retried after a minute. Fetches are unstructured so a caller's deadline
  never cancels them. A request primes what it needs, waits `patience` (3 s), and answers with
  the rest `pending`; clients ask again a few seconds later.
- **Answers.** Favorites (each follow's live, next and last), one local day (`date` + IANA `tz`,
  fetched as the one or two UTC days it covers, plus followed teams' other competitions), and an
  event with broadcasts split by country. The livescore feed is laid over listed events by id;
  a past event with a score is finished.
- **Isolation.** Sports writes no library row, action, point, activity or push, and no agent or
  MCP tool reads it. The export carries the follows and the country.

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
- **Manga (MNG-001).** Search, hydrate and MAL batches pass `type: MANGA` (search adds
  `isAdult: false`), and manga asks for `chapters volumes` and the first staff credits whose role
  is Story or Art. A MAL id on a manga row is looked up among manga only and never goes through
  `anime_mappings`. There is no TMDB stand-in: while AniList is down, manga search is empty and
  says so.
- **When AniList is down (CAT-021).** AniList's 403 "API temporarily disabled", or a non-JSON
  page from its CDN, is an outage (`unavailable`), never `unauthorized`
  (`AniListCatalog.classify`, a hook on `ProviderClient`). While it lasts, TMDB's Japanese
  animation stands in: the anime Discover rows come from `discover/tv` (genre 16, origin JP; this
  season by first air date, trending by air date ± 7 days) with a `note`, cached 30 minutes so
  AniList's own rows return soon after it recovers; anime search answers TMDB's anime hits,
  `incomplete`, with a `notice`; a show AniList already hydrated keeps its stored episodes. AniList
  requests carry the same contact User-Agent as Open Library.
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
  with the connection row locked (refresh tokens are single use); disconnect revokes on Trakt
- OAuth calls go to `auth.trakt.tv`, data to `api.trakt.tv`; every call sends a `User-Agent`
- Pull watched history, watchlist, ratings, lists: every list paged at 250, watched shows with
  `extended=progress` (Trakt sends no episodes without it); 1.5 requests/s, `Retry-After` honoured
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
  by the anchor (stremio-core's rules), and ticks the episodes. Specials are left out. The show is
  found by Cinemeta's `tvdb_id` before its IMDb id (TMDB answers some IMDb series, such as Bleach:
  Thousand-Year Blood War, with a near-empty entry of their own), and ticks of an IMDb series that
  is not the show's own are placed by release day (`StremioEpisodeMap`, shared with the addon's
  events); one that cannot be placed stays unticked rather than guessed.
- Second in the merge order, after Trakt. Then the normal plan → approve flow.

### CSV importers

Parse known column layouts:

- IMDb: title, year, title type, IMDb id (`tconst`), rating, date
- Letterboxd: Name, Year, Letterboxd URI, Rating, Watched Date (URI may yield a slug; resolve via TMDB search + year)
- Goodreads: Title, Author, ISBN, My Rating, Exclusive Shelf, Date Read
- Netflix (IMP-018): `Title`, `Date` from one profile's Viewing activity download. A title with
  a season segment (`Show: Season 1: Episode`, `Limited Series`, `Part 2`, `<Show> 4`) is a show
  whose episodes come by name; anything else is a film. Rows are `nameOnly` with `notAfter` (the
  year first watched). Once the show matches, `EpisodeNameMatcher` numbers its episodes against
  TMDB's list (same season first, else the one episode in the show with that name). The
  all-profiles account download is refused
- TV Time (IMP-012, `TVTimeCSVParser`): one CSV of TV Time's export at a time, told by its columns.
  From *Export my data*: `tvtime-series-episodes.csv` (`series_tvdb_id`, `season`, `episode`,
  `is_watched`, `watched_at`: one row per show, watched episodes ticked, a followed show with none
  watched planned), `tvtime-series.csv` (`status`: `not_started_yet` → wishlist, `continuing` /
  `up_to_date` → in progress, `stopped` → dropped) and `tvtime-movies.csv` (`imdb_id`, `year`,
  `is_watched`: finished on `watched_at`, else wishlist). From the GDPR export:
  `tracking-prod-records-v2.csv` (`key` = `watch-episode-…` / `rewatch-episode-…` with `s_id` the
  show's TVDB id and `s_no`/`ep_no`; `user-series-…` rows carry follow, watch-later and archived
  flags), `tracking-prod-records.csv` (movies only, `entity_type=movie`: by TV Time's English slug
  and release year, or name only up to the year watched when the release date is `0001-01-01`),
  `followed_tv_show.csv` (`tv_show_id`, `archived`) and `seen_episode.csv` (episodes by
  `show_name`, name only). Shows match by TVDB id → TMDB `/find`, IMDb id second; a show whose TVDB
  id TMDB does not know falls back to the exact-name match (`nameOnly` on a row with ids). Episode
  numbers are TVDB's aired order. Lists, ratings and the JSON copies are not read. A `.zip` is
  refused with "unzip it first"

Unmatched rows are counted and listed on the job; they are not silently dropped without stats.

### CAT

- Text list of show names, one per line (`Name` or CAT's `Name (2026)`) → `nameOnly` rows. A
  name-only row matches through `TitleResolver.resolve(named:type:)`: the one TMDB show whose
  normalized title equals it, any year (up to `notAfter` when the source knows when it was watched). Two shows with the name are ambiguous and listed unmatched
  ("Pick the right one by hand"); never a guess. A row with a year takes the normal title + year path
- ICS (file or the user's iCal link): show names from each event's `SUMMARY` with the episode part
  (`S01E02`, `1x02`) removed; events collapse to one row per show. A summary with no readable show
  name is listed unmatched, once. Each row keeps its first episode and that event's `DTSTART` day
  (`airing`): when several TMDB shows share the name (at most 4), the one whose episode list dates
  that episode within a day of it is the match. None or several airing it stays ambiguous
- Every CAT show is planned `wishlist` with no progress (owner, 2026-10-21). No watched-episode import
  from CAT
- The iCal link (`/cat/download_ics/<key>` or `generate_ics`) is checked strictly (https, pogdesign
  host, that path), read once at request time through a `ProviderClient`, and never stored or logged:
  it holds the user's CAT key. No other pogdesign.co.uk page is ever read

## Import pipeline

```text
POST /imports/*  →  parse the file (bounded, 5 MB) into import_rows; the file is not kept
                 →  row in import_jobs (queued)
                 →  worker (leased: a job whose worker died runs again when the lease ends;
                    3 attempts with backoff, then failed with an errorSummary)
                      1. map each row to MediaRef (exact ids → title+year+type; match_aliases later)
                      2. hydrate Title (IDs + TMDB/Open Library). IMP-017: rows go in chunks of
                         50, three chunks in flight, four rows at once inside a chunk; a chunk's
                         MyAnimeList-only rows are fetched from AniList in one `idMal_in` page.
                         Each finished chunk writes `import_jobs.rows_matched` and renews the
                         lease, which is the progress clients show
                      3. merge rows that matched one title (anime seasons tick their TMDB
                         season), then decide: create / update (fill-empty, status forward
                         only, never past one the user chose; in progress ↔ on hold sideways,
                         resumed only by a source that has on hold) / skip / unmatched
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
7. Netflix viewing activity  
8. TV Time export  
9. MyAnimeList XML (anime and manga)  
10. AniList list (anime and manga)  
11. Any other CSV (fills gaps only)  

Later sources fill empty fields; they do not overwrite a non-empty rating, status, or progress from an earlier source unless the incoming event is newer *and* the source is explicitly marked authoritative. v1 can skip “newer” and use fill-empty-only. That is enough.

Idempotency: re-running the same Trakt import updates in place via `(user_id, title_id)` and does not duplicate items.

### Capture (AG-006)

A capture is an import job with `source = capture`. It is user-triggered and out-of-band: it is
not in the merge order, and it plans and applies like every other import (one plan, IMP-011's
"Find it" for unmatched rows, one undoable action on apply).

- **Link:** parsed on the request, never fetched. `themoviedb.org/movie|tv/{id}`,
  `anilist.co/anime/{id}` and `openlibrary.org/works/OL…W` become one row with that id.
  Letterboxd and IMDb links get 422 `capture_use_csv` (their CSV importers bring the whole list);
  any other link gets 422 `capture_unsupported_url`.
- **Text or image:** the request stores the input in `capture_inputs` (job id, user, text or image
  bytes, media type) and returns the job. The worker sends it to the model in one call that must
  answer with the `report_titles` tool (`tool_choice`), turns the reported names into rows
  (deduplicated, at most 50, anime planned as shows, status `wishlist`), and deletes the input
  whatever the model found. `CaptureSweeper` deletes any input still there an hour on. Images are
  at most 5 MB, JPEG/PNG/GIF/WebP; clients downscale to 1568 px on the long edge first.
- **Quota:** a free account starts 3 captures per UTC month (counted from `import_jobs`); the
  fourth gets 402 `capture_quota` with the reset date. Plus lifts it (BIL items).
- **Spend:** every model call records tokens and `cost_micros` in `agent_usage`, priced from
  `ANTHROPIC_PRICE_INPUT` / `ANTHROPIC_PRICE_OUTPUT` (dollars per million tokens).
- A planned capture pushes "N ready · M need a pick" to the user's devices.
- **Plus fair use:** a Plus account has no monthly limit but gets 429 `capture_fair_use` after 30
  captures in a UTC day.

### Aaru Plus (BIL-001…004)

Plus is a StoreKit 2 subscription (`aaru_plus_monthly`, `aaru_plus_yearly`) bought in the Apple
apps only. The server keeps the entitlement, so the web and every Apple device read the same
answer from `GET /v1/me/entitlement` (Plus or not, renewal date, this month's captures and limit,
and the `appAccountToken` to buy with, which is the user id).

- **Verification** happens in `Billing/AppleSignedData.swift`, with no App Store Server API key:
  each JWS's x5c chain must end at Apple Root CA - G3 (compiled in), carry Apple's marker OIDs
  (leaf 1.2.840.113635.100.6.11.1, intermediate 1.2.840.113635.100.6.2.1), be valid at the
  payload's `signedDate`, and name one of `config.appleAudiences` as its bundle id. Built on
  JWTKit's `X5CVerifier` with `swift-certificates` / `swift-asn1` for the policy.
- **`POST /v1/billing/apple/transactions`** (session): the app posts `jwsRepresentation` after a
  purchase, a restore, or each `Transaction.updates` event, so Plus takes effect at once. A
  transaction whose `appAccountToken` names another account gets 409 `plus_other_account`.
- **`POST /v1/billing/apple/notifications`** (public, verified by signature): App Store Server
  Notifications v2 for renewals, expiries, refunds and revocations. The owner is the account
  already holding that original transaction, else the `appAccountToken`. Unknown accounts are
  answered 200 and ignored, so Apple stops retrying.
- **Table `entitlements`**, one row per `original_transaction_id`: user, product, environment,
  `expires_at`, `revoked_at`, `signed_at`. A write lands only if its `signed_at` is not older than
  the row's, so a late notification never undoes a newer one. Plus is active when a row is
  unrevoked and unexpired.
- Sandbox (TestFlight) purchases count on the one production API, the same way Beta and Prod
  share it; the row records `environment`.
- `plus_purchased` fires once per original transaction, on its first active write.

`Stores` is a `final class` (`Data/AllStores.swift`): copying a struct of every store through
`Services` overflowed the stack of a debug test thread once it grew past the entitlements store.

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
written once on the server for web and Apple). A browser-extension token (`kind = browser`, SCR-007) gets
`scrobble:write` only: it never reads the library. Secrets carry a per-surface prefix
(`aaru_st_`, `aaru_mcp_`, `aaru_scr_`) and a token authenticates only on its own surface. The tools live in
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
- First consumer (GRP-010, 2026-10-20): `@aaru` replies in groups, on `claude-haiku-5-5`. The
  adapter sends no `temperature`, `top_p`, `top_k` or assistant prefill; Haiku 5.5 rejects
  them (`platform/infra/docs/llm-haiku-trial.md`). User keys wait for AG-007.
- Second consumer (AG-006, 2026-10-22): capture extraction. `ModelRequest.toolChoice` forces
  one tool (Haiku 5.5 accepts a forced tool; other current models answer it with a 400), and
  `ModelTurn.user(image:mediaType:_:)` sends an image block. `ModelProviding.pricing` turns a
  response's tokens into `agent_usage.cost_micros`.

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
- **Live Activity:** "Now playing" (SCR-009) is one activity per device listing everything that
  plays, up to three rows: library episodes, movies and YouTube videos first, then a track.
  Each row has art, progress and an Ends-at / time-left toggle; episode and movie rows have
  Mark watched. The server starts, updates and ends it by APNs push: the app hands over its
  push-to-start token and its running activity's token (`PUT /v1/devices/live-activity`), kept
  in `live_activity_tokens`. The app also starts it when it opens on something playing that it
  has no activity for. The payload types (`NowPlayingActivityAttributes`,
  `NowPlayingActivityState`) live in `AaruCore`, so the server's pushes and the app decode one
  type. Widgets cannot fetch, so the app saves each row's art into the App Group when it runs; a
  row shows its kind's glyph until then. "Now watching" (`NowWatchingAttributes`, one episode)
  remains only for a check-in started by hand, and either activity ends the other.
- **macOS widgets** come from the same extension and the same snapshot. No second widget
  codebase.

App Group id: `group.$(PRODUCT_BUNDLE_IDENTIFIER)`, so beta and prod builds never share a
snapshot.

### Web (`aaru-client`)

SolidJS + TanStack Start on Cloudflare Workers, Tailwind 4. Decided 2026-10-14 (replaces the
SvelteKit scaffold). Same screens as the Apple apps, in the same order they ship.

- Session: the token lives in an HttpOnly, Secure, SameSite=Lax cookie. Server functions send
  `/v1` calls with it; page scripts never see the token. A 401 clears the cookie once.
- Reads go through TanStack Query (`src/lib/queries.ts`, 30 s fresh): loaders read the cache, so
  hovering a link preloads the page and Back is served from memory; the SSR integration hands
  the server's reads to the browser. Any POST server function marks the cache old
  (`src/start.ts`). The signed-in check runs once per tab (`src/lib/session/query.ts`), not per
  navigation; signing out or reaching sign-in signed out empties the cache.
- API types come from the same `openapi.yaml` as the Apple apps' `AaruAPI` (`openapi-typescript`,
  committed, checked fresh in CI).

- The landing pages (product, waitlist, legal) are a route group in the same app, so there is no
  separate marketing site.
- The logged-in library uses the same `/v1` API as native, with the same screens where they make
  sense: home rows, `WeekGrid`, Title room, lists, settings.
- It is a pure client: no database binding, no business logic, no vendor calls. A rule that
  matters lives on the server.
- Do not fork DTO meaning for the web.
- UI layer (2026-10-21): every shadcn-solid component, on Kobalte (and corvu, embla, cmdk-solid,
  somoto, unovis where the registry uses them), copied as source into `src/components/ui` and
  imported only through its barrel `~/components/ui`. Its CSS variables point at Aaru's design
  tokens (`src/styles.css`), so the look is Aaru's. Routes and feature components compose those
  primitives; compositions such as `ConfirmDialog` and `Segmented` live in `src/components`, not
  in `ui`. ESLint enforces the barrel and fails on raw form controls and modals. Motion stays in
  `src/lib/motion.ts` (DESIGN.md §17).
- App shell (DESIGN.md §18): one pathless layout route, `routes/_shell.tsx`, wraps every `/app`
  page (files `_shell.app.tsx` and `_shell.app_.*.tsx`; URLs unchanged). Its `beforeLoad` is the
  one sign-in check (`requireSession`, through the query cache, with `next`), and its component
  is `components/shell/AppShell.tsx`: the shadcn-solid Sidebar from 1024px, the same sidebar as
  a sheet below (loaded lazily, only on a narrow screen), the one Search dialog (⌘K) that pages
  lend their library to (`useSearchHost`), and the Toaster, which loads on the first `toast()`.
  Back links name the page you came from (`BackLink`).
- Friends (SOC-001/002/003) is `/app/friends` (`_shell.app_.friends.index.tsx`: Lately, invites,
  requests, friends, blocks) and `/app/friends/$handle` (a friend's profile), in the sidebar
  between Lists and Groups. The invite letter `/i/$code` is public, outside the shell.
- Settings are eight child routes of `_shell.app_.settings.tsx` (`account`, `friends`,
  `notifications`, `import`, `connections`, `data`, `about`, `delete`) with a rail from 768px
  and a list below; the old slugs (`connected`, `imports`, `recaps`) and hashes redirect.
  `/app/week` redirects to `/app/calendar`.

## Tracking integrations (Phase 3)

### Scrobble ingest

- `POST /v1/scrobble/{start|pause|stop}` takes a Trakt-compatible body: movie or episode ids
  plus `progress` as a percent. A client or bridge that already speaks Trakt's scrobble shape
  only needs a base URL change.
- Each call writes a `watch_events` row (user, title, episode, progress, source, timestamp).
  A `stop` at **≥ 80%** marks the episode or movie watched through the same data layer as a tap,
  so it lands in `actions` and is undoable. 80% is Aaru's own documented threshold.
- `start` and `pause` feed the "Now playing" Live Activity and, later, room drift
  (ROOM-004). They never change progress.
- **Now playing (SCR-008, SCR-009):** `GET /v1/me/now-playing` returns `items`, the live set:
  open sessions on library titles (a playing one counts until its end plus 10 minutes, 3 hours
  with no duration known, a paused one for 30 minutes) and unexpired `live_plays`. A track
  counts to its end plus 2 minutes (10 with no length); a video to its next expected report
  (at most 5 minutes) plus 2, or 30 minutes paused, and its `stop` deletes it. Order: episodes,
  movies and videos newest first, then tracks, three at most; a track whose `origin_url` is a
  video already shown is dropped. `nowPlaying` (the newest session) stays for older clients.
- **Plays (SCR-009):** a ListenBrainz `playing_now` and a `/v1/scrobble/*` body with
  `source: youtube` + `video {id, title, channel}` become `live_plays` rows, never listens or
  watch events. The video thumbnail is built from the id (`i.ytimg.com`); the server fetches
  nothing from YouTube.
- **Next episode:** a `start` for a different item from the same source closes the user's other
  open sessions from it (Stremio's next episode may never send the last one's `stop`). A closed
  session ticks only when the player last *reported* it at ≥ 80%, never on an extrapolated
  position.
- **Live Activity pushes:** `LiveSetNotifier.sync` runs after each report and play when APNs is
  configured. It recomputes the live set, compares it with `live_activity_states.pushed`, and
  saves by compare-and-swap before pushing. Something playing where nothing did push-starts the
  activity on each device (priority 10); a row added, gone, paused, resumed, ticked, or an end
  time moved by over a minute updates the running activities (priority 5); nothing left ends
  them. Position alone never pushes, so the extension's 2-second reports cost nothing. A ticked
  episode or movie stays 8 seconds as "Watched". `LiveActivitySweepService` runs every 15
  seconds and syncs users whose `next_check_at` (the earliest expiry) has passed, claimed with
  `FOR UPDATE SKIP LOCKED` so replicas never push twice. Best effort: a push failure never
  fails a scrobble; dead tokens are forgotten.
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
- **Music (MUS-005):** `ListenBrainzRoutes` serves ListenBrainz's `POST /listenbrainz/1/submit-listens`
  and `GET /listenbrainz/1/validate-token` outside `/v1`, in ListenBrainz's shapes (`Authorization:
  Token …`, `{listen_type, payload}`, `{code, error}`), so scrobblers that let you set a
  ListenBrainz server send to Aaru. Only a `music` token (`aaru_lb_…`, `scrobble:write`) gets in.
  Listens go to `listens`, a log apart from the library: `ListenService` never calls
  `LibraryService`. `PostgresListenStore` inserts under a per-user advisory lock and drops a listen
  whose normalized artist and track (`track_key`) is within half its length (≤ 90 s) of a stored
  one, so two scrobblers on one play keep one row. Spotify, Apple Music and YouTube are reached
  only through those scrobblers and through history imports (MUS-004). `MusicSetup` writes each
  scrobbler's steps once, with the token filled in, and `POST /v1/agent/tokens` answers them in `music`
  for a music token (MUS-007), so the web and Apple apps show the same ones. The clients disagree on
  the address (submit URL, root with or without `/`, root plus `1/`); the steps give each its own.

### Outbound sync

Trakt history push (SCR-004) and MAL / AniList progress push (SCR-005) are **one-way out**.

- Aaru writes to them after its own write commits.
- What it pushed is never read back as a conflict source, and a remote change never overwrites
  Aaru. Imports stay one-way in.
- Tokens live in `outbound_connections`, encrypted at rest. MAL's, as built, live in
  `mal_connections` beside `trakt_connections` (sealed with `MAL_TOKEN_KEY`).
- MAL uses OAuth with PKCE (`plain`, the only method it takes). AniList uses `SaveMediaListEntry`.

**MyAnimeList push (SCR-005, as built).** `MALSyncService` runs every 30 s in the API process.
`mal_connections.push_cursor` starts at connect time, so the library as it was is never pushed;
each pass reads `LibraryStore.changes` since the cursor for users with newer writes, so a tap, an
import, a scrobble or an undo all go out the same way, and nothing on the write path calls it. A
TMDB show splits into one MAL entry per season through `anime_mappings` (a season two MAL entries
share is skipped); any other anime uses its own MAL id. `mal_entry_states` keeps what Aaru and MAL
last agreed on per entry: a push sends only what differs, and SCR-010 uses the same row to drop
echoes. Aaru's `on_hold` goes out as MAL's `on_hold` (LIB-007); a tick resumes the item, so it
goes out as `watching`. A 401/403 marks the connection
`revoked_at` and pushing stops until the user connects again. Deletes are not pushed.

**MyAnimeList read-back (SCR-010, owner 2026-10-23, as built)** is the one exception to "never
read back". MAL has no webhooks, so `MALPuller` reads the user's own list sorted by
`list_updated_at`, page by page, and stops at the first entry not newer than
`mal_connections.pull_cursor` (MAL's own timestamp; it starts at `connected_at`, so only changes
made after connecting come across). Each `MALSyncService` pass claims up to 10 due connections
(`FOR UPDATE SKIP LOCKED`, stamping `pulled_at`): those a client asked for with
`POST /v1/connections/mal/pull` (ignored when the last read is under 10 minutes old, so clients call
it on every open) and those not read for 6 hours. Changed entries become import rows by IMP-013's
mapping and go through the import plan and forward-only merge (`ImportService.applyFromMAL`), one
journaled action named "MyAnimeList" that Undo takes back; no plan waits for approval. An entry equal
to its `mal_entry_states` row is Aaru's own push coming back and is dropped; every other entry read
is saved there, so the push never sends it back. Once a week the whole list is read and
`mal_entry_states.removed_at` marks known entries MAL no longer lists; `GET /v1/connections/mal`
returns them under `removed`, and Aaru deletes nothing. A 401/403 marks the connection revoked.
There is no conflict engine: fixed precedence, Aaru wins ties.

## Social (Phase 4)

Modelled on Norviq's `social_*` design (`norviq-backend/.../Social`, `CreateSocialTables`).

| Table | Shape |
| --- | --- |
| `social_friend_requests` | from, to, status `pending` / `accepted` / `declined` / `cancelled` |
| `social_friendships` | one row per pair, ordered ids, `created_at` |
| `social_blocks` | blocker, blocked |
| `social_reports` | reporter, target, reason |
| `social_invites` | code (12 random base62), inviter, optional title, expiry (14 days), redeemed_by, revoked_at |
| `social_reactions` | user, owner, title, UTC day, one of six emoji; one per user and row (SOC-007) |
| `social_recommendations` | from, to, title, note (140), created, added_at, dismissed_at; one waiting per pair and title (SOC-006) |
| `social_settings` | `share_library_with_friends` (default on, 2026-10-21); `show_achievements_to_friends` (default on) and `leaderboard_opt_in` (default off), 2026-10-22 |
| `favorites` | user, kind (`film` / `show` / `anime` / `manga` / `book` / `album`), position 0…9, title; key (user, kind, position), unique (user, kind, title) (FAV-001, 2026-10-23) |

Rules:

- **Private by default.** A new account is invisible: nobody can find it, and strangers never see
  any of its library. Friend-only is the most open Aaru ever gets. Once two people are friends
  they see each other's shelves and activity unless one turns off `share_library_with_friends`
  (owner, 2026-10-21: friendship is the opt-in). There are no public profile pages.
- **What a friend sees** (`/v1/social/friends/{userId}/profile`, `/v1/activity`): titles, status,
  rating, the last episode ticked, book page, manga chapter, finish dates and the user's
  favorites (FAV-001). Never notes or owned. Favorites follow `share_library_with_friends`. Activity is
  read from `library_items` and `episode_progress` at query time, ticks only when
  `watched_at_known`, so an import never floods a friend's feed.
- **Invite links (SOC-002, 2026-10-21).** `https://aaruapp.com/i/{code}`, one use. Redeeming
  makes the pair friends in one transaction (the conditional update on the invite is the lock)
  and drops pending requests between them. The preview `GET /v1/invites/{code}` is the only
  public social route and shows only the inviter's name, handle and chosen title; every dead
  end is one 404. The web Worker serves `/.well-known/apple-app-site-association` claiming
  `/i/*` for the App Store and Beta app ids, so the apps open the same URL. Android will claim
  it through `assetlinks.json` when there is an Android app.
- **A block is invisible.** A blocked user gets `404` for everything about the blocker, the
  same response as for a user who does not exist. Blocks apply both ways in feeds,
  leaderboards, rooms, and DMs.
- Friend activity and "Today" stories read `watch_events` and journaled progress, filtered by
  friendship and settings at query time. There is no fan-out table.

## Groups (pulled forward 2026-10-20)

A group is a friends-only space with channels, like a small Discord server. Backlog:
GRP-001…GRP-012.

| Table | Shape |
| --- | --- |
| `profiles` | `user_id`, `handle` (unique, `^[a-z0-9_]{3,20}$`), display name |
| `groups` | name. Ownership is the one `owner` member row (unique partial index); delete is hard and cascades |
| `group_members` | group, user, role `owner` / `admin` / `member`, `joined_at`; `muted` (GRP-012), `share_progress` (GRP-007, default off) |
| `group_invites` | group, inviter, invitee. Pending only: accepted becomes a member row, declined or cancelled is deleted |
| `group_channels` | group, kind `text` / `title` / `watch` / `shelf`, name, topic, position, `is_default`, `title_id` (required for `title`) |
| `group_messages` | channel, author (null once the account is deleted), body (≤ 4,000), `mentions`, `mentions_agent`, `client_nonce`, `edited_at`, `deleted_at`, spoiler season and episode or `spoiler_ending` (GRP-007); `author_kind` `user` / `agent` (an agent message has no author), `components` (title cards), `reply_to` (GRP-011) |
| `group_read_state` | user, channel, `last_read_at`. Unread and mention counts are counted from it, never stored |
| `group_channel_items` | shelf channel, title, `added_by`, position |
| `watch_sessions` | watch channel, title, season, episode, `created_by`, `starts_at`, `ended_at`. One open per channel. State is derived: lobby, countdown until `starts_at`, live, ended. `watch_ready` holds who is ready |
| `agent_replies` | the job row for one `@aaru` mention, claimed with a lease like imports; `capped` and `skipped` rows record mentions over the fair-use cap |
| `agent_usage` | user, UTC day, requests, input and output tokens |

Rules:

- **Friends only.** An invite needs an accepted friendship and no block either way. There are
  no invite links and no discoverable groups.
- **A non-member gets `404`** for the group, its channels and its messages, the same as a group
  that does not exist. Every query is scoped by membership in the data layer (X-011).
- **Server-visible, and said so.** Group messages are plain rows. Every channel header carries
  a "not end-to-end" label. DMs are a different system (below) and never share a table, type or
  route with group messages.
- `#general` is created with the group in one transaction and can never be deleted.
- **Blocks inside a group:** both people can stay members. The blocker's client collapses the
  blocked member's messages, and neither can invite the other.
- Writes go through REST. After commit, the service publishes an envelope to the realtime hub.
  A client that reconnects reads REST `after=` its last message, so the socket is never the
  source of truth. Posts carry a `client_nonce`, which makes retries idempotent.
- **Channel kinds** add behaviour, not separate chat systems:
  - `title`: a message is stamped with the author's furthest episode (or the ending once they
    finished), by hand, or not at all, and a reader who is behind sees it veiled. Finishing the
    title unveils everything. The stamp says where its author is, so only the author ever sees
    it; readers get `veiled` and nothing more. The header lists the progress of members who
    switched on `share_progress` for that group, and nobody else.
  - `shelf`: a list the members edit together. Separate from `lists`, which stay single-owner;
    the two share a renderer. "Add to my library" is the viewer's own journaled tap.
  - `watch`: the watch-together room (below) living in a channel: one open party at a time, a
    ready list, a countdown every client runs against `serverTime`, reactions from a fixed set
    over the socket, and "Mark watched for me", which ticks only the tapper's library through
    `LibraryService`.
- **`@aaru`.** A mention enqueues an `agent_replies` row. The worker builds context from the
  channel's last 30 messages, the channel's title, session or shelf, and the tagger's own
  library. It never reads another member's library. Tools are read-only. The reply is a group
  message with author kind `agent` and catalog components only. Card buttons are the viewer's
  own taps, so the agent has no write path. Per-user and per-group caps apply before any model
  call.
- **Push** for mentions and invites carries no message text, only who, where and a deep link.

## Board (pulled forward 2026-10-22)

A friends-only stream of posts, upvotes and comments (BOARD-001). Tables: `board_posts`
(author, optional title, rating, body, spoiler stamp), `board_upvotes` (post, user),
`board_comments` (post, author kind `user` / `agent`, `reply_to`, `mentions`). The Board itself
is a query, not a table.

- **Visibility is in `BoardService`.** The audience is the viewer plus their friends, minus
  anyone blocked in either direction; a post outside it is the same 404 as a missing one.
  Pages come from the data layer already filtered, so the cursor is keyset on `(created_at, id)`.
- **A review writes the library through `LibraryService`.** A rating on a post adds a new title
  as finished, then rates it (two journal rows); an existing title only gets the rating. A
  still-airing show lands as `in_progress` with its aired episodes ticked (PROG-005), so BOARD-002's
  composer preview must say so. The post keeps its own copy of the rating, so undoing the library action never deletes the post.
- **Spoiler veil** reuses the title-channel stamp: only the author sees the stamp, a reader who
  is behind gets `veiled`.
- Reports reuse `reportUser` on the author, with the note prefixed `post:<id>`.
- `GET /v1/titles/{id}/posts` is the title page's "From friends" slice of the same query.

## Gamification (Phase 5, pulled forward 2026-10-22)

Modelled on Norviq `gamification_xp_events` and Loci `points_events`. Code lives in
`aaru-server/Sources/App/Gamification`; the design and the badge catalog are in
`docs/superpowers/specs/2026-10-22-achievements-design.md`.

- **Ledger, not counter:** `points_events(user_id, kind, points, dedupe_root, seq, dedupe_key,
  reverses, title_id, season, episode, action_id, local_date, time_zone, created_at)`, unique on
  `(user_id, dedupe_key)` where the key is `root#seq`.
  - One idempotent path (X-010): `award` inserts only when the root's last event is not an
    award; `revoke` inserts the negative of the active award. A re-ticked episode, a replayed
    scrobble or a title removed and re-added earns nothing twice; undo then redo nets one.
  - Roots are keyed by title, not library item: `ep:{title}:{s}:{e}`, `finish:{title}`,
    `season:{title}:{s}`, `friend:{low}:{high}`, `room:{session}`, `streak:{runStart}:{n}`.
  - `user_progress` (total, level, streak, time zone, a dirty flag with a lease) is a cache
    rebuilt from the ledger, never the source.
- **Where points are written:** inside the library transaction, from the op and its stored
  inverse (`PostgresLibraryStore.apply` / `undo`), for the journal kinds `add`, `update`,
  `remove`, `episode`, `season` and `undo` only. Imports, approved plans and list edits write
  no points. Friend creation (accept, crossing requests, invite redeem), watch parties and
  live listens award after their own writes. Values and daily caps live in
  `Gamification/PointsRules.swift`.
- **Friend added** counts only when the friendship is mutual and is reversed for both people if
  it ends within 7 days. Re-friending earns nothing.
- **Levels:** `50·L·(L−1)` points to reach level L; level is a pure function of the total.
- **Streaks:** `check_ins(user_id, local_date, time_zone, first_at)` — called streak days
  everywhere but the table — written only by live progress (episodes, finishes, book pages).
  The local date comes from the client's `X-Timezone` header, else the stored zone, else UTC.
  Past days are never recomputed. The rule lives in AaruCore (`Streak`) so the widget agrees.
- **Badges:** `user_badges(user_id, badge, tier, awarded_at, origin, action_id, seen_at)`.
  Definitions live in code. Milestone badges read library facts (so imported history counts);
  activity badges read the ledger and streak days (live only). Undoing the action that earned a
  tier takes it back if the rule no longer holds; nothing else removes a badge. Live writes are
  evaluated right after commit; imports, plans and the first-run backfill are evaluated by
  `GamificationWorker`, which claims dirty users with a lease.
- **Leaderboards** are friends-only, weekly (each person's local dates), and opt-in
  (`leaderboard_opt_in`), with blocks applied both ways. Friend and first-import points are
  left out. Never global.
- **What friends see:** level and non-private badges, behind `show_achievements_to_friends`.

## Realtime, messaging, and watch together (Phase 6)

### Realtime gateway

- `GET /v1/ws` behind the same session as `/v1`. It ships early, with groups (GRP-006): group
  envelopes first, presence and DM notices in Phase 6.
- Apple clients send the bearer token on the upgrade. The web cannot, because its session token
  is in an HttpOnly cookie, so a server function fetches a single-use ticket valid for 60 s from
  `POST /v1/realtime/ticket` and the browser connects with it. A ticket only works from an
  allowed `Origin` (`REALTIME_ORIGINS`); a bearer upgrade cannot come from a browser.
- One in-process hub actor (`RealtimeHub`) keyed by user, as LuminaVaultServer's
  `ConnectionManager`. A group event goes to every member's sockets and the client filters by
  channel; there is no subscribe step. It carries group events, then presence, room events,
  and message-arrival notices. Frames are `RealtimeEvent` in `openapi.yaml`; the server pings
  every 25 s.
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

- Since 2026-10-20 a room is a `watch` channel inside a group (GRP-009), with its session in
  `watch_sessions`. Members come from the group, which is friends-only.
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
- Group alerts (GRP-012): `notification_settings.group_mentions` and `group_invites`, off until
  turned on like `airing`, and `group_members.muted` per group (`PUT /v1/groups/{id}/me`). A post
  alerts the members it tags, unless they muted the group, turned mentions off, or blocked the
  author; a retried post and a repeat invite alert nobody. Alerts go out inline through
  `UserPush`, best effort, like agent requests. The payload names who and where, never the
  message: "{name} mentioned you in #{channel}" with `groupId`, `channelId` and
  `url` `aaru://group/{g}/channel/{c}`; an invite carries `aaru://groups`. iOS routes the tap
  through `PushInbox` and `GroupLink`; the web opens `/app/groups/{g}/{c}`.

## Phasing

`BACKLOG.md` holds the tickets. This is the shape and the gates.

| Phase | Scope | Exit gate |
| --- | --- | --- |
| 0 — Rails | Root CI, Xcode project (iOS + macOS + widget extension, Beta config), fastlane, server image → infra, Workers deploy, SRV foundation | Empty app ships to TestFlight beta; API health live on the cluster; web beta Worker live |
| 1 — Basics | Auth, catalog (TMDB, Open Library, AniList), library, action journal, TV/anime progress, lists, shelves, calendar, Up Next | API complete for a personal tracker |
| 2 — Clients, widgets, imports | iOS + Mac app, widgets + Live Activity, web client, Trakt/CSV/CAT/TV Time/MAL/AniList imports | **Basics done:** beta app and beta web usable end to end, widgets work |
| 3 — Tracking integrations | Scrobble ingest, Plex/Jellyfin webhooks, Stremio addon, outbound Trakt/MAL/AniList | Scrobble from at least one player lands as journaled progress |
| 4 — Social | Profiles, friends, blocks, invites, friend activity, push, groups | Two accounts can friend, see each other's activity, and block cleanly |
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
plans/approvals (OUT-001/002/004, AG-001's tools, AG-003's remote-plan slice). Exception by the
owner's call (2026-10-20): groups, with minimal handles, friends and blocks, the `/v1/ws` gateway
for group events, and a minimal model provider for `@aaru`.

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

### Observability (owner, 2026-10-21)

- **Grafana Cloud.** The cluster's Alloy scrapes `aaru-api` by pod annotation and collects
  its logs. Probes cover `api.aaruapp.com/v1/health`, `aaruapp.com` and `beta.aaruapp.com`, and
  the "Apps / Aaru" board and alerts are generated in the infra repo's `observability/`.
  `/metrics` is served on its own listener (`METRICS_PORT`, 9090), outside the Service and the
  Ingress, so it is never public. Route labels use the endpoint template, never an id.
- **Sentry, errors only.** Server, web (browser and Worker), Apple apps and the browser
  extension report errors and crashes. There is no tracing, no session replay and no PII. URLs
  lose their query; the extension sends a streaming site's origin only. With no DSN it is a
  no-op.
- **PostHog, server only.** A fixed list of product events (`account_created`,
  `import_completed`, `library_action`, `list_created`, `group_created`, `friend_added`,
  `agent_plan_decided`) with a few fixed-word properties, keyed by the account UUID, with
  `$process_person_profile: false` and no IP. Clients send none.
- `docs/privacy.md` states all of this, and changes before any of it does.
- `/internal/metrics` (the `{"users": N}` count for facorreia.com/apps, `METRICS_SECRET`) is a
  separate contract and stays as it is.

## Decisions already made

| Topic | Decision |
| --- | --- |
| Product | One app: library + tracking. Social, gamification, realtime after the Phase 2 gate (2026-10-09). |
| Source of truth | Aaru after import |
| Video catalog | TMDB |
| Book catalog | Open Library |
| Primary user import | Trakt |
| CAT | Pasted list, ICS file, or the user's own iCal link read once; no scraping |
| Netflix | The per-profile Viewing activity CSV (IMP-018); live plays through the browser extension (SCR-007) |
| TV Time | Its export's CSVs, one at a time (IMP-012, 2026-10-21): Export my data or the GDPR zip, unzipped by the user |
| Bingers | Not imported (2026-10-21). Its only official path is a beta API for paid Legend/Icon subscribers; see BACKLOG IMP-019 |
| Scraping | Forbidden. One owner exception (2026-10-21): the SCR-007 browser extension reads the player page the user is watching, in their browser; the server fetches nothing |
| Backend | Hummingbird only |
| First clients | iOS and Mac, with widgets and a Live Activity |
| Web | `aaru-client`: SolidJS + TanStack Start on Cloudflare Workers, pure `/v1` client at parity with the Apple apps (2026-10-14; SvelteKit 2026-10-09 to 10-14) |
| Browser extension | `aaru-extension` (SCR-007, 2026-10-21): Chrome + Firefox, Manifest V3. A client of `/v1/scrobble/*` only, with a `browser` token (scrobble only) handed over on `/connect/extension`. Reads the playing title from the player page in the user's browser; the server fetches nothing from the sites |
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
