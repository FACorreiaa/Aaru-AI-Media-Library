# Friends + groups, plan 1: decisions and server safety — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record the 2026-10-27 owner decision and its backlog items. Then close the two
server holes that must be fixed before any discovery work: unlimited handle lookups and friend
requests, and group invites that survive a block or an unfriend.

**Architecture:** Docs first: `BACKLOG.md` decisions and items, plus `CLAUDE.md`'s exception
list. Then two server-only changes:
- per-user fixed-window limits in `SocialService`, the same pattern as
  `InteractionService.sendLimiter`;
- `PostgresSocialStore` deletes the pair's pending `group_invites` when they stop being
  friends, and `GroupService.accept` re-checks the friendship.

No client code changes. `openapi.yaml` changes only in two summaries, so the generated clients
are regenerated.

**Tech Stack:** Swift 6, Hummingbird 2, swift-openapi-generator, Postgres (raw SQL through
`SQLKit`), swift-testing with `LibraryHarness`.

**Spec:** `docs/superpowers/specs/2026-10-27-friends-groups-design.md` (Steps 0 and 1 of its
build order). Plans 2–8 cover Steps 2–7 and are written as each one lands.

**Work in:** `/Users/fernandocorreiachill/Work/production/apps/aaru-wt-friends-groups`, branch
`feat/friends-groups`. The main checkout at `apps/aaru` is shared with other sessions; never
touch it.

## Global Constraints

- **Staged docs (deviation from the spec's "Docs first", for this reason):** `/privacy` is
  rendered from `docs/privacy.md` at build time (`.github/workflows/ci-web.yml:10`). Claims for
  later steps would go live before their code. So each later plan edits `privacy.md`,
  `ARCHITECTURE.md`, `DESIGN.md` and `VIEWS.md` as its first task. This plan changes none of
  them, because rate limits and the invite fix change no data handling.
- Limits: handle lookup **60 per hour per user**; friend requests **30 per hour per user**;
  429 beyond that, with code `rate_limited`.
- Blocks stay invisible (X-011). A refused accept answers exactly like a missing invite (404,
  `GroupService.noSuchInvite`).
- The service runs one replica; in-process limiters are correct there
  (`Auth/RateLimiter.swift:3-4`). Valkey stays the scale-out path, not built now.
- Every `openapi.yaml` change is followed by `./scripts/generate-api-client.sh` and
  `cd aaru-client && npm run api:generate`. CI fails if they are stale.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not push or
  open a PR unless asked.

## Review Focus

1. **Tests that make many friends from one harness user** (`friend(env, of:)` sends one
   request per call): they must stay under 30 per hour. The whole suite must pass, not only
   the new tests. Task 2 Step 5 runs it.
2. **Hitting the lookup limit must not block sending a request**, and the reverse. They are
   separate budgets. Pinned in Task 2's test.
3. **A block between A and B must not delete C's invite to B.** The fix is scoped to the pair.
   Pinned in Task 3's test.
4. **Unfriend, then become friends again:** a fresh invite must work. The old one is gone,
   and `UNIQUE (group_id, invitee_id)` must not block the new one. Pinned in Task 3's test.
5. **A stale invite refused at accept is also removed**, so it leaves the inbox and does not
   come back. Pinned in Task 3's test.

---

### Task 1: Record the decision and the backlog items

**Files:**
- Modify: `BACKLOG.md`. A new decisions block goes before line 37 (`## Decisions recorded
  2026-10-25`), after the 2026-10-09 block; blocks after 10-09 run newest first.
- Modify: `BACKLOG.md` "Every item" table (rows near `:753-778`).
- Modify: `BACKLOG.md` item sections:
  - SOC items after `### SOC-007` in `## P4 · Profiles, friends, activity` (`:3036`)
  - NAV-004 after `### NAV-003` (`:2730`)
  - GRP items after `### GRP-012` and before `## P4 · Boards` (`:3305`)
- Modify: `CLAUDE.md`:
  - the owner-exceptions sentence under "Later phases" (ends "…the Sports tab (SPT-001…005),
    2026-10-24).")
  - "Out of scope"
- Add: `docs/superpowers/specs/2026-10-27-friends-groups-design.md` (already in the worktree,
  untracked).

**Interfaces:**
- Produces the IDs later plans cite: SOC-008, SOC-009, SOC-010, SOC-011, NAV-004, GRP-013,
  GRP-014, GRP-015, GRP-016, GRP-017.

- [ ] **Step 1: Add `## Decisions recorded 2026-10-27`.** One bullet per owner decision in the
  spec's "Owner decisions" list. Then one bullet per reversal in the spec's "Earlier decisions
  this reverses", each naming what it reverses with its date. Then "Kept as is". Write it in
  the voice of the existing 2026-10-25 block: bold lead-in, then "(owner, 2026-10-27, IDs)".

- [ ] **Step 2: Add the ten items.** Use the existing shape: `### ID · Name · Size`, a
  `**Needs:**` line, one paragraph of what it is (from the spec part named), and a
  `**Done when:**` that can be checked (from the spec's Verification list).

  | ID | Name | Size | Spec part | Needs |
  | --- | --- | --- | --- | --- |
  | SOC-008 | Rate limits on finding and asking | S | A1 | SOC-002 |
  | SOC-009 | Add from anywhere, invite signup, friend alerts | M | A2, A4, A5, A6 (A2 closes SOC-005's friend-request category) | SOC-008, SOC-005 |
  | SOC-010 | Find me by email, Trakt or AniList | L | B: switches, storage, ownership, lookups | SOC-008 |
  | SOC-011 | People you may know | M | B: suggestions; A3 top strip | SOC-010 |
  | NAV-004 | A Friends tab; Groups at the top | M | C1 | NAV-002 |
  | GRP-013 | Group invites end with the friendship | S | C2 | GRP-002 |
  | GRP-014 | Message reactions | M | C3 | GRP-003 |
  | GRP-015 | Replies | M | C4 | GRP-003 |
  | GRP-016 | Images in groups | L | C5 | GRP-003 |
  | GRP-017 | Who's online in a group | M | C6 | GRP-006 |

- [ ] **Step 3: Update the "Every item" table.**
  - Add `Open` rows for the ten new IDs.
  - Add the missing GRP-001…GRP-012 rows:
    - GRP-001…011: `Built, unverified`, with evidence from the GRP-0xx sections and test files
      (`GroupTests`, `GroupKindTests`, `RealtimeTests`, `AgentTests`, `GroupPushTests`) and
      caveat "two-browser / device check not recorded".
    - GRP-012: `Built 2026-10-21`.
  - Set ROOM-001 and ROOM-002 to `Closed (GRP-009)`.

- [ ] **Step 4: Update `CLAUDE.md`.**
  - Append to the owner-exceptions sentence: "; faster friend finding (opt-in email, Trakt and
    AniList discovery, suggestions), a Friends tab, and group reactions, replies, images and
    presence (SOC-008…011, NAV-004, GRP-013…017), 2026-10-27".
  - Add to "Out of scope": "Phone-number matching (deferred 2026-10-27: verifying a number needs
    paid SMS) and friends-of-friends suggestions".
  - Change nothing else. Domain terms land with the plans that build them.

- [ ] **Step 5: Verify.**

  Run: `grep -cE "^### (SOC-0(08|09|10|11)|NAV-004|GRP-01[3-7]) " BACKLOG.md && grep -cE "^\| (SOC-0(08|09|10|11)|NAV-004|GRP-0(0[1-9]|1[0-7])) " BACKLOG.md`
  Expected: `10`, then `27`.

- [ ] **Step 6: Commit**

  ```bash
  git add BACKLOG.md CLAUDE.md docs/superpowers/specs/2026-10-27-friends-groups-design.md docs/superpowers/plans/2026-10-27-friends-groups-01-decisions-and-safety.md
  git commit -m "docs: record 2026-10-27 friends and groups decisions (SOC-008…011, NAV-004, GRP-013…017)"
  ```

---

### Task 2: Rate-limit handle lookup and friend requests (SOC-008)

**Files:**
- Modify: `aaru-server/Sources/App/Social/SocialService.swift` (`lookup` at `:47-51`,
  `sendRequest` at `:55-80`)
- Modify: `aaru-server/Sources/AppAPI/openapi.yaml` (summaries at `:272` and `:297`)
- Regenerate: `aaru-api/` (script) and `aaru-client` API types (`npm run api:generate`)
- Test: `aaru-server/Tests/AppTests/SocialTests.swift`

**Interfaces:**
- Consumes: `FixedWindowRateLimiter(limit:window:)` and its `allow(_ key: String, now: Date) async -> Bool`
  (`Auth/RateLimiter.swift`).
- Produces:
  - `static let lookupsPerHour = 60`
  - `static let requestsPerHour = 30`
  - `static let lookupLimiter: FixedWindowRateLimiter`
  - `static let requestLimiter: FixedWindowRateLimiter`
  - `static let rateLimited: AppError` (`.tooManyRequests`, code `rate_limited`, message "Too
    many tries. Try again later.")
  - private `resolve(handle: String, viewer: UserID) async throws -> (user: SocialUser, relationship: Relationship)`

  All of these live on `SocialService`. The limiters **must be `static`**: `SocialService` is a
  value built per use (`InviteService.social`, `GroupService.social`), so an instance limiter
  would reset on every request.

- [ ] **Step 1: Write the failing test** in `SocialTests`:

  ```swift
  @Test("SOC-008: lookups and requests are limited per hour, separately")
  func rateLimits() async throws {
      try await LibraryHarness.run { env in
          _ = try await env.send(.put, "/v1/me/profile", json: ["handle": freshHandle()])
          let ana = try await friendlyUser(env)
          for _ in 0 ..< SocialService.lookupsPerHour {
              #expect(try await env.send(.get, "/v1/social/users/\(freshHandle())").status == .notFound)
          }
          let over = try await env.send(.get, "/v1/social/users/\(ana.handle)")
          #expect(over.status == .tooManyRequests)
          #expect(try over.json()["code"] as? String == "rate_limited")
          // A spent lookup budget leaves requests alone.
          #expect(try await env.send(.post, "/v1/social/friend-requests", json: ["handle": ana.handle]).status == .ok)
          for _ in 1 ..< SocialService.requestsPerHour {
              _ = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": freshHandle()])
          }
          #expect(try await env.send(.post, "/v1/social/friend-requests", json: ["handle": ana.handle]).status
              == .tooManyRequests)
          // Another user is unaffected.
          #expect(try await env.send(.get, "/v1/social/users/\(ana.handle)", token: ana.token).status == .ok)
      }
  }
  ```

- [ ] **Step 2: Run it and check that it fails.**

  Run: `cd aaru-server && docker compose up -d && swift test --filter SocialTests/rateLimits`
  Expected: FAIL at `over.status == .tooManyRequests` (it is `.ok`).

- [ ] **Step 3: Implement.**
  - Move today's `lookup` body into the private `resolve`.
  - `lookup` checks `Self.lookupLimiter.allow(viewer.description, now: now())` (else throw
    `Self.rateLimited`), then calls `resolve`.
  - `sendRequest` checks `Self.requestLimiter` the same way, right after `requireHandle`, then
    calls `resolve` instead of `lookup`. Every call counts, including no-op asks: enumeration
    is the point.
  - Add a doc comment on the two constants citing SOC-008.

- [ ] **Step 4: Update the summaries in `openapi.yaml`.**
  - `getSocialUser`: append " At most 60 a user per hour (429)."
  - `sendFriendRequest`: append " At most 30 a user per hour (429)."
  - Then regenerate:

  Run: `./scripts/generate-api-client.sh && (cd aaru-client && npm run api:generate)`
  Expected: only doc-comment changes under `aaru-api/Sources` and `aaru-client/src/lib/api`.

- [ ] **Step 5: Run the test, then the whole suite.**

  Run: `cd aaru-server && swift test --filter SocialTests/rateLimits && swift test`
  Expected: PASS, with no new failures elsewhere (Review Focus 1). If a test makes 30 or more
  requests from one user, give that test a fresh `signedInUser` per batch. Don't raise the
  limit.

- [ ] **Step 6: Commit**

  ```bash
  git add aaru-server aaru-api aaru-client/src/lib/api
  git commit -m "feat(server): limit handle lookups and friend requests per user (SOC-008)"
  ```

---

### Task 3: Group invites end with the friendship (GRP-013)

**Files:**
- Modify: `aaru-server/Sources/App/Data/Fluent/PostgresSocialStore.swift`
  - `unfriend` at `:179-187`, which becomes a transaction
  - `block` at `:189-208`
- Modify: `aaru-server/Sources/App/Social/GroupService.swift` (`accept` at `:178-190`)
- Test: `aaru-server/Tests/AppTests/GroupTests.swift`

**Interfaces:**
- Consumes:
  - `stores.social.areFriends(_:_:) async throws -> Bool`
  - `stores.groups.deleteInvite(id:party:) async throws -> (UUID, UserID)?`
  - `GroupInvite.inviter.id`
  - test helpers `claimHandle`, `friend(env, of:)`, `createGroup`, `join` and `withSQL` (all
    existing)
- Produces: no new API. `SocialStore.unfriend(_:_:) -> Bool` and `block(_:_:now:)` keep their
  signatures; both also run the SQL below inside their transaction.

  ```sql
  DELETE FROM group_invites
  WHERE (inviter_id = $a AND invitee_id = $b) OR (inviter_id = $b AND invitee_id = $a)
  ```

- [ ] **Step 1: Write the failing test** in `GroupTests`:

  ```swift
  @Test("GRP-013: unfriending or blocking drops the pair's group invites; accept re-checks friendship")
  func invitesEndWithFriendship() async throws {
      try await LibraryHarness.run { env in
          let mine = try await claimHandle(env)
          let (group, _) = try await createGroup(env)
          func inbox(_ p: Person) async throws -> [[String: Any]] {
              try await env.send(.get, "/v1/me/group-invites", token: p.token).json()["items"] as? [[String: Any]] ?? []
          }
          // Unfriend: the invite goes; becoming friends again allows a fresh one.
          let ana = try await friend(env, of: mine)
          _ = try await env.send(.post, "/v1/groups/\(group)/invites", json: ["userId": ana.id])
          let stale = try #require(try await inbox(ana).first?["id"] as? String)
          #expect(try await env.send(.delete, "/v1/social/friends/\(ana.id)").status == .noContent)
          #expect(try await inbox(ana).isEmpty)
          #expect(try await env.send(.post, "/v1/group-invites/\(stale)/accept", token: ana.token).status == .notFound)
          _ = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": ana.handle])
          _ = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": mine], token: ana.token)
          try await join(env, ana, group: group)

          // Block: the blocked side's invite goes, but a third member's invite to them stays.
          let bob = try await friend(env, of: mine)
          let cy = try await friend(env, of: mine)
          try await join(env, cy, group: group)
          _ = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": bob.handle], token: cy.token)
          _ = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": cy.handle], token: bob.token)
          _ = try await env.send(.post, "/v1/groups/\(group)/invites", json: ["userId": bob.id])
          #expect(try await inbox(bob).count == 1)
          _ = try await env.send(.put, "/v1/social/blocks/\(env.userID)", token: bob.token)
          #expect(try await inbox(bob).isEmpty)
          _ = try await env.send(.post, "/v1/groups/\(group)/invites", json: ["userId": bob.id], token: cy.token)
          #expect(try await inbox(bob).count == 1)

          // A friendship gone behind the store's back: accept refuses like a missing invite, and removes it.
          let dee = try await friend(env, of: mine)
          _ = try await env.send(.post, "/v1/groups/\(group)/invites", json: ["userId": dee.id])
          let orphan = try #require(try await inbox(dee).first?["id"] as? String)
          let deeID = try #require(UUID(uuidString: dee.id))
          try await withSQL { sql in
              try await sql.raw("""
              DELETE FROM social_friendships
              WHERE user_low = LEAST(\(bind: env.userID.rawValue), \(bind: deeID))
                AND user_high = GREATEST(\(bind: env.userID.rawValue), \(bind: deeID))
              """).run()
          }
          let refused = try await env.send(.post, "/v1/group-invites/\(orphan)/accept", token: dee.token)
          let missing = try await env.send(.post, "/v1/group-invites/\(UUID())/accept", token: dee.token)
          #expect(refused.status == .notFound)
          #expect(refused.text == missing.text)
          #expect(try await inbox(dee).isEmpty)
      }
  }
  ```

- [ ] **Step 2: Run it and check that it fails.**

  Run: `cd aaru-server && swift test --filter GroupTests/invitesEndWithFriendship`
  Expected: FAIL at the first `inbox(ana).isEmpty`.

- [ ] **Step 3: Implement the store side.**
  - `unfriend`: run the friendship `DELETE … RETURNING` and the `group_invites` delete in one
    `database.transaction`, and return whether the friendship row existed.
  - `block`: add the `group_invites` delete as a third statement in its existing transaction.
  - Each gets a one-line comment citing GRP-013.

- [ ] **Step 4: Implement the accept re-check.**
  - In `GroupService.accept`, after `pending` is found and before the member-count check:
    `guard try await stores.social.areFriends(pending.inviter.id, viewer)`.
  - Otherwise, `_ = try await stores.groups.deleteInvite(id: invite, party: viewer)` and
    `throw Self.noSuchInvite`.

- [ ] **Step 5: Run the test, then the group and social suites.**

  Run: `cd aaru-server && swift test --filter "GroupTests|SocialTests|GroupKindTests|GroupPushTests"`
  Expected: PASS.

- [ ] **Step 6: Commit**

  ```bash
  git add aaru-server
  git commit -m "fix(server): drop a pair's group invites when the friendship ends; re-check on accept (GRP-013)"
  ```

---

### Task 4: Branch check and backlog status

**Files:**
- Modify: `BACKLOG.md` (the SOC-008 and GRP-013 rows)

- [ ] **Step 1: Run the full checks.**

  Run: `./scripts/lint.sh && (cd aaru-server && swift test) && swift test --package-path aaru-api && (cd aaru-client && npm run check && npm run typecheck && npm test)`
  Expected: all pass. Lint runs swiftformat (check only), swiftlint and periphery.

- [ ] **Step 2: Update the rows.**
  - SOC-008 → `Built, unverified`, evidence "`SocialService.lookupLimiter`/`requestLimiter`;
    SocialTests.rateLimits".
  - GRP-013 → `Built, unverified`, evidence "`PostgresSocialStore.unfriend`/`block`,
    `GroupService.accept`; GroupTests.invitesEndWithFriendship".

- [ ] **Step 3: Commit**

  ```bash
  git add BACKLOG.md
  git commit -m "docs: SOC-008 and GRP-013 built"
  ```
