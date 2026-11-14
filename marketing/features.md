# Aaru: feature inventory

Last verified: 2026-11-14, against `aaru` `origin/main` 21b15bfb. Production runs API image
`3252c467` (`platform/infra` `origin/main` fdc6dc8, `apps/aaru/api/values-production.yaml`).
Four commits on `main` are not live yet (`git log 3252c467..origin/main`): #306, #307, #308
and a pooled-connection retry.

Use this document to pick features, write scripts and plan recordings. Positioning lives in
`strategy.md`, brand in `rules/brand.md`, capture tooling in `rules/video-playbook.md`.

## How to read this

**Where Aaru runs today (2026-11-14):**

| Surface | State |
|---|---|
| Web | Production at `aaruapp.com` (Cloudflare Worker). Beta web on the `env.staging` Worker, deployed on every merge to `main` |
| iPhone, iPad, Mac | TestFlight beta ("Aaru Beta"). iOS and macOS 1.0 (build 3) **submitted to App Review 2026-11-13** as "Aaru - Media Manager", Free, phased release. Check App Store Connect before saying "on the App Store" |
| Browser extension | Built for Chrome and Firefox (`aaru-extension/`), **in no store** (SCR-007) |
| Android | **None.** No Android client exists. The landing page's "Android to follow" and "Google Play" lines are a promise, not a feature |

| Status | Meaning |
|---|---|
| `verified` | Marked Done in `BACKLOG.md` "Every item", in the live API image, reachable from the UI on the platforms named. Read in source: **no screen was rendered for this review**, so rehearse before filming |
| `partial` | Works, with a limit stated on the feature. Follow the limit in any copy |
| `experimental` | Built and in the live image, but `BACKLOG.md` says "Built, unverified": checked against stubs or one device, never by a stranger or on every client. Rehearse it end to end before promising it |
| `planned` | Not available. Never market it. See "Do not market" |

Many `BACKLOG.md` notes still say "Not deployed" from before the Go port (live 2026-10-30).
Everything merged to `main` up to `3252c467` is in production; trust the live image over those
notes, and trust the notes on whether anyone has *seen it work*.

**Platforms:** Web, Apple (iPhone, iPad and Mac, one SwiftUI target), or All.

**Priority** reflects user value and how well it shows on screen, not technical effort.

**Paths** start from the repository root, `~/Work/production/apps/aaru/`: `aaru-server-v2/`
(Go API), `aaru-client/src/` (web), `aaru-ios/Aaru/` (Apple), `aaru-extension/`.

**Labels per kind.** Status words change with the kind; use the one on screen (CLAUDE.md,
"Status"):

| Stored | Films, shows, anime | Books, manga | Albums |
|---|---|---|---|
| `wishlist` | Plan to watch | Plan to read | Plan to listen |
| `in_progress` | Watching | Reading | Listening |
| `on_hold` | On hold | On hold | On hold |
| `finished` | Watched | Read | Listened |
| `dropped` | Dropped | Dropped | Dropped |

Other UI words to keep exact: **Up Next**, **From here** (the title tree), **On air**
(Discover), **Watch party** / **Reading session** (a Room), **AI data sharing**, **Join us on
Discord**, **Ask Aaru** (the store caption for the assistant card).

## The six features to lead with

Chosen for user value, how well they film, and status. Order matters.

| # | Feature | Status | Why it leads |
|---|---|---|---|
| 1 | Bring your history (§1–3) | verified for Trakt, Letterboxd, IMDb, Goodreads, MAL, AniList; experimental for the rest | The first job of every persona in `strategy.md`. Films well: a file goes in, a match table comes out, nothing writes until you approve |
| 2 | Six kinds in one library (§5) | verified | The category claim nobody else makes: films, shows, anime, manga, books and albums with one grammar |
| 3 | Episode progress, Up Next and the week (§6–8) | verified | The nightly habit. Ticks and S·E codes are what trackers recognise |
| 4 | Private by default, export and delete (§24–25) | verified | The trust story and the exit door. Simple to say, easy to show in Settings |
| 5 | Ask Aaru, with plans you approve (§16–17) | experimental | Distinctive and visual, but never the headline (`strategy.md`, rule 5). Show the plan card and undo, not "AI" |
| 6 | From here: where a title leads (§13) | experimental | Shows depth across kinds (a film to its book, an anime to its manga). Unique and pretty on screen |

## Do not market

- **Price, Aaru Plus, a paywall or a trial.** Plus is built (BIL-001…004) and off sale
  (BIL-005, owner: no paying plans for now). Say "free". Never say "free forever" either: the
  landing FAQ says pricing is not final; the export and statistics promise is the only
  permanent one.
- **Android or Google Play.** No client exists.
- **"On the App Store"** until App Review has approved 1.0 and the release is out.
- **The browser extension as something to install.** It is in no store.
- **End-to-end encrypted DMs.** P6, not built. Never imply Aaru has private messaging. Group
  messages are server-visible and every channel says so.
- **Two-way sync** with Trakt, Letterboxd or any provider. Imports are one-way in. The only
  read-back is MyAnimeList (SCR-010), and that needs MAL's written authorisation before anyone
  but the owner connects (`docs/providers.md`). Do not market MAL sync yet.
- **Pushes to Trakt or AniList** (SCR-004, SCR-006): open.
- **Recommendations**, "for you", "personalised picks". Out of scope (CLAUDE.md). Discover rows
  are the same for everyone; From here is catalog data; suggestions only come when you ask Aaru.
- **Public profiles, a feed, followers, "social network".** There are none, by design.
- **Adult titles.** The catalog offers none (CAT-023).
- **Comics and games.** Planned after the P2 gate.
- **Anything in the four commits after `3252c467`** until promoted: the single `#ai-reply`
  channel for `@aaru` (#308), group members in the channel header (#307).
- **Owl in 3D** as a feature. It is an experiment awaiting the owner's verdict (BRD-011).
- **Speed or scale numbers** ("imports 10,000 titles in seconds"). Nothing is measured.
- **Users, reviews, ratings, testimonials.** The strangers count is 0.

## Platform differences

| Area | Web | Apple |
|---|---|---|
| Widgets, Live Activity, App Intents (Shortcuts, Siri) | No | Yes (WID-*, SCR-008) |
| Offline cache | No (APP-009) | Yes, recent library (APP-003) |
| Push | Web push for airing alerts (VAPID) | APNs |
| 3D owl | Sign-in page and landing hero (experiment) | Welcome screen (experiment); App Store build shows the still |
| Buying Plus | Never (web sells nothing) | Built, off sale |
| Browser extension pairing | `connect.extension` route | No |
| Voice question to Aaru | Yes | Yes |

Both clients are on the same `/v1` API with no rules of their own, so a feature that exists on
one usually exists on the other. Where a row above says otherwise, name the platform in copy.

---

# A. Bring your history

## 1. Import from where you keep it now

- **Status:** verified for Trakt (OAuth, IMP-002), IMDb, Letterboxd and Goodreads CSV
  (IMP-004…008), MyAnimeList XML (IMP-013), AniList by username (IMP-014). experimental for
  Stremio (IMP-016), Netflix viewing activity, TV Time (IMP-018), CAT list / ICS (IMP-009/010),
  generic CSV, Goodreads' newer path (IMP-020): none has met a real export from a stranger.
- **Platforms:** All. Settings → Import.
- **What the user does:** connects Trakt, or drops a file; `source=auto` detects the format.
- **Benefit:** years of history arrive in minutes, without retyping.
- **Code:** `aaru-server-v2/internal/imports/`, web `_shell.app_.settings.import.tsx`,
  `_shell.app_.imports.$id.tsx`.
- **What to film:** a Letterboxd CSV from the demo account dropped in, the job page filling.
- **Limits:** imports are jobs, so they finish in the background. 5 MB file cap on some CSV
  paths (IMP-005). Merging never moves a status backward and never overrides one the user
  set by hand (CLAUDE.md, "Merging sources"). Say "import", never "sync".

## 2. See what matched before anything is added

- **Status:** verified (match table and plan); experimental for **Match all**'s best guesses
  (IMP-021).
- **Platforms:** All.
- **What the user does:** reviews matched and unmatched rows, fixes or skips, then approves.
- **Benefit:** no silent bad merges. "Aaru shows you what it matched before anything is
  added" (store description).
- **Code:** `MatchTable` and `PlanCard` in `VIEWS.md`; `imports/matchall.go`.
- **What to film:** the match table with one unmatched row fixed by search, then approve.
- **Limits:** never merges two titles that only share a similar name. Match all's guesses are
  proposals the user approves.

## 3. Undo an import

- **Status:** verified (an applied import is one journaled action; undo that action).
- **Platforms:** All.
- **Benefit:** trying Aaru is safe: a whole import comes back out.
- **Limits:** a discarded import keeps the items it already created; the action's undo removes
  them (`openapi.yaml`, discard import). Rehearse on the demo account before filming.
- **What to film:** after an import, undo it and watch the library empty.
- **Limits:** undo covers what Aaru wrote; it does not touch the source service.

## 4. Capture: paste text, a picture or a link

- **Status:** experimental (AG-006, BOOK-001, BOOK-003). Needs **AI data sharing** allowed.
- **Platforms:** All.
- **What the user does:** pastes a list from notes or a chat (up to 100,000 characters), up to
  five pictures (a shelf, a screenshot), or a TMDB, AniList or Open Library link. Text that
  asks for titles ("X-Men books in reading order") is answered with titles to review.
- **Benefit:** the history that lives in screenshots and notes gets in too.
- **Limits:** 30 a day per account. Pictures and text are deleted once read. Links are parsed
  by id, never fetched. Always ends in a match table and a plan, never a direct write.

---

# B. Track

## 5. Six kinds, one library

- **Status:** verified for films, shows, anime, books; experimental for manga (MNG-001) and
  albums (MUS-001).
- **Platforms:** All.
- **Benefit:** one search, one library and five plain statuses for everything you follow
  (landing page).
- **What to film:** one search for a name that is a film, a book and an anime; add each.
- **Limits:** sports are a separate tab, not library items (§20). Albums have status, rating
  and notes only; tracks are never ticked.

## 6. Episode and chapter progress

- **Status:** verified (PROG-001…005); experimental for PROG-006.
- **Platforms:** All.
- **What the user does:** ticks an episode, a season, or marks a whole show watched; logs the
  last chapter and volume of a manga; page or percentage of a book.
- **Benefit:** always know where you are.
- **What to film:** ticking three episodes on a show page; S·E codes visible.
- **Limits:** anime from MAL or AniList ticks the TMDB season it maps to.

## 7. Up Next and Now

- **Status:** verified (APP-*); experimental for the Now group pages and anime backlog
  (APP-018).
- **Platforms:** All.
- **Benefit:** "what do I watch tonight" answered from your own list.
- **Limits:** On hold items leave Up Next by design.

## 8. The week and airing alerts

- **Status:** verified (calendar); experimental for web push and exact air times (CAT-011 is
  Done, alerts SOC-005 partial: airing push only).
- **Platforms:** All. Push on Apple and web.
- **What to film:** the week grid with three shows airing; an alert on a device (needs a
  physical device).
- **Limits:** air times come from TVmaze for TMDB shows; credit it.

## 9. Statuses, including On hold

- **Status:** experimental (LIB-007, five statuses with Library tabs and counts).
- **Benefit:** pause a show on purpose without losing it.

## 10. Lists and shelves

- **Status:** verified (lists); shelves (saved queries) verified as pins.
- **Platforms:** All.
- **Limits:** "List" is membership; "Shelf" is a saved filter. Keep the words apart.

## 11. Widgets and Live Activity

- **Status:** experimental (WID-001…007, SCR-008): none seen on a device per `BACKLOG.md`.
- **Platforms:** Apple only.
- **What to film:** needs a physical iPhone; the Simulator shows widgets but not pushes.

## 12. Insights and Recap

- **Status:** verified (GAM-006a/c/d/e, Recap); Apple story never run on a device.
- **Platforms:** All.
- **Benefit:** look back at a month or a year, from your own library only.
- **Limits:** imported ticks are not activity (CLAUDE.md, "Recap"). Statistics are free and
  stay free (landing FAQ).

---

# C. Discover the catalog

## 13. From here: where a title leads

- **Status:** experimental (GRAPH-005, GRAPH-006, stub providers only).
- **Platforms:** All.
- **What the user sees:** a title with up to three branches of up to five titles: the person
  who made it, the series, its adaptations, plus the lead and second actor for a film or show.
- **Benefit:** a film leads to its book, an anime to its manga, a director to their next film.
- **Limits:** catalog data, the same for everyone. Never call it "for you" or a
  recommendation. On an iPhone, one person's row at a time.

## 14. Relations, Start here and roadmaps

- **Status:** experimental (GRAPH-001…004).
- **What the user sees:** sequels, prequels, side stories and adaptations; "Start here" on the
  main chain; a list planned in steps (a roadmap).
- **Limits:** relation data from AniList, TMDB collections and Wikidata; credit them.

## 15. Discover and On air

- **Status:** experimental (DISC-001…004, BOOK-002, MUS-002).
- **What the user sees:** trending, on the air, new shows, in theaters, this season's anime,
  trending books, new albums; On air lists the week's airings by channel and the flat-rate
  services per country (JustWatch through TMDB).
- **Limits:** the same rows for everyone. Credit TMDB, TVmaze, JustWatch, AniList, Open
  Library, ListenBrainz where shown.

---

# D. Ask Aaru

## 16. The owl's card: ask, typed or spoken

- **Status:** experimental (ASK-009…011). Needs **AI data sharing** allowed (PRV-002).
- **Platforms:** All. Opened from the owl in the top bar.
- **What the user does:** asks in their own words: what to watch tonight from their own list,
  where they left off, the order to read a series in. Attach a file or a long paste (ASK-010).
- **Benefit:** the larger moves without tapping through screens.
- **Limits:** reads only the user's own data and the catalog. Free for every account. Chats are
  kept until deleted. Voice goes to the cluster's own transcription; audio is never stored.
  Never headline it as "AI" (`strategy.md`, rule 5).

## 17. Plans you approve, writes you can undo

- **Status:** verified for the plan card and undo machinery; experimental inside chat.
- **What the user sees:** one change applies like a tap; anything larger is a `PlanCard` to
  approve; a roadmap shows as a `RoadmapCard` reviewed as an import.
- **Benefit:** "A single change happens like a tap; anything larger is a plan you approve
  first" (store description).
- **What to film:** "mark season three watched", the plan card, approve, then undo.

## 18. Aaru in Claude, Shortcuts and Siri

- **Status:** experimental (AG-001 over MCP, `internal/oauth` for the Claude connector; App
  Intents on Apple).
- **Limits:** an outside agent gets no capability a signed-in session lacks; larger writes
  are approved inside Aaru. Niche: market only to the Apple/automation audience, and only
  after the main story lands.

---

# E. Friends and groups (opt-in, friends only)

## 19. Friends, invites, share links, groups, watch parties

- **Status:** experimental throughout (SOC-*, SHR-002, GRP-*, ROOM-005, GAM-001…005). Two-browser
  and device checks are not recorded for most.
- **Platforms:** All.
- **What exists:** mutual friends by invite link (14 days); a share link to one title anyone
  can open; Recommendations to friends; Boards (friends-only posts); groups with `#general`
  and channels; Watch party / Reading session with a countdown where everyone presses play on
  their own; points, streaks, badges and a friends leaderboard.
- **Limits:** no public anything. Aaru controls nobody's player and shares no screen. Group
  messages are server-visible. `@aaru` in a group only answers for members who allowed AI
  data sharing. Lead with "with friends, if you want", never with social.
- **Filming:** only the review seed's fictional friend (Mira) and groups; never a real person.

---

# F. Music and sports

## 20. Albums, listens, concerts, sports

- **Status:** experimental (MUS-001…008, MUS-010, SPT-001…005).
- **What exists:** albums with status and rating; a listening log from Last.fm, ListenBrainz,
  Spotify extended history and YouTube Music Takeout imports; ListenBrainz-protocol scrobbling
  (Web Scrobbler, Pano Scrobbler, Navidrome, Jellyfin); concerts near a city or by an artist in
  your albums (Ticketmaster); a Sports tab with leagues, teams, fixtures and livescores.
- **Limits:** none tried with a real scrobbler or device. Ticketmaster lists nothing in
  Portugal. Sports are never library items. Secondary story: mention, never lead.

## 21. Browser extension and Now playing

- **Status:** experimental and **not in any store** (SCR-007, SCR-009, SCR-011).
- **Do not market** as installable until published.

---

# G. Apps, privacy and trust

## 22. iPhone, iPad and Mac app

- **Status:** verified on TestFlight; 1.0 in App Review.
- **Benefit:** a native Mac client is rarer than an iPhone one (MARKETING.md §7).

## 23. Web app

- **Status:** verified, production at `aaruapp.com`. Sign in with Apple, Google or an email code.

## 24. Private by default

- **Status:** verified.
- **Copy that is true:** "A new account shows nothing to anyone. There is no public profile, no
  feed, no ads and no tracking." (store description). PostHog receives a few server-side events
  only; Sentry errors only, no PII (`docs/privacy.md`). Check `docs/privacy.md` before any new
  privacy claim: it changes first.

## 25. Export everything, delete your account

- **Status:** verified.
- **What the user does:** Settings → export JSON or a CSV that imports back into Aaru; delete
  the account from Settings.
- **Copy that is true:** "Export will never be a paid feature." (landing FAQ).

## 26. AI data sharing, asked once

- **Status:** experimental (PRV-002). Asked in the first run; unanswered counts as no.
- **Benefit:** nothing of yours reaches a model until you say yes.

## 27. Community Discord

- **Status:** verified link ("Join us on Discord") on the site and in the app.

---

# Evidence and assumptions

**How this was checked.** `CLAUDE.md`, `BACKLOG.md` "Every item" table (line ~927 onward),
`aaru-ios/fastlane/metadata/en-US/` (draft store copy, not owner-approved),
`aaru-ios/fastlane/screenshots/captions.json`, `aaru-client/src/routes/index.tsx` (landing),
`docs/providers.md`, `docs/privacy.md`, and the live tag in `platform/infra`. No screen was
rendered, no app was run.

**Inferred.** That everything merged before `3252c467` is live: the Go server replaced the
Swift one on 2026-10-30, and BACKLOG notes saying "Not deployed" predate it.

**Needs confirmation.**
- App Review outcome for 1.0 (submitted 2026-11-13).
- Whether TMDB's free-tier non-commercial terms still fit once Aaru is marketed (Plus off sale
  helps; `docs/providers.md`).
- Whether MAL's written authorisation has been asked for.
- Whether the landing page should keep "Android to follow" and "Google Play".
