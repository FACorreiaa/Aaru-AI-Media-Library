# Release blockers 1–4 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the remaining open items of BACKLOG.md "Release blockers (2026-11-10)" rows 1–4 (group-message report and board counts are already on main: 7656bdbc, dedb5a06).

**Architecture:** Docs first (privacy rule), then the Go server and `openapi.yaml`, then regenerated clients, then iOS and web surfaces. One branch `fix/release-blockers`, one PR.

**Tech Stack:** Go (echo v5, sqlc, goose), SwiftUI, SolidJS/TanStack Start (shadcn-solid via `~/components/ui`).

**Spec:** BACKLOG.md "Release blockers (2026-11-10)" rows 1–4 and SEC-002 (BACKLOG.md ~4735); docs/audit/security.md "Hardening notes". Code map: see ledger.

## Global Constraints

- Repo rules in `CLAUDE.md` (root of repo) apply: sqlc only, no ad-hoc SQL in handlers; `gofumpt`, `golangci-lint run ./...` clean; errors wrapped.
- `docs/privacy.md` changes before the code that needs it.
- After any `openapi.yaml` change: `cd aaru-server-v2 && make generate`, `./scripts/generate-api-client.sh`, `cd aaru-client && npm run api:generate`. Commit generated output.
- Brand: colours only from tokens, no hex, `Font.aaruDisplay`; web UI only from `~/components/ui`.
- Swift lint is CI's: per package `swiftformat . --lint` and `swiftlint --strict --quiet`.
- Tests never use real keys; DB tests through `internal/testdb` (`AARU_REQUIRE_DB=1`).
- Words: "Sign out of other devices", "Report", "Terms of use".

## Rulings (controller, 2026-11-11)

- R1 Re-auth before delete: `DELETE /v1/me` succeeds only when the presenting session was created at most 10 minutes ago (`sessions.created_at`). Otherwise 403 with error code `reauth_required`. Clients then say "For your safety, sign in again, then delete your account" and offer "Sign in again" (signs out). Works for every sign-in method; no new column. Cost if wrong: one more sign-in for a rare action.
- R2 Sign out everywhere = sign out of OTHER devices: `DELETE /v1/auth/sessions` deletes every session of the user except the presenting one, returns 204. Keeps the user signed in here.
- R3 Sandbox: new config key `billing.accept_sandbox` (env `BILLING_ACCEPT_SANDBOX`), default false. When false, a transaction or notification whose environment is `Sandbox` grants nothing (purchase endpoint answers 409 `sandbox_refused`; notification is acknowledged and ignored). Plus is off sale and only subscriptions exist, so nothing live breaks; TestFlight Plus testing needs the flag set in infra values. Cost if wrong: TestFlight purchases do not unlock Plus until the flag is set.
- R4 Reports reach the owner: each saved report increments Prometheus counter `aaru_social_reports_total{reason}` and logs one line `social report saved` with report id and reason (no note, no user ids). The owner alerts on the counter in Grafana; reading a report stays a DB query documented in `docs/audit/security.md`. No admin UI.
- R5 Profile menu gets both Report and Block (App Store 1.2 needs both reachable from a person). Block reuses the existing block call.
- R6 Terms text is a draft for owner approval: plain, short, matching privacy.md's voice; contact `privacy@aaruapp.com`.

---

### Task 1: Docs (privacy first), terms text, backlog

**Files:** Modify `docs/privacy.md`, `docs/audit/security.md`, `BACKLOG.md`; Create `docs/terms.md`.

- [ ] privacy.md: sessions section says other devices can be signed out from Settings and deleting the account needs a sign-in in the last 10 minutes; reports section says a report is counted and logged by reason only and read by the owner.
- [ ] terms.md (R6): who may use Aaru (13+ or local digital-consent age), your account, your content and what you must not post (harassment, spam, illegal content, impersonation), reporting and blocking and what the owner does with reports (may remove content or close accounts), third-party catalog data credited and not Aaru's, Aaru Plus via Apple and Apple's EULA, no warranty, ending the account (Settings → delete), changes to terms, contact. Same Markdown shape as privacy.md (a `# Terms of use` heading, "Last updated 2026-11-11").
- [ ] security.md Hardening notes: mark the three SEC-002 minimum lines done with how (R1–R3); add "Reading reports" with the SQL `SELECT created_at, reason, note FROM social_reports ORDER BY created_at DESC LIMIT 50;`.
- [ ] BACKLOG.md release blockers table: row for group-message report → Done (7656bdbc), profile report → Done (this branch); board counts row → Done (dedb5a06); terms row → Done pending owner approval of text; SEC-002 minimum → Done (this branch, Sandbox behind `BILLING_ACCEPT_SANDBOX`). Update the matching status rows near BACKLOG.md:1037–1038 and add a decision line for R1–R4 dated 2026-11-11.
- [ ] Commit `docs: terms of use draft, privacy and backlog for the release blockers`.

### Task 2: Server

**Files:** `aaru-server/Sources/AppAPI/openapi.yaml`; `aaru-server-v2/internal/db/queries/auth.sql`; `internal/auth/{service,store}.go`; `internal/httpapi/auth.go`; `internal/config/config.go`; `internal/billing/{service,apple}.go` (+ wiring in app setup); `internal/social/service.go`; `internal/metrics` (wherever counters live); tests in `internal/httpapi/auth_test.go`, `billing_test.go`, `social_test.go`, `internal/config` tests.

- [ ] openapi: `DELETE /v1/me` documents 403 (`reauth_required`). New `DELETE /v1/auth/sessions`, operationId `signOutOtherDevices`, 204, 401. Purchase endpoint documents 409 `sandbox_refused`. Then the three generators.
- [ ] Queries: `SessionCreatedAt :one` (by token_hash, unexpired) and `DeleteOtherSessions :exec` (`user_id = $1 AND token_hash <> $2`). `make generate`.
- [ ] R1: test `TestDeleteAccountNeedsRecentSignIn` — session aged 11 minutes (update created_at in test via testdb) → 403 code `reauth_required`, user still exists; fresh session → 204. Inject a clock if the service has one; else compare in SQL with `now()`.
- [ ] R2: test `TestSignOutOtherDevicesKeepsThisOne` — two sessions, call with A → A still works on `GET /v1/me`, B gets 401; unauthenticated → 401.
- [ ] R3: config `billing.accept_sandbox` bool default false (config test). Test: Sandbox JWS (stub in `billing/apple_test.go`) with flag false → purchase 409 `sandbox_refused`, no entitlement; notification ignored with 200; flag true → granted as today. Production env unaffected.
- [ ] R4: counter `aaru_social_reports_total{reason}` and the log line; test the counter increments in `social_test.go` if metrics are testable there, else a unit test in the social package.
- [ ] `AARU_REQUIRE_DB=1 make test`, `golangci-lint run ./...`, `swift test --package-path aaru-api`, `cd aaru-client && npm run typecheck` all pass. Commit(s).

### Task 3: iOS and Mac

**Files:** `aaru-ios/Aaru/Social/FriendProfileView.swift` (+ model), `Board/ReportPostSheet.swift` (generalise noun to person), `Session/AuthFlow.swift`, the account settings page that has Sign out, `Settings/Pages/AboutView.swift`, `WelcomeView.swift`, `Plus/PlusPaywall.swift`.

- [ ] Profile toolbar menu: "Report" opens the report sheet with noun "person" (reason + note, calls `reportUser` with the profile's user id, note prefix `profile:@<handle>`), and "Block" with a confirm dialog, reusing `SocialModel` block; after block, pop the profile.
- [ ] Account settings: "Sign out of other devices" (confirm dialog, calls `signOutOtherDevices`, shows a done line).
- [ ] Delete account: on 403 `reauth_required` show the R1 message with "Sign in again" (runs sign out).
- [ ] Links: "Terms of use" → `https://aaruapp.com/terms` beside the privacy link in AboutView, and a small Terms · Privacy line on WelcomeView.
- [ ] `xcodebuild build … CODE_SIGNING_ALLOWED=NO` passes; swiftformat/swiftlint strict clean. Commit.

### Task 4: Web

**Files:** `aaru-client/src/routes/terms.tsx` (copy `privacy.tsx`), `components/LegalPage.tsx` (`LegalLinks` adds Terms), `routes/about.tsx`, `routes/_shell.app_.settings.about.tsx`, `routes/_shell.app_.friends.$handle.tsx`, `components/board/ReportPostDialog.tsx` (generalise to person), `lib/board/server.ts` or `lib/social` (report person, block), `components/settings/AccountPage.tsx`, `lib/session/session.ts` (sign out other devices server fn), `routes/_shell.app_.settings.delete.tsx` (R1 handling).

- [ ] `/terms` renders `docs/terms.md` like `/privacy`; Terms in `LegalLinks`, about page and settings About.
- [ ] Profile page: a menu with Report (dialog, kind person, note `profile:@<handle>`) and Block (confirm, then navigate to friends).
- [ ] Account page: "Sign out of other devices" with confirm and a done toast/line.
- [ ] Delete page: 403 `reauth_required` shows the R1 message with "Sign in again" (signs out to /sign-in).
- [ ] vitest for any new lib function (report person note, reauth error mapping).
- [ ] `npm run check && npm run lint && npm run typecheck && npm test && npm run build && npm run size` pass. Commit.
