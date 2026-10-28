# SHR-002 Share links · 01 Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a signed-in user make a reusable public link to a title, a sport event or a concert. Let anyone, signed in or not, open it, and show the sender and note only to the sender's friends.

**Architecture:**
- A `shares` table holds one row per link, pointing at exactly one target: a catalog title (resolved when the link is made), a TheSportsDB event id or a Ticketmaster event id. No event data is stored.
- `ShareService` makes links and builds previews. Previews read the catalog row, or go through the existing shared sports and concert caches, so a link opened hundreds of times costs about one provider call.
- Two `/v1` routes: `POST /v1/shares` (session) and `GET /v1/shares/{code}` (public, optional session).

**Tech Stack:** Swift 6, Hummingbird 2, swift-openapi-generator, Fluent/PostgreSQL raw SQL stores, swift-testing.

**Spec:** `docs/superpowers/specs/2026-10-28-share-links-design.md`. Plans 02 (web) and 03 (iOS) follow once this one merges and its DTOs are fixed.

## Global Constraints

- The share code is 12 characters from `InviteService.newCode()`'s alphabet. The link URL is `{webBaseURL}/s/{code}`.
- A note is trimmed, at most 140 characters, and blank means none.
- The sender (`from`) appears only when the viewer is signed in and is the sender or an accepted friend with no block either way. Otherwise `from` is absent, and the content still shows.
- Rate limits:
  - Create: 60 per hour per user.
  - Preview: 600 per hour per client address (`context.clientAddressForRateLimit`).
- Validation:
  - Sport event id: 1–40 digits (the `getSportEvent` rule).
  - Concert id: `[A-Za-z0-9_-]{1,64}`.
  - Anything else is a 422 on create.
- An unknown code is a 404 with the message "This link doesn't work anymore."
- A concert the provider can't give (concerts off, budget spent, error, or event gone) gives `unavailable: true` with no concert, never an error.
- Nothing about a sport event or concert is stored past the existing caches (CLAUDE.md "Concert", "Sport event").
- Account delete nulls `sender_id` and `note`, and the link keeps resolving.
- PostHog: `share_created` and `share_opened`, each with `distinct_id` = the **sender**, properties `{kind}`. Never the opener's id. No `share_opened` when the sender is null.
- Tests never use real API keys (stub providers: `FakeCatalog`, `FakeSports`, `FakeConcerts`).
- `docs/privacy.md` changes before any code (owner rule, 2026-10-21).

## Review Focus

1. **The same link opened by a blocked user.** Content shows and `from` is absent. It must not be a 404 (the content is public) and must not show the sender. Test: `blockHidesSender` in Task 4.
2. **The sender opens their own link.** `from` shows them (relationship `.self`), and does not 404 or show a stranger view. Test: `senderSeesSelf` in Task 4.
3. **A shared title the opener already has.** `libraryItemId` and `status` come back, so the clients show "In your library" and not Add. Test: `viewerItem` in Task 4.
4. **A share made, then the sender deletes the account.** The link still resolves, with no `from` and no note in the database. Test: `accountDeleteKeepsLink` in Task 2.
5. **Sharing the same thing twice into two chats with different notes.** Two codes, and the first link's note is unchanged. Same note (or none both times) reuses the code. Test: `dedupeByNote` in Task 2.

---

### Task 1: Privacy and decision docs first

**Files:**
- Modify: `docs/privacy.md` (product events list, plus a new "Share links" paragraph)
- Modify: `BACKLOG.md`:
  - Add a "Decisions recorded 2026-10-28" block above 2026-10-27, holding the owner decision.
  - Add an SHR-002 status row next to SHR-001 (around `:760`).
  - Add an `### SHR-002 · Share links · M` item after `SHR-001` (around `:3116`).
- Modify: `CLAUDE.md`: Domain language gets **Share link** after **Invite**. Add a Stack row note if one fits (Deploy is unchanged).
- Modify: `ARCHITECTURE.md`: the public routes list gets `GET /v1/shares/{code}`.

- [ ] **Step 1: Write the privacy text.** A stranger who opens a share link sees catalog content only (title, sport event or concert), never who sent it. A signed-in friend of the sender sees the sender and the note. `share_created` and `share_opened` carry the sender's id and the kind only, and the opener is never identified.
- [ ] **Step 2: Write the BACKLOG decision.** Copy the four owner decisions from the spec's "Owner decisions (2026-10-25)" verbatim, plus the scope line (titles of six kinds, sport events, concerts; not lists, shelves, posts or profiles).
- [ ] **Step 3: Write the CLAUDE.md entry:**
  > **Share link** — a public, reusable link (`aaruapp.com/s/{code}`) to one title, sport event or concert. Anyone can open it; only the sender's friends see who sent it and the note. Not an Invite (no friendship) and not a Recommendation (no inbox).
- [ ] **Step 4: Run `git grep -n "SHR-002" origin/main`.** Expected: no hits other than this branch's.
- [ ] **Step 5: Commit** `docs: SHR-002 share links decision, privacy first`

### Task 2: `shares` table and store

**Files:**
- Create: `aaru-server/Sources/App/Data/Migrations/Migrations+Shares.swift`
- Modify: `aaru-server/Sources/App/Data/Migrations/Migrations.swift`: append `CreateShares()` after `AddProfileDetails()`
- Create: `aaru-server/Sources/App/Data/Stores+Shares.swift`
- Create: `aaru-server/Sources/App/Data/Fluent/PostgresShareStore.swift`
- Modify: `aaru-server/Sources/App/Data/AllStores.swift`: add `let shares: any ShareStore` (property, init param, assignment, after `sports`)
- Modify: `aaru-server/Sources/App/Data/Fluent/PostgresStores.swift`: `shares: PostgresShareStore(database: database)`
- Modify: `aaru-server/Sources/App/Data/Fluent/PostgresAuthStores.swift:33` `deleteUser`: before deleting the user, run `UPDATE shares SET note = NULL WHERE sender_id = $id`
- Create: `aaru-server/Tests/AppTests/TestSupport+UntouchedShares.swift` (`extension UntouchedStore: ShareStore`, the pattern in `TestSupport+UntouchedFavorites.swift`)
- Modify: `aaru-server/Tests/AppTests/TestSupport.swift:323` fake `Stores(...)`: `shares: untouched`
- Test: `aaru-server/Tests/AppTests/ShareStoreTests.swift`

**Interfaces:**
- Produces:
  ```swift
  enum ShareTarget: Sendable, Equatable {
      case title(TitleID)
      case sportEvent(String)
      case concert(String)
      var kind: String // "title" | "sport_event" | "concert"
  }
  struct Share: Sendable, Equatable {
      var code: String
      var senderID: UserID?
      var target: ShareTarget
      var note: String?
      var createdAt: Date
  }
  protocol ShareStore: Sendable {
      /// `StoreConflict` when the code is taken.
      func createShare(_ share: Share) async throws
      func share(code: String) async throws -> Share?
      /// The sender's newest link to this target with exactly this note (nil matches nil).
      func existingShare(sender: UserID, target: ShareTarget, note: String?) async throws -> Share?
  }
  ```

- [ ] **Step 1: Write the migration** `CreateShares: SQLMigration`:
  ```sql
  CREATE TABLE shares (
      code text PRIMARY KEY,
      sender_id uuid REFERENCES users(id) ON DELETE SET NULL,
      kind text NOT NULL CHECK (kind IN ('title', 'sport_event', 'concert')),
      title_id uuid REFERENCES titles(id) ON DELETE RESTRICT,
      sport_event_id text,
      concert_id text,
      note text CHECK (note IS NULL OR char_length(note) <= 140),
      created_at timestamptz NOT NULL,
      CHECK ((kind = 'title') = (title_id IS NOT NULL)
         AND (kind = 'sport_event') = (sport_event_id IS NOT NULL)
         AND (kind = 'concert') = (concert_id IS NOT NULL))
  )
  ```
  Add the index `CREATE INDEX shares_sender ON shares (sender_id, created_at DESC)`. Backward: `DROP TABLE shares`.
- [ ] **Step 2: Write the failing tests** in `ShareStoreTests` (`withMigratedStores`, `signedInUser`, and a title inserted the way `FavoritesTests` does):
  - `roundTrip`: `createShare` for each of the three targets, then `share(code:)` returns an equal `Share`. An unknown code returns nil. A second `createShare` with the same code throws `StoreConflict`.
  - `dedupeByNote`: with shares `(A, title T, "hi")` and `(A, title T, nil)`:
    - `existingShare(A, T, "hi")` returns the first.
    - `existingShare(A, T, nil)` returns the second.
    - `existingShare(A, T, "yo")` returns nil.
    - `existingShare(B, T, nil)` returns nil.
  - `accountDeleteKeepsLink`: A shares with the note "secret", then `stores.users.deleteUser(A)`. `share(code:)` is non-nil with `senderID == nil` and `note == nil`.
- [ ] **Step 3: Run** `cd aaru-server && swift test --filter ShareStoreTests`. Expected: FAIL (no `ShareStore`).
- [ ] **Step 4: Implement** `PostgresShareStore` with raw SQL and binds, as `PostgresFavoriteStore` does. Map a unique violation to `StoreConflict`, the same way `PostgresSocialStore+Invites.swift` `createInvite` does. Wire it into `Stores`, `PostgresStores`, the fake stores and `deleteUser`.
- [ ] **Step 5: Run** `swift test --filter ShareStoreTests`. Expected: PASS.
- [ ] **Step 6: Commit** `feat(server): shares table and store (SHR-002)`

### Task 3: User-free sport event and concert by id

**Files:**
- Modify: `aaru-server/Sources/App/Sports/SportsService+Fixtures.swift`: add `publicEvent` next to `event(id:userID:)` (`:155`)
- Modify: `aaru-server/Sources/App/Concerts/ConcertTypes.swift:167` `ConcertListing`: add `func event(id: String) async throws -> Concert?`
- Modify: `aaru-server/Sources/App/Concerts/TicketmasterConcerts.swift`: implement it with `GET events/{id}.json` through the existing private `get` (so the `CallBudget` applies), mapped by the same code that maps one embedded event today. A 404 returns nil.
- Modify: `aaru-server/Sources/App/Concerts/ConcertService.swift`: add `concert(id:)` and `let eventCache = ConcertCache<Concert>()` (the type's existing TTL)
- Modify: `aaru-server/Tests/AppTests/ConcertTests.swift` `FakeConcerts`: an `events: [String: Concert]` map, a `failing` switch if none exists, and recorded `eventCalls`
- Test: `aaru-server/Tests/AppTests/SportsTests.swift` and `ConcertTests.swift` (new tests in each)

**Interfaces:**
- Produces:
  ```swift
  extension SportsService {
      /// One event with its live line, for anyone: no watch country, no follows, no user.
      /// Throws `SportsOff` when sports are off; nil when the provider has no such event.
      func publicEvent(id: String) async throws -> SportEvent?
  }
  extension ConcertService {
      /// One concert by provider id through the shared cache; nil when concerts are off,
      /// the provider fails or is over budget, or the event is gone. Never throws.
      func concert(id: String) async -> Concert?
  }
  ```

- [ ] **Step 1: Write the failing tests:**
  - `SportsTests.publicEventNeedsNoUser`:
    - `FakeSports.events["42"] = finished event with scores 2–1`.
    - `services.sports.publicEvent(id: "42")` returns that event, normalized with the scores intact.
    - A second call within 5 min makes no new provider call (check the fake's `calls`).
    - `publicEvent(id: "999")` returns nil.
  - `ConcertTests.concertByID`:
    - `FakeConcerts.events["Z1"] = concert`.
    - `concert(id: "Z1")` returns it, and a second call is served from the cache (one `eventCalls` entry).
    - With `failing`, an uncached id returns nil.
    - With `ConcertService(listing: nil)`, it returns nil.
- [ ] **Step 2: Run** `swift test --filter "SportsTests|ConcertTests"`. Expected: FAIL to compile (no `publicEvent`, no `event(id:)`).
- [ ] **Step 3: Implement.**
  - `publicEvent` reuses the `cache.value("event:\(id)", ttl: TTL.event, …)` key and the live priming from `event(id:userID:)`, so both paths share cache entries. Return `Self.normalized(event, live:, now:)`.
  - `concert(id:)` returns `await eventCache.value("event:\(id)", now: now()) { try await listing.event(id: id) }`, and nil when `listing` is nil. Follow how `near` handles a nil or failed fetch.
- [ ] **Step 4: Run** the same filter. Expected: PASS.
- [ ] **Step 5: Commit** `feat(server): look up one sport event or concert without a user (SHR-002)`

### Task 4: ShareService, routes, public preview

**Files:**
- Create: `aaru-server/Sources/App/Shares/ShareService.swift`
- Create: `aaru-server/Sources/App/API/ShareHandlers.swift`
- Modify: `aaru-server/Sources/AppAPI/openapi.yaml`: paths `/v1/shares` (POST) and `/v1/shares/{code}` (GET, `security: []`), plus the schemas below
- Modify: `aaru-server/Sources/App/API/Services.swift`:
  - Add `var shares: ShareService`.
  - In `make`: `ShareService(stores:, resolver:, catalog:, sports:, concerts:, webBaseURL: oauth.webBaseURL)`, passing the same `sports` and `concerts` values used for those fields.
- Modify: `aaru-server/Tests/AppTests/LibraryHarness.swift:56-57`: after replacing `services.concerts` and `services.sports`, rebuild `services.shares` with them. Otherwise the fakes never reach shares.
- Modify: `aaru-server/Sources/App/Auth/AuthMiddleware.swift:31` `isPublic`: also accept `/v1/shares/{code}`, with one path segment after the prefix, the same shape as invites. Update the doc comment.
- Modify: `aaru-server/Sources/App/Telemetry/ProductEvents.swift`: `case shareCreated = "share_created"`, `case shareOpened = "share_opened"`
- Test: `aaru-server/Tests/AppTests/ShareTests.swift` (`@Suite("Share links (SHR-002)", .serialized)`, reusing `SocialTests()` helpers as `InviteTests` does)

**Interfaces:**
- Consumes: `Share`, `ShareTarget`, `ShareStore` (Task 2); `SportsService.publicEvent`, `ConcertService.concert(id:)` (Task 3); `TitleResolver.resolve(_:)`; `CatalogService.detail(_:)`; `SocialService.relationship(_:_:)` (it throws on a block); `stores.social.socialUser(_:)`; `stores.library.item(userID:titleID:)`; `FixedWindowRateLimiter`; `InviteService.newCode()`.
- Produces (Swift):
  ```swift
  enum ShareRequest: Sendable { case title(MediaRef), sportEvent(String), concert(String) }
  struct SharePreview: Sendable {
      var share: Share
      var title: <CatalogService.detail return type>?
      var sportEvent: SportEvent?
      var concert: Concert?
      var unavailable: Bool
      var from: (sender: SocialUser, note: String?)?
      var viewerItem: LibraryItem?
  }
  struct ShareService: Sendable {
      func create(_ viewer: UserID, _ request: ShareRequest, note: String?) async throws -> Share
      func url(_ share: Share) -> URL
      func preview(code: String, viewer: UserID?, clientAddress: String) async throws -> SharePreview
  }
  ```
- Produces (OpenAPI, which plans 02 and 03 consume; names are fixed):
  - `ShareCreate {target: ShareTargetInput, note?: string}`
  - `ShareTargetInput {kind: enum[title, sport_event, concert], ref?: MediaRef, id?: string}`: `ref` for title, `id` otherwise
  - `ShareLink {code: string, url: string}`
  - `SharePreview {kind: enum[title, sport_event, concert], unavailable: boolean, title?: TitleDetail, sportEvent?: SportEvent, concert?: Concert, from?: ShareSender, libraryItemId?: string(uuid), status?: LibraryStatus}`
  - `ShareSender {user: SocialUser, note?: string}`
  - Operation ids: `createShare`, `getSharePreview`.

- [ ] **Step 1: Write the failing tests** in `ShareTests`, using `LibraryHarness.run(concerts: fakeConcerts, sports: fakeSports)`:
  - `createAndOpenSignedOut`:
    - POST a title share (a `FakeCatalog` ref) with the note "watch this". The reply has a 12-character `code` and `url == "https://aaruapp.com/s/\(code)"`.
    - GET `/v1/shares/\(code)` with token `signed-out` returns 200, `kind == "title"`, `title.title` set, and no `from`, `libraryItemId` or `status`.
  - `dedupeByNote`: the same POST twice returns the same code. A different note returns a different code.
  - `friendSeesSender`:
    - `ana = social.friendlyUser(env)`, befriended through `/v1/social/friend-requests` and then `/accept`, as `SocialTests.friendFlow` does.
    - Ana's GET has `from.user.handle == mine` and `from.note == "watch this"`.
    - A second, non-friend user's GET has no `from`.
  - `senderSeesSelf`: the sender's own GET has `from.user.handle == mine`.
  - `blockHidesSender`: after Ana blocks the sender (the block route `SocialTests.blocks` uses), Ana's GET is 200 with content and no `from`.
  - `viewerItem`: Ana adds the title, and then her GET has `libraryItemId` and `status == "wishlist"`.
  - `sportEventResult`: `FakeSports.events["42"]` (finished, 2–1), then a POST `{kind: sport_event, id: "42"}`. The signed-out GET has `sportEvent.home` and the scores set.
  - `concertUnavailable`: with a `{kind: concert, id: "Z1"}` share, a `FakeConcerts` with Z1 gives `concert.name`. With `failing` and a fresh id, the GET is 200 with `unavailable == true` and no `concert`.
  - `badTargets`:
    - A POST with a sport id of `"abc"` is 422.
    - A concert id of `"../x"` is 422.
    - A title with no `ref` is 422.
    - A note of 141 characters is 422.
    - A signed-out POST is 401.
  - `unknownCode`: GET `/v1/shares/nope12345678` is 404.
  - `rateLimits`: 61 POSTs from one user, and the 61st is 429. For the preview, unit-test `ShareService.previewLimiter` at 600 directly, not over HTTP.
  - `publicPath`:
    - `AuthMiddleware.isPublic("/v1/shares/abc")` is true.
    - `"/v1/shares/"` is false.
    - `"/v1/shares"` is false.
    - `"/v1/shares/abc/x"` is false.
- [ ] **Step 2: Run** `swift test --filter "ShareTests"`. Expected: FAIL to compile.
- [ ] **Step 3: Write the openapi paths and schemas** above, then `swift build` to regenerate the server stubs.
- [ ] **Step 4: Implement `ShareService`:**
  - **create:** first the create limiter. Then validate. Resolve a title ref to a `TitleID` with `resolver.resolve`. Then `stores.shares.existingShare` and return it if found. Otherwise insert with `newCode()`, retrying 3 times on `StoreConflict` (copy `InviteService.create`'s loop). Capture `.shareCreated` with `["kind": target.kind]`.
  - **preview:** first the preview limiter. Look up the share by code, or throw a 404.
    - Content by kind: `.title` reads the catalog row (`stores.titles.title` + `catalogState`), never `catalog.detail`, which hydrates episodes and tracks (corrected after review, 2026-10-28). `.sportEvent` calls `publicEvent`, and `SportsOff` or nil becomes `unavailable`. `.concert` calls `concert(id:)`, and nil becomes `unavailable`.
    - When `viewer` and `senderID` are both set, call `relationship(viewer, sender)`. A thrown `AppError` (a block) gives no `from`. `.friend` and `.self` give `from = (socialUser(sender), note)`. Anything else gives no `from`.
    - When the viewer is signed in and the target is a title, read `stores.library.item`.
    - When `senderID != nil`, capture `.shareOpened` for the sender.
- [ ] **Step 5: Implement `ShareHandlers`.** Follow `InviteHandlers.getInvitePreview` for `currentContext()` and `clientAddressForRateLimit`, and convert with the existing `.init(...)` DTO extensions: `TitleDetail`, `SportEvent(event)`, `Concert`, `SocialUser`. Also wire `Services`, the harness, `isPublic` and `ProductEvents`.
- [ ] **Step 6: Run** `swift test --filter "ShareTests|ShareStoreTests|InviteTests"`. Expected: PASS.
- [ ] **Step 7: Commit** `feat(server): share links, public preview with friends-only sender (SHR-002)`

### Task 5: Generated clients and full gate

**Files:**
- Regenerate: `aaru-api/` (`./scripts/generate-api-client.sh`) and `aaru-client/src/lib/api/schema.d.ts` (`cd aaru-client && npm run api:generate`)

- [ ] **Step 1: Run** `./scripts/generate-api-client.sh && swift test --package-path aaru-api`. Expected: PASS, with a diff in `aaru-api` only.
- [ ] **Step 2: Run** `cd aaru-client && npm run api:generate && npm run typecheck`. Expected: PASS. Only the schema file changes; the web code using it comes in plan 02.
- [ ] **Step 3: Run** `cd aaru-server && swift test` (full) and `./scripts/lint.sh`. Expected: PASS.
  - Known flakes, per memory: rerun on `CatalogRefreshTests:66` or a Linux WebSocket signal 11.
- [ ] **Step 4: Commit** `chore: regenerate API clients for share links`, push `feat/share-links`, and open a PR (body via `mattpocock-skills:pr`).
- [ ] **Step 5: After merge,** promote the API by hand. Bump the api tag and the cronjob image in `~/Work/production/platform/infra` to the Swift CI SHA from the run log. The owner merges the infra PR.
