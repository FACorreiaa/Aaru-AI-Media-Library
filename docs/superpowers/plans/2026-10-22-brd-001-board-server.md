# BRD-001 Board Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Friends-only Board on the API: posts (free or about one title, optional rating and spoiler stamp), one upvote per user, comments with one level of nesting, and friends' posts about a title.

**Architecture:** Three new tables behind a raw-SQL `BoardStore` (same shape as `PostgresSocialStore`). `BoardService` owns visibility (friend + block checks through `stores.social`, a 404 that never differs from "missing"). The library write for reviews goes through `LibraryService`. HTTP is generated from `openapi.yaml` and implemented in `BoardHandlers.swift`. No `@aaru` replies, push or realtime here: those are BRD-004.

**Tech Stack:** Swift 6, Hummingbird 2, swift-openapi-generator, SQLKit raw SQL over Postgres, swift-testing.

**Spec:** `docs/superpowers/specs/2026-10-22-boards-and-ask-aaru-design.md` (Part 1, Server).

## Global Constraints

- Worktree `/Users/fernandocorreiachill/Work/production/apps/aaru-boards`, branch `feat/boards-ask-aaru`.
- Tests need Postgres: `cd aaru-server && docker compose up -d`. Run with `swift test --filter <Suite>`.
- Raw SQL migrations only (`SQLMigration`). Append to `allMigrations` in `Sources/App/Data/Migrations/Migrations.swift`; never edit a shipped migration.
- No Fluent, SQLKit or `Database` symbol in a handler file.
- Visibility failures are **404 with the same text as a missing post** (X-011). Never 403 for "not your friend".
- Validation is 422 `validation_failed` with `details[field]`, as in `GroupService.invalid`.
- Body limit 4000 characters, trimmed, non-empty (reuse `GroupService.validBody` or the same rule and copy).
- Rating uses the library scale and validator, `Rating(_:)`: 1–10 in 0.5 steps.
- After every `openapi.yaml` change: `./scripts/generate-api-client.sh` and `cd aaru-client && npm run api:generate`. Commit the generated files with the change (CI fails if stale).
- Any table with a user column names it `user_id` with `ON DELETE CASCADE`, so `rowsReferencing` (account deletion) covers it.
- Domain words: Board, Post, Comment, Upvote. Never "Message" or "Conversation".

## Review Focus

1. **An ex-friend opens a post link:** after unfriending, `GET /v1/board/posts/{id}` is a 404 identical to a missing id, and the post leaves their feed. Test in Task 2.
2. **A block after comments exist:** the blocked person's comments are hidden from the blocker and the blocker's from them, and neither sees the other's posts. Test in Task 5.
3. **Acting on a deleted post:** upvote, comment and list-comments on a deleted post return the missing-post 404. Tests in Tasks 4 and 5.
4. **A double-tapped upvote:** PUT twice keeps the count at 1, and DELETE when not upvoted is a 204. Test in Task 4.
5. **A reply to a reply:** it is stored with `replyTo` set to the top-level comment, so nesting never exceeds one level. Test in Task 5.

---

### Task 1: Board tables and store

**Files:**
- Create: `aaru-server/Sources/App/Data/Migrations/Migrations+Boards.swift`
- Modify: `aaru-server/Sources/App/Data/Migrations/Migrations.swift` (append `CreateBoards()` after `AddLivePlays()`)
- Create: `aaru-server/Sources/App/Data/Stores+Boards.swift`
- Create: `aaru-server/Sources/App/Data/Fluent/PostgresBoardStore.swift`
- Modify: `aaru-server/Sources/App/Data/Stores.swift` (`var boards: any BoardStore`), `Sources/App/Data/Fluent/PostgresStores.swift` (`boards: PostgresBoardStore(database: database)`)
- Modify: `aaru-server/Tests/AppTests/TestSupport.swift` (`fakeStores()` field)
- Create: `aaru-server/Tests/AppTests/TestSupport+UntouchedBoards.swift` (`extension UntouchedStore: BoardStore`, every method throws `Touched()`)
- Test: `aaru-server/Tests/AppTests/BoardStoreTests.swift`

**Interfaces:**
- Produces, in `Stores+Boards.swift`:
  ```swift
  struct BoardPost: Sendable, Equatable {
      let id: UUID; let author: SocialUser; let titleID: TitleID?; let rating: Double?
      var body: String; let spoiler: SpoilerStamp?; let createdAt: Date; var editedAt: Date?
      var upvotes: Int = 0; var upvotedByViewer = false; var commentCount = 0
  }
  struct BoardComment: Sendable, Equatable {
      let id: UUID; let postID: UUID; let author: SocialUser?; let fromAgent: Bool
      let replyTo: UUID?; var body: String; let mentions: [UserID]; let mentionsAgent: Bool
      let createdAt: Date; var deletedAt: Date?
  }
  protocol BoardStore: Sendable {
      func createPost(_ post: BoardPost) async throws -> BoardPost
      func post(_ id: UUID, viewer: UserID) async throws -> BoardPost?          // nil when deleted
      func feed(authors: [UserID], before: UUID?, limit: Int, viewer: UserID) async throws -> [BoardPost] // newest first
      func top(authors: [UserID], since: Date, limit: Int, viewer: UserID) async throws -> [BoardPost]    // upvotes desc, then newest
      func posts(title: TitleID, authors: [UserID], limit: Int, viewer: UserID) async throws -> [BoardPost]
      func editPost(_ id: UUID, body: String, now: Date) async throws
      func deletePost(_ id: UUID, now: Date) async throws
      func setUpvote(post: UUID, user: UserID, on: Bool) async throws            // idempotent both ways
      func upvoters(post: UUID) async throws -> [SocialUser]
      func addComment(_ comment: BoardComment) async throws -> BoardComment
      func comment(_ id: UUID, post: UUID) async throws -> BoardComment?
      func comments(post: UUID, after: UUID?, limit: Int) async throws -> [BoardComment]      // oldest first
      func deleteComment(_ id: UUID, now: Date) async throws
  }
  ```
  `SpoilerStamp` and `SocialUser` are the existing types (`Stores+GroupKinds.swift:24`, `Stores+Social.swift:8`).

**Schema (`CreateBoards`, doc comment `/// BRD-001 Board: posts, comments, upvotes. Friends-only; visibility lives in BoardService.`):**
- `board_posts`:
  - `id uuid PK`, `user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE`
  - `title_id uuid REFERENCES titles(id)`
  - `rating numeric(3,1) CHECK (rating IS NULL OR title_id IS NOT NULL)`
  - `body text NOT NULL CHECK (char_length(body) <= 4000)`
  - `spoiler_season`, `spoiler_episode`, `spoiler_ending`, with the same CHECKs as `Migrations+GroupKinds.swift:22-25`
  - `created_at`, `edited_at`, `deleted_at`
  - Indexes: `(created_at DESC, id DESC) WHERE deleted_at IS NULL`, `(user_id, created_at DESC)`, `(title_id) WHERE title_id IS NOT NULL`
- `board_upvotes`: `post_id uuid REFERENCES board_posts(id) ON DELETE CASCADE`, `user_id uuid REFERENCES users(id) ON DELETE CASCADE`, `created_at`, `PRIMARY KEY (post_id, user_id)`.
- `board_comments`:
  - `id uuid PK`, `post_id … ON DELETE CASCADE`
  - `user_id uuid REFERENCES users(id) ON DELETE CASCADE` (NULL for Aaru)
  - `author_kind text NOT NULL CHECK (author_kind IN ('user','agent'))`, `CHECK ((author_kind = 'user') = (user_id IS NOT NULL))`
  - `reply_to uuid REFERENCES board_comments(id) ON DELETE CASCADE`
  - `body` (same CHECK), `mentions uuid[] NOT NULL DEFAULT '{}'`, `mentions_agent boolean NOT NULL DEFAULT false`
  - `created_at`, `deleted_at`
  - Index `(post_id, created_at, id)`.

- [ ] **Step 1: Write the failing store tests** in `BoardStoreTests.swift` (`@Suite("Board store", .serialized)`, `withMigratedStores`, users from `signedInUser(stores)`):
  - `@Test("BRD-001: feed is newest first and pages by before")`: create 3 posts for one author. `feed(limit: 2)` returns posts 3 and 2; `feed(before: post2.id, limit: 2)` returns `[post1]`.
  - `@Test("BRD-001: upvotes are idempotent and counted")`: `setUpvote(on: true)` twice from A and once from B, then `post(id, viewer: A)` has `upvotes == 2` and `upvotedByViewer == true`. `setUpvote(on: false)` twice from A gives `upvotes == 1`.
  - `@Test("BRD-001: top orders by upvotes inside the window")`: of two posts, the one with 2 upvotes comes first; a post with `since` after its `createdAt` is excluded.
  - `@Test("BRD-001: deleted posts vanish")`: after `deletePost`, `post(id,…) == nil` and the post is absent from `feed`.
  - `@Test("BRD-001: account deletion leaves no board rows")`: a user with a post, an upvote and a comment is deleted through the existing account-deletion path, then `rowsReferencing(user)` has 0 for `board_posts`, `board_upvotes` and `board_comments`.
- [ ] **Step 2: Run them and see them fail.** `swift test --filter BoardStoreTests`. Expected: compile failure, `BoardStore` not found.
- [ ] **Step 3: Implement the migration, records, protocol and `PostgresBoardStore`.**
  - Follow `PostgresSocialStore.swift`: `sql.raw` with `\(bind:)`, Decodable rows with `.convertFromSnakeCase`.
  - Share one `private static let postColumns: SQLQueryString`. It joins `profiles`/`users` for the author, and computes `upvotes`, `upvoted_by_viewer` and `comment_count` (comments with `deleted_at IS NULL`) as scalar subqueries.
  - Keyset paging as in `PostgresGroupStore+Messages.swift:136-160`.
  - Register the migration, the `Stores` field, the Postgres wiring, the `UntouchedStore` conformance and `fakeStores()`.
- [ ] **Step 4: Run the tests and see them pass.** `swift test --filter BoardStoreTests`, then `swift test --filter Contract` (or the full suite) to prove `fakeStores()` still builds. Expected: PASS.
- [ ] **Step 5: Commit.** `git add aaru-server && git commit -m "BRD-001: board tables and store"`

### Task 2: Posts over HTTP — create, feed, read, edit, delete, visibility

**Files:**
- Modify: `aaru-server/Sources/AppAPI/openapi.yaml`
- Create: `aaru-server/Sources/App/Social/BoardService.swift`
- Create: `aaru-server/Sources/App/API/BoardHandlers.swift`
- Modify: `aaru-server/Sources/App/API/Services.swift` (`var board: BoardService`, built in `make` with `stores`, `resolver`, `library`)
- Generated: `aaru-api/Sources/AaruAPI/Generated/*`, `aaru-client/src/lib/api/schema.d.ts`
- Test: `aaru-server/Tests/AppTests/BoardTests.swift`

**Interfaces:**
- Consumes: Task 1 `BoardStore`, `BoardPost`.
- Produces:
  ```swift
  struct BoardService: Sendable {
      let stores: Stores; let resolver: TitleResolver; let library: LibraryService
      var now: @Sendable () -> Date = { Date() }
      static let maxBodyLength = 4000, defaultPageSize = 20, maxPageSize = 50, topLimit = 10
      static let noSuchPost = AppError.notFound("That post isn't here.")
      enum Sort: String { case recent, top }
      func feed(sort: Sort, before: UUID?, limit: Int?, viewer: UserID) async throws -> [BoardPost]
      func create(body: String, title: MediaRef?, rating: Double?, spoiler: GroupService.SpoilerChoice, viewer: UserID) async throws -> BoardPost
      func post(_ id: UUID, viewer: UserID) async throws -> BoardPost         // throws noSuchPost
      func edit(_ id: UUID, body: String, viewer: UserID) async throws -> BoardPost
      func delete(_ id: UUID, viewer: UserID) async throws
      func audience(_ viewer: UserID) async throws -> [UserID]               // viewer + friends, minus blocked/blockers
      func requireVisible(_ id: UUID, viewer: UserID) async throws -> BoardPost
  }
  ```
- OpenAPI (operationIds; schemas under `components/schemas`):
  - `GET /v1/board` → `listBoard` (query `sort` enum `recent|top`, default `recent`; `before` uuid; `limit` 1–50). Response `BoardPostPage {required: [items], items: [BoardPost]}`. `top` ignores `before` and returns ≤ 10 posts from the last 7 days.
  - `POST /v1/board/posts` → `createBoardPost`, body `BoardPostCreate {body (maxLength 4000), title: MediaRef?, rating: number?, spoiler: SpoilerStamp?, spoilerFree: boolean?}`. Response `201` `BoardPost`.
  - `GET|PATCH|DELETE /v1/board/posts/{postId}` → `getBoardPost`, `editBoardPost` (body `BoardPostEdit {body}`), `deleteBoardPost` (204).
  - `BoardPost` schema:
    - required: `id, author, body, createdAt, upvotes, upvotedByMe, commentCount, veiled, mine`
    - optional: `title: TitleSummary`, `rating: number`, `spoiler: SpoilerStamp`, `editedAt`
    - Map it in `extension Components.Schemas.BoardPost { init(_ post: BoardPost, title: Title?, viewer: UserID, veiled: Bool) }` at the bottom of `BoardHandlers.swift`.
    - Hydrate titles in one batch with `stores.titles.titles(ids:)`, as `GroupService.hydrateComponents` does (`GroupService+Agent.swift:78`).

**Rules this task pins:**
- `create` calls `SocialService(stores:).requireHandle(viewer)` first, so posting without a handle is a 422 `handle_required`.
- `rating` without `title` → 422 `details["rating"]`. A bad rating → 422 through `Rating(_:)`. A title that does not resolve → the existing `ResolutionError` mapping.
- Visibility: the author, or `stores.social.areFriends(viewer, author) && !stores.social.isBlocked(viewer, author)`. Anything else is `noSuchPost`. A malformed `postId` is also `noSuchPost`.
- Reports: `social_reports` targets users only. "Report post" in clients calls the existing `reportUser` with the post author, and the note is prefixed with `post:<id>`. No new route.
- Only the author edits or deletes. Anyone else gets `noSuchPost` if they can't see the post, and `GroupService.forbidden("Only the author can change this post.")` if they can.

- [ ] **Step 1: Write the failing HTTP tests** in `BoardTests.swift` with `LibraryHarness.run`. Reuse `claimHandle(env)` and `friend(env, of:)` from `GroupTests.swift`; move them to a shared `TestSupport+Social.swift` if they are `private`.
  - `@Test("BRD-001: friends see posts, strangers and ex-friends get the missing 404")`:
    - Ana (a friend) posts `"hello"`; my `GET /v1/board` includes it.
    - A stranger's `GET /v1/board/posts/{id}` → 404 whose `text` equals that of `GET /v1/board/posts/<random uuid>`.
    - After `DELETE /v1/social/friends/{ana}`, my GET of Ana's post → 404 and the feed no longer has it.
  - `@Test("BRD-001: post validation")`: `"   "` → 422; 4001 characters → 422; `rating: 8` with no title → 422; with no handle claimed → 422 `handle_required`.
  - `@Test("BRD-001: only the author edits or deletes")`: a friend's PATCH → 403; the author's PATCH sets `editedAt`; after the author's DELETE → 204, then GET → 404.
  - `@Test("BRD-001: top this week")`: `?sort=top` returns posts ordered by upvotes; the upvotes are inserted through `env.stores.boards.setUpvote` because the HTTP route arrives in Task 4.
- [ ] **Step 2: Run and see them fail.** `swift test --filter BoardTests`. Expected: 404 on unknown routes, or a compile failure.
- [ ] **Step 3: Write the openapi entries, then regenerate** (`./scripts/generate-api-client.sh`, `cd aaru-client && npm run api:generate`).
- [ ] **Step 4: Implement `BoardService` (create, feed, post, edit, delete) and the five handlers.** The handler shape is `GroupHandlers.swift:139-147`; parse `postId` like `groupID(_:)` at :184. Leave `veiled` false and the library write out until Task 3.
- [ ] **Step 5: Run.** `swift test --filter BoardTests` and `swift test --package-path ../aaru-api`. Expected: PASS.
- [ ] **Step 6: Commit.** `git add -A aaru-server aaru-api aaru-client/src/lib/api && git commit -m "BRD-001: board posts over /v1/board"`

### Task 3: Reviews write the library; spoilers veil

**Files:**
- Modify: `aaru-server/Sources/App/Social/BoardService.swift`, `aaru-server/Sources/App/API/BoardHandlers.swift`
- Test: `aaru-server/Tests/AppTests/BoardTests+Reviews.swift`

**Interfaces:**
- Consumes: `LibraryService.add(_:status:userID:)`, `LibraryService.patch(_:userID:patch:)`, `ItemPatch`, `stores.library.item(userID:titleID:)`, `stores.groupKinds.progress(title:users:)`, `GroupService.autoStamp(_:)`, `GroupService.veils(_:_:)`.
- Produces: `BoardService.feed` and `post` return veil information. Change their return to `BoardService.Page { posts: [BoardPost]; veiled: Set<UUID> }`, and make `post` return `(BoardPost, veiled: Bool)`. Task 2's handlers switch to it.

**Rules:**
- On `create` with a title and a rating, before inserting the post:
  - If `stores.library.item(userID:titleID:)` is nil: `library.add(ref, status: .finished, userID: viewer)`, then `patch(rating:)`.
  - If the item exists: `patch(rating:)` only. The status is untouched.
  - **Deviation from the spec's "one action": this makes two journal rows (add, update).** Undo works per row. Accepted for v1; noted in BACKLOG BRD-001.
- With a title and no rating: no library write.
- The spoiler stamp is computed exactly as `GroupService.post` does at :278-285, using the author's progress. Free posts and `spoilerFree` get no stamp.
- Veil: for each post with a stamp that is not the viewer's own, `veils(stamp, progress[viewer])`. Progress is batched per title over the page.

- [ ] **Step 1: Write the failing tests:**
  - `@Test("BRD-001: a review of a new title adds it as Watched with the rating")`: POST with `title` (a `FakeCatalog` movie ref) and `rating: 9`, then `GET /v1/library` has that title `status == "finished"` and `rating == 9`; `GET /v1/me/actions` (the existing actions route) shows an add and an update.
  - `@Test("BRD-001: a review of a title in progress keeps its status")`: add a show as `in_progress`, post a review with `rating: 7`, then its status is still `in_progress` and its rating is 7.
  - `@Test("BRD-001: spoilers veil friends who are behind")`: I have ticked S1E5 of a show; I post about it with no spoiler choice, so the stamp is S1E5. Ana has ticked S1E2 and sees `veiled == true`. Ben has finished and sees `veiled == false`. My own view: `veiled == false`.
- [ ] **Step 2: Run and see them fail.** `swift test --filter BoardTests`.
- [ ] **Step 3: Implement the library write and the veil.**
- [ ] **Step 4: Run.** `swift test --filter BoardTests`. Expected: PASS.
- [ ] **Step 5: Commit.** `git commit -am "BRD-001: reviews write the library; spoiler veil"`

### Task 4: Upvotes

**Files:**
- Modify: `openapi.yaml`, `BoardService.swift`, `BoardHandlers.swift`; regenerate the clients.
- Test: `aaru-server/Tests/AppTests/BoardTests+Upvotes.swift`

**Interfaces:**
- Produces:
  - `func upvote(_ id: UUID, on: Bool, viewer: UserID) async throws`, which calls `requireVisible` first.
  - `func upvoters(_ id: UUID, viewer: UserID) async throws -> [SocialUser]`, which drops users blocked either way with the viewer.
- OpenAPI:
  - `PUT|DELETE /v1/board/posts/{postId}/upvote` → `upvoteBoardPost` / `removeBoardPostUpvote` (204).
  - `GET /v1/board/posts/{postId}/upvotes` → `listBoardPostUpvoters`, returning `SocialUserList {items: [SocialUser]}`. Reuse the existing schema if a list of `SocialUser` already exists.

- [ ] **Step 1: Write the failing tests:**
  - `@Test("BRD-001: upvote twice counts once; removing twice is fine")`: PUT, PUT → `upvotes == 1`; DELETE, DELETE → 204, 204, `upvotes == 0`.
  - `@Test("BRD-001: upvoting a hidden or deleted post is the missing 404")`: a stranger's PUT → 404; after the author deletes, a friend's PUT → 404.
  - `@Test("BRD-001: upvoters list hides blocked people")`.
- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement and regenerate.**
- [ ] **Step 4: Run.** `swift test --filter BoardTests`. Expected: PASS.
- [ ] **Step 5: Commit.** `"BRD-001: upvotes"`

### Task 5: Comments

**Files:**
- Modify: `openapi.yaml`, `BoardService.swift` (or `BoardService+Comments.swift` if the file passes the lint length), `BoardHandlers.swift`; regenerate the clients.
- Test: `aaru-server/Tests/AppTests/BoardTests+Comments.swift`

**Interfaces:**
- Produces:
  ```swift
  func comments(_ post: UUID, after: UUID?, limit: Int?, viewer: UserID) async throws -> [BoardComment] // drops blocked either way
  func comment(_ post: UUID, body: String, replyTo: UUID?, viewer: UserID) async throws -> BoardComment
  func deleteComment(_ post: UUID, comment: UUID, viewer: UserID) async throws  // comment author or post author
  ```
- OpenAPI:
  - `GET|POST /v1/board/posts/{postId}/comments` → `listBoardComments` (query `after`, `limit` 1–100, default 50) and `createBoardComment` (body `BoardCommentCreate {body (maxLength 4000), replyTo: uuid?}`, response 201).
  - `DELETE /v1/board/posts/{postId}/comments/{commentId}` → `deleteBoardComment` (204).
  - The `BoardComment` schema mirrors `GroupMessage`'s author, `fromAgent`, `replyTo`, `mentionsAgent` and `deleted` fields.

**Rules:**
- Calls `requireVisible` first.
- A `replyTo` that is not a live comment on this post → 422 `details["replyTo"]`. If the target itself has a `replyTo`, store the target's `replyTo`, so nesting stays one level.
- Mentions: `GroupService.mentions(in:members:)` over the post author plus the viewer's friends, wrapped as the member list that function expects; if its signature is member-specific, extract the handle-matching part into a shared function rather than copy it. `@aaru` sets `mentionsAgent`; no reply is queued (BRD-004).
- A deleted comment keeps its row with an empty body and `deleted: true` when it has replies, and is dropped from the list when it has none.

- [ ] **Step 1: Write the failing tests:**
  - `@Test("BRD-001: comments are visible to everyone who sees the post")`: Ana and Ben are both my friends but not each other's. Ben comments on my post, and Ana's list includes Ben's comment with his handle.
  - `@Test("BRD-001: a reply to a reply hangs off the top-level comment")`: comment C1, reply R1 → C1, reply R2 → R1; then `R2.replyTo == C1.id`.
  - `@Test("BRD-001: blocks hide comments both ways")`: Ben comments; Ana blocks Ben. Ana's list has no Ben comments, and Ben gets 404 on Ana's posts.
  - `@Test("BRD-001: post author can delete any comment, others only their own")`.
  - `@Test("BRD-001: commenting on a deleted post is the missing 404")`.
  - `@Test("BRD-001: @aaru in a comment is recorded, not answered")`: `mentionsAgent == true`, and no new comment appears.
- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement and regenerate.**
- [ ] **Step 4: Run.** `swift test --filter BoardTests`. Expected: PASS.
- [ ] **Step 5: Commit.** `"BRD-001: comments"`

### Task 6: Friends' posts on a title, and the docs

**Files:**
- Modify: `openapi.yaml` (`GET /v1/titles/{id}/posts` → `listTitlePosts`, `limit` 1–50, returning `BoardPostPage`), `BoardService.swift` (`func posts(title: TitleID, limit: Int?, viewer: UserID) async throws -> Page`), `BoardHandlers.swift`; regenerate the clients.
- Modify: `CLAUDE.md`:
  - Domain language: Board, Post, Comment, Upvote, and Chat / Chat turn with the "never Conversation/Message" note.
  - The Later phases / exceptions sentence gains "Boards 2026-10-22".
- Modify: `ARCHITECTURE.md`: a Board paragraph under the social section. Visibility is in `BoardService`; the tables; a review writes the library through `LibraryService`.
- Modify: `BACKLOG.md`:
  - Decisions entry dated 2026-10-22 with the owner decisions table from the spec.
  - Items BRD-001…004 and ASK-001…008, with BRD-001 "Built, unverified" and the two-journal-rows note.
- Test: `aaru-server/Tests/AppTests/BoardTests+Title.swift`

- [ ] **Step 1: Write the failing test.** `@Test("BRD-001: a title page lists friends' posts about it, newest first")`: my post and Ana's about title T are both listed; a stranger's post about T is not; Ana's free post is not.
- [ ] **Step 2: Run it and see it fail.**
- [ ] **Step 3: Implement, regenerate, write the docs.**
- [ ] **Step 4: Full verification.** From `aaru-server`: `swift test` (whole suite), `scripts/lint.sh`, `swift test --package-path ../aaru-api`; `cd ../aaru-client && npm run typecheck`. Expected: all green.
- [ ] **Step 5: Commit.** `"BRD-001: friends' posts on a title; docs and backlog"`
