# Aaru backlog

Derived from `README.md`, `CLAUDE.md`, `ARCHITECTURE.md`, `DESIGN.md`, and `VIEWS.md`. This file is the ordered
work list. It does not introduce product decisions; where a decision is still open it is
marked **OPEN** and left for a human.

Scope of this file: Aaru only.

## How to read this

- IDs are stable. Never renumber. Close an item by moving it to **Done** with its ID.
- Order inside a milestone is dependency order. Do not start an item whose `Needs` is open.
- `Size`: S = under a day, M = 1–3 days, L = a week or more.
- Every item names a **Done when** condition that can be checked, not "implemented".
- Items marked **Deferred** exist so nobody re-litigates them. They are not v1 work.

Rules from `CLAUDE.md` that bound every item: Aaru is source of truth after import,
one-way imports, no conflict engine, no scraping, private by default, catalog layer and
library layer stay separate, external IDs stored whenever known, no second backend.

## Status snapshot (verified 2026-08-29)

| Area | State |
| --- | --- |
| `aaru-core` | Domain model present: `Title`, `LibraryItem`, `Progress`, `Rating`, `ExternalIDs`, `MediaRef`, `AaruList`, `ImportJob`, `TitleMatching`, `Episode`, identifiers, validation. Tests exist for validation, rating, matching, external IDs, wire contract, Codable round-trip. |
| `aaru-server` | Hummingbird skeleton. Fluent + Postgres configured in `App+build.swift`, migrations gated behind `db.migrate`. **Zero migrations registered.** `openapi.yaml` is still the generator template (`getHello`). `APIImplementation` implements that one route. A template WebSocket router is wired at `/ws`. |
| `aaru-ios` | Empty directory. |
| `aaru-landing` | Empty directory. |
| `aaru-site` | Empty directory. |
| Auth, search, library, lists, imports | None of it exists. |

So the real starting line is M1, not M0-complete.

---

## Milestone map

| Milestone | Goal | Exit condition |
| --- | --- | --- |
| M1 | Server foundation | Migrations run, spec-first routes generate, auth-less health + error contract stable |
| M2 | Auth | A device can sign in and hold a session across restarts |
| M3 | Catalog + search | `GET /v1/search` returns TMDB and Open Library hits as Aaru DTOs |
| M4 | Library | Add, list, filter, patch status/rating/notes/owned, delete |
| M5 | TV progress | Episode ticks and season bulk-mark, per user |
| M6 | Lists | Manual lists of titles |
| M7 | iOS + Mac client | One multiplatform SwiftUI app doing M2–M6 against the API |
| M8 | Import jobs | Trakt OAuth import end to end, idempotent, with stats |
| M9 | File imports | IMDb / Letterboxd / Goodreads CSV, then CAT list + ICS |
| M10 | Marketing site | `aaru-landing` public, waitlist, legal |
| M11 | Logged-in web | `aaru-site` on the same `/v1` |
| M12+ | Sharing, then realtime | Only after M11 ships and real users exist |
| M13 | Agent surfaces | Composer, plan-preview, and the tool layer on components that already work by hand |
| M14 | Outbound agent surfaces | App Intents and MCP over the same tool layer, with remote approval and revocable tokens |

Native clients (M7) come before importers (M8) per the build order in `CLAUDE.md`: a
library you cannot see is not testable. M8 can start in parallel if two people are
working, but M7 is the gate for "usable".

---

## M1 — Server foundation

### SRV-001 · Delete template scaffolding · S
The generator template left `getHello` and a WebSocket echo router at `/ws`.
`ARCHITECTURE.md` forbids phase-1 WebSocket handlers.

**Done when:** `openapi.yaml` no longer declares `getHello`, `buildWebSocketRouter` and the
`.http1WebSocketUpgrade` server config are gone from `App+build.swift`, and
`HummingbirdWebSocket` is dropped from `Package.swift`. `swift test` passes.

### SRV-002 · `/v1` spec skeleton and error contract · M
**Needs:** SRV-001.
Restructure `openapi.yaml` around the `/v1` prefix. Define the shared error schema once
(`code`, `message`, optional `details`), the auth security scheme, and the pagination
envelope used by every list route. No business routes yet.

**Done when:** the generator produces `/v1`-prefixed protocol stubs, every route in the
spec references the shared error schema, and one deliberate 404 and one 422 return that
shape in a test.

**OPEN:** pagination style — cursor vs offset. Recommendation: cursor keyed on
`(updated_at, id)`, because library sync from a client wants "changed since" anyway.

### SRV-003 · Data layer boundary · M
**Needs:** SRV-001.
`CLAUDE.md`: "PostgreSQL access goes through one data layer. No ad-hoc SQL in route
handlers." Create the repository types (`TitleStore`, `LibraryStore`, `ListStore`,
`ImportJobStore`, `UserStore`) as `Sendable` protocols with Fluent implementations, and
inject them into handlers.

**Done when:** no `Fluent` or `Database` symbol appears in a request handler file, and a
handler test can run against an in-memory or fake store without Postgres.

### SRV-004 · Migration 001: users and auth identities · S
**Needs:** SRV-003.
`users`, `auth_identities` (provider, provider_subject, email, unique on
`(provider, provider_subject)`).

**Done when:** `swift run aaru --db.migrate true` creates both tables against the
docker-compose database and is re-runnable without error.

### SRV-005 · Migration 002: titles and episodes · M
**Needs:** SRV-004.
`titles` with partial unique indexes on each external ID where not null (`tmdb`, `imdb`,
`trakt`, `tvdb`, `isbn`, `open_library`); `show_episodes (title_id, season, episode,
air_date?, tmdb_episode_id?)` unique on `(title_id, season, episode)`.

**Done when:** inserting two titles with the same non-null `tmdb` id fails at the database
level, and two titles with null `tmdb` ids both insert.

### SRV-006 · Migration 003: library, progress, lists · M
**Needs:** SRV-005.
`library_items` unique `(user_id, title_id)`; `episode_progress` unique
`(library_item_id, season, episode)`; `lists`, `list_items`. Include
`lists.visibility` defaulting to `private` — `ARCHITECTURE.md` explicitly allows this one
nullable hook for phase 2. Nothing else forward-looking.

**Done when:** migrations apply clean, and a second `POST` of the same title for the same
user is rejected by the unique index rather than by application code alone.

### SRV-007 · Migration 004: import jobs · S
**Needs:** SRV-006.
`import_jobs` (`user_id`, `source`, `state`, `stats` jsonb, `error_summary`,
timestamps), optional `import_job_events`.

**Done when:** `ImportJob` from `AaruCore` round-trips through the table without a field
being dropped or renamed in meaning.

### SRV-008 · Config, secrets, health · S
**Needs:** SRV-002.
TMDB, Trakt, Open Library, and JWT signing config read through `ConfigReader`. Fail fast
at boot with a named error when a required key is missing. Add `GET /v1/health`
(unauthenticated, no database detail leaked).

**Done when:** starting without `TMDB_API_KEY` exits with a message naming the key, and
`.env` stays untracked. Confirm `aaru-server/.env` is git-ignored before anything is
committed.

### SRV-009 · CI green on the real matrix · S
**Needs:** SRV-004.
`aaru-server/.github/workflows/ci.yml` must run `swift test` for both packages with a
Postgres service container, plus `swiftformat --lint` and `swiftlint`.

**Done when:** CI fails on a deliberately misformatted file and on a failing migration.

---

## M2 — Auth

### AUTH-001 · Session model and middleware · M
**Needs:** SRV-004, SRV-008.
Server-issued session (JWT or opaque bearer, one choice, written into `ARCHITECTURE.md`).
Auth middleware resolves the token to a `userId` and puts it in the request context.
Every `/v1` route except health and auth requires it.

**Done when:** a request without a token to any library route returns 401 in the shared
error shape, and a request with a token for user A cannot read user B's rows (test asserts
this, not a comment).

**OPEN:** JWT vs opaque session. Recommendation: opaque token in Postgres with a
`sessions` table. Revocation matters more than statelessness at this scale, and the
Trakt-token path already means the server keeps state.

### AUTH-002 · Sign in with Apple · M
**Needs:** AUTH-001.
Verify the Apple identity token (JWKS fetch + cache, `aud`, `iss`, `exp`, nonce), create
or match `auth_identities`, issue a session. Handle Apple's private relay email and the
fact that the name arrives only on first authorization.

**Done when:** a replayed token past `exp` is rejected, an unknown `kid` triggers one JWKS
refresh and then fails closed, and signing in twice yields one user row.

### AUTH-003 · Email auth · M
**Needs:** AUTH-001.
Email + password (Argon2id or bcrypt via a vetted library — no hand-rolled hashing) or
magic link. One of the two, not both.

**Done when:** password hashes are never returned by any route, a wrong password and an
unknown email are indistinguishable in response and timing to a reasonable degree, and
sign-up is rate-limited per IP and per email.

**OPEN:** password vs magic link. Recommendation: magic link. It removes password storage,
reset flows, and breach surface; the cost is an email sender dependency.

### AUTH-004 · Sign out and account delete · S
**Needs:** AUTH-002 or AUTH-003.
`DELETE /v1/auth/session` and a full account delete that removes library items, progress,
lists, jobs, and stored provider tokens.

**Done when:** after account delete no row anywhere references the user id, and the
deletion is covered by a test that counts rows in every user-scoped table.

---

## M3 — Catalog and search

### CAT-001 · `CatalogSearching` adapters and provider client base · M
**Needs:** SRV-003, SRV-008.
Implement the protocol from `ARCHITECTURE.md`. Shared HTTP client with timeout, retry with
backoff on 429/5xx, and a central rate limiter so two concurrent imports cannot stampede
TMDB. Cancellation propagates when the client disconnects.

**Done when:** a fake provider returning 429 twice then 200 is retried and succeeds, and a
cancelled request cancels the in-flight provider call.

### CAT-002 · TMDB adapter · M
**Needs:** CAT-001.
Search and detail for `movie` and `show`. Map TMDB external IDs (`imdb_id`, `tvdb_id`)
onto `ExternalIDs`. Poster URLs are referenced, never downloaded.

**Done when:** searching a known title returns `CatalogHit`s carrying `tmdb` and `imdb`
ids, and no TMDB JSON field names appear in any response DTO.

### CAT-003 · Open Library adapter · M
**Needs:** CAT-001.
Search and detail for `book`. ISBN normalization (ISBN-10 to ISBN-13), cover URL,
`openLibrary` work/edition id.

**Done when:** an ISBN-10 and its ISBN-13 form resolve to the same `Title`.

### CAT-004 · `GET /v1/search` · M
**Needs:** CAT-002, CAT-003.
`q` and `type=movie|show|book`. Fan out with structured concurrency when type is absent —
**OPEN:** whether `type` is required. Recommendation: required in v1. Mixed-type ranking
is a research problem and the client has tabs anyway.

**Done when:** results are catalog projections with no library fields on them, and a
provider outage on one type degrades to an error for that type rather than a 500 for the
request.

### CAT-005 · `MediaRef` → `Title` resolution · L
**Needs:** CAT-002, CAT-003, SRV-005.
The find-or-hydrate path every add and every import row goes through. Match on external
IDs first; fall back to `AaruCore.TitleMatching` on normalized title + year + type. Never
merge two titles that only share a similar name.

**Done when:** concurrent adds of the same `MediaRef` from two requests produce exactly one
`titles` row (test with real concurrency, relying on the unique index plus upsert, not a
Swift lock), and a title with no external IDs never merges into one that has them.

### CAT-006 · `GET /v1/titles/{id}` and season hydration · M
**Needs:** CAT-005.
Title detail. For shows, lazily hydrate `show_episodes` from TMDB on first request and
cache. Re-hydrate on a staleness window for airing shows.

**Done when:** the first request for a show populates episodes, the second serves from
Postgres with no TMDB call, and adding a season upstream is picked up after the staleness
window.

**OPEN:** staleness window. Suggested: 24h for shows with an episode airing within 30
days, 30d otherwise.

---

## M4 — Library

### LIB-001 · `POST /v1/library/items` · M
**Needs:** CAT-005, AUTH-001.
Body is a `MediaRef` plus optional initial status. Resolves the title, creates the library
item.

**Done when:** posting the same `MediaRef` twice returns the same item (200/idempotent, not
a duplicate and not a 500 from the unique index).

### LIB-002 · `GET /v1/library/items` with filters · M
**Needs:** LIB-001, SRV-002.
Filters: `type`, `status`, `list`, `isOwned`, plus the pagination envelope. Response embeds
the title projection so a client render needs one call.

**Done when:** filtering by `status=in_progress&type=show` returns only that user's rows,
paginates stably while rows are being written, and the query plan uses an index (verify
with `EXPLAIN`, not by feel).

### LIB-003 · `GET`/`PATCH`/`DELETE /v1/library/items/{id}` · M
**Needs:** LIB-001.
`PATCH` covers `status`, `rating`, `notes`, `isOwned`. Rating validated by
`AaruCore.Rating` (1–10 in 0.5 steps). `status` is consumption only — never write ownership
into it. Setting `finished` stamps `finishedAt`.

**Done when:** an out-of-range or off-step rating returns 422 with the field named, setting
`isOwned` leaves `status` untouched, and patching another user's item returns 404 (not 403
— do not confirm existence).

### LIB-004 · Library sync endpoint for clients · M
**Needs:** LIB-002.
`updatedSince` cursor so a native client can refresh without refetching the library.
Includes tombstones for deletions.

**Done when:** deleting an item on one device makes it disappear on a second device that
only asks for changes since its last sync token.

### AUD-001 · Action journal · M
**Needs:** LIB-003, SRV-006.
Every mutating library write records one row: `id`, `userId`, `actor` (`user` | `agent`),
`kind`, affected item ids, an inverse payload sufficient to revert, `createdAt`. Migration
005. Writes go through the data layer, not each route handler.

This is required by the undo ribbon in `DESIGN.md`. It is not a log file — it is the backing
store for a first-class view, so it is user data with retention, not observability output.

**Done when:** a `PATCH` and a season bulk-mark each produce exactly one journal row inside
the same transaction as the write, and a failed write leaves no row.

**OPEN:** retention. Recommendation: keep 90 days of journal rows, keep the last 20 per user
forever so the ribbon is never empty.

### AUD-002 · Undo endpoint · M
**Needs:** AUD-001, PROG-002.
`GET /v1/actions?limit=` and `POST /v1/actions/{id}/undo`. Undo applies the stored inverse in
one transaction. Undoing is itself journaled with `actor = user`, so undo history stays
honest rather than rewriting the past.

Grouping matters: one agent instruction that touches 18 episodes is **one** action, not 18.
The journal stores the group; the ribbon shows the group's summary string.

**Done when:** marking a season watched and then undoing it returns every episode to its
prior state including episodes that were already watched before the bulk mark, and undoing
the same action twice is rejected with 409 rather than double-applied.

---

## M5 — TV progress

### PROG-001 · `PUT /v1/library/items/{id}/episodes/{season}/{episode}` · M
**Needs:** LIB-003, CAT-006.
Watched true/false for one episode. Writes `episode_progress`.

**Done when:** marking an episode that does not exist in `show_episodes` returns 422, and
marking the same episode twice is idempotent.

### PROG-002 · `POST /v1/library/items/{id}/seasons/{season}/watched` · S
**Needs:** PROG-001.
Bulk mark a season.

**Done when:** one request marks every aired episode of the season in a single transaction,
and unaired episodes are left alone.

### PROG-003 · Derived progress summary · M
**Needs:** PROG-001.
`watchedCount`, `totalCount`, `nextEpisode`, and automatic `status` transitions:
first tick moves `wishlist` → `in_progress`; last aired episode does **not** auto-finish a
running show.

**Done when:** the summary is computed in one query per item list (no N+1), and a show
whose finale has aired plus every episode watched reports `nextEpisode == nil` without
flipping status on its own.

**OPEN:** should completing an ended show auto-set `finished`? Recommendation: yes for
shows TMDB reports as `Ended`/`Canceled`, no otherwise.

### PROG-004 · Book progress · S
**Needs:** LIB-003.
Optional `page` / `percent` on `Progress`. No scrobble positions.

**Done when:** setting `percent` outside 0–100 is rejected, and page and percent cannot
disagree silently (store one, derive the other only if total pages is known).

---

## M6 — Lists

### LST-001 · List CRUD · M
**Needs:** SRV-006, AUTH-001.
`GET/POST /v1/lists`, rename, delete. `visibility` exists in the table and defaults to
`private`; no route exposes changing it in v1.

**Done when:** every list route is user-scoped, and there is no code path that can set
`visibility` to anything but `private`.

### LST-002 · List membership · M
**Needs:** LST-001, CAT-005.
`POST /v1/lists/{id}/items` takes a `MediaRef` or `titleId` so a list can hold a title the
user has no status for. `DELETE /v1/lists/{id}/items/{itemId}`. Manual ordering.

**Done when:** adding a title not in the library succeeds without creating a library item,
and reordering survives a round trip.

### SHF-001 · Saved queries (shelves) · M
**Needs:** LIB-002, LST-001.
`saved_queries` table: `id`, `userId`, `name`, serialized filter, `isPinned`, `createdAt`.
Routes `GET/POST/PATCH/DELETE /v1/shelves`. A shelf resolves to the same filter grammar
`GET /v1/library/items` already accepts — no second query language.

A shelf is a query, a list is membership. See the comparison table in `VIEWS.md`. They share
a renderer, not a table.

**Done when:** a stored filter that returns 12 items today returns 13 after a matching title
is added, with no write to the shelf, and no route can add an item id directly to a shelf.

### SHF-002 · Shelf resolution endpoint · S
**Needs:** SHF-001.
`GET /v1/shelves/{id}/items`, paginated, same DTO as `GET /v1/library/items`.

**Done when:** the shelf result and the equivalent hand-written filter query return byte
identical payloads for the same library state.

---

## M7 — iOS and Mac client

One multiplatform SwiftUI target. If a split ever happens, shared views go through
`AaruCore` plus a thin UI module — never copy-paste.

### APP-001 · App skeleton and API client · L
**Needs:** AUTH-002, SRV-002.
Xcode project in `aaru-ios/`, depends on `AaruCore`. `AaruCore` currently has no HTTP
client — **OPEN:** add a generated OpenAPI client into `AaruCore`, or a thin URLSession
client in the app? Recommendation: generated client in a separate `AaruAPI` module that
depends on `AaruCore`, so `CLAUDE.md`'s "no HTTP client yet in core" holds and the DTOs
still cannot fork.

**Done when:** the app builds for iPhone and Mac from one target, and a 401 anywhere routes
the user to sign-in exactly once (no retry storm).

### APP-002 · Sign in · M
**Needs:** APP-001, AUTH-002.
Sign in with Apple, plus the email path. Token in Keychain, shared correctly on Mac.

**Done when:** the session survives app relaunch on both platforms and sign-out clears the
Keychain item.

### APP-003 · Library screen · L
**Needs:** APP-001, LIB-002.
Filter by type and status. Poster grid and list modes. Last successful fetch is displayed
offline; no offline write queue in v1.

**Done when:** launching in airplane mode shows the last library instead of an error
screen, and 1,000 items scroll without image-loading jank.

### APP-004 · Search and add · M
**Needs:** APP-003, CAT-004, LIB-001.
Type-scoped search, debounce, add with initial status.

**Done when:** adding from search updates the library screen without a full refetch, and a
double-tap on add does not create two items.

### APP-005 · Title detail · L
**Needs:** APP-003, LIB-003, PROG-003.
Status, rating, notes, owned toggle, and for shows the season/episode list with ticks.

**Done when:** an episode tick is optimistic in the UI, reconciles with the server response,
and rolls back visibly on failure.

### APP-006 · Lists screen · M
**Needs:** APP-003, LST-002.

**Done when:** a title can be added to a list from title detail and from search results.

### APP-007 · Settings, sources, import status · M
**Needs:** APP-001, IMP-002.
Connected sources, start an import, watch job state and stats, see unmatched rows.

**Done when:** a running import shows live-ish progress by polling, and a `partial` job
surfaces its unmatched count with a way to see the rows.

### APP-008 · Mac-specific pass · M
**Needs:** APP-005.
Keyboard navigation, multi-column layout, menu bar commands. Same target.

**Done when:** the Mac build is not a stretched iPad app: sidebar navigation, ⌘F search,
⌘N add.

---

## M8 — Trakt import

### JOB-001 · Job queue · L
**Needs:** SRV-007.
Hummingbird Jobs (or equivalent) with a Postgres-backed queue. In-process worker at first;
`ARCHITECTURE.md` allows one binary until imports block request latency. Retries with
backoff, a dead-letter state, and cancellation.

**Done when:** killing the process mid-job leaves the job re-runnable rather than stuck in
`running`, and a job that throws lands in `failed` with an `errorSummary`.

### IMP-001 · Import job contract · M
**Needs:** JOB-001.
`GET /v1/imports`, `GET /v1/imports/{id}`. Every importer reports
`created / updated / skipped / unmatched`. Unmatched rows are listed, never silently
dropped.

**Done when:** a job with 3 unmatched rows returns those 3 rows with enough detail (source
title, year, source ids) for a human to fix them by hand.

### IMP-002 · Trakt OAuth connect · M
**Needs:** IMP-001, AUTH-001.
`POST /v1/imports/trakt/connect`, `GET /v1/imports/trakt/callback`. Token stored encrypted
at rest, never sent to a client. State parameter checked. Refresh handled.

**Done when:** the access token never appears in any response body or log line, the
callback rejects a mismatched `state`, and an expired token refreshes without user
interaction.

### IMP-003 · Trakt import worker · L
**Needs:** IMP-002, CAT-005.
Pull watched history, watchlist, ratings, and lists. Page through the API respecting rate
limits. Map Trakt ids → TMDB/IMDb → `Title`. Upsert `LibraryItem` on `(user_id, title_id)`.
Apply episode progress and ratings.

**Done when:** running the same import twice produces zero duplicates and a second run
reports `updated`/`skipped` rather than `created`, and a 10,000-item history completes
without exhausting the TMDB rate budget.

### IMP-004 · Merge policy · M
**Needs:** IMP-003.
Fill-empty-only, in the order Trakt → IMDb → Letterboxd → Goodreads → CAT. A later source
never overwrites a non-empty rating, status, or progress. `ARCHITECTURE.md` explicitly
permits skipping the "newer wins" rule in v1.

**Done when:** importing Letterboxd after Trakt leaves every Trakt rating intact, and a
test asserts that on a title present in both.

---

## M9 — File imports

### IMP-005 · CSV upload endpoint · M
**Needs:** IMP-001.
`POST /v1/imports/csv` multipart with `source=imdb|letterboxd|goodreads`. Size cap,
content-type check, streamed to disk or memory bounded — never fully buffered without a
limit. Files are parsed and discarded; `ARCHITECTURE.md` says do not store raw provider
dumps long-term.

**Done when:** a 200 MB upload is rejected before it is buffered, a file whose columns do
not match the declared source fails with a readable error, and no uploaded file survives
job completion.

### IMP-006 · IMDb CSV parser · M
**Needs:** IMP-005, IMP-004.
Columns: title, year, title type, `tconst`, rating, date. `tconst` is a hard external ID,
so match confidence is high.

**Done when:** an IMDb export with TV episodes as rows is handled (episodes roll up to the
show or are counted as unmatched — decide once and document), and ratings map onto the
Aaru 1–10 / 0.5 scale without drift.

### IMP-007 · Letterboxd CSV parser · M
**Needs:** IMP-006.
Columns: Name, Year, Letterboxd URI, Rating, Watched Date. No IMDb id in the export, so
resolution goes through TMDB search + year via `TitleMatching`.

**Done when:** an ambiguous title + year pair with two plausible TMDB hits is reported
unmatched rather than guessed, and Letterboxd's 0.5–5 star scale is doubled onto Aaru's
1–10.

### IMP-008 · Goodreads CSV parser · M
**Needs:** IMP-005, CAT-003.
Columns: Title, Author, ISBN, My Rating, Exclusive Shelf, Date Read. Shelf maps to status:
`to-read` → `wishlist`, `currently-reading` → `in_progress`, `read` → `finished`. Custom
shelves become lists.

**Done when:** rows with an empty or `=""`-wrapped ISBN (Goodreads does this) still resolve
by title + author, and a custom shelf produces one Aaru list, not one per row.

### IMP-009 · CAT show list · M
**Needs:** IMP-005, CAT-002.
`POST /v1/imports/cat` with a plain text list of show names. TMDB search, first
high-confidence hit only. No watched state. No scraping of pogdesign.co.uk — ever.

**Done when:** a name with no high-confidence hit is reported unmatched, and every created
item lands as `wishlist` with empty progress.

### IMP-010 · CAT ICS parse · M
**Needs:** IMP-009.
Extract show titles from calendar event names in the user's exported ICS. Treat them as
tracked series. No episode watched-state.

**Done when:** an ICS with 200 events across 15 shows produces 15 candidate titles, not 200,
and event names that do not parse are surfaced rather than dropped.

### IMP-011 · Unmatched row triage UI · M
**Needs:** APP-007, IMP-001.
Let the user resolve unmatched rows by searching and picking the right title.

**Done when:** resolving a row creates the library item with the source's status and rating
applied, and the job's unmatched count decreases.

---

## M10 — Marketing site

### LAND-001 · `aaru-landing` scaffold · M
Hummingbird SSR (Mustache or Elementary) + Tailwind. Separate binary or separate route
tree — it must never hold a library session.

**Done when:** the landing binary has no dependency on the library data layer, and the page
scores well enough on Lighthouse to not embarrass (no blocking JS, no layout shift on the
hero).

### LAND-002 · Waitlist · S
**Needs:** LAND-001.
Email capture with double opt-in and an export.

**Done when:** a submitted address is stored, confirmable, and deletable on request.

### LAND-003 · Legal and privacy copy · S
**Needs:** LAND-001.
Privacy policy that is accurate about what Aaru stores: library data, Trakt tokens,
uploaded CSV contents (transient). App Store requires this before submission.

**Done when:** the policy names every third party data touches (TMDB, Open Library, Trakt,
Apple) and matches what the code actually does.

---

## M11 — Logged-in web

### WEB-001 · `aaru-site` on `/v1` · L
**Needs:** native launch.
Server-rendered library client against the same API. DTO meaning does not fork.

**Done when:** the web client uses the same `/v1` routes as the apps with no web-only
endpoint added, and `ARCHITECTURE.md` is updated to list it as a live client.

---

## M12+ — After real usage

Kept here so they are not forgotten and not started early.

- **SHR-001** Shared lists by link or explicit user ids, read-only first. Needs
  `list_members`. Phase 2 in `ARCHITECTURE.md`.
- **RT-001** WebSocket list updates and presence. Phase 3, and only after phase 2 is
  actually used.

---

## M13 — Agent surfaces

`DESIGN.md` makes the agent the way you speak to Aaru and the component catalog the way it
answers. That layer is built **after** M7, on components that already work by direct touch.
A component the user cannot drive by hand is not allowed to ship behind an agent.

### AG-001 · Tool layer · L
**Needs:** LIB-004, PROG-003, SHF-001, AUD-002.
Server-side tools the model may call: `search_titles`, `read_library`, `plan_import`,
`apply_library_patch`, `list_airs`. Each is a thin, typed wrapper over an existing `/v1`
route. No tool reaches the database directly and no tool returns vendor JSON.

`read_library` wraps `GET /v1/library/items` and `GET /v1/shelves/{id}/items`. It is not
optional: `search_titles` reads the *catalog*, so without it nothing can populate a `Shelf`
or a `TonightStrip`.

**Done when:** removing the tool layer entirely leaves every feature reachable through the
plain API, and each tool's arguments are validated by the same code that validates the route.

### AG-002 · Component envelope · M
**Needs:** AG-001.
The model returns component names and props from the `VIEWS.md` catalog only. Host validates
against the catalog and refuses unknown names, substituting the nearest catalog piece.

**Done when:** a response naming a component outside the catalog renders a catalog fallback
and logs a refusal, never a blank screen or raw text.

### AG-003 · Plan and apply · L
**Needs:** AG-001, AUD-002.
Every multi-item mutation is two steps: a dry run returning a `PlanCard` payload (counts,
per-op diff, unmatched, proposed merges), then an apply against that plan id. Plans expire.
Autonomy — `ask me` / `fill empty only` / `overwrite if newer` — is stored user config, read
by the server, and echoed on the plan. The model does not select it.

**Done when:** applying a plan whose underlying library changed since the dry run is rejected
rather than silently re-planned, and first-run imports cannot be applied without a plan.

### AG-004 · Composer and The Field · L
**Needs:** AG-002, APP-003.
Home becomes the vertical canvas: composer on top, pinned artifacts below (Now, Airs this
week, Unfinished business, last import collapsed).

**Done when:** the home screen renders and is fully usable with the agent disabled or
offline, showing pinned shelves and in-progress items from cache.

### AG-005 · `TonightStrip` · M
**Needs:** AG-002, PROG-003.
One to three next actions with a reason and an estimated duration. Reject and "not tonight"
are recorded as signal.

**Done when:** the strip is derived only from the user's own library — no cross-user data,
no recommendation service — and a reject never re-suggests the same item that night.

**OPEN:** does reject signal persist as user data or stay local? Recommendation: local first,
since it is preference noise, not library truth.

### AG-006 · Capture as an import source · L
**Needs:** AG-003, IMP-005, IMP-011, JOB-001.
`POST /v1/imports/capture` accepts `text`, `image`, or `url` and returns an import job id like
every other importer. `ImportJob.source` gains `capture` in `AaruCore`. Extraction produces
`[MediaRef]` and hands off to the existing `TitleMatching`; do not write a second matcher.
Renders `JobLedger` → `MatchTable` → `PlanCard`, so it adds no component. Corrections promote
into `match_aliases` at pipeline step 7, same as a CSV.

Capture is user-triggered and out-of-band: it does **not** join the Trakt → IMDb →
Letterboxd → Goodreads → CAT merge order.

**Done when:** a pasted list of nine titles produces one import job, one `MatchTable` with
three buckets, and one `PlanCard`, and no library row is written before the plan is approved —
including when only a single row was extracted.

**OPEN:** image extraction is the most expensive and least reliable input. Recommendation:
ship text and URL first behind the same route, image second, so triage is proven on cheap
input.

### AG-007 · Model provider, own key, metering · M
**Needs:** AG-001.
`ModelProviding` protocol in `Server`, following the `CatalogSearching` /
`UserLibraryImporting` style. Anthropic adapter default, keys in environment config. A user
may store their own encrypted key, which lifts the fair-use cap. Table `agent_usage`
(`userId`, `day`, `inputTokens`, `outputTokens`, `costCents`), day-granular. Adds
`GET`/`PATCH /v1/settings`, which is also where the AG-003 autonomy dial is stored.

Metering exists from the first call, not after a bill. This is the answer to the cost-sink
risk in `MARKETING.md`.

**Done when:** every model call in the codebase goes through `ModelProviding` and writes an
`agent_usage` row, a user with their own key is not capped, and no provider name appears
outside its adapter.

---

## M14 — Outbound agent surfaces

Aaru's tool layer with two more transports on it: Apple's agent stack, and MCP. Both are
**skins over M13's tools** — neither adds a capability, a route behind the tools, or a write
path. Phase 1.5, same as M13.

The point of the milestone is not reach, it is `OUT-004`'s approval step: an outside agent
gets to *propose* a change, and the change waits for the user inside Aaru. That is only cheap
because AUD-001 already stores an inverse for every write.

**This is not a public API.** Access is per-user and token-scoped. A documented third-party
platform stays out of scope — see `MARKETING.md` §3.4 and `CLAUDE.md`.

### OUT-001 · Agent tokens · M
**Needs:** AUTH-001, AG-001.
Table `agent_tokens`: `id`, `userId`, `name`, `hashedToken`, `scopes`, `lastUsedAt`,
`expiresAt`, `revokedAt`. Only the hash is stored; the secret is shown once at creation.
Routes `GET`/`POST /v1/agent/tokens` and `DELETE /v1/agent/tokens/{id}`. Scopes are
`library:read`, `library:write`, `imports:write`, defaulting to read-only. Tokens go through
the central rate limiter per X-002.

**Done when:** a token can be created, listed, and revoked from the client; a revoked token is
refused on the next call; deleting the account deletes its tokens; and the secret is
unrecoverable from the database.

### OUT-002 · Action provenance for external callers · S
**Needs:** AUD-001, OUT-001.
`actions.actor` gains `external_agent`; `actions` gains a nullable `agentTokenId`. The undo
ribbon shows which agent made the write. Revoking a token leaves its history readable.

**Done when:** a write made over MCP produces one journal row naming its token, the ribbon
renders that name, and revoking the token does not alter or hide the row.

### OUT-003 · App Intents and Shortcuts · M
**Needs:** AG-002, APP-003.
Each M13 tool is exposed as an App Intent in `aaru-ios`, which yields Siri, Shortcuts,
Spotlight, and the share sheet. `TitleCard` and `TonightStrip` serve as intent snippet views.
Capture's share-sheet target lands here. No server work — this is why it ships before MCP.

**Done when:** "log last episode", "what's on tonight", and sharing a URL into Aaru all work
from Shortcuts without opening the app, and each one produces the same journal row a tap would.

### OUT-004 · MCP endpoint and remote approval · L
**Needs:** OUT-001, OUT-002, AG-003.
`POST /v1/mcp` (streamable HTTP) in `aaru-server/Sources/AppMCP` — inside the existing server,
because MCP is a transport and the no-second-backend rule stands. Exposes exactly M13's tools.

Remote approval: a caller with `library:write` may write a single item directly, exactly as a
tap does. Anything larger returns a plan id and a human summary, and the plan waits in Aaru as
a `PlanCard` labelled with the calling token's name. `POST /v1/plans/{id}/approve` and `/deny`
are the only way through, and no scope grants a caller access to them. Denials are journaled.
Until push exists (`MARKETING.md` item 18), pending plans show in The Field as a pinned
artifact.

**Done when:** deleting `AppMCP` leaves every feature reachable through `/v1`; a multi-item
write requested over MCP cannot land without an in-app approval; a stale plan is rejected
rather than re-planned; and no MCP response contains vendor JSON.

### OUT-005 · Agent-readable digest · S
**Needs:** LIB-002, SHF-002, OUT-001.
`GET /v1/context` — one compact library digest for read-only consumers, so an agent can hold
context without paging the library.

**Done when:** the digest is derived only from routes that already exist, needs only
`library:read`, and contains no provider payloads.

**OPEN:** `MARKETING.md` launch-gate item 14 requires free CSV/JSON export and **no backlog
ticket exists for it** — there is no `EXP` prefix in use. Recommendation: file the export
ticket first and make this a format of that export rather than a second export path.

---

## Moat exploration (post-v1, not scheduled)

You raised Stremio and deeper Trakt integration as the differentiator. Both are
genuinely interesting and both violate v1 scope as written, so they live here as
research items, not backlog work. Note that "Trakt native integration" beyond one-way
import means two-way sync or scrobbling, and both are on the explicit out-of-scope list
in `CLAUDE.md` and `README.md`. Changing that means changing those files first.

### MOAT-001 · Stremio addon exposing an Aaru library · research
Stremio addons are an HTTP protocol: a manifest plus `catalog` / `meta` / `stream`
endpoints. An Aaru addon that serves the user's own wishlist and in-progress rows as
Stremio catalogs is additive, needs no scraping, and does not touch stream sources.
This is the cheapest version of the idea and stays inside the product rules.

Unknowns to settle before it is a backlog item: per-user addon auth (Stremio addons are
URLs — a token in the path is the usual pattern, with the leak risk that implies), whether
it stays private, and whether it pulls Aaru into stream-source territory it should stay
out of.

### MOAT-002 · Watch-state write-back from a player · research
Marking episodes watched from the player is the real moat and the real complexity: it is
two-way sync, which v1 forbids by design because it needs a conflict engine. If this is
the product's point, the honest move is to schedule it as a v2 milestone with its own
conflict model, not to smuggle it into v1.

### MOAT-003 · Trakt as an output, not only an input · research
Pushing Aaru state back to Trakt is a smaller version of MOAT-002 — one direction, one
provider, user-triggered rather than continuous. Still out of v1 scope. Cheapest honest
form: an explicit "push my library to Trakt" job with a dry-run diff, not background sync.

**Recommendation:** ship M1–M9 first. All three of these are more attractive with a real
library behind them, and none of them is testable without one.

---

## Cross-cutting, do continuously

- **X-001** Update `CLAUDE.md` and `ARCHITECTURE.md` in the same change that adds a source,
  status, or client. Both files say this; treat a PR without it as incomplete. A change that
  adds or renames a surface or component updates `DESIGN.md` and `VIEWS.md` too.
- **X-002** Every provider adapter goes through the central rate limiter. No adapter gets
  its own ad-hoc client.
- **X-003** No vendor JSON crosses the API boundary. If a DTO field is named after a TMDB
  or Trakt field, rename it.
- **X-004** Swift 6 strict concurrency stays on. No `@unchecked Sendable` without a comment
  saying why.
- **X-005** Secrets stay in environment config. Never commit `.env` or a key.
- **X-006** No destructive database command against anything but the local docker-compose
  instance.
- **X-007** Every mutating library path writes an `AUD-001` journal row in the same
  transaction and is reversible by `AUD-002`. A write that cannot state its inverse does not
  ship. This applies to user taps as well as agent calls.
- **X-008** A shelf is a saved query, a list is membership. No code path writes `list_items`
  in response to a shelf request. See `VIEWS.md`.
- **X-009** An external agent caller gets no capability a signed-in session does not have.
  Every external write is journaled with its `agentTokenId`, and every multi-item external
  write requires an approval inside Aaru. A token that cannot be revoked from the app does not
  ship, and no caller may approve its own plan.

## Explicitly not doing (v1)

Two-way sync · conflict engine · scrobbling · recommendations · friend graph · activity
feed · collaborative lists · public profiles · AniList / MAL / Serializd / SIMKL ·
music, comics, games · scraping any site without an official export · hosting TMDB or
Open Library artwork · a full web clone before the native apps ship · a second backend ·
a documented public API with third-party clients (M14's agent access is per-user and
token-scoped, which is a different thing).
