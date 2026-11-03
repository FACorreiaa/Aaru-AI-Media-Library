# Go engineering audit — aaru-server-v2

| | |
| --- | --- |
| Date | 2026-11-03 |
| Revision | `e915e71092a84407c155e80a8940cc240e43ac3f` (`main`, clean worktree) |
| Toolchain | go 1.27.3 darwin/arm64 |
| Scope | `aaru-server-v2` (module `aaru-go-api`, ~96k lines incl. generated, 445 files): wiring and shutdown, HTTP layer, outbound providers, background workers, concurrency and in-memory state, database access, hot-path CPU/memory, code health |
| Mode | Read-only audit. No source was changed. No security audit was performed (the X-Forwarded-For item below is an engineering note, not a security finding) |

## 0. Remediation status (handoff, 2026-11-03)

The owner asked for **every finding to be fixed and this file deleted once all are fixed**. A
first session started the work and stopped partway, at the owner's request. All work is
committed on the local branch **`wip/go-audit-fixes`** (from `main` at `e915e710`, not pushed,
not merged), one commit per group, each with its regenerated sqlc code. The combined branch
passes `go build ./...` and `go vet ./...`; lint and the test suite have not been run on it.

| Commit (group) | Scope | State |
| --- | --- | --- |
| `3187f771` (g5) | HLT-001, HLT-002 (fuzz part), HLT-004 | **Done and verified**: gofumpt check, vet, golangci-lint, staticcheck, `-race` on imports/capture/stremioapi + import routes, docker build, 16 fuzz targets × 45 s |
| `0dafd076` (g1) | REL-001 (HTTP part), HTTP-001/002/003/005 (IdleTimeout)/006/007, DB-001, HLT-005, PERF-005 | WIP. Covers every item; lint clean; **full `-race` suite was cut off mid-run, so it is unverified** |
| `2ce42f06` (g2) | REL-001 (workers + claim attempt caps, new `internal/safe`), REL-002…008, REL-004 metrics, DB-002 pool collector, DB-008 gamification part, migration `00002_worker_backoff.sql` | WIP. Touches every item; it stopped while writing the gamification reliability tests. **Unverified** |
| `09dbdfaf` (g3) | REL-001 (caches/goroutines), CON-001…005, HTTP-004, HTTP-005 (WebSocket close on shutdown), HTTP-008 | WIP. Touches every item; it stopped while adding the sports 429 handler test. **Unverified** |
| `6bf57ad2` (g4) | DB-003, DB-004, DB-008 (groups/plans), DB-006 (query edit, partial), DB-007 | WIP and the least complete. **Not started**: PERF-001, PERF-002, PERF-003, PERF-004, PERF-006, DB-005 (no `00003` migration yet). Local EXPLAIN/seed scripts are in `go-audit-measurements/`. **Unverified** |

The worktree used for the commits is `apps/aaru-wt-go-audit`. Continue there, or recreate it with
`git worktree add ../aaru-wt-go-audit wip/go-audit-fixes` from `apps/aaru`.

### Still to do, in order

1. Work in the `wip/go-audit-fixes` worktree. Never switch branches in the shared `apps/aaru`
   checkout. Rebase on `origin/main` first if it has moved, then rerun `make generate`.
2. Integrate by hand. Three commits edit `internal/app/app.go`: g1 (server timeouts, session
   timeouts), g2 (pool collector) and g3 (`RegisterOnShutdown` for sockets). Check that they
   compose. Also check that g1's request-deadline middleware exempts g3's WebSocket route and
   g4's export and upload routes.
3. Finish the incomplete parts:
   - g2: the gamification (REL-006) tests.
   - g3: the sports/concerts 429 handler tests.
   - g4: DB-006 (finish, with EXPLAIN before and after), DB-005 (migration
     `00003_fk_indexes.sql`, `CREATE INDEX CONCURRENTLY`, measure `listens(agent_token_id)`
     first), PERF-001 (stream the listen files, a ctx-aware semaphore instead of
     `listenFileGate`, job insert + stage in one tx), PERF-002 (streamed export listens,
     `SetLimit(3)`), PERF-003, PERF-004, PERF-006. Each perf item needs its benchmark before
     and after, as §3 describes.
4. HLT-003, after everything else is merged: enable `nolintlint`, `bodyclose`, `noctx`,
   `rowserrcheck` and `contextcheck`; narrow or disable `nilnil`; delete the dead `//nolint`
   directives. Not started.
   - Decision for the owner (from g5): plain `go tool gofumpt` reads the module path and
     regroups `aaru-go-api/...` imports, which flags about 400 files. golangci-lint's gofumpt
     does not. g5 set `GOFUMPT = go tool gofumpt -modpath=unset.invalid` in the Makefile so
     `make fmt` matches lint.
   - The alternative is `formatters.settings.gofumpt.module-path: aaru-go-api` plus a one-time
     repo-wide reformat.
5. Verify the combined branch:
   - `go tool gofumpt -modpath=unset.invalid -l .`, `go vet ./...` and `golangci-lint run ./...`
   - `go tool staticcheck ./...`
   - The full `POSTGRES_PORT=<private> AARU_REQUIRE_DB=1 go test -race -count=1 ./...` against a
     throwaway `postgres:17` container. Never use port 5432: it is another project's Postgres
     here. Docker run command: see the `local-test-setup` memory.
6. Docs: the root `CLAUDE.md` Commands section could gain `make vuln` and the fuzz command.
   g1's commit already updates `PORTING.md` for the new `POSTGRES_STATEMENT_TIMEOUT` and
   `POSTGRES_IDLE_TRANSACTION_TIMEOUT` variables and the restored meaning of
   `POSTGRES_POOL_TIMEOUT`.
7. Commit, PR and the promote PR in `platform/infra` only when the owner asks. New env vars
   have defaults, so no infra change is needed to deploy.
8. Not fixable in code, so record it rather than leave it open:
   - Raising `POSTGRES_POOL_SIZE` (DB-002) is an infra-values decision once the pool gauges
     show data.
   - Paging the first `Changes` sync (DB-007) would change the API, so it is deferred.
   - Traefik's forwarded-header trust (HTTP-007) should be confirmed in infra.
9. When everything above is green, **delete this file and `go-audit-measurements/`** in the
   final commit, and squash or reword the `wip(...)` commits before a PR.

Notable result so far: fuzzing found a real crash. `characters()` in
`internal/imports/csvtable.go` panicked or duplicated bytes when given invalid UTF-8, so it was
reachable through the CAT list, the ICS parser and `source=auto` detection. HTTP inputs are
sanitised today, so it was latent. The fix and the crasher seeds are in the g5 commit.

## 1. Executive summary

The codebase is in good shape for a fresh port. `go vet` and `golangci-lint` are clean,
the full suite passes under `-race` against a real Postgres, leasing uses
`FOR UPDATE SKIP LOCKED` in single statements, writes are journaled in one transaction,
pagination is keyset everywhere, bulk writes use `unnest`/COPY, outbound reads are size-capped,
and no worker can take the server down by returning an error.

The risks are concentrated in a few places:

1. **Nothing recovers from a panic, and a job that kills the process is leased again forever.**
   No `recover()` exists anywhere in the module (no echo Recover middleware either). The import
   and `@aaru` claim queries re-lease expired `running` rows with no attempt cap, so a parser panic
   or an OOM-kill on a huge upload becomes a crash loop every 30 minutes on the single replica.
2. **No request has a deadline, and the pool-wait timeout silently changed meaning in the port.**
   `POSTGRES_POOL_TIMEOUT` was "seconds a query waits for a free connection" in Swift; in Go it
   is pgx's dial timeout. Acquire waits on ctx only, there is no `statement_timeout`, and no
   request-scoped timeout. With a pool of 10 shared by HTTP fan-out and ~12 workers, saturation
   becomes unbounded queueing instead of fast failure.
3. **A 64 MiB body limit applies to every route, including unauthenticated JSON ones**, and the
   OpenAPI validator reads and decodes the whole body before the strict handler decodes it again.
4. **Several check-then-act races on the write path**: import Apply (double apply → two journaled
   actions, half-undo), capture quota (parallel requests bypass the 3/month cap and pay for model
   calls), `@aaru` replies (post-then-finish, lease shorter than worst-case run → duplicate
   replies and double spend).
5. **Operational blind spots**: no pool stats, no worker pass/failure/queue-depth metrics, and
   client disconnects reported to Sentry and counted as 500s.

Top interventions (strongest evidence, cheapest fix):

| # | Change | Why |
| --- | --- | --- |
| 1 | Recover middleware + recover-to-error around worker steps + `attempts < max` on both claim queries | Turns a crash loop into one failed job (REL-001) |
| 2 | Request-scoped timeout middleware + `statement_timeout` / `idle_in_transaction_session_timeout` + `pgxpool.Stat` gauges | Restores Swift's fail-fast behaviour and makes the pool observable (DB-001, DB-002) |
| 3 | Per-route body limit: 1 MiB default, larger only on upload routes | Cheap; removes the largest unauthenticated memory lever (HTTP-001) |
| 4 | Lock-and-recheck in one tx for import Apply; advisory lock for capture quota | The repo already has the pattern (`plans.approveTx`, `LockUserListens`) (DB-003, DB-004) |
| 5 | Map `context.Canceled` to 499 without Sentry; normalise the `method` label | Accurate error rates and bounded metric cardinality (HTTP-002, HTTP-003) |

**Not inspected or not verified**: query plans and table sizes (no stats, no `EXPLAIN` run),
production metrics/profiles (none available; no benchmarks exist), Traefik timeouts and forwarded
header handling, pod memory limit and `terminationGracePeriodSeconds`, Deployment rollout strategy
(surge → two pods briefly), importer internals (Trakt, Stremio, AniList fetchers), badge evaluator
reads, most of `social`/`boards`/`groups`/`oauth` SQL, and Swift parity of the races (whether the
Swift server had the same holes). Static review cannot prove absence of races or leaks; `-race`
only covers the paths the tests execute.

## 2. How to read this report

- **Status**: `CONFIRMED DEFECT` (code path traced and wrong), `CODE-SUPPORTED RISK` (failure
  plausible under named conditions), `HYPOTHESIS / MEASURE FIRST` (needs a profile, plan or metric).
  No finding is a `MEASURED BOTTLENECK`: nothing was profiled.
- **Priority**: P0 data loss/corruption or service-breaking; P1 repeatable availability failure or
  resource exhaustion; P2 justified medium impact; P3 optional or pending evidence.
- **Verified** column: `lead` = re-read in source by the audit lead after the subsystem reviewer
  reported it; `reviewer` = traced by one subsystem reviewer only. Re-check `reviewer` items before
  acting on them.
- There are no P0 findings.

## 3. Findings

### 3.1 Summary table

| ID | P | Category | Status | Location | Verified |
| --- | --- | --- | --- | --- | --- |
| REL-001 | P1 | reliability | CONFIRMED DEFECT | `internal/db/queries/imports.sql:34-35`, `groups.sql:293`, `internal/httpapi/router.go:43-52` | lead |
| DB-001 | P1 | database | CONFIRMED DEFECT | `internal/db/db.go:36`, `internal/config/config.go:178` | lead |
| HTTP-001 | P1 | http | CODE-SUPPORTED RISK | `internal/httpapi/router.go:20,47`, `internal/middleware/validate.go` | lead |
| DB-002 | P2 | database | CODE-SUPPORTED RISK / MEASURE FIRST | `internal/db/db.go`, `internal/httpapi/workers.go`, `internal/httpapi/export.go:97-215` | lead (export) |
| DB-003 | P2 | correctness | CONFIRMED DEFECT (race) | `internal/imports/plan.go:251-290`, `internal/imports/listens.go:204-215` | lead |
| DB-004 | P2 | correctness | CONFIRMED DEFECT (race) | `internal/imports/capture.go:82-94` | lead |
| REL-002 | P2 | reliability | CONFIRMED DEFECT | `internal/agent/reply.go:30,85-104,178`, `groups.sql:301` | reviewer ×2 |
| REL-003 | P2 | reliability | CONFIRMED DEFECT | `internal/db/queries/scrobble.sql:121`, `internal/scrobble/service.go:386-391` | reviewer |
| REL-004 | P2 | observability | CONFIRMED (gap) | `internal/metrics/metrics.go:22-30`, `internal/catalog/refresh.go:88` | reviewer |
| HTTP-002 | P2 | observability | CONFIRMED DEFECT | `internal/middleware/errors.go:46-95` | lead (partial) |
| HTTP-003 | P2 | observability | CONFIRMED DEFECT | `internal/middleware/metrics.go:20` | lead |
| CON-001 | P2 | concurrency | CODE-SUPPORTED RISK | `internal/{catalog,concerts,sports}/cache.go`, `internal/provider/client.go:149-165` | reviewer |
| CON-002 | P2 | concurrency | CONFIRMED DEFECT | `internal/realtime/gateway.go:156-166` | lead |
| PERF-001 | P2 | memory | CODE-SUPPORTED RISK | `internal/imports/listens.go:28-32,91-92`, `listen_files.go:64-130` | reviewer ×2 |
| PERF-002 | P2 | memory/db | CODE-SUPPORTED RISK | `internal/httpapi/export.go:161-171` | lead |
| DB-005 | P2 | database | MEASURE FIRST | `baseline.sql` FKs; `internal/auth/store.go:218` | reviewer |
| DB-006 | P2 | database | MEASURE FIRST | `listens.sql` `UnresolvedListens`; `internal/music/store.go:197` | reviewer |
| HLT-001 | P2 | supply chain | CONFIRMED (gap) | `../.github/workflows/ci-go.yml` | lead |
| HLT-002 | P2 | testing | CONFIRMED (gap) | whole module | reviewer |
| CON-003 | P3 | memory | CONFIRMED DEFECT | `internal/sports/cache.go:60-85` | lead |
| CON-004 | P3 | concurrency | CODE-SUPPORTED RISK | `internal/realtime/hub.go:139,152-164` | reviewer |
| CON-005 | P3 | quota | CONFIRMED DEFECT | `internal/concerts/ticketmaster.go:19-42,203` | reviewer |
| HTTP-004 | P3 | outbound | CONFIRMED / RISK | `internal/provider/client.go:240-263`, `transport.go:144` | reviewer |
| HTTP-005 | P3 | http | MEASURE FIRST | `internal/app/app.go:158-162,189-200` | lead |
| HTTP-006 | P3 | observability | CONFIRMED | `internal/mcp/handler.go:99,115`, `scrobble_routes.go:108`, `stremio_routes.go:81`, `oauth_routes.go:136` | reviewer |
| HTTP-007 | P3 | http | HYPOTHESIS | `internal/middleware/auth.go:101-105`, `internal/ratelimit/ratelimit.go:33-39` | reviewer ×2 |
| HTTP-008 | P3 | concurrency | CODE-SUPPORTED RISK | `internal/auth/jwks.go:103-130` | reviewer ×2 |
| REL-005 | P3 | reliability | CODE-SUPPORTED RISK | `internal/mal/pusher.go:233-239`, `mal.sql:42-46` | reviewer |
| REL-006 | P3 | reliability | CODE-SUPPORTED RISK | `internal/gamification/worker.go:76-81`, `music/service.go:117`, `concerts/refresher.go:66,99` | reviewer |
| REL-007 | P3 | reliability | CONFIRMED (by design) | `internal/push/push.go:136,215-231` | reviewer |
| REL-008 | P3 | correctness | CODE-SUPPORTED RISK | `internal/gamification/service.go:164,213` | reviewer ×2 |
| PERF-003 | P3 | db round trips | MEASURE FIRST | `internal/library/store.go:207-337`, `internal/music/store.go:60` | reviewer ×2 |
| PERF-004 | P3 | cpu | MEASURE FIRST | `internal/catalog/episodematch.go:17-26`, `core/matching.go:41-48`, `resolver.go:443-462` | reviewer |
| PERF-005 | P3 | cpu | MEASURE FIRST | `internal/middleware/validate.go:22-52`, `metrics.go:31` | reviewer |
| PERF-006 | P3 | algorithmic | CONFIRMED (O(N)/O(n²)) | `imports/resolve.go:33-75`, `imports/tvtime.go:519`, `gamification/writefacts.go:50-57` | reviewer |
| DB-007 | P3 | database | CODE-SUPPORTED RISK | `internal/library/entries.go:93,256` | reviewer |
| DB-008 | P3 | correctness | CODE-SUPPORTED RISK | `groups/service.go:108`, `plans/service.go:71`, `GamificationEarnedToday` | reviewer |
| HLT-003 | P3 | lint | CONFIRMED | `.golangci.yml`, 204 `//nolint` | reviewer |
| HLT-004 | P3 | build | CONFIRMED | `Dockerfile`, `Makefile`, `go.mod` tool block | reviewer |
| HLT-005 | P3 | logging | CONFIRMED | `internal/middleware/log.go`, slog call sites | reviewer |

### 3.2 P1 findings

#### REL-001 — A panic crashes the pod, and the job that caused it is re-leased forever

- **Status**: CONFIRMED DEFECT (missing recovery + uncapped re-lease); the crash loop itself is a
  code-supported consequence. Found independently by three reviewers; re-read by lead.
- **Evidence**
  - `grep 'recover()'` finds nothing outside tests. The echo chain
    (`internal/httpapi/router.go:43-52`: RequestLog, Metrics, Errors, bodyLimit, Auth, …) has no
    Recover. Workers are bare errgroup goroutines (`internal/app/app.go:179-188`), as are
    `internal/imports/worker.go:50`, `internal/agent/reply_worker.go:31`,
    `internal/catalog/refresh.go:74-89`, the three cache fetchers and the WebSocket keepalive.
  - `ImportJobClaim` (`internal/db/queries/imports.sql:34-35`):
    `OR (j.state = 'running' AND j.locked_until < @now)` with `attempts = attempts + 1` and no
    attempts filter. `ClaimAgentReply` (`groups.sql:293`) has the same shape.
  - `MaxAttempts` is only checked on the Go error path (`internal/imports/service.go:236`,
    `internal/agent/reply.go:84`). A panic or an OOM-kill never reaches it.
  - `Metrics` calls `RequestFinished` without `defer` (`internal/middleware/metrics.go:17-21`), so a
    handler panic leaves `aaru_http_in_flight` incremented.
- **Failure scenario**: an import parser panics on one user's file (or the pod is OOM-killed on a
  24 MB upload, see PERF-001). The single replica restarts, the 30-minute lease expires, the job is
  claimed with attempts 4, 5, 6…, and the pod dies again, every 30 minutes, dropping every
  WebSocket and in-flight request. For `@aaru` the loop is every 120 s and pays for model calls each
  time. A handler panic is caught by net/http, but the client gets a reset/502 rather than the JSON
  500, and Sentry never hears about it.
- **Proposal**
  1. Recover middleware placed right after `Metrics` (so `Errors` sees the error) that converts a
     panic into an error carrying the stack; `defer` the metrics finish.
  2. One `safeStep(func() error) (err error)` helper with `defer recover()` used by `imports.Loops`,
     `ReplyWorker`, the refresh `wg.Go`, and the cache `run` functions. In the caches register
     `close(f.done)`/`delete(inFlight)` in a defer *before* calling `fetch`
     (`internal/catalog/cache.go:92-96` closes after `fetch` returns).
  3. Add `AND j.attempts < @max_attempts` to the expired-`running` branch of both claim queries,
     plus a sweep (or the same statement) that marks over-attempted `running` rows `failed`.
  - Simpler alternative: (1) and (3) only. (3) alone already breaks the loop for OOM-kills, which
    no `recover` can catch.
- **Tests**: panicking echo handler → JSON 500, reporter called once, in-flight back to 0;
  panicking `Loops` step → job ends `failed` after 3 attempts and the loop keeps running; claim
  of an expired `running` row with `attempts = MaxAttempts` returns no row; for each cache, a
  panicking fetch does not wedge later callers (goleak).
- **Rollback**: middleware and helper are additive; the SQL change is a query edit (`make generate`),
  revert the commit.

#### DB-001 — `POSTGRES_POOL_TIMEOUT` lost its meaning in the port; nothing bounds a request

- **Status**: CONFIRMED DEFECT (semantic drift from Swift). Lead verified.
- **Evidence**: `internal/db/db.go:36` sets
  `cfg.ConnConfig.ConnectTimeout = PoolTimeoutSeconds`. The Swift README
  (`aaru-server/README.md:68`) documents the same variable as "seconds a query waits for a free
  connection". In pgx v5, `ConnectTimeout` bounds only dialing a new connection; `pool.Acquire`
  waits on ctx alone. There is no `statement_timeout`, no `idle_in_transaction_session_timeout`,
  and no request-scoped `context.WithTimeout` (the only `WithTimeout` calls are health, shutdown,
  provider transport, realtime, PostHog drain). The `http.Server` sets only `ReadHeaderTimeout`.
- **Failure scenario**: pool saturation (see DB-002) or a lock wait makes requests queue until the
  client gives up instead of failing in 10 s as Swift did. A slow query holds its connection
  indefinitely; provider retries honouring `Retry-After: 60` hold a user request for ~2 minutes
  (HTTP-004).
- **Proposal**
  - An echo middleware applying a request deadline (e.g. 30 s) on non-streaming, non-upload,
    non-WebSocket routes; or a thin acquire wrapper bounding `Acquire` by `PoolTimeoutSeconds` to
    restore the documented meaning.
  - `cfg.ConnConfig.RuntimeParams["statement_timeout"]` (API: e.g. 15 s; migrations run via the
    `--db-migrate` path and must override it) and `idle_in_transaction_session_timeout`.
  - Re-document `POSTGRES_POOL_TIMEOUT` (or keep the old meaning) and update `PORTING.md`.
  - Values are proposals, not measured; agree them with the owner.
- **Test**: `MaxConns=1`, hold the only connection, call a handler, expect 503/504 within the bound.
- **Rollback**: env-driven values; set them to 0 to disable.

#### HTTP-001 — 64 MiB body limit on every route, read and decoded twice before the handler

- **Status**: CODE-SUPPORTED RISK, P1 because the fix is cheap and the deployment is one replica.
  Memory impact not measured; pod memory limit not inspected.
- **Evidence**: `maxBody = 64 << 20` applied globally (`internal/httpapi/router.go:20,47`).
  `validate` (the kin-openapi request validator) runs on public routes such as `/v1/auth/apple`,
  `/v1/auth/google`, `/v1/auth/email/link`, `/v1/auth/email/verify`,
  `/v1/billing/apple/notifications`; kin-openapi reads the whole body and decodes it into `any`
  with `UseNumber`, then the strict handler decodes it again. Per-route rate limits run inside
  handlers, after this. `internal/httpapi/capture.go:27` reads its JSON body with `io.ReadAll`
  bounded only by this global cap although text is limited to 20,000 characters.
- **Failure scenario**: a few concurrent unauthenticated 64 MiB JSON arrays of small numbers expand
  several-fold as `[]any` of `json.Number`, enough to pressure or OOM-kill the pod (which then
  interacts with REL-001).
- **Proposal**: default limit 1 MiB; keep the larger limits only on routes that already read with
  their own bound (`/v1/imports/csv` 24 MiB, `/listenbrainz/` 10 MiB, capture/avatar ≤ 5 MiB).
  Give the capture JSON path ~128 KiB.
- **Test**: 2 MiB JSON body to `/v1/auth/email/link` → 413 before the validator reads it; existing
  upload tests still pass at their limits.
- **Rollback**: constant change.

### 3.3 P2 findings

#### DB-002 — Pool of 10 shared by HTTP fan-out and ~12 workers, with no pool metrics

- **Status**: CODE-SUPPORTED RISK / MEASURE FIRST.
- **Evidence**: production runs 1 replica, pool 10 (default, `config.go:177`), Postgres
  `max_connections=40` (from the infra values, per the DB reviewer). Per-request errgroups without
  `SetLimit`: export 3 then 8 (`internal/export/export.go:90-121`, `internal/httpapi/export.go:97-215`,
  lead-verified), social views 6, tonight 5, Home 4 (`internal/schedule/service.go:107-123`). The
  import matcher runs 4 in flight per loop (`internal/imports/plan.go:32,128`). Trakt/MAL token
  refresh holds a `FOR UPDATE` tx across an outbound HTTP call by design
  (`internal/trakt/store.go:95`, `internal/mal/store.go:160`). Nothing exports `pool.Stat()`.
- **Failure scenario**: two exports + Home + an import can hold all 10 connections; with DB-001
  everyone else waits with no bound.
- **Proposal**: first export `pgxpool.Stat` gauges (acquired, idle, total, `EmptyAcquireCount`,
  `AcquireDuration`, `CanceledAcquireCount`) on the internal `/metrics`. Then decide: `SetLimit(3)`
  on the export fan-out (cheap, do now), raise `POSTGRES_POOL_SIZE` toward 20–25 (under 40 with
  headroom for migrations/psql), or give workers a separate small pool — only with the gauges.

#### DB-003 — Import Apply checks state without a lock and is not atomic with the library write

- **Status**: CONFIRMED DEFECT (race). Lead verified.
- **Evidence**: `internal/imports/plan.go:251-290` reads the job with no `FOR UPDATE`, checks
  `State == planned`, runs `Library.Apply` (its own tx), then saves the plan in a separate tx.
  `applyListens` (`internal/imports/listens.go:204-215`) has the same shape.
- **Failure scenario**: a double tap or client retry applies twice: two journaled actions, and
  `job.action_id` points at the second, so "undo import" undoes half. For listens the second call
  writes 0 rows and overwrites `Stats.Created` with 0. If the plan save fails after the library
  commit, the job stays `planned` and can be applied again.
- **Proposal**: mirror `plans.approveTx` (`internal/plans/store.go:203`): one tx that
  `SELECT … FOR UPDATE` the job by id and user, rechecks state, runs the batch through
  `Library.Store.RunInTx`, and saves the plan. Simpler alternative: claim with
  `UPDATE … SET state='applying' WHERE id=$1 AND user_id=$2 AND state='planned' RETURNING …`.
- **Test**: two concurrent `POST /v1/imports/{id}/apply` → one 200, one 409, one action row.

#### DB-004 — Capture quota is check-then-insert (paid model calls)

- **Status**: CONFIRMED DEFECT (race). Lead verified.
- **Evidence**: `internal/imports/capture.go:82` `checkCaptureQuota` counts, then `CaptureStore().Save`
  and `Store.Insert` (`:94`) run as separate statements.
- **Failure scenario**: N parallel captures from a free account all see `used < 3` and all enqueue
  Anthropic reads; the Plus fair-use cap has the same hole. Spend is metered, so cost is bounded
  by request volume, not by the quota.
- **Proposal**: count + insert in one tx behind `pg_advisory_xact_lock` keyed by user, the pattern
  `LockUserListens` (`listens.sql:7`) and `LockUserForSportFollow` (`internal/sports/store.go:56`)
  already use. Same fix, lower stakes: DB-008.
- **Test**: 10 parallel captures on a free account → exactly 3 accepted.

#### REL-002 — `@aaru` reply can post twice and pay twice

- **Status**: CONFIRMED DEFECT (rare trigger). Reported by two reviewers.
- **Evidence**: `Answer` posts the reply (`internal/agent/reply.go:178`) and the row is marked done
  afterwards in a separate statement (`:100`). `PostAgentReply` inserts the message and can still
  fail afterwards on `Members`/`requireChannel`/`Progress` (`internal/groups/agent.go:93-115`),
  which sends the row to retry. Lease is 120 s (`reply.go:30`) while a run can be 4 rounds × 60 s
  model timeout (`internal/model/anthropic.go:77-80`) plus tool calls, with no lease renewal and no
  overall deadline. `FinishAgentReply` (`groups.sql:301`) updates `WHERE id = $1` only.
  Retry/finish bookkeeping runs on the cancelled ctx at shutdown (`reply.go:85,104`), and
  `reply_worker.go:35` suppresses those errors; imports get this right with `WithoutCancel`
  (`internal/imports/service.go:229`).
- **Failure scenario**: a transient DB error after the insert, a deploy between post and finish, a
  rollout surge, or `AGENT_REPLY_WORKERS > 1` produces a duplicate reply and repeats model rounds.
- **Proposal**: run `Answer` under `context.WithTimeout(ctx, Lease-10s)`; before calling the model,
  finish as `done` if an agent message replying to this mention already exists (or insert the reply
  and finish the row in one tx); do retry/finish/release with `context.WithoutCancel` and release
  without counting the attempt on shutdown, as imports do; guard `Finish`/`Retry` with
  `AND attempts = $n`.
- **Tests**: `Members` stub failing once after insert → exactly one agent message; ctx cancelled
  during `Complete` → row back to `queued`, attempts unchanged; a model stub that blocks → job fails
  inside the lease.

#### REL-003 — Live Activity sweep drops users when a pass fails or is cancelled

- **Status**: CONFIRMED DEFECT.
- **Evidence**: the claim sets `next_check_at = NULL` (`internal/db/queries/scrobble.sql:121`);
  `Sweep` calls `Notifier.Sync` per user (`internal/scrobble/service.go:386-391`); `Sync` only logs
  on error (`internal/scrobble/notifier.go:69-71`); only a successful save sets `next_check_at` again.
- **Failure scenario**: a transient DB/APNs error or a shutdown mid-batch leaves those users with no
  scheduled check; a stale "Now playing" stays on the lock screen until their next scrobble.
- **Proposal**: claim by pushing `next_check_at` forward (e.g. now + 60 s) instead of nulling it; a
  successful save overwrites it, a failure retries by itself. Stop the loop on `ctx.Err()`.
- **Test**: failing `LoadLiveSet` stub → a sweep 60 s later picks the user up again.

#### REL-004 — No worker metrics, no queue depth; catalog refresh failures are silent

- **Status**: CONFIRMED (gap).
- **Evidence**: `internal/metrics/metrics.go:22-30` defines HTTP, imports-finished, scrobble, push and
  LLM counters only. No per-worker pass/failure/duration, no last-success timestamp, no queue depth
  or oldest-age for `import_jobs`/`agent_replies`. Workers log but never report to Sentry.
  `internal/catalog/refresh.go:88` `_, _ = r.Catalog.Detail(ctx, id)` drops every provider error
  after stamping the show as attempted, so a revoked TMDB key goes unnoticed.
- **Proposal**: `aaru_worker_passes_total{worker,result}`,
  `aaru_worker_last_success_timestamp_seconds{worker}`, queue depth and oldest-queued-age gauges
  for imports and agent replies, a refresh failure counter; Grafana alerts on stale last-success
  and growing queue age. Label values are worker names only (bounded).

#### HTTP-002 — Client disconnects become logged, reported 500s

- **Status**: CONFIRMED DEFECT. Lead confirmed `Errors`/`Map` have no cancellation branch.
- **Evidence**: `internal/middleware/errors.go:46-95` maps any unknown error, `context.Canceled`
  included, to `apperr.Internal()`, logs at Error and calls `reporter.Report`. pgx and
  `provider.Client.Do` (`client.go:241-243`) return the ctx error. Sentry sends one goroutine per
  5xx with no sampling (`internal/telemetry/sentry.go:78`, bounded by a 5 s client timeout).
- **Impact**: cancelled searches on mobile networks inflate the 5xx rate and burn Sentry quota.
- **Proposal**: if `errors.Is(err, context.Canceled)` and the request ctx is done → log at Info,
  record status 499, do not report.
- **Test**: handler returns `context.Canceled` with a cancelled request ctx → reporter not called,
  metric `code="499"`.

#### HTTP-003 — Unbounded `method` label on request metrics

- **Status**: CONFIRMED DEFECT. Lead verified.
- **Evidence**: `internal/middleware/metrics.go:20` passes `c.Request().Method` raw into
  `httpRequests.WithLabelValues`. net/http accepts any token as a method. The route label is safe
  (template or "unmatched", covered by a test).
- **Impact**: `curl -X RANDOM$i /` creates a new Prometheus series per request.
- **Proposal**: pass standard methods through, map others to `OTHER`. While there, memoise the
  `echoParam` regex replacement per route (`metrics.go:31`).
- **Test**: request with method `FOO` → label `OTHER`.

#### CON-001 — User-keyed cache misses start detached, untimed fetches on shared provider budgets

- **Status**: CODE-SUPPORTED RISK.
- **Evidence**: every miss in `internal/{catalog,concerts,sports}/cache.go` runs
  `go c.run(context.WithoutCancel(ctx), …)` with no timeout. Keys come from user input with no
  per-user limit: sports search (3 fetches per query, `internal/sports/service.go:146-150`), sports
  event by any numeric id (`internal/sports/fixtures.go:309-317`), concert search/performers
  (`internal/concerts/service.go:209,239`). `Pacer.Acquire` (`internal/provider/client.go:149-165`)
  can therefore wait forever on a detached ctx, and is not FIFO.
- **Failure scenario**: a search-as-you-type burst or id enumeration queues many fetches behind
  TheSportsDB's pacer and starves livescore refresh; each distinct concert query spends one unit of
  the shared 4,500/day Ticketmaster budget, which the background concerts worker also uses, so one
  account can exhaust the day for everyone. Unknown sports ids are cached as `nil` and evict real
  entries from the 3,000-entry cap.
- **Proposal**: per-user `ratelimit.FixedWindow` on sports search/event and concerts
  search/performers; `context.WithTimeout(context.WithoutCancel(ctx), 30*time.Second)` for detached
  fetches; optionally reserve pacer capacity for the livescore key. Longer term, merge the three
  hand-rolled caches into one bounded generic cache (they have already diverged, see CON-003) and
  let the non-onAir caches serve stale while refreshing, as `onAirCache` does.
- **Test**: blocking `Listing` stub, 50 distinct searches with cancelled ctxs → in-flight fetches
  bounded and drained after the timeout.

#### CON-002 — WebSocket typing throttle keyed by a client-chosen channel id

- **Status**: CONFIRMED DEFECT. Lead verified.
- **Evidence**: `internal/realtime/gateway.go:156-160` records `lastTyping[cmd.Channel] = now`
  before `Commands.Typing` checks membership; `Typing` runs up to 3 DB queries
  (`internal/groups/messages.go:334-345`). Errors from `Typing`/`React` are discarded (`:160,:166`).
- **Failure scenario**: one signed-in socket sends 1 KiB frames with random channel ids; each passes
  the throttle, costs DB queries, and grows the map for the life of the connection.
- **Proposal**: one token bucket per connection for all inbound frames (e.g. 5/s, then drop or
  close with 1008); record `lastTyping` only after `Typing` returns nil; cap the map; log non-apperr
  errors at Warn.
- **Test**: fake `Commands` counting calls; 1,000 typing frames on distinct channels → calls ≤ bucket.

#### PERF-001 — Listening-history upload copies the file several times, in the request path, behind an uncancellable global lock

- **Status**: CODE-SUPPORTED RISK; size of the effect is MEASURE FIRST.
- **Evidence**: handler reads up to 24 MB (`internal/httpapi/listen_imports.go:41-45`);
  `jsonObjects` unmarshals the file into `[]json.RawMessage` and then a
  `map[string]json.RawMessage` per element (`internal/imports/listen_files.go:64-92`);
  `spotifyListen` does ~10 reflective `json.Unmarshal` calls per entry (`:118-130`). The package-level
  `listenFileGate sync.Mutex` (`internal/imports/listens.go:32,91-92`) serialises every user, ignores
  ctx, covers parsing only (bodies are buffered before it, parsed listens live through `Stage` after
  it), and contradicts PORTING's "no globals" rule and CLAUDE.md's "imports are jobs, not
  request-path work". Reviewer-reported, not lead-verified: `CreateListenFileImport` inserts the job
  before `Stage` outside a common tx, so a staging failure leaves a job with `RowsTotal` and no rows.
- **Proposal**: stream the array with `json.Decoder` (`Token`/`More`/`Decode`) into a typed struct
  whose `lenientString.UnmarshalJSON` maps a type mismatch to nil (behaviour unchanged); replace the
  global with a size-1 semaphore channel on `Service` acquired with `select` on `ctx.Done()`; stage
  in chunks; put job insert and staging in one tx.
- **Verify**: `BenchmarkParseSpotifyHistory` on a synthetic 24 MB file with `-benchmem`; compare
  `TotalAlloc`/peak heap.

#### PERF-002 — Account export loads every listen into memory

- **Status**: CODE-SUPPORTED RISK. Lead verified.
- **Evidence**: `internal/httpapi/export.go:163`
  `music.NewStore(s.Pool).Listens(gctx, userID, nil, math.MaxInt64)`; rows are copied
  sqlc → `music.Listen` → `api.Listen` and the whole graph sits in memory before encoding, inside an
  8-goroutine errgroup with no `SetLimit` (DB-002).
- **Proposal**: stream the listens section (keyset pages written to the encoder), `SetLimit(3)`.
- **Verify**: export for a seeded user with 500k listens; measure peak heap and wall time.

#### DB-005 — Account deletion fires FK actions on unindexed columns

- **Status**: MEASURE FIRST.
- **Evidence**: `DeleteUser` (`internal/auth/store.go:218`) cascades to `actions`; each deleted
  action runs `ON DELETE SET NULL` on `points_events.action_id`, `user_badges.action_id`,
  `import_jobs.action_id`, `agent_plans.action_id` and `actions.undo_of`, none with a leading index
  in `baseline.sql`. Deleting `agent_tokens` sets `listens.agent_token_id` NULL (unindexed);
  deleting a library item cascades to `tonight_feedback.library_item_id` (unindexed).
- **Impact**: delete cost ≈ (#actions × table scans), growing with the whole platform; on the
  request path inside one tx.
- **Proposal** (goose migration with `-- +goose NO TRANSACTION`, after EXPLAIN):
  `CREATE INDEX CONCURRENTLY … (action_id) WHERE action_id IS NOT NULL` for the four action FKs,
  `actions(undo_of) WHERE undo_of IS NOT NULL`, `tonight_feedback(library_item_id)`. Treat
  `listens(agent_token_id)` separately: nearly every scrobbled listen carries it, so it costs on
  every insert — measure first, or switch that FK to a background cleanup.
- **Verify**: locally seed a user with 5k actions and 50k listens; time `DELETE FROM users` and
  `EXPLAIN (ANALYZE)` a single `DELETE FROM actions` to see trigger time.

#### DB-006 — `UnresolvedListens` rescans every unresolvable listen every minute

- **Status**: MEASURE FIRST.
- **Evidence**: `listens.sql` `UnresolvedListens`, called by `music.ResolverWorker` every minute via
  `internal/music/store.go:197`: `DISTINCT ON (track_key, lower(album))` over all users' unresolved
  listens, anti-join on `music_lookups`, `ORDER BY listened_at DESC LIMIT`. Listens MusicBrainz cannot
  place stay unresolved forever, so the partial index grows without bound and every pass sorts it.
- **Proposal**: drive the worker from a per-key queue (or `music_lookups`) instead of scanning
  listens; at minimum a partial index on `(track_key, lower(coalesce(album,'')))`.
- **Verify**: `EXPLAIN (ANALYZE, BUFFERS)` after importing a large Spotify extended history locally.

#### HLT-001 — No vulnerability scanning; floating lint version

- **Status**: CONFIRMED (gap). Lead verified `ci-go.yml` runs `go test -race`, sets
  `AARU_REQUIRE_DB=1`, runs `golangci-lint-action@v8`.
- **Gaps**: no `govulncheck`, no Dependabot/Renovate for `go.mod`, `golangci-lint-action` has no
  `version:` (results can change with no code change), actions pinned by tag not SHA.
- **Proposal**: add a `govulncheck ./...` step (`golang/govulncheck-action`), pin the lint version,
  enable Dependabot for `gomod` and `github-actions`.

#### HLT-002 — No benchmarks, no fuzz tests

- **Status**: CONFIRMED (gap): 764 tests, 0 `Benchmark`, 0 `Fuzz`, 0 `t.Parallel`.
- **Proposal**: fuzz the parsers that read untrusted files (CSV, MAL XML, TV Time, Spotify/Takeout
  JSON, ICS) — they are the most likely source of the panic in REL-001. Add the benchmarks named in
  PERF-001/003/004/005 so any optimisation starts from a baseline.

### 3.4 P3 findings (short form)

| ID | Finding | Proposal |
| --- | --- | --- |
| CON-003 | `internal/sports/cache.go:76` `failedAt` grows with every distinct failing key and is pruned only on success of that key (`concerts/cache.go:108-113` prunes; sports diverged). `trim` copies and sorts all 3,000 keys under the lock per insert at capacity and evicts by `fetchedAt`, not last use | Prune expired failures in `trim`; fold into the shared cache from CON-001 |
| CON-004 | Hub fan-out runs synchronously on the poster's request (`internal/realtime/hub.go:152-164`, `writeTimeout` 10 s, via `groups.Service.publish`); `Frame` marshals under `h.mu` (`:139`); no per-user socket cap; `/v1/realtime/ticket` unthrottled and `IssueTicket` sweeps under the lock | Per-connection bounded send queue + writer goroutine (or detached fan-out with timeout); socket cap per user; rate-limit ticket issuance. Test: blocking sink → `Publish` returns < 100 ms |
| CON-005 | Ticketmaster `CallBudget.Take` once per `get` (`internal/concerts/ticketmaster.go:203`) while `Client.Do` may send 3 attempts; budget is in memory and resets on restart | Charge per attempt via a client hook, or `MaxAttempts: 1` for Ticketmaster; persist the day's count if the cap matters |
| HTTP-004 | Provider client: `ErrBodyTooLarge` is classed as a network error and retried, downloading up to 8 MiB three times (`transport.go:144`, `client.go:240-244`); backoff has no jitter (`:263`); `Retry-After` read as whole seconds on 429 only and honoured up to 60 s on user requests | Classify as malformed (no retry); add jitter; with DB-001's request deadline, fail fast when `retryAfter` exceeds time left. Retrying POSTs was checked and is safe here |
| HTTP-005 | API `http.Server` sets only `ReadHeaderTimeout` (`internal/app/app.go:158-162`): idle keep-alives never time out, request bodies have no read deadline. `Shutdown` does not close hijacked WebSockets and the gateway ctx is `WithoutCancel` (`gateway.go:96`), so sockets are cut without a close frame | Add `IdleTimeout: 120s` (safe for WebSockets). **Do not** add a global `ReadTimeout`/`WriteTimeout` (breaks WebSockets and 24 MiB uploads); use `http.ResponseController` per route. `RegisterOnShutdown` → close sockets with 1001. Check Traefik's timeouts first |
| HTTP-006 | Raw transports write their own 500 and return nil, so `Errors` never reports them: `internal/mcp/handler.go:99-100,115-116`, `scrobble_routes.go:108-110`, `stremio_routes.go:81`, `oauth_routes.go:136` | Give `Server` the reporter and call it in those branches |
| HTTP-007 | Client address is the first `X-Forwarded-For` hop (`internal/middleware/auth.go:101-105`); if Traefik forwards a client-supplied header, per-IP limits (sign-in, invites) can be bypassed. `FixedWindow.Allow` (`ratelimit.go:33-39`) scans the whole map under the lock on every call once > 10k live keys | Confirm Traefik's trusted-proxy config (compare XFF with `RemoteAddr` in prod logs); take the right-most untrusted hop; sweep at most once per window. Belongs in a security review too |
| HTTP-008 | JWKS singleflight runs on the leader's request ctx (`internal/auth/jwks.go:103-130`): if that client disconnects every waiter fails; a failed refresh leaves `fetchedAt` unchanged, so during an Apple/Google outage every sign-in first waits up to 15 s | Fetch on `WithoutCancel` + timeout; short back-off timestamp after a failure |
| REL-005 | MAL push: any 429/5xx/timeout returns and the whole changeset is retried every 30 s with no per-user backoff (`internal/mal/pusher.go:233-239`); `MALPushesDue` has no `LIMIT` (`mal.sql:42-46`). Pushes are idempotent, so cost not correctness | `push_failures` + `push_not_before` with exponential backoff; `LIMIT` the due query |
| REL-006 | Poison rows retry forever: gamification worker returns any evaluation error and lets the 120 s lease expire, no attempt counter (`internal/gamification/worker.go:76-81`, `GamificationClaimDirty`); music resolver and concerts refresher stop the pass on the first provider error without recording a miss (`internal/music/service.go:117-120`, `internal/concerts/refresher.go:66-68,99-101`) → head-of-line blocking (hypothesis: no deterministic trigger found) | Failure counter + backoff column, give up after N; on a 4xx record a miss and continue |
| REL-007 | Airing alerts are at-most-once: claimed with `ON CONFLICT DO NOTHING` before `Deliver`; a send error is skipped (`internal/push/push.go:136-137`); a DB error for one user ends the pass after that user's claim is written (`:215-231`) | Fine as a product choice — document it. Log-and-continue to the next user instead of returning |
| REL-008 | `markDirty` uses the request ctx, which may already be cancelled, and drops the error (`internal/gamification/service.go:164,213`); badge re-evaluation can be lost until the user's next write | `context.WithoutCancel` + log. Other dropped errors reviewed and fine: `auth/agenttokens.go:373`, `library/store.go:116`, `scrobble/notifier.go:278`, `scrobble/body.go:140,148`, `auth/verifiers.go:65`. Log `agent/reply.go:97` |
| PERF-003 | Import apply / undo: ~3–5 sequential statements per item inside one HTTP-path tx (`internal/library/store.go:207-337`), plus `GamificationSeasonComplete` per (item, season) (`internal/gamification/record.go:126-139`); `music.Store.Insert` up to 1,000 sequential `InsertListen` under the advisory lock (`internal/music/store.go:60`) | Benchmark first (`BenchmarkImportApply` at 500 / 2,000 rows with a pgx `QueryTracer` counting statements); then `pgx.Batch` pipelining or bulk `unnest` for `OpInsertItem`, or move approval into the worker |
| PERF-004 | `MatchEpisodeName` re-normalises every catalog episode for each input name (N×E `NormalizeTitle`); `fold` rebuilds `transform.Chain` + `cases.Fold()` each call (`core/matching.go:41-48`); `EpisodesNamed` refetches TMDB (detail + per-season) for each Netflix row and scrobble stop instead of reading stored `show_episodes` (`catalog/resolver.go:443-462`, `scrobble/service.go:255-263`) | Normalised index built once per list; try `Store.ShowEpisodes` first (also saves TMDB quota). `sync.Pool` for transformers only after `BenchmarkNormalizeTitle` |
| PERF-005 | Per request, kin-openapi's router linearly matches 158 spec paths and decodes JSON bodies into `any` before the strict handler decodes again (`internal/middleware/validate.go:22-52`) | `BenchmarkValidate`; if material, key operation lookup on echo's `c.Path()` + method at startup |
| PERF-006 | Algorithmic: resolving one unmatched import row reloads, re-decides and rewrites all N rows (`imports/resolve.go:33-75`); `slices.Contains` per tick is O(W²) per show (`imports/tvtime.go:519`); `see` is a linear scan, O(n²) over a batch or undo (`gamification/writefacts.go:50-57`); a Tonight GET writes 3 picks in sequential, non-transactional statements (`tonight/service.go:544-553`) | Save only the changed row when the merge group allows; sets instead of slice scans; one tx for the Tonight writes |
| DB-007 | `LIMIT` and optional filters are spliced into library entry SQL (`internal/library/entries.go:93`), so each variant is a distinct prepared statement per connection (not an injection risk: ints and constants only). `Changes(since=nil)` returns up to 100,000 entries with correlated subqueries in one response (`:256`) | Bind `LIMIT $n`; page the first sync |
| DB-008 | Other check-then-insert caps: `GroupOwnedCount` → `CreateGroup` (`groups/service.go:108`, `groups/store.go:93,101`), `PlanPendingCount` (`plans/service.go:71`), `GamificationEarnedToday` → insert (daily cap can overshoot; per-root dedupe stays safe). Hypotheses to EXPLAIN: `GamificationClaimDirty` (`OR evaluated_at IS NULL` defeats the partial index), `ScheduleContinueWatching` (LATERAL remaining count per in-progress show), `LibraryReopenAired` (cross-user scan every 5 min), uncapped unread `count(*)` in `GroupSummaries`/`GroupChannels`, `BoardFeed` | Advisory-lock pattern from DB-004 where the cap matters; EXPLAIN with realistic local data |
| HLT-003 | Lint config: 204 `//nolint`, all with a reason, but 12 name linters that are not enabled (`wrapcheck` ×8 e.g. `groups/social.go:23-60`; `gocritic` ×2 `boards/store.go:55,106`; `nilerr` `realtime/gateway.go:92`; `errchkjson` `imports/store.go:81`) and `nolintlint` is off. `nilnil` is suppressed 115 times for the deliberate Swift-optional pattern | Enable `nolintlint`, `bodyclose`, `noctx`, `rowserrcheck`, `contextcheck`; disable or narrow `nilnil` in config instead of 115 suppressions; delete dead directives |
| HLT-004 | Build: base images not pinned by digest (`golang:1.27-bookworm`, `distroless/static-debian12:nonroot`); `Makefile` `.PHONY` misses `check-fmt vet staticcheck test-race check-all`, `test` runs without `-race`, `check-fmt` uses `gofmt` though the convention is `gofumpt`, `staticcheck` is not a tool dependency (and not installed locally); the `go.mod` tool block pulls sqlc/oapi-codegen trees (mysql, sqlite, TiDB parser, wazero, grpc) into the module graph (not the binary) | Pin digests (Renovate can bump them); fix `.PHONY`, `-race` in `test`, `gofumpt -l` in `check-fmt`; optionally a separate `-modfile=tools.mod` |
| HLT-005 | Logging: no context-aware `slog.Handler`, so the 16 `*Context` calls add nothing; no request id; `RequestLog` writes two Info lines per request | Request-id middleware storing a logger/attrs in ctx + a handler that reads them; one line per request (start line at Debug) |

## 4. Prioritised roadmap

Order respects dependencies (observability before tuning; timeouts before pool sizing).

| Step | Items | Files | Complexity / risk | Validation | Status |
| --- | --- | --- | --- | --- | --- |
| P1-a | REL-001: recover middleware, `safeStep`, cache close-before-fetch, attempt cap in both claims | `httpapi/router.go`, `middleware/`, `imports/worker.go`, `agent/reply_worker.go`, `catalog/refresh.go`, `{catalog,concerts,sports}/cache.go`, `queries/imports.sql`, `queries/groups.sql` | Low / low | Tests listed in REL-001; `go test -race` with `AARU_REQUIRE_DB=1` | APPROVE |
| P1-b | HTTP-001: per-route body limit | `httpapi/router.go`, `httpapi/capture.go` | Low / low (check every route that legitimately takes > 1 MiB) | 413 test + existing upload tests | APPROVE |
| P1-c | DB-001: request deadline middleware, `statement_timeout`, `idle_in_transaction_session_timeout`, re-document the env var | `db/db.go`, `config/config.go`, `httpapi/router.go`, `PORTING.md`, Swift-parity README note | Medium / medium (exclude WebSocket, uploads, export, MCP streaming; migrations need their own timeout) | Saturated-pool test; staging soak | REVISE values with owner, then APPROVE |
| P2-a | DB-002 metrics first: `pgxpool.Stat` collector; REL-004 worker + queue metrics; dashboards/alerts | `metrics/`, `app/app.go`, each worker | Low / low | Unit test per counter; check `/metrics` | APPROVE |
| P2-b | HTTP-002 499 mapping; HTTP-003 method label | `middleware/errors.go`, `middleware/metrics.go` | Low / low | Tests in findings | APPROVE |
| P2-c | DB-003 Apply in one locked tx; DB-004 capture quota advisory lock | `imports/plan.go`, `imports/listens.go`, `imports/capture.go`, queries | Medium / medium (journal semantics must not change) | Concurrency tests in findings | APPROVE |
| P2-d | REL-002 agent reply idempotency + deadline; REL-003 sweep claim | `agent/reply.go`, `groups/agent.go`, `queries/groups.sql`, `queries/scrobble.sql`, `scrobble/service.go` | Medium / low | Tests in findings | APPROVE |
| P2-e | CON-002 per-connection frame bucket; CON-001 per-user limits + fetch timeout | `realtime/gateway.go`, `httpapi/sports.go`, `httpapi/concerts*.go`, caches | Low–medium / low | Tests in findings | APPROVE |
| P2-f | PERF-001 streaming listen parse + semaphore; PERF-002 streamed export + `SetLimit(3)` | `imports/listen_files.go`, `imports/listens.go`, `httpapi/export.go`, `export/export.go` | Medium / medium (parse behaviour must stay identical; reuse parity tests) | Benchmarks with `-benchmem` before/after | MEASURE FIRST (benchmark), then APPROVE |
| P2-g | DB-005 FK indexes, DB-006 resolver scan | new goose migration, `queries/listens.sql`, `music/` | Medium / medium (write amplification; `CONCURRENTLY` outside a tx) | Local EXPLAIN with seeded data | MEASURE FIRST |
| P2-h | HLT-001 govulncheck + pinned lint + Dependabot; HLT-002 fuzz targets for parsers | `ci-go.yml`, `.github/dependabot.yml`, `imports/*_test.go` | Low / low | CI run | APPROVE |
| P2-i | Pool size increase or separate worker pool (DB-002) | config / infra values | Low / medium | Needs P2-a gauges under real load | MEASURE FIRST |
| P3 | Everything in §3.4 | — | Mostly low | Per row | APPROVE when touched; perf items MEASURE FIRST |

Rollback for every item: each is a self-contained commit; SQL changes are query edits plus
`make generate`; index migrations ship with a `DROP INDEX CONCURRENTLY` down step; timeouts and
limits are env/config so they can be relaxed without a deploy of new code. Production only
changes through a promote PR in `platform/infra`.

## 5. Proposals considered and challenged

| Proposal | Verdict | Reason |
| --- | --- | --- |
| Global `ReadTimeout`/`WriteTimeout` on the API server | REJECT | Kills WebSockets and 24 MiB uploads; use `IdleTimeout` + per-route deadlines (HTTP-005, DB-001) |
| Raise pool size now | MEASURE FIRST | No pool stats exist; first add gauges (DB-002). Bound is `max_connections=40` |
| Separate pgx pool for workers | MEASURE FIRST | Adds config surface; only if gauges show workers starving HTTP |
| `listens(agent_token_id)` index | MEASURE FIRST | Write cost on every scrobble; alternative is async cleanup (DB-005) |
| `sync.Pool` for text-folding transformers | MEASURE FIRST | Only after `BenchmarkNormalizeTitle` shows allocation cost matters (PERF-004) |
| Replace kin-openapi validation lookup | MEASURE FIRST | No evidence it is hot (PERF-005) |
| DLQ / outbox for jobs | REJECT for now | Jobs are already durable rows; the defects are the missing attempt cap and idempotency checks, which a DLQ would not fix |
| Retry everything in the provider client more aggressively | REJECT | Shared quotas (MusicBrainz 1/s, Ticketmaster daily, TheSportsDB) — amplification risk; add jitter and stop retrying oversize bodies instead |
| Two-way changes to Swift parity | REVISE | DB-001 restores Swift's documented behaviour; all other fixes keep wire behaviour identical, so PORTING's 1:1 rule holds |
| Separate tools `-modfile` | REVISE (optional) | Cleaner graph, small benefit, extra moving part |

## 6. Evidence log and gaps

Commands run (macOS, go 1.27.3):

| Command | Result |
| --- | --- |
| `git rev-parse HEAD`, `git status --short` | `e915e710…`, clean |
| `go vet ./...` | exit 0. Note: this account's module cache was empty, so `go` downloaded the modules pinned in `go.sum` from the module proxy |
| `golangci-lint run ./...` (repo config) | 0 issues |
| `staticcheck`, `govulncheck` | Not installed; not run |
| `go test -race -count=1 ./...` without a test DB | 35 packages ok, 16 without tests; DB tests skipped. The default `127.0.0.1:5432` belongs to another local project's Postgres; auth failed, so nothing was created there |
| `POSTGRES_PORT=5436 AARU_REQUIRE_DB=1 go test -race -count=1 ./...` against a throwaway `postgres:17` container | 35 packages ok, 0 failures, no data races reported. Slowest: `internal/httpapi` 150 s, `internal/catalog` 10 s |
| Benchmarks, pprof, EXPLAIN | None exist / none run |

Subsystem reviews were done in parallel by five read-only reviewers (workers, concurrency, database,
HTTP/outbound, performance/code health); the lead re-read the source for every item marked `lead`.
Where two reviewers reported the same issue independently it is marked `reviewer ×2`.

Data still needed:

- `EXPLAIN (ANALYZE, BUFFERS)` on a local DB with realistic volume for: `UnresolvedListens`,
  `ScheduleContinueWatching`, `LibraryReopenAired`, `GroupSummaries`, `BoardFeed`,
  `GamificationClaimDirty`, and `DELETE FROM users` for a heavy user.
- Production: pool stats (after P2-a), pod memory limit and OOM history, p95/p99 per route,
  Sentry volume of `context canceled` 500s, Traefik timeout and forwarded-header config,
  rollout strategy and `terminationGracePeriodSeconds`.
- Benchmarks named in PERF-001…005 before any optimisation.

Possible conflicts between recommendations:

- DB-001 request deadline vs export, MCP and uploads that legitimately run long → exempt those
  routes or give them their own budgets.
- DB-005 indexes (faster deletes) vs write amplification on append-heavy tables → decide per index
  from EXPLAIN and insert rate.
- CON-001 per-user limits vs search-as-you-type UX → set limits from observed request rates, and
  let cancelled requests stop waiting (they already do; only the detached fetch continues).
