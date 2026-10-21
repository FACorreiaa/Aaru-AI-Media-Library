# Aaru backlog

Derived from `README.md`, `CLAUDE.md`, `ARCHITECTURE.md`, `DESIGN.md`, and `VIEWS.md`. This file is the ordered
work list. It does not introduce product decisions; where a decision is still open it is
marked **OPEN** and left for a human.

Scope of this file: Aaru only.

## How to read this

- IDs are stable. Never renumber. Close an item by moving it to **Done** with its ID.
  Until then, the **Status** table below is the record of what is done; update its row when an
  item changes.
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

## Decisions recorded 2026-10-21

- **Friend invite links, profiles and basic social now (owner, 2026-10-21).** Pulled forward
  before the P2 gate, in three PRs. (1) SOC-002's invite links: `aaruapp.com/i/{code}`, one use,
  14 days, revocable, at most 20 open. Accepting makes both people friends at once, with no
  request step: the sender asked by sending it, the friend by opening it. A link may carry one
  title ("Watch Arrival with me"), and the friend chooses whether to add it to Plan to watch.
  The Apple apps claim `/i/*` as universal links. iPhone without the app, Android and desktop
  use the web page, which sends a signed-out friend through sign-in and back. There is no
  Android app yet (later, its own project) and no App Store banner (TestFlight only).
  (2) Friend profiles and activity (SOC-001 settings, SOC-003 minimal). Friends see each
  other's library by default, behind one "Show my library to friends" switch. Strangers see
  nothing, ever. (3) Reactions on activity (SOC-007), recommending a title to friends
  (SOC-006), comparing libraries on a profile, and inviting a friend to a group. No DMs (P6).
  The rule against group invite links stands: these are friend invites only.

- **TV Time built, Bingers not (owner's ask, 2026-10-21).** IMP-012 is built from the documented
  export layouts, ahead of a real export. Bingers has no file export and its API is beta and only
  for paid Legend/Icon subscribers, so it waits for the owner's call (IMP-019).
- **AniList outage: TMDB stands in (CAT-021).** AniList disabled its whole public API on
  2026-10-21 ("temporarily disabled due to severe stability issues", HTTP 403 behind
  Cloudflare). Aaru logged that as `unauthorized`, so the anime rows went empty. Now it reads as
  an outage, and until AniList returns, TMDB's Japanese animation fills the anime Discover rows
  (with a note) and anime search (with a notice). The stand-in approximates AniList: a continuing
  show keeps its first air date, so sequels can miss "this season".
- **Mindspace redesign, and Tonight pulled forward client-composed (owner, 2026-10-21).** Aaru
  keeps its name, marks and teal → gold, and gets one visual language on both clients (DESIGN.md
  "Mindspace"): shared tokens generated from `design/tokens.json` with an AA contrast gate,
  Newsreader bundled for headings, a System / Light / Dark setting per device, and texture
  (pinstripe, grain, edge light) on the Field and the Title room only. The first slice is the
  design system, the Field and the Title room on web, iPhone, iPad and Mac; lists, library,
  calendar, import detail, plans, widgets and the settings/groups palette follow as small PRs.
  **Tonight** (`TonightStrip`) is an owner exception before M13: composed on the device from
  Continue watching and today's airings, no new endpoint, no ranking, no reject. The agent's
  Tonight stays M13. No API, auth, import, permission or persistence change.

- **Music scrobbling (MUS-004…008) is built before the P2 gate**, by the owner's call, after
  albums (MUS-001). Aaru speaks ListenBrainz's submit protocol at `/listenbrainz/1/`, so the
  scrobblers people already use send their listens with a music token: Web Scrobbler (YouTube,
  YouTube Music, Spotify and Apple Music on the web), Pano Scrobbler on Android, Navidrome and
  Jellyfin's ListenBrainz plugin. **No Spotify OAuth**: since February 2026 a Spotify app in
  development mode has 5 users, and extended quota needs a registered business with 250k monthly
  users. **No native Apple Music path on iPhone**: Apple's API gives no play times, and iOS
  cannot watch playback in the background. YouTube has no history API. Listens are a separate,
  append-only log and never touch the library; the same play sent twice (one scrobbler retrying,
  or two scrobblers on one play) is kept once. Past listening comes in through MUS-004. Settings
  was split into groups first (#88) so Music joins Connected apps rather than lengthening it.
- **Seasons on Discover (DISC-002) and music as a fifth kind (MUS-001…003) are built before the
  P2 gate**, by the owner's call, with 0 strangers (flagged; the owner chose). Discover gets a
  Seasons view: one season at a time, its name as the headline, kinds Anime · New shows ·
  Returning · Movies. A season is a calendar quarter for every kind (winter Jan–Mar … fall
  Oct–Dec): anime by broadcast season, shows by premiere or by an episode airing, films by
  first release. Music follows in order: albums as a tracked kind (MusicBrainz + Cover Art
  Archive), New albums / Coming soon rows (ListenBrainz fresh releases), then concerts
  (Ticketmaster Discovery) near a saved city or a one-off approximate location, and for artists
  in the user's library. Every surface ships on web and on iPhone/Mac, in Aaru's design system
  on the web and Apple's HIG on Apple; the owner picked the look (season as an object, square
  album covers, a date-led concert list, skeletons that do not shimmer).
- **Netflix viewing history and a browser-extension scrobbler, both now (owner, 2026-10-21).**
  Netflix's per-profile *Viewing activity* download is an official export: imported like any file
  (IMP-018). Netflix, Disney+ and Prime Video have no API, so live plays in a browser come through
  an Aaru browser extension (SCR-007). **This is an owner exception to "no scraping"**: the
  extension reads the player page in the user's own browser, for the user's own session, and
  sends a scrobble to Aaru. It makes no request to the site beyond what the page already makes,
  Aaru's server fetches nothing from these sites, it never controls playback, and it touches no
  stream source. Scrobbling is P3; built ahead of the gate like SCR-003. Its token is a new
  `browser` kind that can only scrobble.
- **Titles known only by name** (CAT, Netflix, a browser player) match by exact normalized name,
  only when exactly one TMDB entry of that type has it and came out by the year it was watched.
  Episodes named but not numbered (Netflix) match by name: in the same season first, else the one
  episode in the show with that name. Anything else stays unmatched; nothing is guessed.
- **Last 7 and 30 days on Home, a fuller Year in Review, and stored genres are built before the
  P2 gate**, by the owner's call, with 0 strangers. Modelled on north's recap: Home gets a
  compact "Last 7 days" strip (a bar per day plus the week's figures) that opens Insights on a
  7 days / 30 days toggle. Items: GAM-006d, then CAT-018, then GAM-006e (Year in Review v2:
  genres, biggest day, the year's arc, kinds, a persona from the user's own numbers).
- **Rolling windows compare with the window just before, in absolute numbers** (`+3`, `−2 h`).
  No percentages: a change from zero has none. A change of zero is not shown. The strip shows
  at zero too, as APP-013 asked.
- **Rolling windows read the same activity as the Recap**: imported and restored ticks still
  never count. A rolling window has no Recap story; the story stays a month or a year.
- **"Synced with Trakt" means connect + import, re-run by the user** (owner). Each user connects
  their own Trakt account (IMP-002) and imports it (IMP-003); importing again fills gaps and moves
  statuses forward under the IMP-004 merge rules. No polling of Trakt, no push out before SCR-004
  (P3), never two-way.
- **Trakt's 2026 API, checked against github.com/trakt/trakt-api:** OAuth calls must use
  `auth.trakt.tv` from 2027-02-01; `/sync/watched/*` is paged (max 250) and shows carry episodes
  only with `extended=progress` (enforced after 2026-06-30); watchlists default to 10 items without
  `page`/`limit`; refresh tokens are single use; requests need a `User-Agent`; reads are 500 per
  5 minutes per user. **Free Trakt accounts can connect only two apps**, so disconnecting revokes
  the token on Trakt to give the slot back. Trakt's policy asks for "Aaru uses Trakt but is not
  endorsed or certified by Trakt" wherever the integration is offered and in the App Store
  description.
- **Owner actions:** GitHub-verify the Trakt developer account before 2027-01-01 (unverified apps
  become unapproved); confirm the app's redirect URI is exactly
  `https://api.aaruapp.com/v1/imports/trakt/callback`; Trakt deletes apps unused for 30 days, so
  connect a real account soon after this ships.
- **CAT import (IMP-009/010), by the owner's call:** shows come in as a pasted list, the iCal file,
  or the user's own CAT iCal link. The link is the one request Aaru makes to pogdesign.co.uk: read
  once when pasted, never stored or logged (it holds the user's CAT key); no other CAT page is read,
  so "no scraping" stands. Every CAT show is planned `wishlist`, no progress. CAT names carry no ids
  and rarely a year, so they match by exact normalized name and only when one TMDB show has it.

- **Concerts in Portugal need a second provider (MUS-009, owner 2026-10-21).** Probed with the
  live key the day MUS-003 shipped: Ticketmaster's Discovery API lists 0 music events in
  Portugal (country and 25/50/100 km around Lisbon and Porto) against 1,215 in Spain (78 within
  25 km of Madrid). Bandsintown is added behind the same `ConcertListing` once the owner has an
  app id; Portuguese ticket sites (BOL, Ticketline, Blueticket) have no public API and are not
  scraped.

## Decisions recorded 2026-10-20

- **Discover rows on Home (DISC-001), by the owner's call:** a new account opened to an empty
  Home. Home now also shows provider-curated public lists: trending shows, this season's anime,
  trending movies, on the air, trending anime, new shows, in theaters, trending books. They are
  the same for every user and read no per-user signal, so they are **not** the out-of-scope
  recommendations engine; nothing personalised ("because you watched…") is allowed under this
  item. Posters stay hotlinked catalog URLs.
- **Discover, Insights and a fuller Home are built before the P2 gate**, by the owner's call,
  with 0 strangers (flagged; the owner chose). Prompted by the owner's own first run: a search
  for "Mobland" from Home found nothing and an empty library left Home, Library and Calendar
  blank. Items: CAT-019, UPN-002, GAM-006c, APP-011…APP-015
  (CAT-020 superseded by DISC-001).
- **Search defaults to All** (CAT-019): `type=all` is TMDB `search/multi` (films and shows,
  people dropped) plus AniList, in parallel, merged on the server, each row keeping its kind.
  **Books stay out of All** (Open Library is the slowest and noisiest provider); All ends with
  a "Search Books for 'x'" row. A TMDB show is dropped only when `anime_mappings` links it to an
  AniList hit in the same results. Nothing is merged on a name.
- **The Discover tab/page is built on DISC-001's rows** (APP-012). This branch first had its
  own `GET /v1/discover?section=` (CAT-020); on merging with DISC-001 the owner kept DISC-001's
  API, so CAT-020 is superseded. Discover shows the same rows as Home (books included) as a full
  destination. Items carry `libraryItemId` for the caller: the server's list cache holds no user
  data, and the per-user mark is one library query applied after the cache read. Still catalog
  data, the same lists for everyone, not a recommendations engine (see the DISC-001 bullet).
- **Insights (GAM-006c) pulls part of GAM-006b forward**: all time, by kind, a ratings
  histogram, on `/v1/me/stats`. Genres (CAT-018), networks, badges and the profile placement
  stay in P5.
- **Status labels are per kind; stored values do not change** (APP-014). `wishlist |
  in_progress | finished | dropped` stay the wire and domain words. Films, shows and anime read
  Plan to watch / Watching / Watched / Dropped; books read Plan to read / Reading / Read /
  Dropped; with no kind, Planned / In progress / Finished / Dropped.
- **"Multiple watchlists" are Lists** (APP-015): Lists become a top-level destination and
  Discover cards get Add to list. There is no starter "Watchlist" list; the `wishlist` status
  already means that. Shelves stay API-only.
- **The iPhone tab bar stops at five**: Home · Discover · Library · Calendar · Lists. Insights
  is not a tab; it opens from Home's stats strip and next to Recap.

- **Agent connections, MCP, the Claude connector and remote approval are built before the P2
  gate**, by the owner's call, with 0 strangers (flagged; the owner chose). The owner wants Aaru
  reachable from Claude, Claude Code, Codex, Hermes and Gemini the way Loci, Khepri and
  LuminaVault are. Items: OUT-001 (all MCP client kinds), OUT-002, OUT-004 with the OAuth front
  door the 2026-10-15 Claude connector note asks for, AG-001's tools (in-process, no model) and
  AG-003's remote-plan slice. Remote plans are always "ask me": there is no autonomy dial
  (AG-007). Not included: the composer, The Field (pending plans pin to Home instead), App
  Intents (OUT-003), `ModelProviding` and capture. MCP lives in `aaru-server/Sources/App/MCP`, a
  folder rather than a SwiftPM target: `aaru` is an executable target, and the done-when
  ("deleting it leaves `/v1` whole") holds for the folder plus its one line in `buildRouter`.
- **MCP tokens are listed apart from Stremio links.** `GET /v1/agent/tokens` takes
  `for=stremio|mcp` and defaults to `stremio`, because shipped Apple builds decode the token kind
  as a closed enum and would fail on an MCP kind. Drop the default once those builds age out.

## Decisions recorded 2026-10-20

- **Imports move status forward only.** A later import may take a title from wishlist to in
  progress to finished, never backward, never out of dropped, and never past a status the user
  chose. Fill-empty stays the rule for ratings and dates. Owner's call after the multi-source
  audit (IMP-004).
- **Web push is un-deferred** (by the owner's call: "notifications working, on web and iOS"):
  airing alerts reach browsers too, over standard Web Push with a VAPID key (`VAPID_CONFIG`,
  sealed in `aaru-env`, generated once). Endpoints are limited to the browsers' push services.
  iPhone and iPad get browser alerts only from Aaru added to the Home Screen.
- **Stremio history import (IMP-016), by the owner's call:** the addon only sees playback after it
  is installed, so past history comes from Stremio's account API through its device-link code: the
  user approves on stremio.com, Aaru reads the library once, logs the session out and never stores
  the key. The API is unofficial; it is used once per import, never polled or synced (still no
  two-way sync). An export-file fallback follows once a real export is in hand.
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
  **2026-10-20:** the alert carries `libraryItemId`, and a tap opens that show on iPhone (also
  from a cold launch). Production has the APNs key (`APNS_KEY_ID` set, `.p8` sealed in
  `aaru-env`). An alert needs the switch on, a show `in_progress`, and an episode that airs after
  the switch was turned on. Mac push still waits on the Push capability in the Mac profile.
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

## Status (verified 2026-10-20)

Checked item by item against `origin/main` at `62dfe1d` (PR #46), every Claude session on this
repo, and the merged PRs here and in the infra repo. Production runs `5be7fef` (infra #376);
#39 (Settings tab), #41 (import merge), #42 (push tap), #45 (web push) and #46 (Stremio history)
are on `main` and wait for the next promote PR. Unmerged branches (Groups, realtime: #40, #44,
#47, #48) are not counted.

| Phase | Done | Gate | What blocks it |
| --- | --- | --- | --- |
| **P0 — Rails** | 14/16 (1 built, unverified; 1 dropped) | **Met** | Nothing. `INFRA_TOKEN` is unset by choice, so promote PRs are opened by hand and Server Deploy's promote job shows red |
| **P1 — Basics (API)** | 30/31 (1 built, unverified) | **Met** | Nothing; CAT-010's first production load of the anime mappings is unconfirmed (CronJob first fires 2026-11-02) |
| **P2 — Clients, widgets, imports** | 31/54 (12 built, unverified; 3 partial; 7 open; 2 deferred; 1 dropped) | Not met | No stranger has used it; widgets and the Live Activity never seen on a device; Trakt never run on a real account; CAT list/ICS import (IMP-009/010) built but never run on a real CAT export; unmatched-row triage (IMP-011) built, never run on a real import |
| **P3 — Tracking** | 1/6 (1 partial) | Not met | Stremio addon built and deployed (SCR-003) but playback never tried live; no `/v1/scrobble/*` routes, no Plex/Jellyfin |
| **P4 — Social** | 0/8 (3 partial) | Not met | Push plumbing (SOC-005, airing alerts), handles and friends by handle (SOC-001/002 minimal), invite links built (SOC-002) |
| **P5 — Gamification** | 1/9 (1 partial) | Not met | Recap (GAM-006a) only; no points ledger, streaks, badges |
| **P6 — Realtime, DMs, rooms** | 0/10 | Not met | Nothing on `main` |
| **P7 — Agent surfaces** | 0/12 (3 partial) | Not met | Agent tokens exist for Stremio only; no tool layer, MCP or model provider |

Totals over 147 items: **Done 75**, built but unverified 12, partial 9, open 44, deferred 2,
dropped 5. "Done" means the item's own **Done when** is met by code on `main` (caveats noted);
"Built, unverified" means the code is on `main` but the Done-when asks for a device run, a real
account or a stranger that has not happened yet.

**Known gaps no item owns yet:**

- **Undo ribbon.** DESIGN.md and AUD-001 require it, WID-002 and OUT-002 depend on it, and the
  server's `POST /v1/actions/{id}/undo` exists, but no client calls it.
- IMP-004's text still says a later source never overwrites a status; since 2026-10-20 (#41)
  status moves forward only (see that day's decision).
- PRV-001's ODbL credit no longer applies: anime mappings come from Fribb (MIT).

### Every item

| ID | Status | Evidence | Caveat |
| --- | --- | --- | --- |
| --- | --- | --- | --- |
| REL-001 | Done | #1 577ba6e; `.github/workflows/ci-*.yml` path filters | Nested `aaru-server/.github` gone |
| REL-002 | Done | #1; no `*.pkg` in tree | |
| REL-003 | Built, unverified | #1, #3; `aaru-ios/Config/{Beta,Release}.xcconfig` | Release app never installed beside Beta on a device |
| REL-004 | Done | #3, #4; `release-apple.yml` succeeds on every main merge | iOS + macOS lanes; `release` dispatch-only |
| REL-005 | Done | infra #292, #321, #376; `api.aaruapp.com/v1/health` = 200 | INFRA_TOKEN unset: Server Deploy run is red, promote PRs opened by hand |
| REL-006 | Done | #20, #21; `web-deploy.yml` (beta on merge, prod on dispatch) | |
| DSN-001 | Dropped | DESIGN.md:421 "ScreensDesign was not used" | Optional item, skipped (Pro plan) |
| DSN-002 | Built | #102, #103, #104, this PR; `npm run tokens:check` in Web CI; screenshots on beta.aaruapp.com (light + dark, real data) and iPhone/iPad simulators | Widgets, Dynamic Type at accessibility sizes, VoiceOver and the Mac layout not yet checked on a device (TestFlight from 35cfb64) |
| SRV-001 | Done | #1; no `getHello`/WebSocket in code | |
| SRV-002 | Done | #1; `openapi.yaml` `/v1` + shared error schema | |
| SRV-003 | Done | #1; no Fluent import under `Sources/App/API`; `TestFakes.swift` | |
| SRV-004 | Done | #1; `Data/Migrations/Migrations.swift` | |
| SRV-005 | Done | #1; Migrations.swift | |
| SRV-006 | Done | #1; Migrations.swift | |
| SRV-007 | Done | #1; Migrations+Imports.swift | |
| SRV-008 | Done | `Config/AppConfig.swift` requires TMDB_API_KEY; `.env` ignored | |
| SRV-009 | Done | `ci-swift.yml` swiftformat --lint + tests on Postgres | Deliberate-failure run not recorded |
| AUTH-001 | Done | #2 5f873ce; AuthMiddleware.swift, APITests 401 | |
| AUTH-002 | Done | #2; AppleVerifierTests (exp, kid refresh) | |
| AUTH-003 | Done | #2, #8; AuthFlowTests rate limit | Email depends on Resend sender config |
| AUTH-004 | Done | AuthFlowTests "AUTH-004: … no row anywhere" | |
| AUTH-005 | Done | #18, #19; GoogleSignInTests linking/409; LinkGoogleButton.swift | |
| CAT-001 | Done | #2; ProviderClientTests (429 retry) | |
| CAT-002 | Done | #2; TMDBCatalog.swift | |
| CAT-003 | Done | #2; ISBNTests, OpenLibraryCatalog.swift | |
| CAT-004 | Done | #2; `/v1/search` | |
| CAT-005 | Done | #2; CatalogResolutionTests (concurrent adds) | |
| CAT-006 | Done | #2, #36; CatalogRefreshTests | |
| CAT-007 | Done | #2; AniListCatalog.swift | |
| CAT-008 | Done | #2; aaru-core anime ids, WireContractTests | |
| CAT-009 | Done | #2; TitleResolver.swift | |
| CAT-010 | Built, unverified | #36 e8bdebb; AnimeMappingLoader.swift; infra #362 CronJob | First production load not confirmed; CronJob first fires Nov 2 |
| LIB-001 | Done | #2; `POST /v1/library/items` | |
| LIB-002 | Done | #2; LibraryTests | No EXPLAIN check in tests |
| LIB-003 | Done | #2; LibraryTests | |
| LIB-004 | Done | LibraryTests "LIB-004: a delete on one device…" | |
| AUD-001 | Done | #2; `actions` journal, LibraryService.swift | |
| AUD-002 | Done | #2; `/v1/actions/{id}/undo`, 409 tests | Server only; no client undo ribbon |
| PROG-001 | Done | #2; episodes PUT route | |
| PROG-002 | Done | #2; seasons watched route | |
| PROG-003 | Done | #2; LibraryTests nextEpisode | |
| PROG-004 | Done | #2; ValidationTests percent | |
| LST-001 | Done | #2; ListShelfTests visibility | |
| LST-002 | Done | #2; `/v1/lists/{id}/items`, `/order` | |
| LST-003 | Built, unverified | ListShelfTests LST-003, CatalogRefreshTests | iOS not checked on TestFlight yet |
| SHF-001 | Done | #2; `saved_queries` | API-only by decision |
| SHF-002 | Done | #2; `/v1/shelves/{id}/items` | |
| CAL-001 | Done | #2, #24; ScheduleTests premiere/finale | |
| CAL-002 | Built (web) | app_.week.tsx, components/calendar/* | Posters, sheets, Missed, filters; `stillUrl` on `CalendarEntry` |
| CAL-003 | Built (Apple) | Calendar/CalendarEpisodeSheet, CatchUpView, CalendarFilter | Same as CAL-002 on iPhone, iPad, Mac; not seen on a device |
| UPN-001 | Done | #2; `/v1/up-next` | |
| APP-001 | Done | #7 432e35f; SessionMiddleware (12 concurrent 401s) | |
| APP-002 | Done | #8; SessionKeychain.swift | Mac relaunch persistence not recorded |
| APP-003 | Built, unverified | #10; LibraryCache.swift | Offline checked in simulator; 1,000-item scroll not measured |
| APP-004 | Done | #10; SearchView.swift, SearchPanel.tsx | iOS not driven in simulator |
| APP-005 | Done | #11; TitleDetailModel.swift | Rollback verified on web only |
| APP-006 | Done | #12; ListsView.swift, AddToListDialog.tsx | |
| APP-007 | Done | #15, #39 e12567e; SettingsView.swift, ImportDetailView.swift | Live-ish polling verified on web only |
| APP-008 | Partial | sidebarAdaptable + ⌘F in RootView/LibraryView | No ⌘N add shortcut |
| APP-009 | Built, unverified | #25 6d90253; HomeCache.swift | Sample data only; web has no offline cache |
| DISC-001 | Built, unverified | #38 eaeb15e; DiscoverService.swift; deployed | No recorded new-account run on 3 clients |
| DISC-002 | Built, unverified | #84; DiscoverSeasonTests, season model tests; deployed f5dcb8c (infra #412) | Not run on a device |
| MUS-001 | Built, unverified | #93; MusicTests, StatsTests; deployed f5dcb8c (infra #412) | Not run on a device |
| MUS-002 | Built, unverified | #98; ListenBrainzReleasesTests; deployed 8b3f017 (infra #413) | Not run on a device |
| MUS-003 | Built, unverified | #105; ConcertTests; deployed f0525f0 (infra #415, key #414) | Not run on a device; Ticketmaster lists nothing in Portugal (MUS-009) |
| MUS-005 | Built, unverified | ListenBrainzRouteTests | Not deployed; not tried with a real scrobbler |
| MUS-006 | Built, unverified | RecordingMatchTests, ListenResolverTests | Not deployed; not run against MusicBrainz itself |
| MUS-007 | Built, unverified | MusicSection (web, Apple); ListenBrainzRouteTests `musicSetup`; music model tests | Not deployed; steps checked against client source, not tried with a real scrobbler |
| MUS-008 | Built, unverified | ListenStatsTests; listening-model and recap deck tests; `/app/music`, MusicView, MusicInsights, OnRepeatCard | Not deployed; not run on a device with real listens |
| MUS-009 | Not started | — | Waits for a Bandsintown app id |
| APP-010 | Done | #23 13227ae; WeekGridView.swift, WeekGrid.tsx | Sample data only |
| WID-001 | Built, unverified | #26 b2285d4; WidgetSnapshot.swift | Not seen on a device |
| WID-002 | Partial | #26; MarkEpisodeWatchedIntent.swift | No undo ribbon in any client |
| WID-003 | Built, unverified | #26; CountdownWidget.swift | Not seen on a device |
| WID-004 | Built, unverified | #26; WeekWidget.swift | Not seen on a device |
| WID-005 | Built, unverified | #35 f7fc4a1; NowWatchingLiveActivity.swift | Not run on a device |
| WID-006 | Built, unverified | #26; same extension for macOS | Mac intent not shown working |
| JOB-001 | Done | #13, #36; ImportWorker.swift, CatalogRefreshService.swift | Journal pruning not built |
| IMP-001 | Done | #13 c12c751; `/v1/imports/{id}` + apply | |
| IMP-002 | Done | #16 9cb13d5; TraktTests (PKCE, state, refresh, refresh lock, revoke); infra #341 | No real Trakt account connected yet |
| IMP-003 | Built, unverified | #16; TraktImporter.swift (paged, `extended=progress`) | Stub Trakt only; 10,000-item run not measured |
| IMP-004 | Done | #41 f54b1e7; ImportMergeTests | Not deployed; no literal Trakt→Letterboxd rating test |
| IMP-005 | Done | #13; `/v1/imports/csv` 413/422 tests | 5 MB cap |
| IMP-006 | Done | #13; CSVImportParser.swift | |
| IMP-007 | Done | #13; CSVImportParser.swift | |
| IMP-008 | Done | #13; ImportParserTests | |
| IMP-009 | Built, unverified | `feat/cat-import`; CATImport.swift, CATImportTests | Stub catalog and synthetic lists only; no real CAT profile paste yet |
| IMP-010 | Built, unverified | `feat/cat-import`; CATCalendarParser, CATCalendarFeed | SUMMARY format confirmed on a real export (`Show S01E02 - \nTitle`, 45 shows); a same-name tie breaks on the episode's air date; link not yet run live |
| IMP-011 | Built, unverified | `POST /v1/imports/{id}/rows/{index}/resolve`; ImportService+Resolve.swift, ImportResolveTests; "Find it" on web + Apple import detail | Not run on a real import yet |
| IMP-012 | Built, unverified | `feat/import-tvtime-bingers`; TVTimeCSVParser, TVTimeImportTests | Fixtures written from documented column shapes; no real export run yet |
| IMP-013 | Done | #28 b70e9bd; AnimeListImportTests | Fixtures only, no real 300-entry export |
| IMP-014 | Done | #28, #41; `/v1/imports/anilist` | |
| IMP-016 | Built, unverified | #46 62dfe1d; Imports/Stremio/*, StremioImportTests | Not deployed; no real account library |
| IMP-017 | Built | ImportSpeedTests, imports model tests; local run of a 2,001-entry MAL export | Live 2026-10-21 (API c8b19e7, LuminaVaultInfra#405; web prod); Apple ledger not run on a device |
| IMP-018 | Built, unverified | `feat/netflix-import`; NetflixCSVParser, EpisodeNameMatcher, NetflixImportTests | No real export run yet |
| IMP-019 | Open | BACKLOG IMP-019 | Bingers has an API only for paid plans; owner decides |
| PRV-001 | Done | #27 8d5ddc3; docs/providers.md, AboutView.swift | privacy@ routing not set up |
| CAT-011 | Done | #24 7edc80c; TVmazeAirTimes.swift | |
| CAT-012 | Open | no Google Books code | |
| CAT-013 | Open | no Wikidata code | |
| CAT-014 | Open | no watch-providers code | |
| CAT-015 | Open | none | Scheduled after P2 gate |
| CAT-016 | Open | none | Scheduled after P2 gate |
| CAT-017 | Deferred | heading "Deferred" | |
| CAT-019 | Done | #43 5be7fef; CatalogSearchAllTests (Mobland) | Stub tests |
| CAT-020 | Dropped | superseded by DISC-001 | |
| CAT-021 | Built | AniListCatalog.classify, TMDB anime stand-in | Stub tests; live AniList outage 2026-10-21 |
| UPN-002 | Done | #43; ScheduleTests UPN-002 | |
| GAM-006c | Done | #43; StatsTests "all time equals the years summed" | |
| GAM-006d | Done | #65; StatsTests GAM-006d, insights/home model tests | iOS not run on a device |
| APP-011 | Done | #43; SearchPanel.tsx, SearchView.swift | Not seen on a device |
| APP-012 | Done | #43; DiscoverScreen.swift, app_.discover.tsx | |
| APP-013 | Done | #43; HomeSummary.swift, app.tsx | The strip hid at zero until GAM-006d |
| APP-014 | Done | #43; LibraryRow.swift, library/model.ts labels | |
| APP-015 | Done | #43; RootView `lists` tab | |
| APP-017 | Built | library/NowSection (web), Library/NowSection (Apple) | Watching, Reading, Listening; book page counts from Open Library (`titles.page_count`, backfilled) |
| LAND-001 | Partial | #5, #9; routes/index.tsx, demo/ gone | No prerender config found; Lighthouse never run |
| LAND-002 | Open | no waitlist code | |
| LAND-003 | Done | #27; docs/privacy.md, /privacy | Names all six third parties |
| WEB-001 | Done | #9 da50ed5 + later; ARCHITECTURE.md lists it | |
| SCR-001 | Built | #36; ScrobbleService.swift, ScrobbleRoutes.swift, ScrobbleTests, ScrobbleRouteTests | `/v1/scrobble/*` for scrobble tokens only (SCR-007); no live player yet |
| SCR-002 | Open | no Plex/Jellyfin code | |
| SCR-003 | Done | #36 e8bdebb; Sources/App/Stremio; deployed | Verified in Stremio Web on local server; playback events not tried |
| SCR-004 | Open | none | |
| SCR-005 | Open | none | |
| SCR-006 | Open | none | |
| SCR-007 | Built, unverified | `aaru-extension/`; session + site fixture tests; ScrobbleRouteTests; `/connect/extension` | Site selectors not yet checked on the live players; not in any store |
| SCR-008 | Built, unverified | NowPlaying.swift, NowPlayingNotifier.swift, LiveActivityPush.swift, NowPlayingTests; `NowPlayingCard` (web, iOS); `/v1/me/now-playing` | Live Activity pushes not yet seen on a device |
| SOC-001 | Built, unverified | `profiles`, `PUT /v1/me/profile`, `social_settings` (`share_library_with_friends`), `/v1/me/social-settings`, `/v1/social/friends/{userId}/profile`; SocialTests, FriendTests | Points, streaks and leaderboard settings wait for P5 |
| SOC-002 | Built, unverified | requests, friends, blocks, reports; invite links (`social_invites`, `/v1/social/invites`, `/v1/invites/{code}`, web `/i/{code}`, AASA); SocialTests, InviteTests | Seed signing ran on the branch 2026-10-21; universal links not tried on a device; contact email hash not built |
| SOC-003 | Partial | `GET /v1/activity` (dated ticks and finishes, 14 days); FriendTests; web `/app/friends`, iOS Friends tab | No `FriendStories` on Home, no scrobbles, no save-to-wishlist yet |
| SOC-004 | Open | none | |
| SOC-005 | Partial | #17, #42, #45; Push.swift, `/v1/devices`, `/v1/me/notifications` | Airing push only; no friend-request category |
| SOC-006 | Built, unverified | `social_recommendations`, `/v1/social/recommendations`, `/v1/me/recommendations*`; InteractionTests; web Recommend (title page, profile) and inbox, iOS RecommendSheet and inbox | No push to the recipient yet (needs a notification category) |
| SOC-007 | Built, unverified | `social_reactions`, `PUT/DELETE /v1/activity/{id}/reaction`, reactions on `ActivityItem`; InteractionTests; web and iOS Lately rows | |
| SHR-001 | Open | none | |
| GAM-001 | Open | none | |
| GAM-002 | Open | none | |
| GAM-003 | Open | none | |
| WID-007 | Open | none | |
| GAM-004 | Open | none | |
| GAM-005 | Open | none | |
| GAM-006a | Done | #32 4657b9d; StatsTests, Recap* (iOS + web) | Apple story never run on device |
| GAM-006e | Done | #67; StatsTests+YearReview, recap model tests | Persona copy awaits the owner; Apple story never run on device |
| GAM-006b | Partial | #43 Insights covers all-time/by-kind | No genres, profile placement, badges |
| CAT-018 | Done | #66; GenreTests, CatalogAdapterTests "genre names" | Pulled forward 2026-10-21 for GAM-006e; backfill runs in the catalog refresher |
| RT-001 | Open | none (PR #48 open) | |
| DM-001 | Open | none | |
| DM-002 | Open | none | |
| DM-003 | Open | none | |
| DM-004 | Open | none | |
| DM-005 | Open | none | |
| ROOM-001 | Open | none | |
| ROOM-002 | Open | none | |
| ROOM-003 | Open | none | |
| ROOM-004 | Open | none | |
| AG-001 | Built | Agent/AgentTools.swift | All five tools, over MCP; no in-app composer (AG-004) |
| AG-002 | Open | none | |
| AG-003 | Partial | Plans/PlanService.swift, `/v1/plans` | Remote agent plans only; no autonomy dial |
| AG-004 | Open | none | |
| AG-005 | Open | none | |
| AG-006 | Open | none | |
| AG-007 | Open | no ModelProviding | |
| OUT-001 | Partial | #36; AgentTokenService.swift, `/v1/agent/tokens` | Stremio and MCP kinds; `imports:write` not mintable |
| OUT-002 | Partial | #36; ProvenanceTests, `agentName` on `/v1/actions` | No MCP; no client ribbon renders it |
| OUT-003 | Partial | MarkEpisodeWatchedIntent.swift (widget/Live Activity) | No Shortcuts provider, "tonight", share URL |
| OUT-004 | Built | Sources/App/MCP, `/v1/plans`, Sources/App/OAuth | Claude connector unverified against claude.ai until deployed |
| OUT-005 | Open | none | |
| MOAT-001 | Dropped (promoted) | now SCR-003 | SCR-003 built |
| MOAT-002 | Dropped (promoted) | now SCR-001/002 | |
| MOAT-003 | Dropped (promoted) | now SCR-004 | |

### P0 progress log (from 2026-10-09; merged in #1, deployed 2026-10-15)

| Item | State |
| --- | --- |
| SRV-001…SRV-008 | Built; 13 server tests pass against local Postgres; `--db-migrate` verified from the CLI. |
| SRV-009, REL-001 | Root workflows written (`ci-swift`, `ci-apple`, `ci-web`); all checks pass locally. Unverified on GitHub until pushed. |
| REL-002 | Done. |
| REL-003 | Project builds for iOS Simulator and macOS; Beta/Release settings resolve. Side-by-side install on a device needs App IDs registered and real icons. |
| REL-004 | Lanes and workflows written. Needs ASC records, App IDs, secrets, and one Seed signing run. |
| REL-005 | Image builds from the repo root and was smoke-tested locally (migrate, fail-fast, health 200); promote workflow written; infra draft PR LuminaVault/LuminaVaultInfra#292. Needs `TMDB_API_KEY` sealed, first image tag, `/data/pg-aaru` on the node, `INFRA_TOKEN`, and the domain. |
| REL-006 | Workers configs + deploy workflow written; check/lint/test/build pass locally. Domain `aaruapp.com` (Cloudflare, 2026-10-15): prod Worker on `aaruapp.com` (+ `www` → apex 301), beta on `beta.aaruapp.com`, no `workers.dev`; security headers in `src/start.ts`. Needs `CLOUDFLARE_API_TOKEN` + `CLOUDFLARE_ACCOUNT_ID` (token also needs Workers Routes + DNS edit on the zone for the custom domains). |

### P1 and later progress log (from 2026-10-09)

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
| IMP-016 Stremio history | Built 2026-10-20 (server, iPhone, iPad, Mac, web): Settings → Stremio → "Import my Stremio history" shows a code + QR, polls every 3 s, then opens the import's plan. Watched films, in-progress titles, wishlist, and ticked episodes (bitfield over Cinemeta's list). Checked with stub transports and a live link-code create/read only; not yet against a real account's library. The export-file fallback waits for a real export. |
| PRV-001, LAND-003 | Built 2026-10-16: `docs/providers.md` (register) and `docs/privacy.md` (policy, rendered at `aaruapp.com/privacy`); `/about` and the Apple About screen show the TMDB logo + notice, TVmaze (CC BY-SA), AniList, Open Library. `privacy@aaruapp.com` needs Cloudflare Email Routing. No self-serve export yet (policy says "ask us"). |
| APP-009 Home rows | Built 2026-10-16 on iPhone, iPad, Mac and web: Home is the first destination (Home · Library · Calendar; web library moved to `/app/library`). Continue watching (one-tap check advances optimistically), Airing soon / Coming up (badges from `airTimeKnown`), Start watching. Apple renders from a disk cache first; the web has no offline cache yet. In-progress movies are not in Continue watching (server returns shows only). Checked with sample data only. |
| WID-001…004, WID-006 | Built 2026-10-16 (iOS + macOS, one extension): App Group snapshot (`Shared/WidgetSnapshot.swift`) written after every Home load and tick, an hourly `BGAppRefreshTask` on iOS, cleared on sign-out. Up Next (small/medium/large) with an interactive "mark watched" App Intent that calls the same PUT with the shared Keychain token, advances optimistically and restores on failure; Next Episode countdown (small + Lock Screen accessories on iOS; entries at each air time flip to "Out now"); This Week (large/extra large, Monday-first, deep links `aaru://title/{id}`). Not yet seen on a device; no undo ribbon for widget ticks; the large Up Next has no progress bar (the snapshot has no episode totals). WID-005 (Live Activity) is next. |
| WID-005 | Built 2026-10-19 (iOS only, client-side; no server change): "Start watching" from an aired episode's context menu in title detail and from Home's Continue watching card starts a `NowWatchingAttributes` Live Activity (one at a time; poster downsampled into the App Group). Lock Screen + Dynamic Island: poster, `S1 · E8 · Name`, progress bar, "Ends at" ↔ "Nm left" via `ToggleEndTimeIntent`, "Mark watched" via `MarkNowWatchingIntent` (same PUT and widget path as the Up Next check). Stale after end + 30 min ("Did you finish?"), ended on app foreground and in the background refresh; ticking that episode anywhere ends it with a brief "Watched". Started by check-in only; scrobble start is P3. Not yet run on a device. |
| DISC-001 Discover rows | Built 2026-10-20 on iPhone, iPad, Mac and web: `GET /v1/discover` returns up to eight public rows (TMDB trending/on the air/new shows/trending movies/in theaters, AniList this season + trending, Open Library weekly trending), cached in memory for 6 h, a failing provider dropping only its row; items the caller has carry `libraryItemId`. Home renders them under the user's rows; a new account sees a slim "Add a show" header above them. Adding from a card is search's add (wishlist, or a status, or a list). TMDB rows checked with stubs only (no local key); AniList and Open Library checked live. |
| APP-010 + catch-up month | Built 2026-10-15 on iPhone, iPad, Mac and web: Calendar destination with Week (CAT grid / iPhone day pager) and Month (Stremio-style posters + agenda). Server adds `backdropUrl`, `network`, `airTimeKnown`, `episodeOverview`; range up to 42 days. Checked with sample data only. |
| CAT-019, UPN-002, GAM-006c, APP-014 (server) | Built 2026-10-20 on `feat/discover-insights`, tests against stubs only: `type=all` search with `releaseDate` on hits, Up Next `counts` + `unfinished`, `/v1/me/stats?span=all` with `byKind` and the ratings distribution, per-kind labels in journal summaries and the Stremio catalog name. CAT-020's own `/v1/discover` was dropped for DISC-001's in the merge. Clients (APP-011…APP-015: Discover tab/page on DISC-001's rows, Insights, Home additions, Lists tab) are being built. |

**P1 gate** (works end to end against the production API on `maat`): met. The API has been live
on `maat` since 2026-10-15 with the Apple and web clients on it.

---

## Phase map

| Phase | Groups | Exit gate | Status (2026-10-20) |
| --- | --- | --- | --- |
| **P0 — Rails** | REL, M1 server foundation | CI green from repo root; empty app builds to TestFlight beta; API image deploys to `maat` via promote PR; web Worker deploys | **Done** — gate met |
| **P1 — Basics (API)** | M2 auth, M3 catalog + anime, M4 library, M5 progress, M6 lists, Calendar + Up Next | A personal tracker works end to end over `/v1`: sign in, search movies/shows/anime/books, add, tick episodes, lists, calendar, up next | **Done** — gate met |
| **P2 — Clients, widgets, imports** | M7 iOS + Mac, Widgets, M10/M11 web, M8 Trakt, M9 file imports, catalog sources | **The "basics done" line.** TestFlight beta and the beta Worker are usable by a stranger end to end; widgets work; Trakt + CSV imports work | In progress — 29/54 done; not met |
| **P3 — Tracking integrations** | Scrobble, Stremio, Plex/Jellyfin, outbound Trakt/MAL/AniList | A play in Plex, Jellyfin or Stremio moves Aaru progress without a tap | Started — 1/6 (Stremio addon) |
| **P4 — Social** | Profiles, friends, activity, push, shared lists, groups | Two users can friend, see each other's activity, and block cleanly; friends chat in a group | Not started (airing push plumbing only); groups pulled forward 2026-10-20, in review (GRP-001…GRP-012) |
| **P5 — Gamification** | Points ledger, levels, streaks, badges, leaderboard, stats | Points and streaks are idempotent and survive replays and undo | Started — 1/9 (Recap) |
| **P6 — Realtime, DMs, watch together** | WebSocket gateway, libsignal DMs, rooms, SharePlay | E2E DMs between two devices; a room counts down and checks off together | Not started |
| **P7 — Agent surfaces** | M13 agent, M14 outbound agent | As written in M13/M14 | Not started |

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

### DSN-002 · Mindspace visual language · L · owner, 2026-10-21
One visual language on web, iPhone, iPad and Mac (DESIGN.md "Mindspace"). The steps:
- colours from one file, `design/tokens.json`, generated for both clients and gated at WCAG AA;
- Newsreader for headings;
- a System / Light / Dark setting per device;
- texture on the Field and the Title room only;
- Tonight composed on the device until M13.

No API, auth, import, permission or persistence change.

**Done when:** every client colour comes from the token file. No hand-written hex, no
`weekGold`, no `Color.accentColor`. Every heading is in Newsreader, the widgets included. The
Field and the Title room ship on all clients. The owner has checked the TestFlight build:
widgets, Dynamic Type at accessibility sizes, VoiceOver, and the Mac window.

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

### LST-003 · Fill a list from inside it; rows that say what is airing · M
**Needs:** LST-002, APP-006, CAT-006.
A list was easy to make and hard to fill: "Add to list" lived only on a title page, a search
hit and a Discover card. Now "Add titles" inside a list opens search aimed at it (one tap adds,
"On this list" after), and every library row offers "Add to list". `GET /v1/lists/{id}` returns
`items`, one `ListItem` per member in order: the title, the caller's `LibraryEntry` when there
is one, and for shows `showStatus` and `nextAiring` (the first episode not aired yet). `titles`
stays for clients that predate it. A show only on a list has its episodes loaded on add and
refreshed by `CatalogRefresher` like a tracked one; Calendar and Up Next stay library-only.

**Done when:** a title can be added from inside a list on web and iOS, and a list row shows
status, progress, show status and next airing, including for a show not in the library.

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
**Progress 2026-10-21:** Trakt on all three clients: Connect (the web redirects, Apple uses the
system web-auth sheet back to `aaru://settings/trakt`), "Connected as …", Import from Trakt (opens
the plan), Disconnect. Unverified against a real Trakt account.
Settings (from the library's More menu on Apple, a "Settings" link on the web): account name and
sign-in providers, sign out, delete account (confirmed, cannot be undone), "Import from IMDb /
Letterboxd / Goodreads" with a file picker, and every import with its state. An import's page
polls every 2 s while matching, then shows the plan (new, filled in, already there, not matched,
with each unmatched row's reason) with Approve or Discard; after approval it shows the result and
a `partial` job keeps its unmatched rows listed. Verified on the web against a local API with a
real Goodreads-format file matched through Open Library: progress then plan, title + author
matched a book with no ISBN, approve added two books and turned a custom shelf into a list. The
Apple screens build but were not driven in the simulator.

**Progress 2026-10-20 (Apple):** Settings is the fourth tab (Home · Library · Calendar ·
Settings; a sidebar item on iPad and Mac) and the Mac Settings window (Cmd-,). The Library's More
menu no longer carries Settings or Sign out. Owner: "the iOS app doesn't even have a settings
view": the old entry point was too buried to find.

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

### DISC-002 · Seasons on Discover · M · pulled forward 2026-10-21
**Needs:** DISC-001.
`GET /v1/discover/season?kind=&season=&year=&page=`: one page of one season, the same for
everyone. Anime from AniList (`season`/`seasonYear`, popularity, 50 a page); new shows, returning
shows and films from TMDB `discover/tv` (`first_air_date`, or `air_date` with an earlier
premiere) and `discover/movie` (`primary_release_date`), popularity first, a vote floor only on
seasons that have ended. Years 1970 to next year, pages 1–20, else 422. A bounded in-memory page
cache (200 pages; 6 h for the current and coming seasons, 7 days for past ones; stale served on
failure). A provider down with nothing cached reads `unavailable`, not an empty season. Web:
`/app/discover?view=seasons` (`SeasonBrowser`); iPhone and Mac: the Discover tab's Today |
Seasons control (`SeasonBrowser.swift`). The Today row "Fall 2026 anime" links to it.

**Done when:** on iPhone, Mac and web, flipping Fall 2026 → Winter 2027 → Summer 2025 shows each
kind's titles, a title adds in one tap and turns into a link to the item, and AniList being down
says so on the Anime tab only.

### MUS-001 · Albums as a fifth kind · L · pulled forward 2026-10-21
**Needs:** LIB-001, APP-004.
`MediaType.album`: one MusicBrainz release group of type Album or EP, stored with its
`musicbrainz` id, the artist credit as `byline`, the first release year, up to five genres by
tag count, and a Cover Art Archive cover URL (`release-group/{mbid}/front-250`, referenced,
never hosted). MusicBrainz is paced at one request a second with a contact User-Agent. Search
`type=album` goes to MusicBrainz alone; `all` never includes albums, as with books. An album has
status, rating and notes, no progress: Plan to listen / Listening / Listened / Dropped. Its page
carries a tracklist (`album_tracks`) from the release group's earliest official release, fetched
the first time the page opens and again after 30 days; MusicBrainz failing shows the album
without it. Stats count an album finish with no minutes (`albumsFinished`; `byKind` lists
`album` only when the period has one, so older clients keep decoding). Clients: a square cover
everywhere, Music in search and the Library kind filter, a Home "Listening" row, albums in
Insights and the Recap, and a Listening widget on iPhone and Mac. Calendar, Up Next, episodes
and the Live Activity stay video only. Artist MBIDs for concerts are stored with MUS-003, not
here.

**Done when:** on iPhone, Mac and web, searching "Radiohead" finds *OK Computer* with its square
cover, it adds in one tap, its page shows the tracklist, Listened moves it into the year's
Insights, and the Listening row and widget show an album in progress.

### MUS-002 · New albums and Coming soon on Discover · M
**Needs:** MUS-001, DISC-001.
Two Discover rows from ListenBrainz (no key), each cached 6 h like the other rows. Fresh releases
carry no listen counts of their own (checked 2026-10-21: every `listen_count` is 0), so each row
is ranked by this month's sitewide stats: New albums are the month's most-played release groups
that came out in the last 30 days; Coming soon is the next 30 days of releases by the month's
1,000 most-played artists (never "Various Artists"), soonest first. Albums and EPs of new work
with a cover only: no singles, live records, compilations or spoken word. Hits are albums with
their `musicbrainz` id, so "already in your library" works.

**Done when:** both rows show on Today on three clients and a card adds the album in one tap.

### MUS-003 · Concerts · L
**Needs:** MUS-001, the owner's Ticketmaster key (sealed `TICKETMASTER_API_KEY`).
Ticketmaster Discovery events near a saved city (Open-Meteo geocoding, rounded to 2 decimals)
or a one-off approximate location sent in a POST body and never stored, 25 · 50 · 100 km; and
upcoming concerts for artists in the user's library, matched by MusicBrainz artist id only.
A daily call budget under the 5,000 limit; tickets link out. Discover gains a Concerts view.

As built: `POST /v1/concerts/near` sends Ticketmaster only the point's 5-character geohash cell
(about 5 km), which also keys a 6 h cache shared by everyone in that cell; the exact rounded
point is never logged or stored. `GET /v1/concerts/artists` asks for the user's matched artists
in batches of 20 performer ids. A refresher every 30 minutes fills `album_artists` from
MusicBrainz (once per album in someone's library) and matches artists to Ticketmaster
performers (20 a pass, again after 30 days); an artist with no MusicBrainz link on Ticketmaster
stays unmatched rather than matched by name. The budget stops at 4,500 calls a UTC day and the
cache serves what it has. The city search (`GET /v1/concerts/places`) goes to Open-Meteo and its
query is dropped from request logs. Not in the account export, like the other settings.

**Done when:** concerts near a saved city and near "Use my location" list on three clients, and
an artist in the library with a tour shows under "Your artists on tour".

### MUS-009 · Concerts from Bandsintown · M
**Needs:** MUS-003, the owner's Bandsintown app id (partner application), sealed as
`BANDSINTOWN_APP_ID` in `aaru-env`.
Ticketmaster has no Portugal listings (decision 2026-10-21). A `BandsintownConcerts` adapter
behind `ConcertListing` gives upcoming dates per artist, worldwide. "Your artists on tour" asks
both providers and merges by date, venue and artist. "Near <city>" adds the user's own artists'
dates within the radius when Ticketmaster has nothing there; Bandsintown cannot list everything
playing near a place, so the section says it shows only their artists. Artists match by
MusicBrainz id where Bandsintown gives one, else not at all. Its own call budget and cache;
tickets link out; credit "Concerts from Bandsintown".

**Done when:** an artist in the library with a Lisbon date shows under "Your artists on tour"
and under "Near Lisbon" on three clients.

### MUS-004 · Listening history import · M · pulled forward 2026-10-21
**Needs:** MUS-005.
Past listens into the listening log, as import jobs the user confirms, undone by job: Last.fm by
username (`user.getRecentTracks`), ListenBrainz by username, Spotify's extended streaming
history (`ts` is when a play ended; plays under 30 s and podcast episodes are skipped), and
YouTube Music from Google Takeout's `watch-history.json` (`header` "YouTube Music" only). The
same duplicate window as live listens applies. Never part of the library import order.

**Done when:** a Last.fm username and a Spotify history file each import with a count of new and
duplicate listens, show in the log, and undo in one step.

### MUS-005 · Listening log and ListenBrainz ingest · M · pulled forward 2026-10-21
**Needs:** OUT-001.
`listens`: one row per play (artist, track, album, length, ISRC and MusicBrainz ids when sent,
the scrobbler and the service it heard), append-only, deleted with the account, in the export.
A `music` token (`aaru_lb_`, `scrobble:write` only) opens `POST /listenbrainz/1/submit-listens`
(`single`, `playing_now` which stores nothing, `import` of up to 1,000) and
`GET /listenbrainz/1/validate-token`, in ListenBrainz's shapes. A listen of the same normalized
artist and track within half its length (at most 90 s, 30 s when unknown) of a stored one is the
same play and is dropped. `GET /v1/me/listens` pages the log; `GET /v1/me/listens/top` ranks
artists, tracks or albums over a period read like `/v1/me/stats`.

**Done when:** Web Scrobbler pointed at Aaru logs a YouTube Music play once, Pano Scrobbler the
same, and the play shows in `/v1/me/listens`.

### MUS-006 · Listens resolved to MusicBrainz · M
**Needs:** MUS-005, MUS-001.
A background pass looks each new track up once (sent ids, then ISRC, then an exact
artist-and-title search) through `MusicBrainzCatalog`'s paced client, and fills recording,
release group and artist ids. A listen then has its album's cover, and links to the album when
it is in the catalog. Nothing is guessed: only an exact match fills ids.

### MUS-007 · Music in Settings → Connected apps · S
**Needs:** MUS-005, APP-007 groups (#88).
Web and Apple: connect a scrobbler (the token shown once), the address each scrobbler wants with
Copy, a collapsed "How to set it up" for Web Scrobbler, Pano Scrobbler, Navidrome and Jellyfin,
live connections with last use and Revoke, and the last listen received.

### MUS-008 · Listening on Insights, a Music page and the Recap · M
**Needs:** MUS-005, MUS-006.
Insights gains a Music block (listens, minutes, top artists, tracks and albums); a Music page
lists recent listens with the top lists by period; the Recap gains a top-artist card when the
period has listens.

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

**Progress 2026-10-21:** token, refresh and revoke go to `auth.trakt.tv`; every call sends a
`User-Agent`. A refresh runs with the connection row locked (`SELECT … FOR UPDATE`), so two
callers never spend the single-use refresh token twice; a refresh Trakt refuses (`invalid_grant`)
counts as revoked. The lifetime comes from `expires_in` (Trakt has said both 24 hours and 7 days).
`DELETE /v1/imports/trakt/connection` revokes on Trakt first, best effort.

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

**Progress 2026-10-21:** every read is paged (`page`, `limit=250`, until `X-Pagination-Page-Count`
or an empty page); watched shows ask for `extended=progress`; watchlist and ratings are read per
type (`/movies`, `/shows`). The Trakt pacer is 1.5 requests/s (Trakt: 500 reads per 5 minutes per
user), and a 429 waits for `Retry-After` (up to a minute). Trakt's 420 (an account limit) and 423
(a locked account) fail the job at once with the reason.

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

**Correction and progress 2026-10-20:** the 2026-10-15 test only covered a manual add followed by
Goodreads. An audit found status stuck at its first import (an IMDb watchlist title stayed
wishlist after Letterboxd said watched), MAL rows after Trakt creating a second, AniList-backed
copy of the show, and later AniList seasons ticked as season 1 or skipped. Now, by the owner's
choice: status moves forward only (wishlist → in progress → finished), never backward, never out
of dropped, never past a status the user set (`status_by_hand`, backfilled from the journal, undo
restores it). MAL ids resolve through `anime_mappings`, and rows for one title merge, each season
ticked where its mapping says. `ImportMergeTests` covers same-source-twice, wishlist then
finished, dropped and hand-set statuses staying, undo, Trakt then MAL, and two AniList seasons.

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

**Built 2026-10-22:** `POST /v1/imports/{id}/rows/{index}/resolve` with the `mediaRef` of a
search hit. Before approval the pick joins the plan, which is decided again as a whole (rows on
one title still merge). After approval the row is decided against the library as it is then
(fill empty, forward only, never past a status set by hand) and written at once as its own
undoable action ("Matched “…” from Goodreads by hand"); the job turns `succeeded` when nothing is
left unmatched. Each unmatched row on the import page has "Find it" (web dialog, Apple sheet):
the catalog search, started on the row's title and kind.

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

**Progress 2026-10-21 (owner's ask):** built without a real export, from the column layouts public
converters pin against anonymised real exports (Trakt's importer fixtures in `trakt/trakt-web`,
`lukearran/TvTimeToTrakt`, `gulian/rewatch`'s format notes). `source=tvtime` (and `auto`, by
columns) takes one CSV at a time; the user unzips the export. *Export my data* (2026):
`tvtime-series-episodes.csv`, `tvtime-series.csv`, `tvtime-movies.csv`. GDPR export:
`tracking-prod-records-v2.csv` (episodes by show TVDB id, follow / watch-later / archived flags),
`tracking-prod-records.csv` (movies only, by name + release year), `followed_tv_show.csv`,
`seen_episode.csv` (episodes by show name). Shows go TVDB id → TMDB, then IMDb; an old TVDB id
TMDB does not know falls back to the exact-name rule (2026-10-21 decision). Not read: custom
lists, ratings (`tv_show_rate.csv`, `ratings-live-votes.csv`), the JSON copies, a zip.

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

**Progress 2026-10-20:** MAL rows also resolve through the anime mapping (by MAL id), so MAL after
a Trakt import lands on the same TMDB show (IMP-004's 2026-10-20 note).

### IMP-019 · Bingers import · M · OPEN
**Needs:** IMP-001, IMP-016.
Bingers (bingers.app, by TV Time's founder, July 2026) has no file export: its privacy page offers
a copy of your data by email to privacy@bingers.app. Its one official path is a **beta API**
(`api.bingers.app/v1`, OpenAPI 3.1, "change feeds, for mirrors and sync tools": `/v1/follows`,
`/v1/entries`, `include=titles` for IMDb/TMDB/TVDB ids), reached by OAuth 2.1 with a device flow
(a client metadata JSON Aaru would host as its `client_id`) or a personal token.

**OPEN (owner):** not built 2026-10-21, because (1) the API answers 403 unless the Bingers user pays
for the Legend or Icon plan; (2) `/v1/entries` rows name episodes by Bingers UUID only, and the
episodes endpoint that would number them has no response schema in the contract; (3) it is beta
and broke `/v1/library` on 2026-10-14; (4) nothing can be checked without a paid account. If the
owner wants it: Stremio's link-code shape (device code → approve on bingers.app/activate → one
read of `/v1/follows` + `/v1/library` → token dropped), statuses from `/v1/library`
(`not_started`/`watch_later` → wishlist, `stopped` → dropped, `completed` → finished, else in
progress), films from `/v1/entries`. Merge order: after TV Time, before MyAnimeList.

**Done when:** a paid test account's library imports with episode ticks, and running it again
plans only skips.

### IMP-016 · Stremio history import · M
**Needs:** IMP-001, SCR-003.
Past Stremio history through Stremio's device-link code: approve on stremio.com, one library
read, logout, key discarded. Shows tick from the watched bitfield over Cinemeta's episode list.
Second in the merge order (after Trakt).

**Done when:** a real Stremio account imports its watched movies, ticked episodes and in-progress
shows, and running it again plans only skips and updates.

Export-file fallback (`/v1/imports/csv` with a Stremio JSON export, same mapper): waits for a
real export sample.

### IMP-017 · Import speed and progress · M · 2026-10-21
**Needs:** IMP-001, IMP-013.
A 2,001-entry MyAnimeList export sat on "MyAnimeList · Waiting" with nothing else on the page,
while the worker matched one row at a time (one AniList request per anime, 90 a minute at best).
Rows now go in chunks of 50, three in flight; a chunk's MyAnimeList-only rows cost one AniList
`idMal_in` request. Uploads insert rows 500 per statement. `ImportJob` carries `rowsTotal` and
`rowsMatched`; the web page and the Apple import screen show a `JobLedger` of steps (DESIGN §3)
instead of a bare state, poll the job list instead of re-reading every row, and let a job still in
line be cancelled.

**Done when:** a 2,000-entry export shows steady progress and plans in about a minute (local run
with an empty catalog: 70 s, bounded by AniList's rate; was ~22 min at one request per entry).

### IMP-018 · Netflix viewing history · M · 2026-10-21
**Needs:** IMP-005, IMP-011.
`source=netflix` (and `auto`, by its `Title,Date` columns): Netflix → Account → Profile →
Viewing activity → Download all, `NetflixViewingHistory.csv`, one profile per file. The full
account download (`Profile Name` column, every profile in the household) is refused with a
pointer to the per-profile file. `Show: Season 1: Episode name` (also `Limited Series`, `Part N`,
`<Show> 4`, and Netflix's season words in other languages) is a show; anything else is a film.
One row per show (`in_progress`, its episodes by name) and per film (`finished`, last watched
date). Dates are read in the file's own layout (month first unless a day passes 12). Matching
follows the 2026-10-21 name-only decision; `notAfter` is the year first watched, so a later
remake drops out. Merge order: after CAT, before TV Time.

**Done when:** a file with a show, a film, a remade title and an unknown episode plans the show
with its named episodes ticked, the film finished, the remake unmatched with "Several films are
called …", and the unknown episode not ticked (`NetflixImportTests`).

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

## P2 · Discover, Insights, Home (pulled forward 2026-10-20)

See the 2026-10-20 decisions. No new tables.

### CAT-019 · All-kinds search · S
**Needs:** CAT-001, CAT-002.
`GET /v1/search?type=all`: TMDB `search/multi` (movie and tv; person and adult dropped) and
AniList in parallel, AniList with a short deadline. One provider failing returns the other's
hits with `incomplete: true`; both failing is a 502. A TMDB show is dropped only when an
`anime_mappings` row links it to an AniList hit in the same results. Hits carry `releaseDate`.

**Done when:** "Mobland" with `type=all` returns the TMDB show, a mapped anime appears once,
two same-named titles with no shared id both stay, and Open Library is never called.

### CAT-020 · Discover feed · M — Superseded by DISC-001
Superseded by DISC-001 (2026-10-20). This branch built its own `GET /v1/discover?section=`
(trending, upcoming films, new shows, on the air, anime this season and next); when it met
DISC-001 on `main`, the owner kept DISC-001's API and this one was dropped, code and tests. The
Discover tab/page (APP-012) renders DISC-001's rows. The id stays so old references resolve.

### UPN-002 · Library counts and Unfinished business · S
**Needs:** UPN-001.
`GET /v1/up-next` gains `counts` (items per status) and `unfinished`: every `dropped` item and
every `in_progress` item untouched for 30 days, newest change first, never one already in
Continue watching. Shows carry their next unwatched aired episode.

**Done when:** a dropped show and a 31-day-old book appear, a 29-day-old book does not, and no
title is in both Continue watching and Unfinished business.

### GAM-006c · Insights · M
**Needs:** GAM-006a.
`/v1/me/stats?span=all` (one bucket per year from the first active year), `byKind`, and a
10-bin ratings `distribution`. A browsable Insights view on iPhone, Mac and web: month, year or
all time; totals, buckets, by kind, top titles, ratings, longest run. Static, no motion.

**Done when:** all-time totals equal the yearly stats summed, and imported ticks are still left
out.

### GAM-006d · Last 7 and 30 days · M · pulled forward 2026-10-21
**Needs:** GAM-006c.
`/v1/me/stats?span=last7|last30&tz=`: the 7 or 30 local days ending today, one bucket per day,
with `from`/`until` and `prior` (the totals of the equal-length window just before, read in the
same query). Insights opens with 7 days / 30 days ahead of Month, Year, All time; each tile shows
its absolute change against `prior`, the chart is time per day with a track under empty days.
Home's "This month" strip becomes "Last 7 days": a bar per day by time and the week's figures,
shown at zero, opening Insights on 7 days.

**Done when:** a week's totals equal the same seven days read as a month, `prior` equals the week
before read on its own, imported ticks never count, and a new account's Home shows the strip at
zero.

### APP-011 · Search defaults to All; Home refreshes after an add · S
**Needs:** CAT-019.
Search opens on All on every client, each row labelled with its kind. An add from search shows
on Home without a manual refresh. On the web, Search opens in place on Home.

**Done when:** searching "Mobland" from Home and adding it puts it in Start watching on iPhone,
Mac and web without reloading.

### APP-012 · Discover screen · M
**Needs:** DISC-001.
Discover on iPhone, Mac and web: DISC-001's rows (`GET /v1/discover`, the rows Home shows) as a
full destination, posters with a kind and date badge. A card whose item carries
`libraryItemId` reads "On your shelf" and opens the item; else Add (with status) and Add to
list. TMDB, AniList and Open Library credits in the footer.

**Done when:** a title can be added, and added to a list, from Discover on all three clients.

### APP-013 · Home stats, counts, Unfinished business, lists · M
**Needs:** UPN-002, GAM-006c, DISC-001.
Home adds a stats strip (opens Insights; the last 7 days since GAM-006d), status count chips, an Unfinished business
row and list chips. Discover on Home is DISC-001's rows under the user's rows; there is no
separate teaser.

**Done when:** a new account's Home shows its stats and counts at zero above DISC-001's rows,
not a blank page.

### APP-014 · Status labels per kind · S
Clients and server journal summaries label statuses per kind (see 2026-10-20). Stored values,
ids and the Stremio catalog ids do not change.

**Done when:** no client shows "Wishlist", and the API still sends `wishlist`.

### APP-015 · Lists as a top-level destination · S
**Needs:** APP-006.
Lists is a tab on iPhone and a sidebar entry on iPad and Mac; Home shows list chips.

**Done when:** Lists is one tap from anywhere on iPhone and Mac.

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

**2026-10-20:** redesigned after bingers.app, in Aaru's own palette and type: poster fan hero,
App Store and Google Play buttons (Coming soon), one card per kind (TV shows, movies, anime,
books, music, sports), X link (@fatc88). Music and sports cards read as live by owner's call;
the library itself still tracks films, shows, anime and books only.

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

**Progress 2026-10-21 (HTTP):** `POST /v1/scrobble/start|pause|stop` (`Scrobble/ScrobbleRoutes.swift`),
hand-written like MCP: only a scrobble token (`kind = browser`, `aaru_scr_…`, `scrobble:write`
only) gets in; a session, MCP token or Stremio link is 401. Trakt's body (`movie`, or `show` +
`episode` with `season`/`number`/`title`; `progress` in percent; `ids` as numbers or strings) plus
`source` (`netflix`, `disney_plus`, `prime_video`), `ref` (the player's id for one film or
episode) and optional `durationMs`. No ids → matched by title + year, else by name alone
(2026-10-21 decision); no number → episode by name. The answer names the outcome (`recorded`,
`watched`, `stopped`, `unmatched`) and the matched title. A title not in the library is added and
ticked: two journal rows.

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

### SCR-007 · Browser extension scrobbler · L · 2026-10-21
**Needs:** SCR-001, OUT-001, IMP-018 (name-only matching). Owner exception to "no scraping",
recorded 2026-10-21.
`aaru-extension/`: one Manifest V3 codebase for Chrome and Firefox (Safari later, through the Mac
target). Content scripts on Netflix, Disney+ and Prime Video read the playing title from the
player's title overlay and the page URL only (title, season and episode or episode name; no
calls to the sites' internal APIs) and follow the page's main `<video>` for position and
duration. The background worker sends `start`, `pause` (also every 5 minutes while playing),
and `stop` (on end, on the next episode, on leaving the page) to `POST /v1/scrobble/*` with a
`kind = browser` token that has `scrobble:write` only and works nowhere else. The server
resolves names through `TitleResolver`; a play it cannot match is kept as an unmatched watch
event and the extension says "Not matched". Settings on the web and the Apple app list and
revoke browser tokens; the web connect page hands a new token to the extension. Store
submission (Chrome Web Store, AMO) waits for the owner.

**Progress 2026-10-21:** built. `aaru-extension/` (WXT 0.21, Chrome + Firefox MV3, `web-ext lint`
clean): content scripts report what they see on a port, `Session` turns it into scrobbles, the
background sends them (stops retried for a day) and sets the badge; the popup shows now, recent
and the connection in Aaru's tokens. Connections on web, iPhone and Mac list and revoke browser
tokens; `/connect/extension` hands over the token. Readers were written from the players' known
markup with fixtures; **check them on the live sites** before a store submission.

**Done when:** an episode played past 80% on each site ticks that episode once, journaled as
the browser extension; a film nobody can tell apart from a remake stays unmatched; a revoked
token gets 401 and the extension asks to connect again.

### SCR-008 · Now playing on Home and the Live Activity by push · M · 2026-10-21
**Needs:** SCR-001, SCR-003, WID-005, SOC-005 (APNs). Owner, 2026-10-21: watching Cyberpunk:
Edgerunners S2·E7 in Stremio showed nothing on web or iOS, though Stremio's `player` events had
been arriving all along (prod logs) and were stored in `watch_events` with nothing reading them.
`GET /v1/me/now-playing` reads the newest open session back (playing until its end plus 10
minutes, paused for 30). Home shows it as the `NowPlayingCard`: full width above Tonight on the
web (polled every 30 s while visible), above Tonight on iPhone and Mac; Tonight and Continue
watching leave that show out meanwhile. The server pushes the "Now watching" Live Activity over
APNs: push-to-start on a session's first `start`, update on pause and resume, end on the stop,
from tokens the app registers at `PUT /v1/devices/live-activity`; the app also starts it when it
opens on a session. The app follows its tokens from launch, so a background launch (iOS waking it
for a push-started activity) uploads the activity's token, and a token that arrives after a pause
or stop hears the session as it stands: update, or end (2026-10-22). The activity's token goes
up before its poster is fetched, under a background-task assertion: in the first live test
(Bleach, 2026-10-22) the poster download used up the wake, so pause and stop missed the Lock
Screen until the app was opened. Stremio reports a new episode only once it has played a while
(E12's first `start` came 2:41 in), so the activity appears that late. A `start` for the next episode closes the last one, ticking it only when it
was last reported at ≥ 80%. With it, the web's last-7-days block became a wide strip under
Tonight (owner, same day). This closes WID-005's "scrobble start is P3" and SCR-001's "may start
the WID-005 Live Activity via push".

**Done when:** an episode playing in Stremio shows on web Home within 30 s and on iPhone Home;
the Live Activity appears on a locked phone without opening Aaru (after one launch), reads
"Paused" on a pause, and ends with "Watched" when the episode ticks; episode after episode each
ticks once, also when Stremio skips the `stop`.

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
added by handle only. The contact email hash stays here for later.
**Invite links, 2026-10-21:** `social_invites` (12-character code, inviter, optional title,
expiry, redeemed by, revoked). `POST/GET /v1/social/invites`, `DELETE …/{code}`,
`POST …/{code}/redeem {addTitle}`, and the public preview `GET /v1/invites/{code}`. Every dead
end (unknown, spent, revoked, expired, blocked either way) is the same 404. Both sides need a
handle. Web `/i/{code}`; the apps open the same URL as a universal link
(`/.well-known/apple-app-site-association`).
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

**Minimal, 2026-10-21 (owner):** `GET /v1/activity` reads the library at query time: one row per
friend, title and UTC day, from episode ticks with a known date and finishes, over the last 14
days. Imported and restored ticks never show. One switch, `share_library_with_friends` (on by
default; the owner chose friends-see-by-default), hides a friend's activity and shelves. The Friends tab
on iOS and `/app/friends` on the web list it under "Lately"; a friend's profile
(`/app/friends/{handle}`) is shelf first: Watching, You both (both want, both finished, they
loved and you haven't), Recently finished. Never their notes.

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

### SOC-006 · Recommend a title to friends · M
**Needs:** SOC-002. Pulled forward 2026-10-21 (owner).
`social_recommendations` (from, to, title, note up to 140 characters, added, dismissed). Send to
up to 10 friends from a title or a friend's profile; the friend's inbox adds it to Plan to watch
in one tap (the same write as a tap) or dismisses it. Push to the recipient. Agents get none of it.

**Done when:** a recommendation reaches only friends, a block hides it both ways, and adding it
journals one ordinary library action.

### SOC-007 · Reactions on friend activity · S
**Needs:** SOC-003. Pulled forward 2026-10-21 (owner).
`social_reactions` (user, action, one emoji from a fixed set of six). Shown on activity rows and
on your own items on your profile. No push.

**Done when:** only a friend who can see the action can react to it, and unfriending or blocking
removes the reaction from view.

**Built 2026-10-21:** a reaction is on an activity row (`{owner}-{title}-{day}`), one per person,
from ❤️ 😂 😮 😭 🔥 👏. Lately now shows your own rows too ("You finished Heat"), so you see what
friends left; your own rows take no reaction.

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
Tables `groups` (name) and `group_members` (role `owner` | `admin` | `member`, `joined_at`).
Ownership is the one `owner` row, held unique by a partial index; there is no owner column.
Deleting a group is a hard delete that cascades to its channels and messages. Creating a group
inserts the owner and a `#general` text channel (`is_default`) in one transaction. `#general`
can be renamed, never deleted. The owner can't leave without transferring ownership or deleting
the group. Owner and admins manage channels; admins remove members, the owner removes anyone.
Account delete empties the user's messages, hands owned groups to the oldest admin, else the
oldest member, and deletes a group nobody else is in (extends AUTH-004). `muted` arrives with
GRP-012. A user owns at most 10 groups.

**Done when:** a new group has exactly one member and one channel, `#general`; a non-member gets
404 for the group, its channels and its messages; and the owner's leave is refused.

### GRP-002 · Group invites, friends only · S
**Needs:** GRP-001.
`group_invites` (inviter, invitee) holds pending invites only, like friend requests: accepting
turns it into a `member` row, declining or cancelling deletes it. Insert only when inviter and
invitee are friends (a block ends a friendship, so a block also stops it). `GET
/v1/me/group-invites` is the invitee's inbox. Joining marks every channel read up to then.

**Done when:** inviting a non-friend returns 422, inviting someone who blocked you returns the
same 422 with no hint of the block, and accepting adds the member once (a second accept is a
404 and adds nothing).

### GRP-003 · Text channels and group messages · M
**Needs:** GRP-001.
`group_channels` (`kind` `text`, name, topic, position) and `group_messages` (body,
`mentions`, `mentions_agent`, `client_nonce`, `edited_at`, `deleted_at`). GRP-007 adds the other
kinds and the spoiler stamp; GRP-010 adds the agent author, `components` and `reply_to`.
`group_read_state` holds each member's read point per channel; unread and mention counts are
counted from it, never stored. Channel names are lowercase with dashes (`movie-night`). Cursor
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
actor (LuminaVault's `ConnectionManager` is the template). Events go to every member of the
group and clients filter by channel: `ready` on every connect, `message.created` /
`message.updated` / `message.deleted`, `typing`, `read` (your other devices), `group.updated`
(name, channels, members or invites changed: refetch), `group.removed`, `invites.changed`. The
shape is `RealtimeEvent` in `openapi.yaml`. Writes stay on REST; the socket only announces, and
on `ready` clients refetch what is on screen. Apps send their bearer token on the upgrade; the
web gets a 60 s single-use ticket from `POST /v1/realtime/ticket` because its session token is
cookie-only, and a ticket only works from an allowed `Origin` (`REALTIME_ORIGINS`). The server
pings every 25 s; Traefik's idle timeout is 600 s and `api` is DNS-only, so nothing else sits in
the path. Presence stays in RT-001.

**Done when:** a message appears on the other client within two seconds, a reconnect fills the
gap from REST with no duplicates, a used or expired ticket is refused, and a non-member's
socket receives nothing for the group.

### GRP-007 · Title channels and the spoiler guard · M
**Needs:** GRP-006, PROG-001.
A `title` channel is bound to one title, created from search or "Discuss in group…" on the
Title page, and named after it unless named by hand. Its header is a `TitleCard`. A message is
stamped with the author's furthest episode (the ending once they finished), a hand-set episode
or the ending, or nothing (`spoilerFree`). A reader whose progress is behind sees `SpoilerVeil`;
finishing the title unveils everything. Only the author sees a stamp, since it says where they
are; readers get `veiled`. Members' progress shows in the header
(`GET …/channels/{id}/progress`) only for members who switch on `share_progress` for that group
(`PUT /v1/groups/{id}/me`, default off).

**Done when:** a reader at S1E3 sees a message stamped S1E5 veiled, a reader at S2E1 does not,
and a member with `share_progress` off never appears in the header.

### GRP-008 · Shelf channels · M
**Needs:** GRP-006.
`group_channel_items` (title, `added_by`, position), up to 200 per shelf, at
`…/channels/{id}/items`. Separate from `lists`, which stay single-owner; they share a renderer.
Any member adds or removes titles, and `shelf.updated` tells the others. Each item carries the
viewer's own status. "Add to my library" is the existing `POST /v1/library/items`, journaled
with the user as actor.

**Done when:** two members edit the same shelf live, and "Add to my library" writes one
journaled, undoable action for the tapper only.

### GRP-009 · Watch channels · L
**Needs:** GRP-006, PROG-001.
Absorbs ROOM-001. `watch_sessions` (title, season, episode, host, `starts_at`, `ended_at`; one
open per channel) and `watch_ready`, at `…/channels/{id}/party`. State is derived: `lobby`
until the host or an admin starts a 3–60 s countdown, `countdown` until `starts_at`, `live`
until ended. Every response carries `serverTime` so clients count down against it.
`WatchPanel`: ready list, the countdown, reactions over the socket (😂 😱 😭 ❤️ 👏 🔥, one a
second per socket, never stored), and "Mark watched for me" (`…/party/watched`), which ticks
only the tapper's progress through `LibraryService`, during or after the party.

**Done when:** members on web, iOS and Mac see the same countdown within 500 ms, and ending the
session ticks the episode only for members who tap.

### GRP-010 · Model provider, minimal · M
**Needs:** none.
The groups subset of AG-007: `ModelProviding` plus `AnthropicMessagesProvider`, raw HTTP to the
Messages API (no Swift SDK) with `claude-haiku-5-5` at effort `low`. It sends no `temperature`,
`top_p`, `top_k` or assistant prefill (see `platform/infra/docs/llm-haiku-trial.md`), and replays
content blocks unchanged so thinking survives a tool loop. Env follows the trial contract:
`ANTHROPIC_API_KEY` (sealed in `platform/infra`; unset turns `@aaru` off and `GroupDetail.agent`
says so), `ANTHROPIC_MODEL`, `ANTHROPIC_EFFORT`, `ANTHROPIC_WORKSPACE_ID` (sent as
`anthropic-workspace-id` when the key is not scoped to one workspace), and `ANTHROPIC_BASE_URL` for
tests. Metering in
`agent_usage` (user, UTC day, requests, input and output tokens). No user keys yet.

**Done when:** tests against a stub server pass, a request body never contains `temperature`,
and usage rows add up per user and day.

### GRP-011 · `@aaru` replies in channels · L
**Needs:** GRP-003, GRP-010.
A message with `mentions_agent` enqueues an `agent_replies` row, claimed with the
`FOR UPDATE SKIP LOCKED` lease used by imports by `AgentReplyWorker`, retried twice, then
answered with a short apology. `agent.thinking` tells clients it is working. Context: the
channel's last 30 messages, the channel's title, party or shelf, and **the tagger's own**
library, read-only. Tools: `search_titles`, `title_details`, `list_airs`, `read_my_library`,
and `show_titles`, which attaches title cards using refs the other tools handed out (so the
model cannot invent ids). Up to 4 rounds. The reply is a group message with author kind
`agent`, no author, `reply_to` the mention, and title cards only. In a title channel it is
told the tagger's progress, avoids spoiling past it, and is stamped there. Its card buttons
are the viewer's own taps. Caps: 30 mentions per user per UTC day, 10 per group per hour;
over the cap Aaru says once that it is resting (per user per day, per group per hour), without
calling the model, and then stays quiet. A refusal gets a one-line reply.

**Done when:** a tagged question gets one reply, the model's context never contains another
member's library, the cap reply makes no model call, and no tool can write.

### GRP-012 · Group push and tap routing · M
**Needs:** GRP-002, GRP-003, the airing push (decision 2026-10-15).
`group_mentions` and `group_invites` toggles in notification settings, plus per-group mute. The
payload carries no message text: "{name} mentioned you in #{channel}" and
`aaru://group/{g}/channel/{c}`. iOS routes a tap to the channel.

**Done when:** a muted group sends nothing, a mention push opens the right channel from a cold
start, and no push payload contains message text.

Built 2026-10-21: both switches are off until turned on, like `airing`. Browsers get the same
alerts through web push and open `/app/groups/{g}/{c}`. Mac push stays off.

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

### GAM-006e · Year in Review v2 · M · pulled forward 2026-10-21
**Needs:** GAM-006a, CAT-018.
`/v1/me/stats` adds `topGenres` (top three by time, films, shows and anime, from CAT-018's
stored genres), `biggestDay` (the local day with the most time, then episodes, earliest on a
tie) and `persona` (the first rule that holds: `binger` a day of 6+ episodes or 14 days in a
row, `bookworm` books are most of 2+ finishes, `anime` anime is most of the time,
`completionist` 24+ finished, `explorer` 3+ kinds, else `steady`). The year's deck adds biggest
day, genres, kinds and persona cards; a month adds genres only. The share image adds the top
genre and the persona.

**Done when:** genres, biggest day and persona come only from the user's own library, imported
ticks still never count, the persona is the same on every client for the same year, and the
share image holds no posters and no other user's data.

### GAM-006b · Profile stats and genres · M
**Needs:** GAM-001, GAM-006a, CAT-018.
MAL-style all-time stats on a profile (`StatsPanel`): days watched, mean score, genre and
network breakdowns, anime vs TV. A genre card joins the Recap once genres are stored.

**Done when:** every number matches `/v1/me/stats` summed over the same years.

### CAT-018 · Store genres · S · pulled forward 2026-10-21
TMDB `genres` and AniList `genres` are decoded today but only used to compute `isAnime`. Store
them as `titles.genres text[]` at hydration, and backfill titles already in libraries.

Built: names in the provider's order, books none. The backfill is a pass in the catalog
refresher (40 titles every five minutes), fill-empty-only, stamped in `genres_attempted_at` and
retried after a week when the provider has none. Not on the Title DTO yet; GAM-006e reads them.

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

**Progress 2026-10-20 (remote plans, for OUT-004):** every library write is split into a dry
run (`LibraryService+Prepare.swift`, `PreparedWrite`) and a commit; a tap still does both at
once. An outside agent's change bigger than a tap is stored as an `agent_plans` row holding the
exact `LibraryOp` batch and a basis (each touched item's `updated_at` in microseconds, and the
titles it adds). Approval runs in one transaction: status, expiry (24 h) and basis are checked
again, then the op is applied and journaled as one `external_agent` action, undoable. A moved
item or a title added meanwhile makes the plan `stale` and nothing is written. No autonomy dial:
remote plans are always "ask me".

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

**Progress 2026-10-20 (MCP kinds):** `kind` adds `claude_code`, `codex`, `hermes`, `gemini` and
`other` (migration `AddAgentTokenKinds`). Their secrets are `aaru_mcp_…`, scoped `library:read`
plus `library:write` if allowed, never `scrobble:write`. A token authenticates only on its own
surface: an MCP secret is not a Stremio link and a Stremio link cannot call MCP.

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
`LibraryService.delete` and `markSeasonWatched` take a `Caller` too, for the MCP tools.

### OUT-003 · App Intents and Shortcuts · M
**Needs:** AG-002, APP-003.
Each M13 tool is exposed as an App Intent in `aaru-ios`, which yields Siri, Shortcuts,
Spotlight, and the share sheet. `TitleCard` and `TonightStrip` serve as intent snippet views.
Capture's share-sheet target lands here. No server work — this is why it ships before MCP.

**Done when:** "log last episode", "what's on tonight", and sharing a URL into Aaru all work
from Shortcuts without opening the app, and each one produces the same journal row a tap would.

### OUT-004 · MCP endpoint and remote approval · L
**Needs:** OUT-001, OUT-002, AG-003.
`POST /v1/mcp` (streamable HTTP) in `aaru-server/Sources/App/MCP` — inside the existing server,
because MCP is a transport and the no-second-backend rule stands. Exposes exactly M13's tools.

Remote approval: a caller with `library:write` may write a single item directly, exactly as a
tap does. Anything larger returns a plan id and a human summary, and the plan waits in Aaru as
a `PlanCard` labelled with the calling token's name. `POST /v1/plans/{id}/approve` and `/deny`
are the only way through, and no scope grants a caller access to them. Denials are journaled.
Until push exists (`MARKETING.md` item 18), pending plans show in The Field as a pinned
artifact.

**Done when:** deleting `App/MCP` leaves every feature reachable through `/v1`; a multi-item
write requested over MCP cannot land without an in-app approval; a stale plan is rejected
rather than re-planned; and no MCP response contains vendor JSON.

**Progress 2026-10-20 (endpoint):** `POST /v1/mcp` built, hand-rolled JSON-RPC (no SDK), stateless:
`initialize` (2025-11-25, 2025-06-18, 2025-03-26), `ping`, `tools/list`, `tools/call`;
notifications get 202, `GET`/`DELETE` 405. It authenticates itself: only an `aaru_mcp_` token,
never a session or a Stremio link; a browser `Origin` is refused; 401 carries
`WWW-Authenticate`. Tools are AG-001's (`Agent/AgentTools.swift`) and answer `/v1` DTOs. A
caller with `library:write` applies one change to one item (at most one episode, never a
removal) at once, journaled as the token; anything larger is refused until plans land.
`GET /v1/agent/setup/{kind}` serves each client's setup (Claude Code, Codex, Hermes, Gemini CLI,
other) so web and Apple show the same steps.

**Progress 2026-10-20 (remote approval):** anything bigger than a tap, and any removal, now
becomes a plan (AG-003): the tool answers `applied: false` with a `planId`, and the user gets a
push ("Laptop wants to change your library"). `GET /v1/plans`, `GET /v1/plans/{id}`,
`POST /v1/plans/{id}/approve` and `/deny` take a session only, so an agent token gets 401 and no
caller approves its own plan. A token has at most 20 plans waiting; revoking it expires them.
Pending plans pin to the top of Home on web and Apple ("Waiting for you"), and the push opens
the plan. **Denials are recorded on the plan row** (`status = denied`, `decided_at`, the token),
not as an `actions` row: the action journal holds only undoable writes, and `agent_plans` is the
ledger of what each token asked for.

**Progress 2026-10-20 (OAuth front door, the Claude connector):** `Sources/App/OAuth`, per the
MCP authorization spec. `/.well-known/oauth-protected-resource` (and `/v1/mcp` under it),
`/.well-known/oauth-authorization-server`, `POST /oauth/register` (RFC 7591; every client is
public, https or loopback redirects only, 20 per address per hour), `GET /oauth/authorize`
(S256 PKCE only; `resource` must be the MCP endpoint), `POST /oauth/token`, `POST /oauth/revoke`,
all CORS `*` without credentials. Authorize sets an `aaru_oauth` binding cookie on
`OAUTH_COOKIE_DOMAIN` and sends the browser to the web consent page (`/oauth/consent`), which
answers through `GET/POST /v1/oauth/requests/{id}…` with the session and that binding, so a
consent link sent to someone else approves nothing. The access token is an `agent_tokens` row
(`issuance = oauth`, `aaru_oat_`, one hour, kind from the client's name: `claude`,
`claude_code`, …); the refresh token (30 days) rotates, and a replayed refresh token or a reused
code revokes the connection. MCP's 401 names the resource metadata. Settings lists these
connections with the others; revoking one stops its refresh. `kind = claude` cannot be minted
with a pasted token. New env: `WEB_BASE_URL`, `OAUTH_COOKIE_DOMAIN`.

**Progress 2026-10-20 (`plan_import`):** the fifth tool. `imports:write` is mintable for MCP
clients ("Allow imports", off by default; migration `AddImportsWriteScope`). The agent hands Aaru
a list export as text (format detected, or named); it becomes an ordinary import job, matched by
the worker and approved by the user in Aaru like any other import. The tool never writes the
library. The user gets a push that opens the import on the web.

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
without an official export (Pogdesign, IMDb pages, AniDB; the one owner exception is SCR-007's
browser extension reading the user's own player page, 2026-10-21) · a Stremio `stream` resource or any
stream source · hosting TMDB, Open Library or AniList artwork · a second backend · a documented
public API with third-party clients (M14's agent access and P3's scrobble tokens are per-user
and token-scoped, which is a different thing).

Moved out of this list on 2026-10-15 and scheduled after the P2 gate: music, manga, comics and
games (see the 2026-10-15 decisions).

Moved out of this list on 2026-10-09 and scheduled after the P2 gate: scrobbling (P3), MAL /
AniList (P1 catalog, P3 push), friend graph and activity (P4), shared lists (P4), gamification
(P5), realtime, DMs and watch-together (P6). Serializd and SIMKL stay unintegrated.
