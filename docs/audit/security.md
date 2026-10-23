# Security audit: run-1 (2026-10-23)

A source-first, read-only review of the whole repository at `cd4ea2f` (`main`), done with the
`security-audit` skill in guidance mode. Nothing was deployed, probed, built or fetched; the only
code executed was a single-file Swift harness of one function, under `sandbox-exec` with the
network denied. The run artifacts (coverage ledger, hunter briefs, the harness and its output)
live outside the repo at `~/security-audit-skill/aaru/run-1`.

**Read the limits first.** The skill's hunter and verifier agents could not be launched in this
session (auto mode refused them), so one reviewer traced the code alone. 36 of 79 coverage units
were reviewed at `cd4ea2f`; 42 are deferred and hold only reconnaissance notes from `50232df`.
The one confirmed finding was demonstrated by the harness but **not independently verified**.
Nothing here is scheduled: the owner decided on 2026-10-23 to document and move on.

## The one finding (low)

**A music scrobble token sent as `?token=` is written to request logs.**
Fingerprint `aaru-server/logging/bearer-token-in-url-query-retained`.

- `GET /listenbrainz/1/validate-token` accepts the token as a query parameter, ListenBrainz's
  legacy form (`aaru-server/Sources/App/Music/ListenBrainzRoutes.swift`, `validate`). The common
  clients send `Authorization: Token …`, which is never logged.
- `RedactedLogRequestsMiddleware.redacted` keeps the query string for every path except
  `/stremio/…`, the Trakt callback and `/v1/concerts/places`
  (`aaru-server/Sources/App/HTTP/RedactedLogRequestsMiddleware.swift`), and logs it at info.
- The ingress adds to it: Traefik's access log is on (JSON) and the infra chart sets no
  `accesslog.fields.queryParameters` drop, so `RequestPath` keeps every query. That retains the
  realtime ticket (`/v1/ws?ticket=`, 60 s, single use), the Trakt callback `code` and `state`, the
  Stremio token path, and this token, in Grafana Cloud.
- Harness: a verbatim copy of `redacted()` returned
  `/listenbrainz/1/validate-token?token=aaru_mus_DUMMY…` unchanged while `/stremio/<token>/…`
  became `/stremio/[token]/…` and the Trakt callback lost its query.

Who it affects: a reader of the API or ingress logs gets one user's `aaru_mus_` token (music
group, `scrobble:write` only). It can submit listens and now-playing updates as that user until
revoked. No library read, no session. The design says token secrets exist only as a SHA-256 in
Postgres; the log breaks that for this path.

**Fix (SEC-001):** refuse the `?token=` form on `validate-token` (header only); make `redacted()`
return the bare path for `/listenbrainz/` routes; in the infra chart set
`accesslog.fields.queryParameters.defaultMode: drop`. Regression: `redacted("/listenbrainz/1/validate-token", query: "token=x")`
equals the bare path, and the route answers 400 without an Authorization header.

## Resolved negative

The reconnaissance lead that per-client rate limits key on the first `X-Forwarded-For` hop
(`API/AppRequestContext.swift`) is not exploitable as deployed: Traefik 3.7.4 runs with default
`forwardedHeaders` (no `insecure`, no `trustedIPs` in `cluster/traefik/helmchartconfig.yaml`),
which strips client-supplied `X-Forwarded-*` before appending the real address, and
`externalTrafficPolicy: Local` keeps that address intact. The magic-link, DCR and invite-preview
limiters therefore key on the real client IP. A config change at the ingress would reopen this.

## Hardening notes (not findings, SEC-002)

- Google sign-in verifies the nonce only when the client sends one
  (`Auth/GoogleIdentityVerifier.swift`); both clients send one, so require it.
- `DELETE /v1/me` needs only a session; there is no sign-out-everywhere; sessions last 90 days
  without rotation (`API/AuthHandlers.swift`, `Auth/AuthService.swift`).
- A DCR client whose name contains "claude" is stored as kind `claude` / `claude_code`
  (`OAuth/OAuthService.swift`). The consent page shows the self-asserted name and the redirect
  host, so the kind adds little, but derive it from the redirect host, not the name. DCR clients
  never expire.
- `GET /v1/oauth/requests/{id}` is session-only and UUID-guarded without the binding cookie that
  approve and deny require (`API/OAuthHandlers.swift`).
- An MCP or OAuth token with `library:write` can repeat tap-sized adds and updates up to the
  120/min token limit without a plan (`Agent/AgentTools.swift`). Intended per `CLAUDE.md`; a
  per-token rolling cap on unplanned writes would bound it.
- Sandbox-environment App Store transactions grant Plus like Production ones
  (`Billing/BillingTypes.swift`, `isActive`). Fine while TestFlight is the only channel; revisit
  before an App Store release.
- Request logs keep query strings on ordinary routes (`/v1/search?q=`): user-typed text in logs.
  Drop queries by default and allowlist the few that matter.

## Reviewed and clean at `cd4ea2f`

Auth gate and sign-in flows (code and link limits, Apple and Google verification); App Store
signed data (x5c chain to Apple Root G3 with marker policy, bundle check, `signed_at`-monotonic
upsert, `appAccountToken` bound to the session user); ListenBrainz submit (token group, scope,
10 MB, 1000 listens, per-token limit); `/internal/metrics` (constant-time secret, off when
empty); friend invites (12-char random codes, 14 days, 20 open, limiters, uniform 404); the
board, friend profile, activity and leaderboard (friends only, blocks, owner opt-in); capture
import (size caps, quotas, tool-constrained model output, plan-only rows, input deletion);
device and Live Activity registration (hex tokens, topic allowlist, owner binding); Sentry and
PostHog payloads (route template and random id only); MCP transport guards and the tap-sized
rule; agent token service; Stremio CORS and cache policy; zlib inflate ceiling; WebSocket tickets
(single use, Origin allowlist); CAT iCal host pinning; the extension handshake and manifest; the
iOS URL scheme and Keychain; CI triggers and expressions; the in-process limiters.

## Deferred (SEC-003): what the next run hunts

Not reviewed at `cd4ea2f`; reconnaissance notes from `50232df` only.

- `@aaru` in groups: the reply posts the tagger's library facts to the whole group, and other
  members' text is in the prompt (`Agent/AgentReplyService.swift`, `Agent/GroupAgentTools.swift`).
  Disclosure, not writes.
- Scrobble name-only matching writes finished and ticks from client text
  (`Scrobble/ScrobbleService.swift`); bounded to the token's own user.
- Account deletion silently promotes the oldest admin or member to owner of each owned group
  (`Data/Fluent/PostgresAuthStores.swift`).
- Library, lists, export, undo and deletion isolation; raw `SQLQueryString` builders; import
  parsers (MAL XML external entities, CSV cost) and merge rules; the Trakt callback; OAuth token
  exchange and refresh; Stremio `player`/`library` events and the zlib FFI; realtime fan-out after
  membership changes and hub cardinality; web-push endpoint handling; group kinds and social
  enumeration; web CSRF on server functions, navigation and rendering (no script-src CSP while the
  connect page handles the raw scrobble secret in page JS); extension content scripts; widget
  intents; the promote PR path, Docker context, config defaults and codegen; pre-authentication
  work and parser cost.

## How to resume

Run `/security-audit` outside auto mode, from a worktree pinned to one commit (the shared
checkout moved 276 commits during this run). The ledger, 15 hunter briefs, the sandbox runner and
the promotion tool in `~/security-audit-skill/aaru/run-1` are ready; re-seed units with
`_tools/gen-ledger.cjs`, re-brief with `_tools/build-brief.cjs`, then run the candidate and
record verifiers on the finding above and any new candidates.
