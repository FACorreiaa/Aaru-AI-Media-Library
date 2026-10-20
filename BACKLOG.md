# Aaru backlog

Derived from `README.md`, `CLAUDE.md`, `ARCHITECTURE.md`, `DESIGN.md`, and `VIEWS.md`. This file is the ordered
work list. It does not introduce product decisions; where a decision is still open it is
marked **OPEN** and left for a human.

Scope of this file: Aaru only.

## How to read this

- IDs are stable. Never renumber. Close an item by moving it to **Done** with its ID.
- Work is grouped into **phases** (P0–P7). Each phase has an exit gate. Inside a phase,
  milestones (`M1`…`M14`) and groups keep their old IDs; order inside a group is dependency
  order. Do not start an item whose `Needs` is open.
- `Size`: S = under a day, M = 1–3 days, L = a week or more.
- Every item names a **Done when** condition that can be checked, not "implemented".
- Items marked **Deferred** exist so nobody re-litigates them. They are not v1 work.

Rules from `CLAUDE.md` that bound every item: Aaru is source of truth after import,
one-way imports, no conflict engine, no scraping, private by default, catalog layer and
library layer stay separate, external IDs stored whenever known, no second backend.

## Decisions recorded 2026-10-09

- Friends, activity, DMs, realtime, scrobbling, gamification, and watch-together are **no
  longer out of scope**. They are scheduled in P3–P6 and **do not start before the P2 gate**
  ("basics done").
- Web is `aaru-client/`: SvelteKit on Cloudflare Workers, a pure `/v1` client. The landing
  page is a route group inside it. `aaru-landing/` and `aaru-site/` are retired.
- **One backend.** Beta is client-side only: the TestFlight `.beta` app and the staging Worker
  both talk to the production API (Khepri pattern).
- **Anime is first-class from P1** (AniList catalog, `anilist`/`mal`/`anidb` external IDs).
- DMs are **Signal-grade (libsignal)**. Licence and web support are OPEN — see DM-003, DM-004.

## Decisions recorded 2026-10-20

- **Discover rows on Home (DISC-001), by the owner's call:** a new account opened to an empty
  Home. Home now also shows provider-curated public lists: trending shows, this season's anime,
  trending movies, on the air, trending anime, new shows, in theaters, trending books. They are
  the same for every user and read no per-user signal, so they are **not** the out-of-scope
  recommendations engine; nothing personalised ("because you watched…") is allowed under this
  item. Posters stay hotlinked catalog URLs.
- **Groups are built before the P2 gate**, by the owner's call, with 0 strangers (flagged; the
  owner chose). A group is a friends-only space with channels and a default `#general`, where
  members chat and can tag `@aaru`. Section `P4 · Groups` (GRP-001…GRP-012). Pulled forward with
  it: SOC-001 and SOC-002 in minimal form (handles, friends by handle, blocks, reports; no
  `social_settings`, invite links or email hash yet) and the groups subset of RT-001.
- **Group chat is server-visible**, labelled "not end-to-end" in every channel header, so the
  agent can read a channel when someone tags it. DMs stay E2E (DM-001…DM-005, unchanged). This
  resolves ROOM-002's OPEN item as "plain, clearly labelled".
- **Membership is friends-only.** You can invite only an accepted friend, and neither side may
  have blocked the other. There are no invite links to groups and no public or discoverable
  groups.
- **Channel kinds:** `text`, `title` (a thread about one title, with a spoiler guard), `watch`
  (absorbs ROOM-001) and `shelf` (a group list; absorbs SHR-001's collaborative editing).
- **The agent posts in a group only as a reply to an explicit `@aaru` mention.** It uses
  read-only tools and catalog components, reads only the tagger's own library, and has no write
  path. It never starts a thread, DMs, or sends friend requests or invites (`VIEWS.md`).

## Decisions recorded 2026-10-19

- **Episodes and Stremio are built before the P2 gate**, by the owner's call, with 0 strangers
  (flagged; the owner chose). Episodes first: stills and synopses on title detail, real anime
  episode names (CAT-010), a scheduled show refresh that also loads imported shows (JOB-001's
  second kind), and the title room (`SeasonMap` + an episode sheet) on iOS, Mac and the web.
- **Un-deferred for Stremio:** OUT-001 (minimal: `kind = stremio` tokens only, no AG-001 tool
  layer, no OAuth), OUT-002 (minimal: the token named on journal rows), SCR-001 as a service
  only, and SCR-003. `POST /v1/scrobble/*` HTTP routes wait for SCR-002 or the first bridge.
- **Stremio sends playback events now.** stremio-core PR #1070 (merged 2026-10-02, core-web
  v0.64) lets an addon declare `player` and `library` resources and receive plain GETs:
  `player/{type}/{videoId}/action=start|pause|stop&currentTime=ms&duration=ms.json` and
  `library/{type}/{metaId}/action=libraryAdd|libraryRemove|watched|unwatched[&videoId=…].json`.
  Confirmed on Stremio Web and Stremio 5 desktop; Android and iOS unverified. This closes
  SCR-003's OPEN item: the addon serves catalogs plus `player` and `library` events. No
  subtitles-request inference, no Trakt re-read (that is two-way sync), and **no `stream`
  resource, ever**.
- The addon lives at `/stremio/{token}/…` outside `/v1` (the protocol fixes the paths). Its
  token has `library:read` + `scrobble:write`; `library:write` is opt-in and only admits
  `unwatched` and `libraryAdd`. `libraryRemove` is always ignored: Aaru is the source of truth.

## Decisions recorded 2026-10-16

- **The Recap (GAM-006a) is built before the P2 gate**, by the owner's call, with 0 strangers.
  It is a Spotify Wrapped-style story for a month or a year, on iPhone, Mac and the web
  together. It reads the library, not the points ledger, so it no longer needs GAM-001. Profile
  stats, genres and badges (GAM-006b) stay in P5.
- **Imported history is not activity.** An episode tick written by an import or restored by an
  undo has no real watch date (`episode_progress.watched_at_known = false`), so the Recap leaves
  it out. A dated finish from an import (Letterboxd, Goodreads, MAL, Trakt movies) counts on its
  day.

## Decisions recorded 2026-10-15

- **Airing-episode push notifications move into P2** (by the owner's call; was SOC-005 in P4): an
  APNs key, `apns_devices` with environment (beta/sandbox and release/production share one API),
  a notifications setting, and a scheduled job that sends "New episode of X" once per episode for
  shows the user follows. Web push is not part of it.
  **Progress:** built. Server: `PUT /v1/devices`, `DELETE /v1/devices/{token}`, `GET`/`PUT
  /v1/me/notifications`; an in-process job every 10 minutes announces each newly aired episode of an
  `in_progress` show once (claimed in Postgres first), skipping watched episodes and anything that
  aired before the user turned alerts on; dead tokens are forgotten. Config `APNS_KEY_ID`,
  `APNS_PRIVATE_KEY` (sealed), `APNS_TEAM_ID`. iOS: a "New episodes" switch in Settings asks
  permission, registers the token (Debug → sandbox, TestFlight/App Store → production), and
  sign-out forgets the device. Mac push is not on yet (it needs its own entitlement key).
  Episodes come from what is already hydrated; a scheduled show refresh is still JOB-001 work.
- **Sign in with Google is un-deferred** (AUTH-005, by the owner's call): iOS, Mac and web, Google ID
  tokens verified server-side against Google's JWKS, identities keyed on Google's `sub`, never
  merged on email; linking Google to an existing account from Settings.
- **Sign in with Apple on the web** needs an Apple Services ID on a verified domain: waits for the
  domain. The iOS/Mac apps already have it.
- **Media scope widens** (by the owner's call): Aaru should track as many kinds of media as it
  can, not only movies, shows, anime and books. Scheduled after the P2 gate, in this order:
  **manga** (cheapest: AniList already serves it, books-style progress by chapter/volume),
  **music** (albums as the tracked unit; MusicBrainz + Cover Art Archive as the catalog, no key,
  1 req/s with a contact User-Agent; ListenBrainz/Last.fm history as an import source), then
  comics and games as candidates. Each new kind is a `MediaType` in `AaruCore`, a catalog
  adapter, a status vocabulary that still maps onto the four statuses, and an entry in
  `CLAUDE.md`'s stack table. Music stays out of the calendar and episode progress.
- **Connectors the owner wants, all already scheduled** (recorded so they are not lost):
  **Trakt** — import in P2 (IMP-002 connect, IMP-003 worker), one-way history push out in P3
  (SCR-004, MOAT-003); never two-way. **Stremio** — the catalogs-only addon in P3 (SCR-003,
  MOAT-001), no `stream` resource. **Claude** — OUT-004's `/v1/mcp` endpoint, added to Claude
  as a custom connector. A remote connector in Claude authenticates with OAuth per the MCP
  authorization spec (authorization-server metadata, dynamic client registration, PKCE), so
  OUT-004 also needs an OAuth front door that mints the same scoped agent tokens as OUT-001;
  a pasted bearer token alone is not enough for claude.ai.

## Decisions recorded 2026-10-14

- **The web client is SolidJS + TanStack Start** on Cloudflare Workers (replaces SvelteKit), and
  it mirrors the Apple apps feature for feature: whatever ships on iPhone and Mac ships on the
  web in the same phase. Paraglide i18n was dropped with SvelteKit; the apps are English-only
  too, so translation returns for all clients together.
- Sign in with Google is deferred (AUTH-005).

## Decisions recorded 2026-10-10

- More free catalog sources are scheduled in **P2 · Catalog sources** (PRV-001, CAT-011…CAT-017):
  TVmaze air times, Google Books fallback, Wikidata cross-ids, TMDB watch providers, the
  anime-offline-database, and — after the P2 gate — OMDb and Fanart.tv.
- **Trakt API access is OPEN** (IMP-002): app creation reportedly became VIP-only in mid-2026.
  **Resolved 2026-10-16:** the owner created the "Aaru" Trakt app (no VIP needed); its Client ID
  is configured on `maat` with PKCE and no client secret. First real connect is the proof.

## Status snapshot (verified 2026-10-09)

| Area | State |
| --- | --- |
| `aaru-core` | Domain model present: `Title`, `LibraryItem`, `Progress`, `Rating`, `ExternalIDs`, `MediaRef`, `AaruList`, `ImportJob`, `TitleMatching`, `Episode`, identifiers, validation. ~32 tests: validation, rating, matching, external IDs, wire contract, Codable round-trip. No anime IDs, no user/social types. |
| `aaru-server` | Hummingbird skeleton. Fluent + Postgres configured in `App+build.swift`, migrations gated behind `db.migrate`. **Zero migrations registered.** `openapi.yaml` is still the generator template (`getHello`). A template WebSocket echo is wired at `/ws`. CI sits in `aaru-server/.github/workflows/` and therefore never runs. |
| `aaru-client` | Fresh `sv create` template: Svelte 5, Kit `next`, adapter-cloudflare, Tailwind 4, Paraglide (en/es/pt), Storybook, Vitest, Playwright. Untracked. No Aaru code. |
| `aaru-ios` | Empty directory. No Xcode project. |
| Release | No fastlane, no TestFlight lane, no infra entry, no Worker deploy. `swiftly.pkg` (10 MB) committed at repo root. |
| Auth, search, library, lists, imports | None of it exists. |

So the real starting line is P0.

### P0 progress (2026-10-09, branch `p0-rails`, not yet pushed)

| Item | State |
| --- | --- |
| SRV-001…SRV-008 | Built; 13 server tests pass against local Postgres; `--db-migrate` verified from the CLI. |
| SRV-009, REL-001 | Root workflows written (`ci-swift`, `ci-apple`, `ci-web`); all checks pass locally. Unverified on GitHub until pushed. |
| REL-002 | Done. |
| REL-003 | Project builds for iOS Simulator and macOS; Beta/Release settings resolve. Side-by-side install on a device needs App IDs registered and real icons. |
| REL-004 | Lanes and workflows written. Needs ASC records, App IDs, secrets, and one Seed signing run. |
| REL-005 | Image builds from the repo root and was smoke-tested locally (migrate, fail-fast, health 200); promote workflow written; infra draft PR LuminaVault/LuminaVaultInfra#292. Needs `TMDB_API_KEY` sealed, first image tag, `/data/pg-aaru` on the node, `INFRA_TOKEN`, and the domain. |
| REL-006 | Workers configs + deploy workflow written; check/lint/test/build pass locally. Domain `aaruapp.com` (Cloudflare, 2026-10-15): prod Worker on `aaruapp.com` (+ `www` → apex 301), beta on `beta.aaruapp.com`, no `workers.dev`; security headers in `src/start.ts`. Needs `CLOUDFLARE_API_TOKEN` + `CLOUDFLARE_ACCOUNT_ID` (token also needs Workers Routes + DNS edit on the zone for the custom domains). |

### P1 progress (2026-10-09, branch `p1-basics`, stacked on `p0-rails`, not pushed)

Server side of P1 is built: 62 server tests and 37 core tests pass against local Postgres,
with every provider stubbed.

| Group | State |
| --- | --- |
| M2 Auth (AUTH-001…004) | Done. Email sign-in answers 503 until `RESEND_API_KEY` and a verified sending domain exist. |
| M3 Catalog (CAT-001…009) | Done. CAT-010 (load the anime mapping dataset) is open: `anime_mappings` is empty until then. |
| M4 Library + journal (LIB-001…004, AUD-001/002) | Done. Journal pruning (90 days / last 20) waits for JOB-001. |
| M5 Progress (PROG-001…004) | Done. |
| M6 Lists + shelves (LST-001/002, SHF-001/002) | Done. List writes are journaled and undoable. |
| CAL-001, UPN-001 | Done. Network comes from TMDB's first network / AniList's first streaming link (2026-10-15); TVmaze (CAT-011, built 2026-10-16) refines TMDB dates to exact times and the network; its CC BY-SA credit still needs the About screen (PRV-001). Shows hydrate when added; refreshing every tracked show on its staleness window needs a job (JOB-001). |
| Account export | Built 2026-10-16: `GET /v1/me/export` (JSON: everything incl. watched episodes, lists, shelves; CSV: one row per item in the generic-import columns, so it re-imports; formula cells defused). Settings → Export your data on iPhone/iPad/Mac (save panel) and web (`/app/export`, native download). Privacy policy updated. |
| IMP-013, IMP-014 | Built 2026-10-16: MyAnimeList XML upload (`source=mal`, `application/xml`; clients gunzip `.xml.gz`) and AniList by username (`POST /v1/imports/anilist`, read in the worker; private list / unknown user fails with a clear message). Both resolve through AniList, so the same anime from both is one title. Also (owner's ask): `source=auto` detects MAL-format XML / IMDb / Letterboxd / Goodreads, and any other CSV imports by its column names (title, year, type, IMDb/TMDB/TVDB/MAL/AniList ids, ISBN, status words, ratings on 5/10/100 scales). IMP-012 TV Time still waits for real exports. |
| PRV-001, LAND-003 | Built 2026-10-16: `docs/providers.md` (register) and `docs/privacy.md` (policy, rendered at `aaruapp.com/privacy`); `/about` and the Apple About screen show the TMDB logo + notice, TVmaze (CC BY-SA), AniList, Open Library. `privacy@aaruapp.com` needs Cloudflare Email Routing. No self-serve export yet (policy says "ask us"). |
| APP-009 Home rows | Built 2026-10-16 on iPhone, iPad, Mac and web: Home is the first destination (Home · Library · Calendar; web library moved to `/app/library`). Continue watching (one-tap check advances optimistically), Airing soon / Coming up (badges from `airTimeKnown`), Start watching. Apple renders from a disk cache first; the web has no offline cache yet. In-progress movies are not in Continue watching (server returns shows only). Checked with sample data only. |
| WID-001…004, WID-006 | Built 2026-10-16 (iOS + macOS, one extension): App Group snapshot (`Shared/WidgetSnapshot.swift`) written after every Home load and tick, an hourly `BGAppRefreshTask` on iOS, cleared on sign-out. Up Next (small/medium/large) with an interactive "mark watched" App Intent that calls the same PUT with the shared Keychain token, advances optimistically and restores on failure; Next Episode countdown (small + Lock Screen accessories on iOS; entries at each air time flip to "Out now"); This Week (large/extra large, Monday-first, deep links `aaru://title/{id}`). Not yet seen on a device; no undo ribbon for widget ticks; the large Up Next has no progress bar (the snapshot has no episode totals). WID-005 (Live Activity) is next. |
| WID-005 | Built 2026-10-19 (iOS only, client-side; no server change): "Start watching" from an aired episode's context menu in title detail and from Home's Continue watching card starts a `NowWatchingAttributes` Live Activity (one at a time; poster downsampled into the App Group). Lock Screen + Dynamic Island: poster, `S1 · E8 · Name`, progress bar, "Ends at" ↔ "Nm left" via `ToggleEndTimeIntent`, "Mark watched" via `MarkNowWatchingIntent` (same PUT and widget path as the Up Next check). Stale after end + 30 min ("Did you finish?"), ended on app foreground and in the background refresh; ticking that episode anywhere ends it with a brief "Watched". Started by check-in only; scrobble start is P3. Not yet run on a device. |
| DISC-001 Discover rows | Built 2026-10-20 on iPhone, iPad, Mac and web: `GET /v1/discover` returns up to eight public rows (TMDB trending/on the air/new shows/trending movies/in theaters, AniList this season + trending, Open Library weekly trending), cached in memory for 6 h, a failing provider dropping only its row; items the caller has carry `libraryItemId`. Home renders them under the user's rows; a new account sees a slim "Add a show" header above them. Adding from a card is search's add (wishlist, or a status, or a list). TMDB rows checked with stubs only (no local key); AniList and Open Library checked live. |
| APP-010 + catch-up month | Built 2026-10-15 on iPhone, iPad, Mac and web: Calendar destination with Week (CAT grid / iPhone day pager) and Month (Stremio-style posters + agenda). Server adds `backdropUrl`, `network`, `airTimeKnown`, `episodeOverview`; range up to 42 days. Checked with sample data only. |

**P1 gate** (works end to end against the production API on `maat`) is not met until P0's
deploy steps are done.

---

## Phase map

| Phase | Groups | Exit gate |
| --- | --- | --- |
| **P0 — Rails** | REL, M1 server foundation | CI green from repo root; empty app builds to TestFlight beta; API image deploys to `maat` via promote PR; web Worker deploys |
| **P1 — Basics (API)** | M2 auth, M3 catalog + anime, M4 library, M5 progress, M6 lists, Calendar + Up Next | A personal tracker works end to end over `/v1`: sign in, search movies/shows/anime/books, add, tick episodes, lists, calendar, up next |
| **P2 — Clients, widgets, imports** | M7 iOS + Mac, Widgets, M10/M11 web, M8 Trakt, M9 file imports, catalog sources | **The "basics done" line.** TestFlight beta and the beta Worker are usable by a stranger end to end; widgets work; Trakt + CSV imports work |
| **P3 — Tracking integrations** | Scrobble, Stremio, Plex/Jellyfin, outbound Trakt/MAL/AniList | A play in Plex, Jellyfin or Stremio moves Aaru progress without a tap |
| **P4 — Social** | Profiles, friends, activity, push, shared lists, groups | Two users can friend, see each other's activity, and block cleanly; friends chat in a group |
| **P5 — Gamification** | Points ledger, levels, streaks, badges, leaderboard, stats | Points and streaks are idempotent and survive replays and undo |
| **P6 — Realtime, DMs, watch together** | WebSocket gateway, libsignal DMs, rooms, SharePlay | E2E DMs between two devices; a room counts down and checks off together |
| **P7 — Agent surfaces** | M13 agent, M14 outbound agent | As written in M13/M14 |

**Hard rule:** no P3–P6 code before the P2 gate. Social and gamification on a library nobody
has used is supply-side polish. Exceptions by the owner's call are listed in the decisions
above (Recap, Episodes and Stremio, Discover, Groups).

Native clients (M7) come before importers (M8) per the build order in `CLAUDE.md`: a
library you cannot see is not testable. M8 can start in parallel if two people are
working, but M7 is the gate for "usable". Web (WEB-001) ships alongside native in P2.

---

# P0 — Rails

## P0 · Release rails

Templates: Khepri (`apps/north/north-ios-app/khepri/{fastlane,Config,.github/workflows}`) for
iOS, Norviq/Skyvisor entries in `platform/infra` for the server, LuminaVaultWebApp for the
Worker. All infra work happens in `~/Work/production/platform/infra` — never in an app-local
`*-infra` copy.

### REL-001 · CI from the repo root · S
GitHub only runs workflows from the repo root. Move `aaru-server/.github/workflows/ci.yml` to
`.github/workflows/` and split jobs: `core` (`swift test --package-path aaru-core`), `server`
(with a Postgres service container), `web` (`npm ci && npm run check && npm run lint &&
npm run test:unit -- --run` in `aaru-client`), `apple` (`xcodebuild build` for iOS + macOS,
added once REL-003 lands). Path filters so a web change does not run Swift jobs.

**Done when:** a PR touching only `aaru-client/` runs only the web job, and the old nested
workflow file is gone.

### REL-002 · Remove `swiftly.pkg` from git · S
A 10 MB installer is committed at the repo root. Delete it and ignore `*.pkg`.

**Done when:** `git ls-files '*.pkg'` is empty. History rewrite is **not** part of this item.

### REL-003 · Xcode project with Beta and Release configs · M
**Needs:** nothing.
Plain `.xcodeproj` in `aaru-ios/` (siblings use no generator), one multiplatform app target
(iOS + macOS), a widget extension (`AaruWidgets`), and a `Shared/` group for App Intents used
by both. `Config/Base.xcconfig` includes a git-ignored `Secrets.xcconfig`.

- Configurations `Debug`, `Beta`, `Release`. Beta bundle id is the prod id + `.beta`;
  extensions follow (`….beta.widgets`). Separate scheme "Aaru Beta".
- `APP_GROUP_ID = group.$(PRODUCT_BUNDLE_IDENTIFIER)`; keychain access group shared with the
  widget for the session token.
- `API_BASE_URL` is the **production** API in every config except `Debug` (localhost). One
  backend, per the 2026-10-09 decision.
- Depends on `AaruCore` by local path.

**Done when:** Beta and Release install side by side on one device with different icons/names,
and both the app and the widget read the same App Group container.

### REL-004 · fastlane lanes and release workflow · M
**Needs:** REL-003, REL-001.
Copy Khepri's lanes: `seed_signing` (match), `beta` (match appstore, build number from App
Store Connect, `upload_to_testflight` internal only), `release`, `hotfix`. `release.yml`
runs `beta` on `workflow_run` after the apple CI job passes on `main`, and `release` on manual
dispatch. Secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `MATCH_*`, `SECRETS_XCCONFIG`.
macOS ships through the same lanes (TestFlight for Mac).

**Done when:** a merge to `main` produces a TestFlight build of the Beta app for iOS and Mac
with no manual step, and `release` is never triggered by a push.

### REL-005 · Server deploy on `maat` · M
**Needs:** SRV-008, REL-001.
Read `platform/infra/docs/deployment.md` ("Adding a new app") first.

- CI builds `ghcr.io/<org>/aaru-server:<sha>` and opens a promote PR in the infra repo that
  sets the tag in `apps/aaru/api/values-production.yaml`. Merging the PR is the deploy.
- `argocd/apps/aaru-api-production.yaml` and `aaru-data.yaml` on `charts/norviq-app`.
- Postgres StatefulSet + static PV + backup CronJob, modelled on
  `apps/norviq/data/postgres.yaml`. One database, one app role.
- Namespace `horus`. Add the API and its DB to `cluster/network-policies/horus.yaml`
  (default-deny ingress — a missing rule looks exactly like the service being down).
- Sealed secrets (`TMDB_API_KEY`, JWT key, DB URL, …) sealed for `horus` **and** the exact
  secret name, plus a `*.example.yaml` key template. See `platform/infra/secrets/README.md`.
- Public ingress `api.<domain>` via Traefik + cert-manager; Cloudflare DNS grey-cloud.

**Done when:** `curl https://api.<domain>/v1/health` returns 200 from the cluster, a new image
only reaches production through a merged promote PR, and no file under `apps/aaru/` holds
infra.

**OPEN:** the domain. Nothing is registered yet.

### REL-006 · Web Workers: beta and prod · S
**Needs:** REL-001.
`aaru-client/wrangler.jsonc`: the production Worker plus `env.staging` (beta). Both point
`API_BASE_URL` at the production API. CI builds with `CLOUDFLARE_ENV=staging` for beta and
deploys with `wrangler deploy`: staging on every merge to `main`, prod on manual dispatch.

**Done when:** a merge to `main` updates the beta Worker URL, and prod moves only on dispatch.

### DSN-001 · ScreensDesign pass on tracker apps · S · optional
The ScreensDesign MCP research tools need a Pro plan (blocked on 2026-10-09). If it is bought,
pull screens and flows for Trakt, TV Time, Serializd, Sequel, Letterboxd and AniList clients
and attach findings to `DESIGN.md`.

**Done when:** `DESIGN.md` cites at least one recorded flow per surface it borrows from.

## P0 · M1 — Server foundation

### SRV-001 · Delete template scaffolding · S
The generator template left `getHello` and a WebSocket echo router at `/ws`. Realtime is P6
(RT-001), built properly behind auth; an unauthenticated echo must not ship before then.

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

**Decided 2026-10-09:** cursor keyed on `(updated_at, id)`, because library sync from a client wants "changed since" anyway.

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

**Done when:** `swift run aaru --db-migrate` creates both tables against the
docker-compose database and is re-runnable without error.

### SRV-005 · Migration 002: titles and episodes · M
**Needs:** SRV-004.
`titles` with partial unique indexes on each external ID where not null. TMDB and Trakt
number movies and shows separately, so `tmdb` and `trakt` are unique per `(type, id)`;
`imdb`, `tvdb`, `isbn`, `open_library`, and the CAT-008 anime ids (`anilist`, `mal`, `anidb`)
are globally unique; `show_episodes (title_id, season, episode,
air_date?, tmdb_episode_id?)` unique on `(title_id, season, episode)`.

**Done when:** inserting two titles of the same type with the same non-null `tmdb` id fails
at the database level, and two titles with null `tmdb` ids both insert.

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
**Needs:** SRV-004, REL-001.
The root workflow from REL-001 must run `swift test` for both packages with a Postgres
service container, plus `swiftformat --lint` and `swiftlint`.

**Done when:** CI fails on a deliberately misformatted file and on a failing migration.

---

# P1 — Basics (API)

Server-first. Every item here is reachable over `/v1` before any client screen exists.

## P1 · M2 — Auth

### AUTH-001 · Session model and middleware · M
**Needs:** SRV-004, SRV-008.
Server-issued session (JWT or opaque bearer, one choice, written into `ARCHITECTURE.md`).
Reuse, do not reinvent: `apps/lumina/LuminaVaultServer/Sources/App/Auth/` has a working
Hummingbird `JWTAuthenticator`, `JWTKeyLoader`, and `AppleOAuthProvider` (app-ID and
Services-ID audiences, which the web Sign in with Apple needs).
Auth middleware resolves the token to a `userId` and puts it in the request context.
Every `/v1` route except health and auth requires it.

**Done when:** a request without a token to any library route returns 401 in the shared
error shape, and a request with a token for user A cannot read user B's rows (test asserts
this, not a comment).

**Decided 2026-10-09:** opaque token in Postgres with a `sessions` table (was OPEN). Revocation matters more than statelessness at this scale, and the
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

**Decided 2026-10-09:** magic link, sent through Resend (was OPEN). It removes password storage,
reset flows, and breach surface; the cost is an email sender dependency.

### AUTH-004 · Sign out and account delete · S
**Needs:** AUTH-002 or AUTH-003.
`DELETE /v1/auth/session` and a full account delete that removes library items, progress,
lists, jobs, and stored provider tokens.

**Done when:** after account delete no row anywhere references the user id, and the
deletion is covered by a test that counts rows in every user-scoped table.

### AUTH-005 · Sign in with Google · M
Not before the web client (WEB-001) is live. On Apple devices, Sign in with Apple already
covers it (App Store 4.8 requires Apple sign-in whenever Google is offered, and Aaru has it),
and email magic links cover everyone else. **Trigger:** sign-in funnel data from the web
client shows Android/Windows visitors leaving at sign-in.

When it starts: verify Google ID tokens server-side with the same JWKS verifier as Apple, add a
Google OAuth client and consent-screen brand verification, and decide **account linking** first
— Apple often hides the email behind a private relay, so the same person signing in with Apple
then Google becomes two accounts unless identities can be linked from a signed-in session.

**Done when:** a user who signed in with Apple can link Google from settings and then sign in
with either into one account, and signing in with an unlinked Google account never merges
into an existing account on email alone.

**Progress (2026-10-15):** server done. `POST /v1/auth/google {idToken, nonce?}` verifies the
ID token against Google's JWKS (shared cache with Apple; `iss`, `aud` ∈ `GOOGLE_CLIENT_IDS`,
`exp`, nonce when sent) and signs in or creates the account keyed on Google's `sub`; the email
is kept only when Google marks it verified. `POST /v1/me/identities/google` links Google to the
signed-in account; a Google account already on another user is a 409, never a merge. Without
`GOOGLE_CLIENT_IDS` both routes answer 503. Clients: the Google OAuth clients exist (iOS for
`com.fernandocorreia.aaru`, iOS for `.beta`, web). iOS/Mac sign in through the OAuth code flow
with PKCE in the system sheet (no Google SDK; Debug/Beta use the beta client, Release the main
one) and Settings offers "Link Google account"; the web uses Google Identity Services' button on
sign-in and in Settings (`GOOGLE_CLIENT_ID` Worker var). Every deployed web origin must be listed
on the web client.

---

## P1 · M3 — Catalog and search (movies, shows, anime, books)

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
`q` and `type=movie|show|anime|book` (`anime` is a search scope over the AniList adapter,
see CAT-008). Fan out with structured concurrency when type is absent —
**Decided 2026-10-09:** `type` is required in v1 (was OPEN). Mixed-type ranking
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

**Decided 2026-10-09:** 24h for shows with an episode airing within 30 days, 30d otherwise.

### CAT-007 · AniList adapter · M
**Needs:** CAT-001.
Anime catalog from AniList GraphQL (`graphql.anilist.co`; reads need no key, ~90 req/min — goes
through the central rate limiter per X-002). Search, detail, episode count, `airingSchedule`,
and AniList's own cross-IDs (`idMal`). AniDB ids come from community mapping data where
available, never from scraping AniDB.

**Done when:** searching a known anime returns `CatalogHit`s carrying `anilist` and `mal` ids,
and no AniList field name appears in a response DTO.

### CAT-008 · Anime in `AaruCore` · M
**Needs:** CAT-007.
`ExternalIDs` gains `anilist`, `mal`, `anidb`; `titles` gains partial unique indexes on each
(migration alongside SRV-005 if it has not shipped, else its own migration). `Title` gains an
anime marker; search gains the `anime` scope.

**Decided 2026-10-09:** an `isAnime` facet on `movie`/`show`, not a fourth `MediaType`.
Anime series then reuse `ShowProgress`, `show_episodes`, calendar, Up Next, and every widget
with no second code path; anime films are movies with the flag.

**Done when:** an anime series added from the `anime` scope ticks episodes through the same
PROG routes as any show, and the `wire contract` test in `AaruCore` covers the new ids.

### CAT-009 · Anime matching rules · M
**Needs:** CAT-005, CAT-008.
AniList and TMDB model seasons differently (AniList often has one entry per cour/season; TMDB
one show with seasons). Resolution maps AniList entries onto a TMDB show + season when a
cross-ID exists and keeps them as separate titles otherwise. Never merge on name.

**Done when:** a multi-cour series with a known TMDB mapping resolves to one `Title`, one
without a mapping stays separate, and no two titles merge on title similarity alone.

### CAT-010 · Load the anime mapping dataset · S
**Needs:** CAT-009.
`anime_mappings` is empty until filled. Load the community AniList → TMDB/TVDB/MAL/AniDB
mapping (Fribb/anime-lists, MIT: AniList, MAL, AniDB, TVDB, TMDB, IMDb ids) with a one-shot
`aaru --anime-mappings <file>` run, and refresh it monthly. Where Fribb has no row, fill from
manami-project/anime-offline-database (ODbL 1.0: attribution and share-alike on the derived
table, recorded in PRV-001). Catalog data only: no user rows, no scraping. No key needed.

**Done when:** a mapped AniList id from the dataset resolves to its TMDB show in production,
and re-running the load is idempotent.

**Progress 2026-10-20:** built. `aaru --anime-mappings <path|url|default>` loads Fribb's
`anime-list-full.json` in one transaction (20,874 AniList rows, 6,958 with a TMDB show on
2026-10-20); re-running changes nothing. Only TMDB TV ids are kept (films would attach to the
wrong show). anime-offline-database stays out until Fribb's gaps are measured (its ODbL
share-alike is a real duty). Unmapped anime now get episode names from AniList's
`streamingEpisodes` titles. Still to do: the monthly CronJob in the infra repo, and the first
production load.

---

## P1 · M4 — Library

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

**Decided 2026-10-09:** keep 90 days of journal rows, and the last 20 per user forever. The prune
runs as a job, so it lands with JOB-001; until then nothing is deleted.

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

## P1 · M5 — TV and anime progress

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

**Decided 2026-10-09:** yes for shows TMDB reports as `Ended`/`Canceled`, no otherwise.

### PROG-004 · Book progress · S
**Needs:** LIB-003.
Optional `page` / `percent` on `Progress`. No scrobble positions.

**Done when:** setting `percent` outside 0–100 is rejected, and page and percent cannot
disagree silently (store one, derive the other only if total pages is known).

---

## P1 · M6 — Lists

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

## P1 · Calendar and Up Next

What the Trakt home rows, the Pogdesign-style week grid, and every widget read. Derived,
never stored as user truth.

### CAL-001 · `GET /v1/calendar?from&to` · M
**Needs:** PROG-003, CAT-006, CAT-007.
Airing episodes for the caller's tracked shows and anime in a date range (max 35 days): title,
season, episode, episode name, network/platform, air time in the caller's timezone, watched
flag, and `kind` (`premiere` | `finale` | `regular`). TMDB air dates plus AniList
`airingSchedule` for anime. Same window drives the week grid and the calendar widget.

**Done when:** a week query returns one row per airing episode of a tracked show, sorted by air
time in the requested timezone, with a premiere and a finale flagged, in one query plan (no
N+1).

### UPN-001 · `GET /v1/up-next` · M
**Needs:** PROG-003.
Continue Watching: for each `in_progress` show/anime, the next unwatched aired episode, its
runtime, remaining count and remaining runtime ("10 left · 8h 40m"), and a finale flag. Start
Watching: `wishlist` items, newest first. Movies in progress with a stored position (P3) report
time left.

**Done when:** ticking the next episode moves the row to the following one, a show with every
aired episode watched drops out until a new episode airs, and the response is one call for the
whole home screen.

**P1 gate:** a personal tracker works end to end over `/v1` against the production API on
`maat`: sign in, search movies/shows/anime/books, add, tick, list, calendar, up next.

---

# P2 — Clients, widgets, imports

The "basics done" line. Nothing in P3–P6 starts until this phase's gate is met.

## P2 · M7 — iOS and Mac client

One multiplatform SwiftUI target. If a split ever happens, shared views go through
`AaruCore` plus a thin UI module — never copy-paste.

### APP-001 · App skeleton and API client · L
**Needs:** AUTH-002, SRV-002, REL-003.
Builds on the REL-003 project in `aaru-ios/`, depends on `AaruCore`.
**Decided 2026-10-14:** a generated client in its own package, `aaru-api/` (`AaruAPI`), not in
`AaruCore`. The generator output is committed (no build plugin for Xcode or fastlane to trust)
and CI fails when it drifts from `openapi.yaml`, so the DTOs cannot fork. `AaruAPI` gains an
`AaruCore` dependency when the first screen maps wire types onto domain models.

**Done when:** the app builds for iPhone and Mac from one target, and a 401 anywhere routes
the user to sign-in exactly once (no retry storm).

**Progress 2026-10-14:** done. `SessionMiddleware` attaches the bearer token and reports a
rejected token once however many requests were in flight (tested with 12 concurrent 401s, no
retries); `SessionStore` routes `RootView` back to the welcome screen. Debug and Beta builds
show the API's health in the welcome footer; verified "API ok" against a local server in the
iPhone 17 Pro simulator. The token lives in memory until APP-002 moves it to the Keychain.

### APP-002 · Sign in · M
**Needs:** APP-001, AUTH-002.
`WelcomeView` (DESIGN.md §0) already exists with both buttons; this item replaces its "next
beta" notice with the real flow (and the system `SignInWithAppleButton`).
Sign in with Apple, plus the email path. Token in Keychain, shared correctly on Mac.

**Done when:** the session survives app relaunch on both platforms and sign-out clears the
Keychain item.

**Progress 2026-10-14:** built. The system Sign in with Apple button sends Apple's identity
token and the raw nonce (its SHA-256 goes to Apple) to `/v1/auth/apple`. The email path works
without a domain: every sign-in email now carries a 6-digit code next to the link, and
`/v1/auth/email/verify` takes `{email, code}` as well as `{token}` (migration
`AddMagicLinkCodes`; codes are stored hashed with their email, five wrong codes lock the link,
and using either the code or the link kills both). The token lives in the Keychain (this
device only, the iOS-style keychain on macOS too); sign-out ends the server session when it
can and always clears the Keychain. The app gained the `com.apple.developer.applesignin`
entitlement. **Not yet verified on a device:** relaunch persistence and a real Apple sign-in
need a signed build, a live API (infra #292) and `RESEND_API_KEY` for email. Universal links for
the emailed link wait for the domain.

### APP-003 · Library screen · L
**Needs:** APP-001, LIB-002.
Filter by type (movie / show / anime / book) and status. Poster grid and list modes. Last successful fetch is displayed
offline; no offline write queue in v1.

**Done when:** launching in airplane mode shows the last library instead of an error
screen, and 1,000 items scroll without image-loading jank.

**Progress 2026-10-14 (all three clients):** built. The library comes from `/v1/library/sync`
(everything the first time, then only changes) and is filtered on the device: All, Films,
Shows, Anime, Books, plus status; poster grid or list (remembered). iOS/macOS cache the last
sync on disk (cleared on sign-out) and show it with an "Offline" note when the server cannot be
reached; posters stay in a 512 MB URL cache. Verified in the simulator: online sync, then the
same shelf with the API down. The web reads the same sync on each visit (no offline mode: the
page itself needs the Worker). **Not measured yet:** 1,000-item scrolling.

### APP-004 · Search and add · M
**Needs:** APP-003, CAT-004, LIB-001.
Type-scoped search, debounce, add with initial status.

**Done when:** adding from search updates the library screen without a full refetch, and a
double-tap on add does not create two items.

**Progress 2026-10-14 (all three clients):** built. Films/Shows/Anime/Books scopes, 300 ms
debounce (a new keystroke cancels the pending request), Add (Wishlist) or add as In progress /
Finished. The added entry is inserted into the shelf directly, no refetch; hits already on the
shelf show "On your shelf" by any shared provider id. A second tap while adding waits, and the
server returns the existing item for a repeat add. Verified on the web against a local server
(AniList and Open Library, which need no key): a double-click added one item, an In progress
add kept its status, the shelf updated in place. The iOS search screen builds and shares the
same calls but was not driven in the simulator.

### APP-005 · Title detail · L
**Needs:** APP-003, LIB-003, PROG-003.
Status, rating, notes, owned toggle, and for shows the season/episode list with ticks.

**Done when:** an episode tick is optimistic in the UI, reconciles with the server response,
and rolls back visibly on failure.

**Progress 2026-10-15 (all three clients):** built. Status, 5-star rating (two points a star on
the 1–10 scale), owned, notes, page for books, synopsis; for shows, seasons (specials last) with
a tick per episode and "Mark watched" per season; unaired episodes cannot be ticked. Every write
is optimistic, replaced by the server's answer, and rolled back with a message at the bottom
of the screen on failure. Server: single-item responses (`GET` item, episode and season writes)
now carry `watchedEpisodes`; lists and sync do not. AniList descriptions are cleaned to plain
text. Verified on the web against a local API: a tick, a rating and a status change saved (the
first tick also moved the status to In progress, and the page took the server's word for it),
and with the API stopped a tick rolled back with "Aaru could not reach the server". The iOS
screen builds and makes the same calls but was not driven in the simulator.

### APP-006 · Lists screen · M
**Needs:** APP-003, LST-002.

**Done when:** a title can be added to a list from title detail and from search results.

**Progress 2026-10-15 (all three clients):** built. A Lists screen (create, rename, delete; reached
from the library toolbar on Apple, a "Lists" link on the web), a list screen (its titles in
order; remove; reorder by drag on Apple, up/down on the web; a title already on the shelf opens
its Title room), and an "Add to list" picker on the title screen and on every search result,
where a new list can be made on the spot. Titles need not be in the library to be on a list; a
repeat add changes nothing (server rule). Verified on the web against a local API: a list made
from Frieren's title page, The Hobbit added from search without adding it to the library, a
reorder and a remove that both survived a reload. Also fixed on the web: the title page's
status menu showed the first option instead of the saved one, and unknown addresses now get a
branded "Nothing lives here" page. The Apple screens build but were not driven in the
simulator.

### APP-007 · Settings, sources, import status · M
**Needs:** APP-001, IMP-002.
Connected sources, start an import, watch job state and stats, see unmatched rows.

**Done when:** a running import shows live-ish progress by polling, and a `partial` job
surfaces its unmatched count with a way to see the rows.

**Progress 2026-10-15 (all three clients):** built for file imports; Trakt waits for IMP-002.
Settings (from the library's More menu on Apple, a "Settings" link on the web): account name and
sign-in providers, sign out, delete account (confirmed, cannot be undone), "Import from IMDb /
Letterboxd / Goodreads" with a file picker, and every import with its state. An import's page
polls every 2 s while matching, then shows the plan (new, filled in, already there, not matched,
with each unmatched row's reason) with Approve or Discard; after approval it shows the result and
a `partial` job keeps its unmatched rows listed. Verified on the web against a local API with a
real Goodreads-format file matched through Open Library: progress then plan, title + author
matched a book with no ISBN, approve added two books and turned a custom shelf into a list. The
Apple screens build but were not driven in the simulator.

### APP-008 · Mac-specific pass · M
**Needs:** APP-005.
Keyboard navigation, multi-column layout, menu bar commands. Same target.

**Done when:** the Mac build is not a stretched iPad app: sidebar navigation, ⌘F search,
⌘N add.

### APP-009 · Home rows · L
**Needs:** APP-003, UPN-001, CAL-001.
Trakt-style home (`DESIGN.md`, `VIEWS.md`): `ContinueRow` (backdrop, "57m", "10 left · 8h 40m",
"Finale" badge, one-tap check), `StartRow` (posters, runtime), `CalendarRow` ("Today · New",
"In 3 hours", "In 2 days"). Every check is a PROG write and journals like any tap. Pull to
refresh; cached for offline like APP-003.

**Done when:** checking an episode from `ContinueRow` advances the card to the next episode
optimistically and rolls back on failure, and the screen renders from cache in airplane mode.

### DISC-001 · Discover rows on Home · M
**Needs:** APP-009, CAT-002, CAT-003, CAT-007.
`GET /v1/discover`: provider-curated public rows, the same for everyone — TMDB trending shows,
on the air, new shows (premiered in the last 90 days), trending movies, in theaters; AniList
this season's anime and trending anime; Open Library's weekly trending books. TMDB TV rows
leave out anime (AniList is the anime source) and news, soap and talk; poster-less hits are
dropped. One in-memory cache (6 h TTL, concurrent fetches coalesced, stale served and a 5 min
back-off on failure). One library query marks items the caller already has. Home renders the
rows after Continue / Airing / Start; an empty library gets a compact header instead of the
full empty state. Not personalised, ever (decision 2026-10-20).

**Done when:** a brand-new account opens Home on iPhone, Mac and web and sees the rows, adds a
title from a card in one tap, and that card turns into a link to the item; a provider being
down drops only its row.

### APP-010 · Week grid · L
**Needs:** APP-001, CAL-001.
Pogdesign CAT-style `WeekGrid`: seven day columns, previous/next day stepping, today
highlighted, each cell a banner image + title + `SxxEyy` + episode name + network · time, a
check box to mark watched, and state colours for watched / premiere / finale. On iPhone it
collapses to a day pager; on Mac and iPad it is the full grid. Our own data from CAL-001 —
nothing is read from pogdesign.co.uk.

**Done when:** the iPhone pager and the Mac grid render the same CAL-001 response, and ticking
a cell writes the same PROG route as title detail.

---

## P2 · Widgets

One widget extension, iOS and macOS. Patterns to copy: App Group JSON snapshot written by the
app (`apps/lumina/LuminaVaultClient/.../Services/AppGroup/WidgetSnapshotStore.swift`),
interactive widget button via App Intent (`apps/north/north-ios-app/khepri/Shared/LogWaterIntent.swift`),
Live Activity (`KhepriWidgets/WorkoutLiveActivity`). Prior art in the category: Trakt
(Continue Watching widget with progress bars, "Now Watching" Live Activity with Ends-at),
Sequel (Watch Next with mark-watched at larger sizes, Countdown, Upcoming), Kiroku (airing
countdown Live Activity). Nobody ships a streak widget or a CAT-style week widget.

### WID-001 · Widget data path · M
**Needs:** APP-009.
The app writes a compact snapshot (up next, today's airings, the week, streak later) into the
App Group after every successful sync and every local write, then calls
`WidgetCenter.reloadAllTimelines()`. Widgets read the snapshot; they never hold library state
of their own. A background refresh task updates the snapshot when the app is not running. The
widget may call the API itself only for the WID-002 intent, using the shared Keychain token.

**Done when:** ticking an episode in the app updates every placed widget within a few seconds,
and a widget with no snapshot shows an empty state rather than a placeholder forever.

### WID-002 · Up Next widget with "mark watched" · M
**Needs:** WID-001, PROG-001.
Small: one next episode. Medium: three. Large: five with progress bars ("4 left · 1h 36m").
An App Intent button on each row ticks the episode through the same PROG route, journals as a
user tap (X-007), and advances the row.

**Done when:** ticking from the Home Screen widget without opening the app moves the server
state, the row advances, and the undo ribbon in the app shows the action.

### WID-003 · Airing countdown and Lock Screen accessories · S
**Needs:** WID-001, CAL-001.
Next airing episode of a tracked show ("In 3h · S1E8"). Accessory circular / rectangular /
inline on the Lock Screen; small on the Home Screen. Timeline entries at each air time so the
countdown flips without a refresh.

**Done when:** the countdown reaches "Out now" at the air time with the app closed.

### WID-004 · Week calendar widget · M
**Needs:** WID-001, CAL-001.
Large and extra-large (iPad, Mac): the CAT week in miniature — seven columns, up to three
episodes per day, watched state, today highlighted. Tapping a cell deep-links to the episode.

**Done when:** the widget and `WeekGrid` agree on every cell for the same week.

### WID-005 · "Now watching" Live Activity · M
**Needs:** WID-001, APP-009.
Started from title detail ("Start watching") or by a scrobble in P3. Lock Screen + Dynamic
Island: poster, `S1·E8 · Lanterns`, a progress bar, and "Ends at 1:20 PM" — tapping toggles to
"41m left" (Trakt's behaviour). Ends on check-off or after runtime + grace. "Mark watched"
button via App Intent.

**Done when:** a Live Activity started on the phone ends itself and ticks the episode when the
user taps "Mark watched", and stale activities never outlive runtime + grace.

### WID-006 · macOS widgets · S
**Needs:** WID-002, WID-004.
Same extension built for macOS: Up Next and week calendar in desktop and Notification Center
sizes. Interactive intent works on Mac.

**Done when:** the Mac app's widgets update from the same snapshot path and the mark-watched
intent works on macOS.

---

## P2 · M8 — Trakt import

### JOB-001 · Job queue · L
**Needs:** SRV-007.
Hummingbird Jobs (or equivalent) with a Postgres-backed queue. In-process worker at first;
`ARCHITECTURE.md` allows one binary until imports block request latency. Retries with
backoff, a dead-letter state, and cancellation.

**Done when:** killing the process mid-job leaves the job re-runnable rather than stuck in
`running`, and a job that throws lands in `failed` with an `errorSummary`.

**Progress 2026-10-15:** built for imports (`ImportWorker`, a ServiceLifecycle service in the
same binary). Jobs are leased with `FOR UPDATE SKIP LOCKED`; an expired lease makes a dead
worker's job runnable again; 3 attempts with 30 s/60 s backoff, then `failed` with a summary.
Both done-when conditions are tests. Generalise when a second job kind (show refresh, journal
pruning) arrives.

**Progress 2026-10-20:** show refresh built as a periodic loop (`CatalogRefreshService`), not as
`import_jobs` rows: it has no payload or owner, so the hydration timestamps are the queue. Every
5 minutes it refreshes up to 40 tracked shows, never-loaded first (imported shows land here), then
shows past their CAT-006 window; a failed show waits an hour. Calendar and Up Next still load up to
10 never-loaded shows per request so a first view after an import is not empty.

### IMP-001 · Import job contract · M
**Needs:** JOB-001.
`GET /v1/imports`, `GET /v1/imports/{id}`. Every importer reports
`created / updated / skipped / unmatched`. Unmatched rows are listed, never silently
dropped.

**Done when:** a job with 3 unmatched rows returns those 3 rows with enough detail (source
title, year, source ids) for a human to fix them by hand.

**Progress 2026-10-15:** built, with a plan step: `GET /v1/imports`, `GET /v1/imports/{id}`
(every row with its outcome and reason), `POST /v1/imports/{id}/apply`, `DELETE /v1/imports/{id}`.
New state `planned`: nothing touches the library until the user approves, and the approval is one
undoable action.

### IMP-002 · Trakt OAuth connect · M
**Needs:** IMP-001, AUTH-001.
`POST /v1/imports/trakt/connect`, `GET /v1/imports/trakt/callback`. Token stored encrypted
at rest, never sent to a client. State parameter checked. Refresh handled.

**Done when:** the access token never appears in any response body or log line, the
callback rejects a mismatched `state`, and an expired token refreshes without user
interaction.

**OPEN (2026-10-10):** a third-party report says Trakt made API app creation VIP-only in
mid-2026 and removed free accounts' apps. Not confirmed on trakt.tv. Before starting: check
whether `trakt.tv/oauth/applications` lets this account create an app. If not, decide between
a Trakt VIP subscription for the app owner and making the file imports (M9) the primary path.

**Resolved 2026-10-15:** the app exists (client id in hand). Trakt issues it **no client secret**:
sign-in is PKCE only and redirect URIs must be `https://` on a host Aaru owns (no `oob`, no
`localhost`, no custom schemes). **Progress:** built against a stubbed Trakt. `POST
/v1/imports/trakt/connect {returnTo}` makes a PKCE pair (S256) and a one-time `state` (stored
hashed, 10 minutes) and returns Trakt's authorize URL; Trakt redirects to `GET
/v1/imports/trakt/callback` (a plain route outside `openapi.yaml`, so its `Location` is not
percent-encoded), which exchanges the code with the verifier, seals both tokens with AES-GCM
(`TRAKT_TOKEN_KEY`), and sends the browser to `returnTo?trakt=connected|denied|failed` (only `aaru://`
and the web origin are allowed). Tokens refresh an hour before expiry. `GET`/`DELETE
/v1/imports/trakt/connection`. Config: `TRAKT_CLIENT_ID` (public), `TRAKT_TOKEN_KEY` (secret, 32
bytes), `TRAKT_REDIRECT_URI`, `TRAKT_RETURN_PREFIXES`. **Blocked on the domain** for production:
the redirect URI must be `https://api.<domain>/v1/imports/trakt/callback`.

### IMP-003 · Trakt import worker · L
**Needs:** IMP-002, CAT-005.
Pull watched history, watchlist, ratings, and lists. Page through the API respecting rate
limits. Map Trakt ids → TMDB/IMDb → `Title`. Upsert `LibraryItem` on `(user_id, title_id)`.
Apply episode progress and ratings.

**Done when:** running the same import twice produces zero duplicates and a second run
reports `updated`/`skipped` rather than `created`, and a 10,000-item history completes
without exhausting the TMDB rate budget.

**Progress 2026-10-15:** built against a stubbed Trakt. `POST /v1/imports/trakt` queues a job whose
rows the worker reads from Trakt (watched movies and shows with every watched episode, watchlist,
ratings, lists), keyed by Trakt id so one title is one row; then the same plan → approve → one
undoable action as file imports. Watched shows are `in_progress` with their episodes ticked (an
existing item only gains the ticks it lacks); a rating alone means watched; a title only on a
Trakt list joins the Aaru list without joining the library. A revoked token fails the job at once
and drops the dead connection. Re-runs are skip/update, never duplicates (the plan's existing
rule). Not yet measured: a 10,000-item history.

### IMP-004 · Merge policy · M
**Needs:** IMP-003.
Fill-empty-only, in the order Trakt → IMDb → Letterboxd → Goodreads → CAT. A later source
never overwrites a non-empty rating, status, or progress. `ARCHITECTURE.md` explicitly
permits skipping the "newer wins" rule in v1.

**Done when:** importing Letterboxd after Trakt leaves every Trakt rating intact, and a
test asserts that on a title present in both.

**Progress 2026-10-15:** fill-empty-only is built and tested across any two sources (an existing
rating survives, an empty one is filled, a status is never overwritten). The Trakt half waits for
IMP-002/003.

---

## P2 · M9 — File imports

### IMP-005 · CSV upload endpoint · M
**Needs:** IMP-001.
`POST /v1/imports/csv` multipart with `source=imdb|letterboxd|goodreads`. Size cap,
content-type check, streamed to disk or memory bounded — never fully buffered without a
limit. Files are parsed and discarded; `ARCHITECTURE.md` says do not store raw provider
dumps long-term.

**Done when:** a 200 MB upload is rejected before it is buffered, a file whose columns do
not match the declared source fails with a readable error, and no uploaded file survives
job completion.

**Progress 2026-10-15:** built as `POST /v1/imports/csv?source=&filename=` with a `text/csv` body
(not multipart; see ARCHITECTURE.md). 5 MB cap checked from the declared length, then by reading
at most 5 MB; the file is parsed into rows at once and never stored. Tested: oversize is 413,
wrong columns are 422 naming the source and the missing column.

### IMP-006 · IMDb CSV parser · M
**Needs:** IMP-005, IMP-004.
Columns: title, year, title type, `tconst`, rating, date. `tconst` is a hard external ID,
so match confidence is high.

**Done when:** an IMDb export with TV episodes as rows is handled (episodes roll up to the
show or are counted as unmatched — decide once and document), and ratings map onto the
Aaru 1–10 / 0.5 scale without drift.

**Progress 2026-10-15:** built. Decided: episode rows are unmatched with a reason ("add the show
instead"). Ratings and watchlist exports both read; ratings are already 1–10. Matching needs the
real TMDB key (IMDb ids resolve through TMDB find).

### IMP-007 · Letterboxd CSV parser · M
**Needs:** IMP-006.
Columns: Name, Year, Letterboxd URI, Rating, Watched Date. No IMDb id in the export, so
resolution goes through TMDB search + year via `TitleMatching`.

**Done when:** an ambiguous title + year pair with two plausible TMDB hits is reported
unmatched rather than guessed, and Letterboxd's 0.5–5 star scale is doubled onto Aaru's
1–10.

**Progress 2026-10-15:** built. Ambiguity is the resolver's existing rule (unmatched, never
guessed); stars are doubled; the watchlist export is told apart by its file name. Needs the real
TMDB key to match.

### IMP-008 · Goodreads CSV parser · M
**Needs:** IMP-005, CAT-003.
Columns: Title, Author, ISBN, My Rating, Exclusive Shelf, Date Read. Shelf maps to status:
`to-read` → `wishlist`, `currently-reading` → `in_progress`, `read` → `finished`. Custom
shelves become lists.

**Done when:** rows with an empty or `=""`-wrapped ISBN (Goodreads does this) still resolve
by title + author, and a custom shelf produces one Aaru list, not one per row.

**Progress 2026-10-15:** built and tested end to end (Open Library needs no key, so it also works
locally): `=""` ISBNs, title + author fallback, custom shelves become one list each (an existing
list of that name is reused).

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

### IMP-012 · TV Time export import · M
**Needs:** IMP-005, IMP-004.
TV Time shut down on 2025-07-15 and its users hold GDPR data exports. Parse the export's
followed shows, watched episodes, and watched movies. Joins the merge order after CAT. Episode
rows resolve through TVDB ids (TV Time was TVDB-based) → TMDB.

**Done when:** a real TV Time export produces show progress per episode with unmatched rows
listed, and re-running it creates nothing new.

**OPEN:** export format varies by request date. Collect two real exports before writing the
parser. **Parked 2026-10-16 by the owner** (never used TV Time, no export to build from): build it
only when a user who has an export asks.

### IMP-013 · MyAnimeList XML import · M
**Needs:** IMP-005, CAT-009.
MAL's list export (XML): `series_animedb_id`, watched episodes, status, score. `mal` id is a hard
external ID. Status maps: Watching → `in_progress`, Completed → `finished`, On-Hold →
`in_progress`, Dropped → `dropped`, Plan to Watch → `wishlist`. Score 1–10 maps 1:1.

**Done when:** a MAL export with 300 entries lands with episode progress, and entries without a
TMDB mapping still import as AniList-backed titles rather than unmatched.

### IMP-014 · AniList import · M
**Needs:** IMP-001, CAT-009.
Public list read by username over GraphQL (no OAuth needed for a public list). Same status map
as IMP-013; AniList's score format is normalised to Aaru's 1–10.

**Done when:** importing the same user via MAL XML and AniList produces no duplicate titles.

Merge order for one account becomes Trakt → IMDb → Letterboxd → Goodreads → CAT → TV Time →
MAL → AniList. `CLAUDE.md` and `ARCHITECTURE.md` carry the same order.

---

## P2 · Catalog sources

Free sources that close gaps TMDB, AniList and Open Library leave. Every one goes through the
central rate limiter (CAT-001) and maps onto `ExternalIDs`; none is ever a library row. Free
tiers are mostly **non-commercial** (TMDB, TVmaze): PRV-001 records the terms so a paid plan
in `BUSINESS.md` cannot ship on a free key by accident.

### PRV-001 · Provider register, keys, attribution · S
**Needs:** nothing.
`docs/providers.md`: one row per provider — key or none, where the secret lives (sealed for
`horus`), rate limit, licence/terms (commercial use allowed or not), and the attribution the
app must show. Covers TMDB, AniList, Open Library, Trakt, MyAnimeList, TVmaze, Google Books,
Wikidata, Fribb anime-lists, anime-offline-database, OMDb, Fanart.tv. Register a free
**MyAnimeList API client ID** now (needed by SCR-005; MAL XML import IMP-013 needs no key). The
attribution list feeds LAND-003 and the app's About screen.

**Done when:** every provider the server calls has a row, every row with a key names its
sealed secret, and the About screen and privacy page show every required attribution (TMDB
logo + notice, TVmaze CC BY-SA, ODbL).

### CAT-011 · TVmaze air times and networks · M
**Needs:** CAL-001, PRV-001.
TMDB gives air *dates*; the week grid, "In 3 hours" badges and airing widgets need air
*times*. Look shows up on TVmaze by `tvdb`/`imdb` id (`/lookup/shows`, no key), store
`tvmaze` on `ExternalIDs`, and fill `show_episodes.airs_at` with the exact timestamp and
`titles` with network / streaming platform (closes the network gap noted under CAL-001). TMDB
stays the episode source; TVmaze only refines time and network. ~20 calls / 10 s per IP.

**Done when:** a calendar row for a US network show carries the correct local air time and
network, a show TVmaze does not know still appears with its TMDB date, and `CLAUDE.md` and
`ARCHITECTURE.md` list TVmaze as a source.

### CAT-012 · Google Books fallback · S
**Needs:** CAT-003, PRV-001.
When Open Library has no hit for an ISBN, or no cover, ask Google Books (free key, ~1,000
requests/day). Same `book` `CatalogHit` shape; `isbn` stays the join key. Open Library is still
asked first.

**Done when:** an ISBN Open Library lacks resolves via Google Books, an ISBN both know
resolves to one `Title`, and the daily quota running out degrades to "not found", not a 500.

### CAT-013 · Wikidata cross-id fill · M
**Needs:** CAT-005, JOB-001.
A background job fills missing external ids (a movie with `tmdb` but no `imdb`, a book with
`isbn` but no `openLibrary`, an anime with `anilist` but no `tmdb`) from Wikidata SPARQL (no
key). Never on the request path. Never merges two `Title`s: a filled id that collides with
another title's id is logged for review, not applied.

**Done when:** a title missing one id gains it on the next job run, and a collision leaves both
titles unchanged with one review log line.

### CAT-014 · Where to watch · S
**Needs:** CAT-006.
TMDB `watch/providers` per title and region (same TMDB key; data from JustWatch, which TMDB
requires be credited). Shown on the Title room. Cached with the title's staleness window.

**Done when:** a title shows streaming/rent/buy providers for the caller's region with the
JustWatch credit, and a region with no data shows nothing rather than an empty box.

### CAT-015 · OMDb ratings · S · after the P2 gate
**Needs:** PRV-001.
IMDb and Rotten Tomatoes ratings by `imdb` id (free key, 1,000/day), cached 7 days. Display
only; never written onto the user's rating.

**Done when:** a title with an `imdb` id shows external ratings, and the daily cap is never
exceeded under a 10,000-item import (ratings fetched lazily on view, not on import).

### CAT-016 · Fanart.tv artwork · S · after the P2 gate
**Needs:** PRV-001.
Clear logos and backdrops for the Title room and widgets (free personal key). Referenced by
URL like posters, never re-hosted.

**Done when:** a title with Fanart.tv art shows its clear logo, and one without falls back to
the TMDB backdrop with no layout change.

### CAT-017 · MyAnimeList fallback search · S · Deferred
Only if AniList misses titles users actually search for. MAL API v2 reads with the PRV-001
client ID. Deferred until there is a measured miss rate; Jikan is out (it scrapes MAL).

---

## P2 · Web (`aaru-client`)

SolidJS + TanStack Start on Cloudflare Workers (since 2026-10-14), a pure client of `/v1` at
parity with the Apple apps. No database, no business logic, no web-only endpoint. The landing
page lives in the same app.
`aaru-landing/` and `aaru-site/` are retired; M10 and M11 keep their IDs below.

### LAND-001 · Landing route group · M
**Needs:** REL-006.
`src/routes/(marketing)/` prerendered: hero, features, pricing note, FAQ. It never reads a
session cookie and imports nothing from the library code. Remove the `sv create` demo routes
and stock Storybook stories in the same change.

**Done when:** the marketing routes prerender with no client JS required, `demo/` is gone, and
Lighthouse shows no layout shift on the hero.

**Progress 2026-10-10:** built on branch `landing-and-sources`. Hero, imports, bento, native
apps, FAQ; en/es/pt prerendered at `/`, `/es`, `/pt` (Paraglide now `url` strategy first);
`demo/` and stock stories removed; brand assets from `docs/brand/`. Open: the hero CTA only
scrolls the page until LAND-002 adds the waitlist; Lighthouse not run; `og:image` uses the
placeholder domain (`src/lib/site.ts`).

**2026-10-14:** ported to SolidJS (`src/routes/index.tsx`), English only (see the 2026-10-14
decision). The hero CTA now goes to sign-in.

### LAND-002 · Waitlist · S
**Needs:** LAND-001.
Email capture with double opt-in and an export. Stored through a `/v1` route, not in a Worker
KV.

**Done when:** a submitted address is stored, confirmable, and deletable on request.

### LAND-003 · Legal and privacy copy · S
**Needs:** LAND-001.
Privacy policy that is accurate about what Aaru stores: library data, Trakt tokens, uploaded
CSV contents (transient), and — once P4–P6 ship — friends, activity, and that DM content is
end-to-end encrypted and unreadable by Aaru. App Store requires this before submission.

**Done when:** the policy names every third party data touches (TMDB, Open Library, AniList,
Trakt, Apple, Cloudflare) and matches what the code actually does.

### WEB-001 · Logged-in web on `/v1` · L
**Needs:** APP-009 (shape parity), AUTH-002, AUTH-003, REL-006.
Sign in (email code + Sign in with Apple JS), home rows, `WeekGrid`, search and add, title
detail with episode ticks, lists, settings and imports, shipped screen by screen alongside
APP-002…APP-010. The session lives in an HttpOnly cookie; TanStack Start server functions send
every `/v1` call with it, so page scripts never see the token.

**Done when:** the web client uses the same `/v1` routes as the apps with no web-only
endpoint, a token is never readable from page JS, and `ARCHITECTURE.md` lists it as a live
client.

**Progress 2026-10-14:** sign-in at parity with APP-002. `/sign-in` sends a code and verifies it
(and shows Apple's own button once `APPLE_SERVICES_ID` is set; it needs a Services ID on a
verified domain). `/app` is the signed-in shell with sign-out, matching the Apple apps'
"Signed in" screen. Verified in Chrome against a local server: a wrong code shows the server's
message, the right code signs in, a reload keeps the session, sign-out deletes the server
session and the cookie, and `/app` redirects to `/sign-in` when signed out.

**Progress 2026-10-14 (2):** the library (APP-003) and search and add (APP-004) at parity. An
unreachable API keeps the session (only a 401 ends it) and pages show a branded error with
"Try again" instead of a stack trace.

**P2 gate (the "basics done" line):** the TestFlight Beta app (iOS + Mac) and the beta Worker
are usable end to end by someone who is not the author — sign in, import from Trakt or a CSV,
track a week of episodes from home, week grid, and widgets. Record the strangers count in
`MARKETING.md` when this is met.

---

# P3 — Tracking integrations

Start only after the P2 gate. Imports stay one-way **in**; pushes in this phase are one-way
**out** and are never read back as a conflict source, so no conflict engine is needed.

## P3 · Scrobbling and players

### SCR-001 · Scrobble ingest · L
**Needs:** OUT-001, PROG-001, AUD-001.
OUT-001 (agent tokens) is pulled forward from P7 and built as the first P3 item; its table
and revoke UI serve scrobble, Stremio, and agent callers alike.
`POST /v1/scrobble/start|pause|stop`, body shaped like Trakt's (`movie` or `show`+`episode` ids,
`progress` percent) so existing tools map onto it. Writes `watch_events` (`userId`, `titleId`,
season/episode, `startedAt`, `progress`, `source`, `stoppedAt`). `stop` at ≥ 80% marks the
episode or movie watched through the PROG route (Aaru's own threshold, documented); `pause`
stores a resume position used by UPN-001. Auth is a scoped per-user token (`scrobble:write`)
reusing `agent_tokens` — not a second credential type. A scrobble may start the WID-005 Live
Activity via push (needs SOC-005).

**Done when:** a start → pause → stop at 85% produces one watched episode and one journal row,
a duplicate stop is a no-op, and a token without `scrobble:write` gets 403.

**Progress 2026-10-20 (service only):** `ScrobbleService` + `watch_events` built; Stremio's
`player` events are its first caller (SCR-003), and `POST /v1/scrobble/*` waits for SCR-002.
One open session per user, source and item; the longest non-zero duration wins, so Stremio's
first `start` with duration 0 still counts. `stop` at ≥ 80% ticks the episode (or finishes the
movie) through `LibraryService` as the token's caller; already watched, short of 80%, unknown
duration, or a second `stop` within 10 minutes writes nothing. A title not in the library is
added (in progress / finished) and then ticked: two journal rows, not one. Unknown ids are kept
as unmatched rows with no library write. The 403 condition lives in the Stremio adapter.

### SCR-002 · Plex and Jellyfin webhooks · M
**Needs:** SCR-001.
`POST /v1/scrobble/hooks/plex/{token}` (multipart JSON; `media.play`, `media.pause`,
`media.stop`, `media.scrobble`) and `/hooks/jellyfin/{token}` (Webhook plugin, flat JSON).
Map `Guid` entries (`tmdb://`, `imdb://`, `tvdb://`) to `MediaRef`. Jellyfin `PlaybackStop`
counts only past 90%.

**Done when:** a recorded Plex and a recorded Jellyfin payload each tick the right episode in a
test, and an unknown guid lands as an unmatched scrobble the user can resolve.

### SCR-003 · Stremio addon · L
**Needs:** UPN-001, OUT-001. Promotes MOAT-001.
Served by `aaru-server` under `/stremio/{token}/` (manifest, `catalog`, `meta`, `player`,
`library`), not a second service. Catalogs: Continue watching, Next 7 days (CAL-001), Wishlist.
Settings in `aaru-client` and the Apple app mint a `kind = stremio` token (`library:read` +
`scrobble:write`, opt-in `library:write`) and show the install URL. `player` events go to the
SCR-001 service; `library` `watched` marks tick; `libraryRemove` is ignored. **No `stream`
resource, ever** — Aaru does not touch stream sources.

**Done when:** installing the addon in Stremio shows the user's Continue Watching catalog, the
manifest declares no `stream` resource, and revoking the token empties the catalogs.

**Progress 2026-10-20:** server built (`Sources/App/Stremio`). One hand-written `/stremio/**`
route: CORS on every answer (errors too), `Cache-Control: private`, 120 requests a minute per
token. Manifest `com.aaruapp.library`: `catalog`, `meta` (`aaru:` only), `player` and `library`
(`tt`, `aaru:`); catalogs Continue watching, Next 7 days, and a movie and a series Wishlist
(`skip`, up to 2,000). Items use the IMDb id when known so Cinemeta and stream addons recognise
them, else `aaru:{titleId}` with Aaru's own `meta` and `videos`. Events follow the 2026-10-19
decision; a missing `scrobble:write` is 403. A revoked token gets a 404 manifest and empty
catalogs. Route and parser tests cover each done-when line. Not yet tried in a real Stremio
client.

**Progress 2026-10-20 (Settings):** web (`components/StremioSection.tsx`) and Apple
(`Settings/StremioSection.swift`) connect, show the install links once, list links with last
use, and revoke. The catalog is named Wishlist (id `aaru-wishlist`), the domain word.

**Manual check 2026-10-20 (Stremio Web, local server):** install from the web install link; all
four rows render (the board loads rows lazily, as they scroll into view); an `aaru:` show opens
with Aaru's own `meta` and episode list; "Mark as watched" sends `library … action=watched`
for both `aaru:` and `tt` ids and journals one "Stremio: …" action; "Mark as non-watched"
unticks (with `library:write`); "Mark rest as watched" sends every episode id in one request
and journals one action for the ones that changed; after revoke and a reload the rows are
empty. Chrome asks for local-network access before an HTTPS page may call `127.0.0.1`, so
local testing needs that permission. Not checked: `player` events (playing needs a stream
addon and Stremio's streaming server) and Stremio 5 desktop (needs the deployed HTTPS API).
Aaru's ticks do not show as watched in Stremio; nothing writes Stremio's own watched state.

Traefik on `maat` keeps `RequestPath` in its JSON access log and Alloy ships it to Grafana
Cloud, so the token would leave the cluster; infra PR LuminaVault/LuminaVaultInfra#362 masks
it before remote write. Ship that before anyone connects Stremio. Traefik's security headers
leave CORS alone.

**Resolved 2026-10-19:** Stremio core 0.64 sends `player` and `library` events to addons
that declare them (see the decisions above). Do **not** route Stremio → Trakt → Aaru by
re-reading Trakt — that is two-way sync.

### SCR-004 · Push history to Trakt · M
**Needs:** IMP-002, SCR-001. Promotes MOAT-003.
One-way out: user-triggered "push my library to Trakt" job with a dry-run diff (reuses the
AG-003 plan shape when it exists), then optional forward push of new watches. Never reads Trakt
back after the initial import.

**Done when:** a dry run lists exactly what will be added on Trakt, applying it is idempotent,
and nothing Aaru pushes is ever re-imported as a change.

### SCR-005 · Push progress to MAL and AniList · M
**Needs:** CAT-009, SCR-001, PRV-001 (MAL client ID).
One-way out per connected account: MAL API v2 (OAuth2 PKCE; `PATCH
/v2/anime/{id}/my_list_status` with `num_watched_episodes`, `status`, `score`) and AniList
(`SaveMediaListEntry`). Tokens encrypted at rest like IMP-002.

**Done when:** ticking an anime episode in Aaru updates both connected lists within a minute,
a revoked provider token surfaces in settings rather than failing silently, and no provider
token appears in a response or log.

### SCR-006 · Movie resume position · S
**Needs:** SCR-001, UPN-001.
`pause` positions feed Continue Watching for movies ("1h 27m left").

**Done when:** a paused movie shows time left on home and drops off when stopped past 80%.

---

# P4 — Social

Start only after the P2 gate. Private by default: a new account has no public surface, social
settings default to friends-only, and nothing is visible to a non-friend. Design copied from
Norviq (`apps/norviq/norviq-backend/Sources/StockPlanBackend/Social/`,
`Migrations/CreateSocialTables.swift`).

## P4 · Profiles, friends, activity

### SOC-001 · Profile and social settings · M
**Needs:** AUTH-001.
**Pulled forward 2026-10-20 for groups, minimal:** `profiles` (`handle`, display name) and
`GET/PUT /v1/me/profile` only. Avatars are generated monograms. `social_settings` waits for
SOC-003.
`profiles` (`handle` unique, display name, avatar URL) and `social_settings` (`visibility`
`private` | `friends`, `show_activity`, `show_points`, `show_streaks`, `leaderboard_opt_in`,
`discoverable_by_email_hash`). Defaults: `private`, everything off.

**Done when:** a fresh account is invisible to every other account until it changes a setting,
and no route exposes a profile to an unauthenticated caller.

### SOC-002 · Friends, requests, blocks, invites · L
**Needs:** SOC-001.
**Pulled forward 2026-10-20 for groups, minimal:** requests, friendships, blocks and reports,
added by handle only. `social_invites`, invite links (they need universal links) and the
contact email hash stay here for later.
Tables `social_friend_requests` (pending/accepted/declined/cancelled), `social_friendships`,
`social_blocks`, `social_reports`, `social_invites` (short code, expiry). Add by handle, by
invite link, or by contact email hash (opt-in). A blocked user gets **404** on everything about
the blocker, never 403. Unfriend is silent. Account delete removes all of it (extends AUTH-004).

**Done when:** a block hides the blocker from search, requests, activity, and leaderboards in
both directions (test asserts each), and an invite link adds a friend in one tap after sign-up.

### SOC-003 · Friend activity and "Today" stories · L
**Needs:** SOC-002, PROG-001.
`GET /v1/activity` — friends' watch events (ticks, finishes, ratings, scrobbles), filtered by
each friend's `show_activity`. Grouped per friend per day into Trakt-style stories
(`FriendStories`: "Kevin · Watched S2 · E9 · 12:11 PM", poster, save-to-wishlist button).
Derived from the journal and `watch_events`; no second write path.

**Done when:** an undone tick disappears from friends' activity, a friend with `show_activity`
off never appears, and the feed is friends-only with no global variant.

### SOC-004 · Friends on the Title room · S
**Needs:** SOC-003.
"3 friends watched this · Ana is on S2E4" on title detail, and their ratings if shown.

**Done when:** only friends with matching visibility appear, and the query is one call.

### SOC-005 · Push notifications · M
**Needs:** SOC-002, REL-003.
APNSwift. `apns_devices` (`userId`, token, `environment` sandbox/production, bundle id) so the
Beta and Release apps share one API. Categories: friend request, accepted, new episode of a
tracked show, (later) DM, room invite. Per-category preferences. Copy
`LuminaVaultServer/Sources/App/Services/APNSNotificationService.swift`.

**Done when:** a Beta build and a Release build on the same account both receive a friend
request push, and turning a category off stops it on every device.

### SHR-001 · Shared lists · M
**Needs:** SOC-002, LST-002.
Was M12+. Share a list with friends, read-only first (`list_members`, `lists.visibility`
gains `friends`). Collaborative editing moved to `shelf` channels (GRP-008) on 2026-10-20.

**Done when:** a friend can open a shared list and add its titles to their own library, and a
non-friend gets 404.

## P4 · Groups (pulled forward 2026-10-20)

A **group** is a friends-only space with channels, like a small Discord server. Creating one
creates `#general`. Group messages are **server-visible** and every channel header says so; DMs
stay E2E. A non-member gets **404** on everything about a group. Caps: 50 members, 20 channels,
4,000 characters per message. No presence, attachments or invite links in v1.

`docs/privacy.md` changes in the same PR as the behaviour, never ahead of it: handles,
friends and blocks with SOC-001/002; group messages being server-visible, readable by members
and kept until deleted with GRP-003; Anthropic as a processor that sees a channel's recent
messages when `@aaru` is tagged with GRP-011.

### GRP-001 · Groups, members, `#general` · M
**Needs:** SOC-001, SOC-002.
Tables `groups` (name, owner, `deleted_at`) and `group_members` (role `owner` | `admin` |
`member`, `muted`, `joined_at`). Creating a group inserts the owner and a `#general` text channel
(`is_default`) in one transaction. `#general` can be renamed, never deleted or archived. The
owner can't leave without transferring ownership or deleting the group. Owner and admins manage
channels and members. Account delete removes the user's memberships and hands owned groups to
the oldest admin, or deletes them when there is none (extends AUTH-004).

**Done when:** a new group has exactly one member and one channel, `#general`; a non-member gets
404 for the group, its channels and its messages; and the owner's leave is refused.

### GRP-002 · Group invites, friends only · S
**Needs:** GRP-001.
`group_invites` (inviter, invitee, status `pending` | `accepted` | `declined` | `revoked`). Insert
only when inviter and invitee are friends and neither has blocked the other. `GET
/v1/me/group-invites` is the invitee's inbox. Accepting adds a `member` row.

**Done when:** inviting a non-friend returns 422, inviting someone who blocked you returns the
same 422 with no hint of the block, and accepting adds the member once (a double accept is a
no-op).

### GRP-003 · Text channels and group messages · M
**Needs:** GRP-001.
`group_channels` (`kind` `text` | `title` | `watch` | `shelf`, name, topic, position) and
`group_messages` (author kind `user` | `agent`, body, `components`, `reply_to`, `mentions`,
`mentions_agent`, spoiler stamp, `client_nonce`, `edited_at`, `deleted_at`).
`group_read_state` holds each member's last read message and unread mention count. Cursor
pagination by `(created_at, id)`. A retried post with the same `client_nonce` returns the first
message. Mentions are parsed on the server from `@handle` and checked against members. A delete
wipes the body and keeps the row. A blocked member's messages arrive flagged so the client
collapses them.

**Done when:** pagination returns every message exactly once across pages, a duplicate nonce
creates no second row, and a mention of a non-member is dropped.

### GRP-004 · Web groups surface · L
**Needs:** GRP-003, WEB-001.
`app_.groups` layout route. Desktop: `GroupRail`, `ChannelList`, `MessageList`, collapsible
`MemberList`. Tablet: rail and channels move into a drawer. Phone: stacked groups → channels →
chat. `Composer` with `@` autocomplete for members and Aaru, optimistic send and retry. Dialogs
to create a group, create a channel and invite friends. The open channel polls every 5 s while
visible until GRP-006 lands.

**Done when:** two friends on two browser profiles can create a group, invite, accept and
chat, and the layout works at 375 px with no horizontal scroll.

### GRP-005 · Apple groups surface · L
**Needs:** GRP-003, APP-001.
`AppTab.groups`. iPhone: `NavigationStack`, groups → channels → chat, members in a sheet.
iPad and Mac: `NavigationSplitView` inside the tab, members in `.inspector`. `GroupsModel` is
injected through `AppServices` and reset on sign-out.

**Done when:** the same flow as GRP-004 works between an iPhone simulator and a Mac, and
sign-out leaves no group data on screen.

### GRP-006 · Realtime for groups · L
**Needs:** GRP-003.
The groups subset of RT-001: `/v1/ws` (`hummingbird-websocket`), an in-process `RealtimeHub`
actor (LuminaVault's `ConnectionManager` is the template), envelopes `message.*`, `typing`,
`read`, `member.*`, `channel.*`, `invite.received`. Writes stay on REST; the socket only
announces. The web gets a 60 s single-use ticket from `POST /v1/realtime/ticket` because its
session token is cookie-only. Origin is checked. Presence stays in RT-001.

**Done when:** a message appears on the other client within two seconds, a reconnect fills the
gap from REST with no duplicates, a used or expired ticket is refused, and a non-member's
socket receives nothing for the group.

### GRP-007 · Title channels and the spoiler guard · M
**Needs:** GRP-006, PROG-001.
A `title` channel is bound to one title, created from search or "Discuss in group…" on the
Title page. Its header is a `TitleCard`. A message is stamped with the author's current season
and episode, or a hand-set one. A reader whose progress is behind sees `SpoilerVeil`.
Members' progress shows in the header only for members who switch on `share_progress` for that
group (default off).

**Done when:** a reader at S1E3 sees a message stamped S1E5 veiled, a reader at S2E1 does not,
and a member with `share_progress` off never appears in the header.

### GRP-008 · Shelf channels · M
**Needs:** GRP-006.
`group_channel_items` (title, `added_by`, position). Separate from `lists`, which stay
single-owner; they share a renderer. Any member adds or removes titles. "Add to my library" is
a normal tap through the library data layer, journaled with the user as actor.

**Done when:** two members edit the same shelf live, and "Add to my library" writes one
journaled, undoable action for the tapper only.

### GRP-009 · Watch channels · L
**Needs:** GRP-006, PROG-001.
Absorbs ROOM-001. `watch_sessions` (title, season, episode, `starts_at`, state `lobby` |
`countdown` | `live` | `ended`). `WatchPanel`: ready list, a countdown driven by server time,
ephemeral reactions over the socket, and "Mark watched for me", which ticks only the tapper's
progress.

**Done when:** members on web, iOS and Mac see the same countdown within 500 ms, and ending the
session ticks the episode only for members who tap.

### GRP-010 · Model provider, minimal · M
**Needs:** none.
The groups subset of AG-007: `ModelProviding` plus an adapter for the Anthropic Messages API
with `claude-haiku-5-5`. It sends no `temperature`, `top_p`, `top_k` or assistant prefill (see
`platform/infra/docs/llm-haiku-trial.md`). The key is a sealed secret in `platform/infra`.
Metering in `agent_usage` (user, day, requests, tokens). No user keys yet.

**Done when:** tests against a stub server pass, a request body never contains `temperature`,
and usage rows add up per user and day.

### GRP-011 · `@aaru` replies in channels · L
**Needs:** GRP-003, GRP-010.
A message with `mentions_agent` enqueues an `agent_replies` row, claimed with the
`FOR UPDATE SKIP LOCKED` lease used by imports. Context: the channel's last 30 messages, the
channel's title, session or shelf, and **the tagger's own** library, read-only. Tools:
`search_titles`, `title_details`, `list_airs`, `read_my_library`. The reply is a group message
with author kind `agent`, `reply_to` the mention, and catalog components only. Its card
buttons are the viewer's own taps. Caps: 30 mentions per user per day, 10 per group per hour;
over the cap Aaru says once that it is resting, without calling the model.

**Done when:** a tagged question gets one reply, the model's context never contains another
member's library, the cap reply makes no model call, and no tool can write.

### GRP-012 · Group push and tap routing · M
**Needs:** GRP-002, GRP-003, the airing push (decision 2026-10-15).
`group_mentions` and `group_invites` toggles in notification settings, plus per-group mute. The
payload carries no message text: "{name} mentioned you in #{channel}" and
`aaru://group/{g}/channel/{c}`. iOS routes a tap to the channel.

**Done when:** a muted group sends nothing, a mention push opens the right channel from a cold
start, and no push payload contains message text.

---

# P5 — Gamification

Start only after the P2 gate. Points are a **ledger**, never a counter — copied from Norviq
(`StockPlanBackend/Gamification/XPService.swift`) and Loci (`0113_gamification.up.sql`).

## P5 · Points, streaks, badges

### GAM-001 · Points ledger · M
**Needs:** AUD-001.
`points_events` (`userId`, `kind`, `points`, `dedupeKey`, `createdAt`), unique on
`(userId, dedupeKey)`; one idempotent `award(kind:dedupeKey:)` used everywhere. A cached
`user_progress` row (total, level, current/longest streak) is rebuilt from the ledger.

Kinds and suggested values (tune later, keep in code): episode watched 10, movie finished 25,
book finished 50, season finished 30 bonus, scrobbled stream +5 on top, friend added 20
(mutual accept only), room attended 15, first import 50. Daily caps per kind. Undoing a tick
writes a negative compensating event with its own dedupe key — the ledger is never edited.

**Done when:** replaying the same scrobble twice awards once, undo-then-redo nets one award,
unfriend within 7 days reverses the friend award, and `user_progress` rebuilt from scratch
equals the cached row.

### GAM-002 · Levels · S
**Needs:** GAM-001.
Level curve `50·L·(L−1)` XP (same as Norviq/Loci). Level shown on profile and in settings.

**Done when:** level is a pure function of total points with a table-driven test.

### GAM-003 · Streaks · M
**Needs:** GAM-001.
Daily watch streak from check-ins (`user_id`, `local_date`, `time_zone` from `X-Timezone`).
A day counts when at least one episode, movie, or book progress lands. Milestone bonuses at
7/30/100 days. Trakt-style `StreakBar` on home.

**Done when:** a tick at 23:50 local and one at 00:10 local count as two days, and changing
timezone never breaks a streak retroactively.

### WID-007 · Streak widget · S
**Needs:** GAM-003, WID-001.
Small + accessory: flame, day count, the last seven days as bars.

**Done when:** the widget flips to the new count at local midnight after a tick, with the app
closed.

### GAM-004 · Badges · M
**Needs:** GAM-001.
`user_badges` (`userId`, `badgeType`, `tier`, `awardedAt`); definitions in code. Discovery
badges (first import, first list, first friend, first room) and milestone badges (100 episodes,
first finished anime, 10 books, a full season in a day). Awarded from ledger events only.

**Done when:** every badge has a unit test for its rule, and re-running the evaluator awards
nothing new.

### GAM-005 · Friends leaderboard · S
**Needs:** GAM-001, SOC-002.
Weekly, friends only, opt-in (`leaderboard_opt_in`); blocks applied both ways. No global
board.

**Done when:** a user who has not opted in never appears on anyone's board, including their
friends'.

### GAM-006a · Recap: month and Year in Review · M · pulled forward 2026-10-16
**Needs:** PROG-003.
`GET /v1/me/stats?year=&month=&tz=`: episodes, minutes, active days, finished titles by kind
(anime counted once), month or day buckets, the busiest by time and the one with the most
episodes (none on a tie), the longest run of days, the top
five titles by time, mean and highest rating, and the first and last title of the period. Day
and month edges are the user's time zone; a date-only finish (00:00 UTC) keeps its day
everywhere. Clients play it as a story of animated cards (`RecapStory`) that ends in a share
image. Home offers the year from Dec 1 to Jan 15 and last month in a month's first week;
Settings (web) and the Library menu (Apple) open any of this year, last month and last year.

**Progress 2026-10-16:** built on the server, the web and the Apple apps. All server tests
(Postgres included) and web tests pass; the web story was run locally against seeded data, with
and without reduced motion, and its share image checked. Still to do: run the Apple story on a
device or simulator, with Reduce Motion on and off.

**Done when:** stats are derived only from the user's own library, imported and restored
ticks never count as activity, a tick at 23:30 UTC on Dec 31 lands in the next year east of
UTC, and the share image contains no other user's data.

### GAM-006b · Profile stats and genres · M
**Needs:** GAM-001, GAM-006a, CAT-018.
MAL-style all-time stats on a profile (`StatsPanel`): days watched, mean score, genre and
network breakdowns, anime vs TV. A genre card joins the Recap once genres are stored.

**Done when:** every number matches `/v1/me/stats` summed over the same years.

### CAT-018 · Store genres · S
TMDB `genres` and AniList `genres` are decoded today but only used to compute `isAnime`. Store
them as `titles.genres text[]` at hydration, and backfill titles already in libraries.

**Done when:** a hydrated movie, show and anime each carry their provider's genres, and the
backfill leaves no tracked title without them where the provider has some.

---

# P6 — Realtime, DMs, watch together

Start only after the P2 gate and after SOC-002.

## P6 · Realtime gateway

### RT-001 · WebSocket gateway and presence · L
**Needs:** SOC-002, AUTH-001.
Was M12+ ("list updates and presence"). `/v1/ws` behind the same auth, one connection per
device, typed envelopes (`presence`, `activity`, `dm`, `room.*`, `list.updated`). In-process
`ConnectionManager` actor as in `LuminaVaultServer/Sources/App/WebSockets/ConnectionManager.swift`.
Single replica is documented; Valkey pub/sub is the scale-out path, not built now.
Presence is friends-only and respects `show_activity`. The gateway, hub and group envelopes
ship early with GRP-006 (2026-10-20); this item adds presence, activity and DM delivery.

**Done when:** a friend's "watching now" appears within two seconds, a blocked user receives
nothing, and a dropped connection resumes without duplicate events.

## P6 · Encrypted direct messages (libsignal)

The server is a key directory and a ciphertext mailbox. It never sees plaintext, never holds
a private key, and cannot add a device to a conversation silently.

### DM-001 · Key directory · L
**Needs:** RT-001, SOC-005.
Per **device**: identity key, signed prekey, batch of one-time prekeys (Kyber prekeys too, per
current libsignal). Routes to upload, fetch a bundle (consumes one one-time prekey), and
replenish when low. `devices` table shared with `apns_devices`. Only friends can fetch a
bundle.

**Done when:** fetching a bundle consumes exactly one one-time prekey, a non-friend gets 404,
and the server stores no private key material (schema review + test).

### DM-002 · Ciphertext mailbox · M
**Needs:** DM-001.
`messages` (`id`, `toDeviceId`, `fromUserId`, `ciphertext`, `type`, `createdAt`) deleted on
acknowledged delivery, with a TTL for undelivered rows. Delivery over RT-001, APNs wake-up
with no content in the payload. Attachments are out of the first cut.

**Done when:** a message is deleted from the server after the recipient device acks, and a push
payload never contains message text.

### DM-003 · Apple client · L
**Needs:** DM-002, APP-001.
`LibSignalClient` (Swift). Keys in the Keychain (this-device-only), sessions persisted
locally, safety-number view to verify a friend, conversation list and `ConversationView`.

**Done when:** two physical devices exchange messages, a database dump of the server shows
only ciphertext, and changing a device key shows the safety-number change to the other side.

**OPEN (licence, must be decided before this item starts):** libsignal is **AGPL-3.0**.
Shipping it inside a closed-source App Store app likely obliges publishing the app's source.
Options: open-source the Apple client, or pick a permissively licensed protocol
implementation. This is a human decision, not an engineering one.

### DM-004 · Web DMs · M
**Needs:** DM-003, WEB-001.
**OPEN:** libsignal's TypeScript package is Node-native and does not run in a browser or a
Worker. Options: a WASM build of libsignal, or DMs native-only with the web showing "open on
your iPhone or Mac". Recommendation: native-only first.

**Done when:** the decision is recorded in `ARCHITECTURE.md` and the web either works end to
end or shows the native-only state with no broken route.

### DM-005 · Multi-device · M
**Needs:** DM-003.
iPhone + Mac on one account: per-device sessions, sender fans out to every recipient device and
its own other devices; "linked devices" list with revoke.

**Done when:** a message sent from the Mac appears on the sender's iPhone, and a revoked device
stops receiving within one message.

## P6 · Watch together

Aaru does not own a player, so "together" means a shared moment, not playback control.

### ROOM-001 · Watch-together rooms · L
**Needs:** RT-001, SOC-002.
**Folded into GRP-009 on 2026-10-20:** a room is a `watch` channel inside a group. Kept for its
done-when.
Create a room from a title or episode, invite friends, a lobby with who's ready, a synced
countdown to "press play" in your own player, reactions on a shared timeline, and a shared
check-off at the end (each member's own PROG write, journaled as their tap). Awards
`room attended` (GAM-001).

**Done when:** four members on mixed iOS/Mac/web see the same countdown within 500 ms, and
ending the room ticks the episode for each member who confirms — never for one who does not.

### ROOM-002 · Room chat · M
**Needs:** ROOM-001.
**Resolved 2026-10-20:** plain and server-visible, clearly labelled; E2E stays for DMs. Room
chat is the `watch` channel's own messages (GRP-003, GRP-009) and lives as long as the channel,
not only the session.

**Done when:** closed by GRP-009.

### ROOM-003 · SharePlay · M
**Needs:** ROOM-001.
`GroupActivity` with `.generic` metadata and `GroupSessionMessenger` for Apple users on a
FaceTime call: same countdown, reactions, check-off. Not `.watchTogether` — that needs an
`AVPlayer` Aaru does not have.

**Done when:** two Apple devices on FaceTime run a room over SharePlay with no Aaru room
server involved, and the result still journals each member's tick.

### ROOM-004 · Drift from scrobbles · S
**Needs:** ROOM-001, SCR-001.
When members scrobble, show "Ana is 2 min ahead".

**Done when:** drift shows only for members whose scrobbles arrived in the last minute.

---

# P7 — Agent surfaces

Unchanged from before 2026-10-09. Phase 1.5 in older notes means P7 here.

## P7 · M13 — Agent surfaces

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

## P7 · M14 — Outbound agent surfaces

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
`library:read`, `library:write`, `imports:write`, and `scrobble:write` (added for SCR-001),
defaulting to read-only. Built in P3 ahead of the rest of M14, because scrobbling needs it. Tokens go through
the central rate limiter per X-002.

**Done when:** a token can be created, listed, and revoked from the client; a revoked token is
refused on the next call; deleting the account deletes its tokens; and the secret is
unrecoverable from the database.

**Progress 2026-10-20 (minimal, for Stremio):** server built. `agent_tokens` adds a `kind`
(`stremio` only until OUT-004) so Settings can list Stremio links; `imports:write` is not
mintable yet. Secrets are `aaru_st_` + 32 random bytes, stored as SHA-256; `last_used_at` is
written at most hourly; 120 requests per token per minute. `POST` answers the Stremio manifest,
`stremio://` and Stremio Web install links (`PUBLIC_BASE_URL`, default
`https://api.aaruapp.com`). Request logs redact `/stremio/<token>/` and the Trakt callback's
query. All done-when conditions are server tests; the Settings UI comes with SCR-003.

### OUT-002 · Action provenance for external callers · S
**Needs:** AUD-001, OUT-001.
`actions.actor` gains `external_agent`; `actions` gains a nullable `agentTokenId`. The undo
ribbon shows which agent made the write. Revoking a token leaves its history readable.

**Done when:** a write made over MCP produces one journal row naming its token, the ribbon
renders that name, and revoking the token does not alter or hide the row.

**Progress 2026-10-20 (minimal):** built. `actions.agent_token_id` (set null on delete); writes
take a `Caller` (`.user` by default, `.agent(token)` for outside callers) so the row is
`external_agent` and the summary starts with the token's name ("Stremio: marked S1E2 of X
watched"). `GET /v1/actions` returns `agentName`, still readable after revoke. Undo is unchanged.

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

## Moat exploration — resolved 2026-10-09

These were research items while scrobbling and Trakt output were out of scope. That rule changed;
they are now scheduled. IDs stay so history reads.

### MOAT-001 · Stremio addon exposing an Aaru library · promoted
Now **SCR-003** (P3). Catalogs only, token in the addon URL, no `stream` resource.
Built 2026-10-20 ahead of the gate (owner's call), with `player`/`library` events; see SCR-003.

### MOAT-002 · Watch-state write-back from a player · promoted
Now **SCR-001** + **SCR-002** (P3). It is not two-way sync: a player *sends* a watch event into
Aaru, the same direction as an import. Aaru never reads player state back as a conflict source,
so no conflict engine is needed.

### MOAT-003 · Trakt as an output, not only an input · promoted
Now **SCR-004** (P3): user-triggered push with a dry-run diff, one-way out.

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
- **X-010** Every points award goes through GAM-001's idempotent `award` with a dedupe key. No
  code increments a counter.
- **X-011** Social reads respect `social_settings` and blocks in one place (the data layer),
  not per route. A blocked user gets 404, never 403.
- **X-012** The server never stores DM plaintext or a private key. Any log line, push payload,
  or error message that could contain message content is a bug.
- **X-013** All infra changes go to `~/Work/production/platform/infra`. Secrets are sealed for
  namespace `horus` and the exact secret name.

## Explicitly not doing

Two-way sync · conflict engine · recommendations engine (DISC-001's public provider rows are
not one: nothing personalised) · a global or public activity feed ·
public profile pages indexed by search engines · scraping any site
without an official export (Pogdesign, IMDb pages, AniDB) · a Stremio `stream` resource or any
stream source · hosting TMDB, Open Library or AniList artwork · a second backend · a documented
public API with third-party clients (M14's agent access and P3's scrobble tokens are per-user
and token-scoped, which is a different thing).

Moved out of this list on 2026-10-15 and scheduled after the P2 gate: music, manga, comics and
games (see the 2026-10-15 decisions).

Moved out of this list on 2026-10-09 and scheduled after the P2 gate: scrobbling (P3), MAL /
AniList (P1 catalog, P3 push), friend graph and activity (P4), shared lists (P4), gamification
(P5), realtime, DMs and watch-together (P6). Serializd and SIMKL stay unintegrated.
