# Server audit: queries, indexes, concurrency (2026-10-21)

This audit covers `aaru-server/` (Sources/App, Sources/AppAPI, Tests) and `aaru-core/`, with every file read. It was done on branch `audit/server`, cut from `main` at 1825ab8.

The fixes come in six commits:

1. **544958c** adds the indexes. They are in one new additive migration, `AddAuditIndexes`, registered last. No existing migration was edited.
2. **f21c26c** batches the per-row store loops and rewrites two period scans so they can use indexes.
3. **d12db74** covers the pool size, worker counts, outbound timeouts, cancellation and actor reentrancy. This commit also moves the raw SQL out of the boot path: `waitForDatabase`'s `SELECT 1` now lives in `PostgresHealth.ping()`.
4. **dbcb85e** fixes two small correctness bugs and adds tests for the batched writes.
5. This document.
6. A lint-only split: `ImportJobStore` and `saveEpisodes` move into their own files to stay under the 400-line limit, with no code change.

The API shape is unchanged: `openapi.yaml` was not touched.

## New configuration

All keys are optional. The defaults are safe for one replica.

| Env var | Config key | Default | What it sets |
| --- | --- | --- | --- |
| `POSTGRES_POOL_SIZE` | `postgres.pool.size` | 10 | Postgres connections per event loop. Fluent binds the store to one loop, so in practice this is the process's whole pool. Before this change it was 1. |
| `POSTGRES_POOL_TIMEOUT` | `postgres.pool.timeout` | 10 | Seconds a query waits for a free connection. |
| `IMPORTS_WORKERS` | `imports.workers` | 1 | Concurrent import jobs per process, clamped to 1…8. Jobs are leased with `SKIP LOCKED`, so the workers never share a job. |
| `AGENT_REPLY_WORKERS` | `agent.reply.workers` | 1 | Concurrent `@aaru` reply jobs per process, clamped to 1…8. |

Size the pool so that pool size × replicas stays under Postgres `max_connections` (the default is 100), with headroom left for migrations and psql.

## Findings

Status is **fixed** (in this branch) or **deferred**, with the reason. File paths are relative to `aaru-server/Sources/App/`.

| ID | Sev | Where | Problem | Fix | Status |
| --- | --- | --- | --- | --- | --- |
| SRV-001 | High | `App+build.swift:213` (`makeFluent`), `:29` | The pool was effectively one connection. `Stores.postgres(fluent.db())` binds every store to one event loop's pool, and FluentPostgresDriver defaults to `maxConnectionsPerEventLoop: 1`. Every HTTP handler and all six background loops shared that one connection, so `async let` gave no parallelism. A slow transaction (plan approve, import apply) stalled every request, and waiters failed after 10 s. | `maxConnectionsPerEventLoop` and `connectionPoolTimeout` come from config (`POSTGRES_POOL_SIZE`, default 10). | fixed |
| SRV-002 | High | `Data/Migrations` (`group_messages.reply_to`) | `reply_to` had a self-FK with `ON DELETE SET NULL` and no index. Deleting one message seq-scanned `group_messages` once for each deleted row, so deleting a channel with 1,800 messages took **81.9 s** against 1M messages. | Partial index `group_messages_reply_to`. The same delete now takes **10.7 ms**. | fixed |
| SRV-003 | High | `library_items.title_id`, `list_items.title_id` | Neither column was indexed, although both are FKs and both are hot join columns. The genre and page-count backfills, "albums missing artists", due airings and group title progress all join `library_items` by title. The genre backfill took **14.8 s** (10.5M buffer hits). | Indexes `library_items_title` and `list_items_title`. The genre backfill now takes **21.9 ms**. | fixed |
| SRV-004 | Med | FKs with no index | The following FKs had no index, so a cascade delete or a lookup by owner scanned the table: `agent_replies.channel_id`, `actions.agent_token_id`, `watch_events.agent_token_id`, `agent_plans.agent_token_id`, `oauth_codes.user_id`, `oauth_codes.agent_token_id`, `group_invites.inviter_id`, `watch_ready.user_id`, `watch_sessions.channel_id`. | Indexes on each of them. The nullable token columns get partial indexes. `watch_sessions` is indexed on `(channel_id, created_at DESC)` to serve "latest session". | fixed |
| SRV-005 | Med | `Data/Fluent/PostgresScrobbleStore` (`stoppedRecently`) | The scrobble stop de-dupe check (user, source, external ref, `stopped_at`) used the user index and filtered: **0.74 ms, 506 buffers** per stop. | Index `watch_events_stopped (user_id, source, external_ref, stopped_at)`, now **0.36 ms, 3 buffers**. | fixed |
| SRV-006 | High | `Imports/ImportService+Plan.swift`, `ImportService+Decide.swift`, `ImportRowMerge.swift` | Plan and apply made 4–7 sequential store calls per distinct title (`item`, `entry`, `statusSetByHand`, `watched`, plus up to 3 mapping and title lookups), so a 2k-row import ran 10k+ queries. Apply did this inside the approve HTTP request. | A `MergeContext` is loaded once per plan or apply. `importStates(userID:titleIDs:)` reads items and ticks in 2 queries, `mappings(anilist:)` and the new `mappings(mal:)` each take one query, and `titles(ids:)` takes one. After that, `decide` and `seasonRows` are pure. | fixed |
| SRV-007 | High | `Data/Fluent/PostgresCatalogStores+Episodes.swift:10` (`saveEpisodes`; it was in `PostgresCatalogStores.swift`) | Each episode was upserted in its own statement, and the statements were not in a transaction. | One transaction. Episodes are de-duplicated (the last copy wins, because a multi-row `ON CONFLICT DO UPDATE` cannot touch a row twice), upserted in 500-row `VALUES` chunks, and followed by one `titles` update. 1,000 episodes: **171 ms → 75 ms** locally, and 1 statement instead of 1,000 when the database is across the network. | fixed |
| SRV-008 | High | `Data/Fluent/PostgresLibraryStore.swift:112, 182` | Ticks and unticks ran one statement per episode. Marking a season or a whole show watched meant hundreds of round trips. | `insertTicks` writes them with one `unnest(uuid[], int[], int[]) … ON CONFLICT DO NOTHING`. Unwatch is one `DELETE … USING unnest(…)`. 1,000 ticks: **222 ms → 111 ms** locally. | fixed |
| SRV-009 | Med | `Data/Fluent/PostgresCatalogStores.swift:111` (`fillIDs`) | One UPDATE per external-id column (up to 9), on every import row that matched an existing title, including rows that changed nothing. | One `UPDATE … SET col = coalesce(col, $v) … WHERE … (col IS NULL OR …)`. If a unique id is already held by another title, it falls back to the per-column path, which skips that one column, so the "never merge" rule is unchanged. | fixed |
| SRV-010 | Med | `Data/Fluent/PostgresImportJobStore.swift:163` (`savePlan`) | One UPDATE per import row. | Chunked `UPDATE import_rows … FROM (VALUES …) AS v(…)`. | fixed |
| SRV-011 | Med | `Data/Fluent/PostgresLibraryStore+Lists.swift:77`, `PostgresCatalogStores+Tracks.swift:7` | List members and album tracks were inserted one row at a time. | List members: one `INSERT … SELECT FROM unnest(…) WITH ORDINALITY`. Tracks: one transaction holding the delete, one multi-row insert and the title update. | fixed |
| SRV-012 | High | `Export/AccountExport.swift:19` | Export called `watched(itemID:)` once per show and `titles(ids:)` once per list. | One `watched(itemIDs:)` call, one `titles(ids:)` over the union of all list members, and the reads run under `async let`. | fixed |
| SRV-013 | Med | `Data/Fluent/PostgresStatsStore.swift:22` | The stats period filter compared `(watched_at AT TIME ZONE z)::date`, which no index can serve: **115 ms**, with 17k buffers read from disk. | Sargable outer bounds (period ±1 day, in UTC) on both `UNION` branches. The exact local-day filter is kept inside those bounds. Now **10.3 ms**. | fixed |
| SRV-014 | Med | `Data/Fluent/PostgresListenStore.swift:131` | Same problem for the listens period: **13.2 ms, 2,688 buffers**. | `listened_at >= (start::date)::timestamp AT TIME ZONE zone AND listened_at < …`. Now **8.5 ms, 149 buffers**. | fixed |
| SRV-015 | Med | `Data/Fluent/PostgresGroupStore+Messages.swift:192` | The `clientNonce` retry lookup ignored the channel, so a nonce reused in another channel returned the earlier message and published it to the wrong group. | The lookup also matches `channel_id`. A reuse in another channel is a `StoreConflict` (409). Test: `nonceRetryStaysInItsChannel`. | fixed |
| SRV-016 | High | `HTTP/HTTPTransport.swift:40, 84` | All outbound calls used `HTTPClient.shared`: connect and read timeouts of 90 s, 20 redirects, and no owner shutting it down. `timeout.components.seconds` dropped the sub-second part. AsyncHTTPClient's deadline stops at the response head, so a server that trickles out its body could outlast the "60 s" Anthropic timeout indefinitely. | One app-owned client (connect 5 s, read 120 s, 5 redirects, pool idle 60 s), shut down by `HTTPClientService`, which runs before the HTTP server in reverse shutdown order. `send` races execute plus body collect against `Task.sleep(for: timeout)`. `Duration` is converted to nanoseconds. | fixed |
| SRV-017 | Med | `Imports/ImportService.swift:114` | Graceful shutdown counted as a failed attempt. On the third attempt the job was marked failed for good, with the error "Matching stopped: CancellationError()". | On cancellation, `importJobs.release` returns the lease (`queued`, attempt refunded, due now) and the error is rethrown. Test: `releasedJobIsClaimedAgain`. | fixed |
| SRV-018 | Med | `Imports/ImportWorker.swift:27`, `Agent/AgentReplyWorker.swift` | Each worker was a single sequential loop, with no way to configure it. | `workerLoops` runs N loops in a discarding task group (`IMPORTS_WORKERS`, `AGENT_REPLY_WORKERS`). | fixed |
| SRV-019 | Med | `Schedule/ScheduleService.swift:49`, `Data/Fluent/PostgresScheduleStore.swift:170` | A show the provider does not know, or one requested during an outage, was never stamped. It was retried with up to 10 sequential provider calls on every calendar, Up Next and Stremio request. | Each attempt is stamped first. The query skips shows attempted within the last hour. Hydration runs 3 at a time. | fixed |
| SRV-020 | Med | `Catalog/CatalogRefreshService.swift:50, 67` | The genre and page-count backfills used `try?`, which swallowed `CancellationError`. The attempt was then stamped with an empty result, so a title cut off at shutdown was skipped for 7 days. | `try Task.checkCancellation()` after each provider call, before stamping. | fixed |
| SRV-021 | Low | `Catalog/DiscoverService.swift`, `DiscoverSeasons.swift:196`, `Concerts/ConcertService.swift:143` | Actor reentrancy: any waiter on a shared fetch cleared `inFlight[key]` and wrote the cache using the `now` it captured before the await. A late waiter could clear a newer fetch or overwrite newer state. | Only the waiter whose task is still `inFlight[key]` settles the cache. The others return the value. | fixed |
| SRV-022 | Med | `Auth/AppleIdentityVerifier.swift:95` (`AppleJWKSCache`) | On a cold or expired cache, each concurrent sign-in fetched the JWKS separately. If the refresh after the 12 h TTL failed, every sign-in failed even though the cached keys were still valid. | Concurrent sign-ins join one in-flight fetch. When a refresh at TTL fails, the held keys keep serving. An unknown `kid` still fails closed. | fixed |
| SRV-023 | Low | `Catalog/CatalogTypes.swift:119` | `Date.catalogDay` let Calendar roll invalid dates over: MAL's `2020-05-00` became Apr 30, and month 13 became the next year. | The date must round-trip to the same year, month and day, or it is nil. | fixed |
| SRV-024 | Low | `Catalog/AniListText.swift:10` | `&amp;` was decoded first, so `&amp;lt;` (a literal `&lt;`) was decoded twice, to `<`. | `&amp;` is decoded last. | fixed |
| SRV-025 | Low | `App+build.swift` | There was an unused duplicate `makeTraktAPI` overload with different pacing. | Removed. | fixed |
| — | — | `Data/Stores.swift`, `Data/Fluent/PostgresCatalogStores.swift` | Lint only: with the new batched requirements, both files went over the 400-line limit. | `ImportJobStore` and the batched defaults moved to `Data/Stores+Imports.swift`; `saveEpisodes` moved to `PostgresCatalogStores+Episodes.swift`. Code unchanged. | fixed |
| SRV-026 | Med | `Realtime/RealtimeHub.swift:94-125` | `publish` waits for every socket write, with no timeout. One stalled client holds up the REST mutation that published until autoPing (25 s) closes it. Frame order across concurrent publishes is not guaranteed. | Needs a bounded per-connection outbox (`AsyncStream`, `.bufferingNewest`) drained by one writer task. | deferred: changes delivery semantics, and the realtime tests assert synchronous delivery. Its own PR. |
| SRV-027 | High | `Catalog/TMDBCatalog.swift:23-52`, `TitleResolver.swift:213, 236` | The resolver's TMDB search adds IMDb ids for up to 10 hits, so it costs 11 calls per lookup. Letterboxd, CAT, Netflix and name-only scrobble rows need only the TMDB id. A 2k-row import comes to about 22k calls, roughly 9 minutes at 40 requests/s. | `search(…, enrichIDs: false)` from the resolver, and possibly an LRU of external ids. | deferred: provider-adapter behaviour, outside the store/concurrency scope. Changes what search hits carry. |
| SRV-028 | Med | `Imports/ImportService+Plan.swift:150-184` | Two concurrent approvals can both see `.planned` and both apply. The apply and `savePlan` run in separate transactions, so a crash between them leaves the job re-appliable. | An atomic `planned → applying` compare-and-set in `ImportJobStore`. | deferred: needs a new job state, and so a migration and an API enum value. |
| SRV-029 | Med | `Catalog/TitleResolver.swift:58-70` | `prefetchingMAL` makes sequential per-ref `titles.find` and mapping lookups, and `hydrate` repeats the mapping lookup. | Use `mappings(mal:)` (added here) and a new `titles(malIDs:)`, held for the run. | deferred: resolver refactor; the store primitive is now in place. |
| SRV-030 | Med | `Imports/ImportService+Stremio.swift:81-89` | One sequential Cinemeta call per watched show, redone on every retry. | `boundedMap(limit: 5)`. | deferred: provider path; low traffic. |
| SRV-031 | Med | `Catalog/TitleResolver.swift:252-258` | `episodes(of:named:)` refetches the full TMDB episode list every time and ignores stored episodes. This affects Netflix rows and scrobble stops. | Read `titles.episodes` first, and hydrate only when it is empty. | deferred: resolver behaviour change, needs its own tests. |
| SRV-032 | Med | `Catalog/EpisodeNameMatcher.swift:16-20` | Episode names are normalised O(names × episodes) times; a long soap is about 1M normalisations on the cooperative pool. | Build a normalised-name dictionary once per show. | deferred: CPU only, bounded by import size. |
| SRV-033 | Med | `Scrobble/ScrobbleService.swift:50, 72-80` | Every start and pause re-resolves the title, and a name-only report re-runs the TMDB search (with SRV-027's 10 extra calls). | Reuse the open session's `titleID`. | deferred: scrobble behaviour, separate change. |
| SRV-034 | Med | `Trakt/TraktConnectService.swift:114-125` | The Trakt token refresh, up to 3 tries with backoff, runs inside a row lock and so holds a pooled connection. | Use one attempt with a short timeout. | deferred: low frequency. Less pressing now that the pool is larger than 1. |
| SRV-035 | Med | `Social/GroupService+Agent.swift:22-29` and other check-then-insert caps (`GroupService.swift:72, 157-184`, `+Channels.swift:13`, `+Kinds.swift:109`, `SocialService.swift:67`, `PlanService.swift:20`) | Counts are read and the insert follows, so concurrent requests can exceed caps. The agent cap (30 a day per user, 10 an hour per group) has model cost. | Advisory lock, or a conditional `INSERT … SELECT WHERE count < cap`. | deferred: several call sites, each with its own test. The agent cap should go first. |
| SRV-036 | Med | `API/AppRequestContext.swift:33-35` | The rate-limit key is the first `X-Forwarded-For` hop, which the client controls, so the magic-link and OAuth-registration limits can be bypassed. | Use the hop Traefik appends (the last one), or a trusted-proxy count. | deferred: depends on the ingress topology in `platform/infra`, which is out of scope. |
| SRV-037 | Low | `MCP/MCPRoutes.swift:16, 52` | The MCP body is capped at 1 MiB, but `plan_import` advertises 5 MB. | Raise `maxBody` to about 6 MiB, or change the documented limit. | deferred: product call. |
| SRV-038 | Low | `App+build.swift:268` | `MCP_ALLOWED_ORIGINS` is named in a comment but never loaded. | Load it in `AppConfig`. | deferred: config surface; needs the infra values. |
| SRV-039 | Low | `OAuth/OAuthService.swift:245-249` | The authorization code is burned before the client and PKCE checks. | Check first, then burn in the same statement. | deferred: auth flow, its own review. |
| SRV-040 | Low | `Push/Push.swift:47-64` | The two `APNSClient`s are never shut down, so in-flight sends are cut at shutdown. | Register them as Services. | deferred: low impact. |
| SRV-041 | Low | `Auth/AuthMiddleware.swift:34-40` | Requests with an agent token also run a session lookup that always misses. | Skip it for the agent-token prefixes. | deferred: one cheap indexed query per request. |
| SRV-042 | Low | `Realtime/RealtimeRoutes.swift:55-60` | The typing rate limit is keyed by channel and recorded before membership is checked, and `lastTyping` grows without bound. | A per-connection token bucket and a capped map. | deferred: goes with SRV-026. |
| SRV-043 | Low | `Realtime/RealtimeRoutes.swift:41-66` | Sockets stay open after sign-out, account delete or session expiry. | `hub.disconnectAll(user)` from sign-out and delete. | deferred: goes with SRV-026. |
| SRV-044 | Low | Hummingbird 2.26 | A handler is not cancelled when the client disconnects (it gets `onCancel` only at server shutdown). Long handlers run to completion. | Move side effects (APNs sends, publishes) to a bounded background queue. | deferred: framework behaviour; design change. |
| SRV-045 | Low | `Data/Fluent/PostgresListenStore` (`unresolved`) | The listen resolver sorts 138k rows. It is a background job, a partial index already exists, and the time is dominated by a cold cache (416–710 ms). | — | deferred: background, once a minute. |
| SRV-046 | Low | `listens.agent_token_id`, `show_episodes (title_id, airs_at)`, `trakt_auth_requests`, `stremio_link_requests` FKs | These are unindexed. The `listens` index would cost writes on the hottest insert path. `show_episodes (title_id, airs_at)` was measured: the calendar went from 11.8 to 7.5 ms, not worth the write cost on 800k rows. The other two tables are tiny and short-lived. | — | deferred: measured, not worth it. |
| SRV-047 | Low | `Data/Fluent/PostgresListenStore` (insert) | Listens are inserted one row at a time. | A multi-row insert. | deferred: needs a de-dupe within the batch against the unique key first. |
| SRV-048 | Low | `Stats/StatsService.swift:21-54` | `music()` and the `prior` top query run after `activity` and `titles`, although neither depends on them. | `async let`. | deferred: a few ms now that the pool is larger than 1. |
| — | — | Lower-severity notes from the read-through, all deferred as small or behavioural: `ListService` running the full `detail()` before and after each mutation; `ISO8601DateFormatter` created per item; AniList `airingSchedule(perPage: 50)` dropping air times after episode 50; export round-trip gaps (anime films, albums, the "Watched Episodes" column); Stremio routes mapping every error to 500; `ListenService.all()` loading every listen; import delete check-then-act; the stats `now()` read twice. | | | deferred |

**Confirmed OK:**
- The Anthropic adapter sends only `model`, `max_tokens`, `system`, `messages`, `tools` and `output_config`: no `temperature`, `top_p` or `top_k`, and no assistant prefill.
- No global mutable state, `nonisolated(unsafe)`, `@unchecked Sendable` or blocking calls in scope.
- No IDOR in the group routes: every channel and message lookup is scoped by group, and every service entry checks the viewer's role.
- `Push.swift`'s `.raw(…)` is APNs alert text, not SQL.
- Route handlers contain no SQL.

## EXPLAIN (ANALYZE, BUFFERS) before and after

### How it was measured

- **Database.** A throwaway local Postgres 17, migrated at `origin/main` and then seeded:

  | Table | Rows |
  | --- | --- |
  | `episode_progress` | 1.69M |
  | `import_rows` | 1.0M |
  | `group_messages` | 998k (one channel holds 100k) |
  | `show_episodes` | 800k |
  | `listens` | 694k |
  | `library_items` | 310k (200 users; 3 heavy users with 5k items) |
  | `watch_events` | 100k |
  | `list_items` | 100k |
  | `actions` | 80k |
  | `titles` | 60k |
  | `agent_replies` | 20k |
  | `agent_plans` | 10k |
  | `import_jobs` | 5k |

  About 1.35 GB in total.
- **Runs.** Each query ran three times and the best execution time is reported. Writes ran inside `BEGIN … ROLLBACK`.
- **Columns.**
  - "Before" is `origin/main`.
  - "Indexes" is the same database right after `AddAuditIndexes` was applied (the upgrade path) on a quiet machine.
  - "After" is the final branch.
- **The "After" run was noisy.** It ran while other builds were using the machine, so its times are inflated across the board, including for queries this branch did not touch. Compare buffer counts across that run rather than milliseconds.

### Queries the branch changed

| Query | Before | Indexes | After (final) |
| --- | --- | --- | --- |
| Delete a channel with 1,800 messages (`reply_to` FK trigger) | 81,929.9 ms (trigger 81,927.8 ms) | 10.7 ms (trigger 9.9 ms) | 39.8 ms under load, 17 buffers |
| Genre backfill (`titlesMissingGenres`) | 14,824.0 ms, 10,521,103 buffers | 21.9 ms, 51,178 buffers | 25.6 ms, 51,178 buffers |
| Page-count backfill (`booksMissingPageCount`) | 67.6 ms | 28.2 ms | 31.0 ms |
| Albums missing artists | 50.0 ms, 5,074 buffers | 3.0 ms | 3.3 ms |
| Scrobble stop de-dupe (`stoppedRecently`) | 0.74 ms, 506 buffers | 0.36 ms, 3 buffers | 0.41 ms, 3 buffers |
| Stats month (`watched_at` period) | 115.6 ms, 17,336 buffers read from disk | — | 10.3 ms, 0 buffers read |
| Listens top month (`listened_at` period) | 13.2 ms, 2,688 buffers | — | 8.5 ms, 149 buffers |
| Due airings (2-day window) | 2.1 ms | 2.0 ms | 3.8 ms under load, 3 buffers |
| Group title progress | 0.74 ms | 0.90 ms | 0.99 ms, 9 buffers |

A manual run of due airings with a 7-day window went from 48 ms to 7 ms once `library_items_title` existed: the join to in-progress items stops scanning by user.

### Hot reads with no change

These were checked to make sure nothing regressed or was missing. Buffer counts are identical before and after, so their plans did not change. The time differences come from the noisy "After" run.

| Query | Before | After (under load) | Buffers |
| --- | --- | --- | --- |
| Library page (keyset, 51 rows) | 2.3 ms | 4.0 ms | 777 |
| Library filtered (show, in progress) | 3.0 ms | 4.6 ms | 2,070 |
| Library item by title | 1.2 ms | 3.0 ms | 37 |
| Sync changes (2 days) | 1.6 ms | 5.0 ms | 371 |
| Calendar (3 weeks) | 11.8 ms | 18.3 ms | 7,639 |
| Continue watching | 2.3 ms | 3.5 ms | 859 |
| Start watching | 3.0 ms | 12.7 ms | 205 |
| Unfinished | 2.8 ms | 3.9 ms | 1,047 |
| Library counts | 1.1 ms | 1.2 ms | 113 |
| Stale tracked shows (refresher) | 61.8 ms | 66.1 ms | 11,127 |
| Group summaries | 8.5 ms | 8.5 ms | 2,958 |
| Group channels | 2.3 ms | 2.6 ms | 606 |
| Group messages, latest page | 0.7 ms | 0.7 ms | 8 |
| Group messages, before cursor | 3.4 ms | 3.7 ms | 370 |
| Recent listens | 0.9 ms | 1.3 ms | 137 |
| Import jobs list | 0.7 ms | 0.9 ms | 103 |
| Import claim next (`SKIP LOCKED`) | 0.3 ms | 0.5 ms | 7 |
| Agent reply load / claim | 0.5 / 0.3 ms | 0.7 / 0.5 ms | 15 / 7 |
| Pending plans | 0.3 ms | 0.4 ms | 20 |
| Actions list | 0.4 ms | 0.6 ms | 63 |

### Batched writes: round trips

These ran on local loopback, so they show only part of the gain. In production the database is a network hop away, and the saving per statement is larger.

| Write | Per-row loop | Batched | Statements |
| --- | --- | --- | --- |
| 1,000 episode ticks (`setEpisodes`) | 221.8 ms | 110.8 ms | 1,000 → 1 |
| 1,000 catalog episodes (`saveEpisodes`) | 171.1 ms | 75.2 ms | 1,000 → 2 (one transaction) |
| Import plan or apply, per distinct title | 4–7 queries | 0 (6 queries per run, up front) | 10k+ → about 6 for a 2k-row import |
| Account export, per show | 1 query | 0 (1 query) | N → 1 |

## Verification

- `swift build` and `swift test` pass: 331 tests in 59 suites, against a local Postgres. Four of them are new:
  - `nonceRetryStaysInItsChannel`
  - `saveEpisodesUpserts`
  - `releasedJobIsClaimedAgain`
  - `catalogDayRejectsRollover`
- `aaru --db-migrate` was run two ways:
  - on an empty database (the fresh path);
  - on the seeded database migrated at `origin/main` (the upgrade path), where `AddAuditIndexes` applied cleanly over 1.35 GB.
