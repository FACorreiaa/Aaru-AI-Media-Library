# Aaru architecture

Aaru is a private-first media library for movies, TV, and books. Clients are native Swift. The server is Hummingbird. Collaboration is a later phase and must not leak into v1 data-model or API design beyond nullable hooks that already exist (e.g. a `visibility` field defaulting to private).

## Goals

- One language on the wire and in the apps: Swift models in `AaruCore`.
- Catalog providers are replaceable; the library schema is not.
- Imports are asynchronous, idempotent, and one-way.
- iOS and Mac ship first. The logged-in web app is a second client of the same API, not a second product.

## System context

```text
                    ┌─────────────┐     ┌─────────────┐
                    │    TMDB     │     │ Open Library│
                    └──────┬──────┘     └──────┬──────┘
                           │ metadata          │
┌──────────┐   JSON    ┌───▼───────────────────▼───┐     ┌─────────┐
│ iOS app  │──────────▶│     Hummingbird API       │────▶│ Postgres│
└──────────┘           │                           │     └─────────┘
┌──────────┐           │  auth · library · search  │
│ Mac app  │──────────▶│  lists · import jobs      │     ┌─────────┐
└──────────┘           └───────────┬───────────────┘     │  Trakt  │
┌──────────┐                       │ enqueue             └────┬────┘
│ Web app  │──────────▶            ▼                          │ OAuth
│ (later)  │           ┌─────────────────────┐                │ + history
└──────────┘           │ Import workers      │◀───────────────┘
                       │ Trakt / CSV / CAT   │
                       └─────────┬───────────┘
                                 │ hydrate IDs + posters
                                 ▼
                       ┌─────────────────────┐
                       │ Marketing site SSR  │
                       └─────────────────────┘
```

v1 web surface is marketing only. It does not read a user’s library.

## Process boundaries

| Component | Responsibility | Must not do |
| --- | --- | --- |
| `aaru-core` (`AaruCore`) | Shared DTOs, identifiers, status enums, title matching, lightweight validation | Persistence, HTTP server, TMDB secret handling |
| `aaru-server` | HTTP, auth, Postgres, jobs, provider adapters | SwiftUI, store-kit, vendor JSON leaked to clients |
| `aaru-ios` | Presentation, local cache, Sign in with Apple | Direct TMDB/Trakt calls (go through Aaru API) |
| `aaru-landing` | Public marketing pages | Session library UI, ever |
| `aaru-site` | Logged-in web client on `/v1`, after native launch | Forking DTO meaning from the native clients |

Native apps talk only to Aaru. That keeps API keys, rate limits, and ID mapping on the server.

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
}
```

### Title (catalog)

A canonical work Aaru knows about. Created on first add or during import hydration.

- `id` — Aaru UUID
- `type` — `MediaType`
- `title`, `originalTitle`, `year`
- `synopsis` (optional, from catalog)
- `posterURL` (catalog URL, not hosted)
- `ids` — `ExternalIDs`
- `seasons` — only for shows; episode lists may be lazy-loaded

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

v1 does not need continuous scrobble positions.

### List

- `id`, `userId`, `name`, `createdAt`
- items reference `libraryItemId` or `titleId` (prefer `titleId` so a list can include titles not yet in a status)

### Import job

- `id`, `userId`
- `source` — `trakt` | `imdb_csv` | `letterboxd_csv` | `goodreads_csv` | `cat_list` | `cat_ics`
- `state` — `queued` | `running` | `succeeded` | `failed` | `partial`
- `stats` — created / updated / skipped / unmatched
- `errorSummary`

## Persistence

PostgreSQL. Suggested tables:

- `users`
- `auth_identities` (Apple, email)
- `titles` (unique indexes on each external id where not null)
- `show_episodes` (title_id, season, episode, optional air date, optional tmdb episode id)
- `library_items` (unique `(user_id, title_id)`)
- `episode_progress` (unique `(library_item_id, season, episode)`)
- `lists`, `list_items`
- `saved_queries` (shelves — a stored filter, never membership rows)
- `import_jobs`, `import_job_events` (optional log lines)
- `actions` (action journal: one row per mutating library write, with its inverse)
- `match_aliases` (match ledger: aggregate crosswalk from a source row key to an external id)
- `agent_tokens` (per-user agent access: hashed secret, scopes, `lastUsedAt`, revocation)
- `agent_usage` (model spend per user per day: tokens in and out, cost in cents)

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

The pre-launch converter tools on the landing site write to the same ledger through the
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

GET    /v1/search?q=&type=movie|show|book
GET    /v1/titles/{id}

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

GET    /v1/imports
POST   /v1/imports/trakt/connect          # start OAuth
GET    /v1/imports/trakt/callback
POST   /v1/imports/csv                    # multipart, source=imdb|letterboxd|goodreads
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

Each adapter lives in `Server` and implements a narrow protocol.

```swift
protocol CatalogSearching: Sendable {
    func search(query: String, type: MediaType) async throws -> [CatalogHit]
    func hydrate(ids: ExternalIDs, type: MediaType) async throws -> CatalogTitle
}

protocol UserLibraryImporting: Sendable {
    func importLibrary(userId: UUID, credential: ImportCredential) async throws -> ImportResult
}
```

### TMDB

- Search and detail for `movie` and `show`
- Season/episode lists when a show is added or when the user opens progress
- Map `imdb_id` from TMDB external IDs onto `titles.ids`

### Open Library

- Search and detail for `book`
- ISBN and cover URL

### Trakt

- OAuth user token stored encrypted at rest
- Pull watched history, watchlist, ratings, lists
- Map Trakt ids → TMDB/IMDb → `Title`
- First importer in the merge order

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
POST /imports/*  →  row in import_jobs (queued)
                 →  worker
                      1. fetch or parse source
                      2. map each row to MediaRef (exact ids → match_aliases → title+year+type)
                      3. hydrate Title (IDs + TMDB/Open Library)
                      4. upsert LibraryItem
                      5. apply progress/ratings if present
                      6. mark job succeeded / partial / failed
                      7. after the job: promote confirmed corrections into match_aliases
```

Merge when the same user imports several sources, in order:

1. Trakt  
2. IMDb CSV  
3. Letterboxd CSV  
4. Goodreads CSV  
5. CAT  

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

The agent layer is phase 1.5: it is built after the native client, on components that already
work by direct touch. See M13 in `BACKLOG.md`.

## Outbound agent surfaces

The tool layer above has two transports besides Aaru's own composer. Both are **skins over
the same tools**. Neither adds a capability, a route behind the tools, or a write path.

| Transport | Where it lives | Notes |
| --- | --- | --- |
| App Intents / Shortcuts | `aaru-ios` | Each tool is an App Intent. `TitleCard` and `TonightStrip` serve as snippet views. No server work |
| MCP | `aaru-server/Sources/AppMCP`, `POST /v1/mcp` | Streamable HTTP. In the existing server — MCP is a transport, not a second backend |

**This is not a public API.** Access is per-user and token-scoped: the user generates a token
in settings for their own agents. A documented third-party platform with quotas and
deprecation policy remains out of scope until there are real users. See `MARKETING.md` §3.4.

`agent_tokens` scopes, defaulting to read-only:

| Scope | Grants |
| --- | --- |
| `library:read` | `read_library`, `search_titles`, `list_airs` |
| `library:write` | `apply_library_patch` for a single item; plan proposal for anything larger |
| `imports:write` | `plan_import`, including capture. Never an apply |

### Remote approval

An external caller holding `library:write` cannot write more than one item directly. It gets
a plan id, and the plan waits for the user **in Aaru**:

1. The caller calls a `plan_*` tool; the server returns a plan id and a human summary.
2. Aaru renders it as a `PlanCard` labelled with the calling token's name. Until push
   notifications exist, it appears in The Field as a pinned artifact.
3. The user approves or denies via `POST /v1/plans/{id}/approve` or `/deny`. There is no
   route by which a caller approves its own plan, and no scope grants it.
4. Apply runs through the same data layer as a tap: one `actions` row, `actor =
   external_agent`, `agentTokenId` set, inverse recorded, undoable.
5. Denials are journaled too, so the ledger answers what a token tried to do.

Rules:

- A single-item write within scope may skip the plan, because that is what a user tap does.
  An external caller gets a tap's power, never more.
- Plans expire, and a plan whose library changed since the dry run is rejected rather than
  re-planned. Unchanged from the agent-tools rules above.
- Agent tokens go through the central rate limiter (X-002). A token is not a bypass.
- Every rule in "Agent tools" applies unchanged. In particular: deleting `AppMCP` must leave
  every feature reachable through `/v1`.

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

- Sign in with Apple is the primary native path.
- Email auth is for web and for users without Apple.
- Server issues its own session. Provider tokens (Trakt) are stored separately and never sent to the client.

## Clients

### Native (MVP)

SwiftUI, `AaruCore` client, URLSession.

Minimum screens:

- Sign in
- Home / library (filter by type and status)
- Search and add
- Title detail (status, rating, notes, TV episodes)
- Lists and shelves
- Undo ribbon over the last write
- Settings → connected sources, autonomy setting, and import status

Local cache: display last successful library fetch offline. No offline write queue in v1 unless it falls out naturally.

Prefer a single multiplatform target for iPhone and Mac.

Screens are composed from the `VIEWS.md` component catalog. Every component must be usable
by direct touch before the agent is allowed to emit it — a failed model call should degrade
to a working screen, never a blank one.

### Marketing site

`aaru-landing`. SSR from Hummingbird (Mustache or Elementary) + Tailwind. Explain the product, waitlist, legal. No library session.

### Logged-in web (after native launch)

`aaru-site`. Same `/v1` API. Can be server-rendered pages or a thin Swift/JS client later. Do not fork DTO meaning for the web.

## Phasing

### Phase 1 — this architecture

Personal library, search, statuses, TV progress, lists, Trakt + CSV + CAT list imports, iOS + Mac.

### Phase 1.5 — agent surfaces

Composer, plan-preview, tool layer, and The Field as home. Requires the action journal and
saved queries from phase 1. Adds no new write path.

Also phase 1.5: capture as an import source, the model provider with own-key support, and the
outbound transports (App Intents, MCP) with remote approval. Capture is the one new data
source, and it reuses the existing import pipeline rather than adding one. See M13 and M14 in
`BACKLOG.md` and `docs/superpowers/specs/2026-09-07-agentic-surfaces-design.md`.

### Phase 2 — light collaboration

Share a list by link or with explicit user ids. Read-only first. Needs `lists.visibility` and `list_members`. Still no social feed.

### Phase 3 — realtime

Hummingbird WebSockets for list updates and presence. Only after phase 2 is used.

Do not create WebSocket handlers or a graph of follows in phase 1 “to save time later.”

## Deployment notes

- API and workers can be one binary at first (`Application` + job consumer in-process).
- Split workers when imports block request latency.
- Linux host for Hummingbird in production; macOS is fine for development.
- TMDB and Trakt keys are environment variables.
- Rate-limit provider adapters centrally so two users importing Trakt cannot stampede TMDB.

## Decisions already made

| Topic | Decision |
| --- | --- |
| Product | One app: library + tracking. Collab later. |
| Source of truth | Aaru after import |
| Video catalog | TMDB |
| Book catalog | Open Library |
| Primary user import | Trakt |
| CAT | Manual list / ICS only |
| Scraping | Forbidden |
| Backend | Hummingbird only |
| First clients | iOS and Mac |
| Web library | After native launch |
| Ownership vs status | Prefer `isOwned` + consumption `status` |
| Shelf vs list | Shelf is a saved query, list is membership. Never merged. |
| Agent writes | Journaled in `actions` and undoable. No agent-only write path. |
| Agent UI | Native component catalog only. No model-authored layout. |
| Third-party agent access | Per-user, token-scoped, over the same tool layer. Not a public API. |
| External agent writes | Single item like a tap; anything larger proposes a plan the user approves in Aaru. |
| Agent model | Pluggable `ModelProviding`. Anthropic default, own key supported, spend metered per day. |
| Capture | An import source, not a subsystem. Renders `MatchTable` then `PlanCard`. Never writes unplanned. |
| Match ledger | `match_aliases` is aggregate catalog data: no user ids, no user rows, day-granular dates, two confirmations to promote, published in full. |

If a change violates a row in that table, update this file in the same PR.
