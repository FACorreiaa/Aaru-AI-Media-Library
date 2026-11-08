# Aaru: product marketing strategy

Last verified: 2026-11-06, against `aaru-server-v2` 9c0848e (the API image production runs, pinned in infra `apps/aaru/api/values-production.yaml` at infra e838769), `aaru-client` 6d5944fe (the production Worker on aaruapp.com, last deployed 2026-10-29) and 1cf2ea5e (the beta Worker on beta.aaruapp.com), `aaru-ios` 1cf2ea5e (the latest internal TestFlight build), and `aaru-extension` 1cf2ea5e (not published).

Related documents:

- `features.md`: the feature inventory, with what can and cannot be shown.
- `rules/brand.md`: colours, type, logo and mascot rules, and voice.
- `rules/video-playbook.md`: how to capture and produce videos.
- `rules/content-calendar.md`: what is planned and approved.
- `../MARKETING.md` (2026-08-29, revised 2026-09-02), `../BUSINESS.md` (2026-09-12) and `~/Work/production/marketing/aaru/MARKETING-PLAN.md` (2026-09-30): older plans, all written before the product existed. They are kept for their reasoning, and section 8 lists what has gone out of date.

## Rules for anyone writing from this document

1. The product is **Aaru**. There is no other public name. Write "Aaru", not "AARU", and don't name the repositories or the server in public material.
2. Every claim must trace to `features.md`. If a feature has a status other than `verified`, follow the limits written on that feature.
3. Never invent users, testimonials, statistics or results. As far as this repository shows, **no stranger has used Aaru yet** (`BACKLOG.md`, P2 gate: "No stranger has used it"). There are no customer quotes or usage numbers to cite.
4. **Don't lead with AI.** The owner's own rule is "Do not put 'AI' in the headline, the app name, or the first screenshot" (`MARKETING.md` §12). Show what Aaru does, never that it is AI.
5. **Production is three different builds.** The API runs 9c0848e, the public website runs a client from 2026-10-29, and the iPhone app reaches internal TestFlight testers only. A feature on `main` is not live until it is in the build a stranger can reach. `features.md` says which.
6. Items marked **Needs confirmation** are open decisions. Do not resolve them by guessing.

---

## 1. Product overview

| | |
|---|---|
| **Product name** | Aaru |
| **Website** | https://aaruapp.com (the beta web app is https://beta.aaruapp.com) |
| **Tagline** | "Your stories. Your world." (the brand poster). The live landing page title is "One private library for everything you follow". |
| **One sentence** | Aaru is one private library for the films, shows, anime, manga, books and albums you follow: what you plan to, what you are in the middle of, and what you finished, with your old history brought in and free to take out again. |
| **Category** | Personal media tracker (TV, film, anime, manga, books, music). The iOS project's category is Entertainment (`public.app-category.entertainment`). |
| **Operator** | One individual developer. The privacy policy says "Aaru is run by an individual developer based in the European Union" and names no company. The landing page links the X account @fatc88. **Needs confirmation:** whether to name the developer in public material. |
| **Price today** | Free. Nothing can be bought anywhere. See section 6. |

**Elevator pitch.** People who track what they watch and read keep it in several places: Trakt or TV Time for shows, Letterboxd for films, MyAnimeList or AniList for anime, Goodreads for books. Each holds one slice, and moving between them loses rows. Aaru holds all of it in one private library, brings each old history in with a review step before anything is written, and lets you leave with a free export. It is built around "what is next for me": the next episode, what airs this week, what you left unfinished.

### Supported platforms

| Surface | State on 2026-11-06 | Notes |
|---|---|---|
| **Web** | **Live** at aaruapp.com | Anyone can create an account. The production Worker was built from 6d5944fe on 2026-10-29, so it **lacks** the assistant, the new Books page, Match all and book capture, which are only on beta.aaruapp.com. English only. Sign-in: "Continue with Google" works for anyone. "Continue with email" sends from Resend's shared test sender, which per the infra comment delivers only to the Resend account owner, so **email sign-in very likely fails for strangers** (inferred). Sign in with Apple is hidden on the web. |
| **Web beta** | Live at beta.aaruapp.com | Runs `main`, against the same production API and data. |
| **iPhone and iPad** | **Internal beta only** | "Aaru Beta" goes to TestFlight on every merge to `main`, with `distribute_external: false` (`aaru-ios/fastlane/Fastfile`). There is **no public TestFlight link** in the repo, and the App Store lookup for `com.fernandocorreia.aaru` returns nothing. The release lane has never been run. Requires iOS 18. |
| **Mac** | **Not distributed** | The app builds for macOS 15, but the Fastfile ships `PLATFORMS = %w[ios]` "until the team has a Mac Installer Distribution certificate". The landing page says otherwise (section 8). |
| **Browser extension** (Chrome, Firefox) | **Built, not published** | Version 0.1.0. No Chrome Web Store or Firefox Add-ons listing exists (`aaru-client/src/lib/agents/extension.ts`: `EXTENSION_STORES = []`). Its readers for Netflix, Disney+, Prime Video and YouTube have not been checked on the live players. |
| **AI agents over MCP** | Live on the API | Claude (as a custom connector), Claude Code, Codex, Hermes, Gemini CLI and other MCP clients. Requests that carry a browser `Origin` header are refused. Never verified against claude.ai (`BACKLOG.md` OUT-004). |
| **Stremio** | Live on the API | A Stremio addon (catalogs and playback ticks) and a one-time history import. Playback events never tried live. |
| **Music scrobblers** | Live on the API | Web Scrobbler, Pano Scrobbler, Navidrome and Jellyfin's plugin, over the ListenBrainz protocol. Never tried with a real scrobbler. |
| **Android** | **None** | The landing page shows "Google Play" and "Android to follow". No Android code exists. |
| **Plex, Jellyfin video** | **Not built** | Listed in `CLAUDE.md`'s stack, but no webhook code exists (`BACKLOG.md` SCR-002). |

---

## 2. Target audience

**Needs confirmation.** The audience below comes from `PRODUCT.md`, `MARKETING.md` and `MARKETING-PLAN.md`. Neither the repository nor this review contains research, interviews or usage data. Replace these personas with evidence once real users exist.

**Primary users.** "Cross-media power trackers" (`PRODUCT.md`): people who already keep their history somewhere, juggle several kinds at once, track to the episode and the chapter, care when an import drops a row, and check in most evenings, on the phone on the sofa or at a desk, in a dim room.

**Secondary users** (ranked in `MARKETING.md` §6, written 2026-09-02 and unverified since):

- Trakt users unhappy with paying to see their own statistics. Competitor prices in `MARKETING.md` are from memory and must be re-checked before use.
- Letterboxd users who also read, and Goodreads leavers.
- Former TV Time users. `MARKETING.md` §3.5 says TV Time shut down on 2025-07-15; re-verify before quoting.
- Anime and manga trackers with MyAnimeList or AniList lists.
- Pogdesign CAT users who rely on an episode calendar.
- People who use Claude or other agents and want them to reach their library, with approval inside Aaru (`BUSINESS.md` calls this "the only real wedge").

### Personas (hypotheses)

| Persona | Situation | Frustration | What Aaru offers them |
|---|---|---|---|
| **The cross-media tracker** | A few shows and an anime airing this week, a film tonight, a book and a manga in progress | Five apps, five statuses, no single "what is next" | One library for six kinds, The Field on Home, the calendar |
| **The migrating Letterboxd or IMDb user** | Years of history in a CSV export | Imports that silently drop or mis-merge rows | A review of every row before anything is written, "Find it" for misses, one-step undo |
| **The anime regular** | A MyAnimeList or AniList list, seasons that map badly between sites | Trackers that treat anime as a TV afterthought | AniList-backed anime, MAL and AniList import, MAL kept in step both ways |
| **The episode-calendar user** | Follows 20 shows, needs to know what airs when | Calendars that show everything except their own shows | Week, Month and Missed views from their own library, On air by channel with where to stream |
| **The agent user** | Lives in Claude or Claude Code | Their assistant can't see or safely change their media library | One connection, reads freely, and anything larger than one change waits for Approve inside Aaru |

**Who Aaru is not for.** People who want public reviews, followers or a public feed (Aaru has none, on purpose). People who want personalised recommendations (Discover is the same for everyone; only the assistant suggests when asked). Android-only users, except on the web. Non-English speakers: every surface is English only. Anyone expecting automatic tracking from Plex, Jellyfin or a store-installed browser extension today.

---

## 3. Problem and solution

**Main problem.** A person's history of stories is split by medium and by app. Each tracker holds one kind, moving between them loses data, and none of them answers "where am I in everything" in one place.

**Why it matters.** The work is bookkeeping: ticking 40 episodes, reconciling a 2,000-row export, remembering whether you finished something (`MARKETING.md` §3.2). When the bookkeeping is painful, people stop tracking, and the history they did keep is locked in someone else's app.

**How Aaru solves it.**

- **One library, one grammar.** Six kinds share the same statuses, progress, ratings, notes and lists, each with its own words (`CLAUDE.md`, "Domain language").
- **History comes in with a review.** Every import is a job that matches rows to catalog titles first and shows the result. "Nothing changes until you approve it, and an import undoes in one step" (`aaru-client/src/lib/imports/model.ts`).
- **"Where you are, not what exists"** (`PRODUCT.md`). Home leads with what you are in the middle of, what airs next and what is waiting for you.
- **Easy out.** Export to JSON or a CSV Aaru can import back, at any time.

**Primary value proposition.** Everything you follow, in one calm, private library that you can fill from your old apps and leave whenever you like.

### Key user benefits

1. **One place for every kind.** Films, shows, anime, manga, books and albums in one search and one library.
2. **Bring your history without bad merges.** You see every match before it is saved, and you can undo the whole import.
3. **Always know what is next.** Next episodes, what airs this week by channel, what you left unfinished.
4. **Private by default.** No public profile, no feed, no ads. Friends and groups are opt-in and friends-only.
5. **Leave whenever you like.** A full JSON export or a library CSV, free.

---

## 4. Positioning and differentiation

**Positioning statement.** For people who follow stories across films, TV, anime, books, manga and music and are tired of keeping them in five apps, Aaru is the one private library that brings that history in carefully and always shows what is next. Single-medium trackers own one slice and a public profile. Aaru holds every kind, privately, and lets you leave.

**The chosen claim.** **One calm, private library for everything you follow.** The landing page ("Everything you watch, read and follow. One calm library."), `PRODUCT.md`'s purpose and the welcome screen ("Everything you watch, read and listen to, in one library.") already agree on it. Do not sell a feature list, and do not lead with the assistant (rule 4).

### Differentiators, with evidence and limits

| Claim | Evidence | Limit you must respect |
|---|---|---|
| Six kinds in one library | `MediaType` and per-kind status labels (`aaru-client/src/lib/library/model.ts`) | Sports is a separate tab, not part of the library. Albums take status, rating and notes only; tracks are never ticked |
| Imports you review before they write | Import jobs, row states "Not matched" / "Will be added" / "Will be filled in", "Find it", "Undo this import" (`aaru-client/src/routes/_shell.app_.imports.$id.tsx`) | Trakt, Netflix, TV Time, CAT, Goodreads and Stremio parsers have **never run on a real user's export** (`BACKLOG.md`). Say "imports from", never "flawless" or "every row" |
| The widest import list in the product's own copy | IMDb, Letterboxd, Goodreads, Pogdesign CAT, Netflix, TV Time, MyAnimeList, AniList, Trakt, Stremio, any CSV; Last.fm, ListenBrainz, Spotify and YouTube history for music | Don't claim "the most imports" against competitors: no comparison exists |
| Private by default | No public profile or feed; friends are mutual; groups have no invite links (`CLAUDE.md` product rules) | **Group messages are server-visible**, and every channel says "not end-to-end". Encrypted DMs are **not built**. Never say "encrypted" |
| Free export, both ways | `GET /v1/me/export` JSON, and a CSV Aaru re-imports (`aaru-server-v2/internal/export/export.go`) | The JSON leaves out daily usage counts, undo history, proposed plans and import records (`docs/privacy.md`). Say "your library and everything you added", not "every byte" |
| Agents propose, you approve | MCP's `apply_library_patch` applies one small change like a tap; anything larger becomes a plan approved inside Aaru, with a push "{agent} wants to change your library" (`aaru-server-v2/internal/mcp`) | A one-item change **does** apply without approval, and is undoable. Five tools. Connector unverified on claude.ai |
| No ads, no data sale | `docs/privacy.md`: "Aaru does not sell or rent data, has no advertising code" | The server sends product counts to PostHog (EU) and errors to Sentry. The landing meta says "No ads, no tracking"; prefer "no ads, no data sale" in new copy |

### Reasons someone would choose Aaru

- They track more than one kind and want one place.
- They have an export file and want to move it without losing rows.
- They want to see what airs this week from their own shows.
- They want a library nobody else can see.
- It costs nothing today, and they can always take their data out.

### Alternatives

No feature-by-feature comparison has been done, so **make no comparative claims**, and never name a competitor in an ad.

- `MARKETING.md` names Trakt, Letterboxd, Goodreads, Simkl, Serializd, TV Time, StoryGraph, Sequel and medialib.net. Its prices and facts are from 2026-09 or earlier and are marked "re-verify before quoting".
- Trakt, Letterboxd, Goodreads, MyAnimeList and AniList appear in the product as import sources. Treat them as on-ramps in copy, not as enemies (`MARKETING.md` §3.4: "Trakt is not the enemy; it is the on-ramp").
- Keeping lists in notes or a spreadsheet, or not tracking at all, is probably the real competitor. This is inferred.

---

## 5. Marketing messaging

**Main headline.** Everything you watch, read and follow. One calm library.

This is the live landing hero. Its subline there is "Bring your history, leave whenever you like."

**Supporting headline.** Films, shows, anime, manga, books and albums in one private library. Bring your history in, and take it out whenever you like.

**Elevator pitch (30 seconds).**

> You keep your shows in one app, your films in another, your books somewhere else, and your anime list on a site of its own. Aaru puts all of it in one private library. Bring your history from Letterboxd, IMDb, Goodreads, MyAnimeList or a CSV, check every match before it is saved, and undo it in one step if you change your mind. Home shows what you are in the middle of and what airs next. Nobody sees your library unless you invite them, and you can export it any time.

**Short description (50 words).**

> Aaru is one private library for the films, shows, anime, manga, books and albums you follow. Bring your history from the apps you already use, review every match before it is saved, and see what is next at a glance. No public profile, no ads. Export whenever you like. Free today.

**Long description (about 190 words).**

> Aaru is a calm, private library for every story you follow.
>
> Films, shows, anime, manga, books and albums sit in one search and one library, each with its own words: Watching and Watched for a show, Reading and Read for a book, Listening for an album. Tick an episode and the next one is waiting.
>
> Bring the history you already keep. Aaru reads exports from Letterboxd, IMDb, Goodreads, MyAnimeList, AniList, Netflix, TV Time and more, matches every row to a title, and shows you the result first. You fix the ones it couldn't find, approve, and it lands as one action you can undo.
>
> Home answers "what is next for me": what you are in the middle of, what airs soon, what you left unfinished. The calendar shows this week's episodes from your own shows, and On air shows the week's new episodes by channel.
>
> Your library is private. There is no public profile and no feed. Friends and groups are opt-in and friends-only. Export everything as JSON or a CSV, any time, for free.
>
> Aaru is free today, on the web.

### Five benefit messages

1. **All of it, in one library.** Your shows, films, anime, manga, books and albums, with one search.
2. **Bring your history. Check it first.** Every row is matched and shown to you before anything is saved, and the whole import undoes in one step.
3. **Know what's next.** The next episode, what airs this week, and what you left unfinished, on one screen.
4. **Private by default.** No public profile, no feed, no ads. Friends only when you invite them.
5. **Leave whenever you like.** Your library as JSON or CSV, free, any time.

### Brand voice

Calm, private, nocturnal. Serene and exact, it proposes and never pushes: "may I", never "done". Short, plain, second person, quietly confident. No exclamation marks, no "AI-powered", no gamer bravado (`PRODUCT.md`). See `rules/brand.md` for the full rules.

| Do | Don't |
|---|---|
| Specific: "S2 · E4 is next", "Add 7 · 2 need a pick" (as real UI or labelled sample data) | Hype: "revolutionary", "the Letterboxd killer", "10x" |
| Admit limits: "Nothing is added until you approve what Aaru found" | "Flawless import", "never lose a row" |
| Plain sentences a tired person can read at night | Gamer RGB energy, all caps, exclamation marks |
| "Private by default", "friends only" | "Encrypted", "end-to-end", "secure" |
| "Aaru suggests, you approve" | "Aaru does it for you", "AI-powered" |

---

## 6. Conversion

**Primary call to action.** "Get started on the web", linking to `https://aaruapp.com/sign-in`. This is the live label. **Before promoting it, fix email sign-in** (section 8): today only "Continue with Google" reliably works for a stranger.

**Secondary call to action.** None for iPhone today: there is no public TestFlight link and no App Store listing. Do not write "Download on the App Store", "on iPhone" as an available surface, or "on Mac". When a public TestFlight link exists, "Join the iPhone beta" becomes the secondary CTA.

**Community call to action.** "Join us on Discord" (`https://discord.gg/GG55YPANC`), which the landing footer and `MARKETING.md` §7 (owner, 2026-10-23) already use.

**Agent audience call to action.** "Connect your agent": sign in, then Settings > Connections > Agents. Developer audience only.

**Pricing.** Verified: nothing can be bought. "Aaru Plus" exists in code on Apple (StoreKit products `aaru_plus_monthly`, `aaru_plus_yearly`, `aaru-ios/Aaru/Plus/PlusModel.swift`), but no products exist in App Store Connect, the iOS paywall cannot be reached, and the server paywalls nothing (`BACKLOG.md` BIL-005, owner 2026-11-05). The landing FAQ says: "Pricing is not final. Your library, your export and your statistics will never sit behind a paywall." and "Export will never be a paid feature." Say **"free today"**. Never present Plus, a price, Import Pass, Founding or Household (`MARKETING.md` §5.2) as purchasable. Fair-use limits exist (30 captures a day, 30 assistant questions a day), so **don't advertise "unlimited"**.

### Suggested landing page messaging

The current page has good copy. This order fits the verified product:

1. **Hero.** "Everything you watch, read and follow. One calm library." One real screen recording of Home, and the primary CTA.
2. **All of it, in one library.** Search across kinds, then a library with mixed posters. Fix the line "four plain statuses" first (section 8).
3. **Bring your history with you.** A real import review: matched rows, a "Find it", Approve, Undo.
4. **Always know what's next.** Home's Continue watching and Coming up, a tick, then the calendar week.
5. **Private by default. No ads, no feed.** Friends and groups are opt-in. Say "not end-to-end" for groups if groups appear.
6. **Leave whenever you like.** The export buttons.
7. **Where it runs.** Web today. iPhone, iPad and Mac only once there is a public way in. Remove Google Play.
8. **Questions and final CTA.**

### Objections

| Objection | Honest answer |
|---|---|
| "Will it mess up my history?" | Every import is matched and shown first; unmatched rows wait for "Find it"; the whole import is one action you can undo. Note that most importers have not yet run on a real user's export. |
| "Who can see my library?" | Nobody, unless you add them as a friend. Friends are mutual, there is no public profile or feed. Friends do see your badges and level by default, behind a switch (`BACKLOG.md`, 2026-10-22). |
| "Is it really free? What's the catch?" | Nothing can be bought today. The FAQ promises the library, export and statistics will never be paywalled. No ads, no data sale. |
| "Can I leave?" | Export as JSON or a CSV Aaru can re-import, at any time. Deleting the account is self-serve in Settings. |
| "Does it use AI on my data?" | Only when you ask: a capture, a question to Aaru, or tagging @aaru in a group. The privacy policy names Anthropic as the recipient and says it does not train on the data. Voice is transcribed on Aaru's own server and not stored. |
| "Who is behind this?" | One individual developer in the EU. It is early software with no uptime promise. Lean into the honesty, and don't imply a company or a team. |
| "Is there an iPhone app?" | It exists, in a private beta. Today the way in is the web. |
| "Does it track automatically?" | Not yet for most people. The browser extension is not in any store, and Plex and Jellyfin are not supported. Stremio and music scrobblers connect today, for technical users. |

---

## 7. Measurement

From `MARKETING.md` §10, which still fits.

**Activation** is at least one source imported **and** at least 25 library items within 24 hours.

**Leading indicator.** Import match rate: rows matched to a title on the first pass.

**Gates** (`MARKETING.md` §8, `MARKETING-PLAN.md` §6):

- Phase B: the first 10 strangers, recruited by hand, each watched through an import. "No launch post. No Product Hunt."
- Phase C, the public launch, needs 100 strangers, and the App Store release, Show HN and Product Hunt on one day.
- "Do not launch publicly before ten strangers have imported successfully." (`MARKETING.md` §12).

**Kill criteria.** None written for Aaru. `MARKETING-PLAN.md` gives exit conditions per phase (10 strangers imported and returned; then 3 friend circles of 3 or more for 2 weeks). **Needs confirmation:** the owner's equivalent of "ten conversations and no signups means the pitch is wrong".

**Instrumentation.** PostHog receives a few server-side product events only (`aaru-server-v2/internal/telemetry/posthog.go`); the apps and the website send none. Sentry gets errors only. The operator can read the user count at `/internal/metrics` with the metrics secret. **Needs confirmation:** the current stranger count.

---

## 8. What must be fixed before spending on promotion

These were found during this review. None was changed, because the brief excluded application code.

**Would break under traffic**

- **Email sign-in.** Production sends from `Aaru <onboarding@resend.dev>`, Resend's shared test sender, which the infra comment says "delivers only to the Resend account owner's own address". A stranger who chooses "Continue with email" will very likely get "The sign-in email could not be sent." (`aaru-server-v2/internal/auth/magiclink.go`). Fix: a verified domain sender, as the comment itself says.
- **No way onto iPhone or Mac.** TestFlight is internal testers only and Mac builds are not uploaded. Any Apple call to action leads nowhere.
- **AI spend.** The assistant, capture and @aaru run on Anthropic (`claude-haiku-5-5`, low effort) through Aaru's own workspace (`ANTHROPIC_WORKSPACE_ID`). Per-user caps exist (30 questions and 30 captures a day), but spend is only metered, not capped (`aaru-server-v2/internal/agent/usage.go`), and the workspace's own spend limit could not be read from here. When the provider refuses for credit, users see "Aaru is resting". Real-model video takes and campaign traffic share it.
- **Open security items.** `BACKLOG.md` SEC-001 and SEC-002 are marked "Pick these up before the first strangers".
- **One API replica** with in-memory rate limits (`values-production.yaml`). Fine for tens of users; note it before a launch spike.

**Production web is behind `main`**

The production Worker is from 2026-10-29. Until it is redeployed (a manual dispatch of `web-deploy.yml`):

- It shows a Plus upsell for something nobody can buy: "Plus lifts the monthly limit on captures. It is bought in the Aaru app on iPhone, iPad or Mac…" and "Not subscribed · N of M captures this month" (`aaru-client/src/components/settings/AccountPage.tsx` at 6d5944fe). The server no longer has a monthly limit.
- Its `/privacy` page (built from `docs/privacy.md`) is dated 27 October and does not cover the assistant, voice or read-aloud, which are live on the API and on TestFlight.
- It has no assistant, Match all or the new Books page.

**Public copy that is false or misleading today**

| Where | Says | Reality |
|---|---|---|
| Landing FAQ "When can I use it?" | "Aaru is in private beta on iPhone, Mac and the web." | Web is open to anyone; iPhone is internal TestFlight only; Mac is not distributed |
| Landing, store buttons and platforms | "Coming soon to the App Store and Google Play.", "Android to follow" | No Android code exists |
| Landing #kinds, `/about`, iOS welcome | "four plain statuses" | Five: On hold was added (LIB-007) |
| Landing #kinds | Lists Sports among the kinds you track | Sports is a separate tab; it never enters the library |
| Landing, iOS welcome, sign-in, PWA manifest | Kind lists that omit manga ("Films, shows, anime, books and albums"; "Films, shows, anime and books") | Six kinds; the landing also says "Movies" where the app says "Films" |
| Landing meta, `/privacy` meta | "No ads, no tracking." | Defensible under the policy's wording, but the server sends product events to PostHog. Prefer "No ads, no data sale" |
| Web and iOS Settings > Connections | "Install Aaru for Chrome or Firefox." | Not in any store; the same screens also say "Not in the Chrome Web Store or Firefox Add-ons yet." |
| `docs/privacy.md` | Describes buying Aaru Plus through Apple | No products exist |
| `CLAUDE.md` | "TestFlight, iOS + macOS"; "user key supported"; Plex + Jellyfin webhooks in the stack | iOS only; no own-key code; no Plex/Jellyfin code. Don't write from `CLAUDE.md`'s stack table |
| `README.md` | A Hummingbird skeleton with one route; "Never: … music"; clients "not scaffolded" | Entirely out of date. Don't write from the README |
| `BACKLOG.md` status table | Many server items "Not deployed"; P3–P7 summary says "no MCP" | Production now runs the server code on `main`. Use `features.md` |

**Missing for production work**

- No demo environment, seed script, fake model, UI tests or launch arguments (`rules/video-playbook.md`).
- No App Store metadata or screenshots in the repo; the only existing screenshots (`docs/audit/apple-shots/`) show the retired brand.
- Brand masters are reconstructions from one 1536×1024 poster (`rules/brand.md`).

**Superseded in the older plans.** `MARKETING.md` §0 and `MARKETING-PLAN.md` §1 ("pre-product", "no web app") no longer apply: the API, web app, iPhone app and extension exist. Their pricing tables (Import Pass, Plus at ~$3.99, Founding, Household) and "Capture is Plus, with 3 free a month" are replaced by BIL-005 (free, 30 captures a day). The free web converter tools, the open match ledger and the "this row is wrong" button (§3.3, §4) were never built. Still useful: the positioning reasoning, the persona ranking, the channels list, the "do not say" list, the activation definition, the phase gates and the risk list. `MARKETING-PLAN.md`'s Facebook, X and Instagram friend-import analysis still holds and none of it is built.

---

## 9. Evidence and assumptions

### How this was checked

Source was read with `git show` at each production commit, and at `origin/main` 1cf2ea5e. Note that the local checkout's `main` is at cb3fa704, 11 commits behind `origin/main`. Production settings came from infra `origin/main` (e838769). Release state came from GitHub Actions run history (read only): the last production web deploy, and the TestFlight runs. On 2026-11-06 these public pages were fetched: aaruapp.com, `/about`, `/privacy`, and the App Store lookup by bundle id.

**Not done.** Nobody ran the product for this review. **No screen was rendered for this review, rehearse before filming.** No build was made, no AI call was sent, no sign-in was attempted, and the cluster was not queried. "Verified" means the code exists in the build a stranger can reach and production settings allow it, not that someone watched it work.

### Verified

- Features, labels and navigation, as cited in `features.md`.
- The production API image (9c0848e) and that `aaru-server-v2` is unchanged between it and `origin/main`; the production image is built from `aaru-server-v2` (the GHCR repository is still named `aaru-server`).
- The production web Worker's commit (6d5944fe, 2026-10-29) from the last manual run of `web-deploy.yml`.
- TestFlight: iOS only, internal only (`Fastfile`); the App Store lookup returned no result on 2026-11-06.
- No billing anywhere a user can reach; no Android code; no encrypted DMs, SharePlay, Plex or Jellyfin code; no own-key support.
- 62 badges defined, 9 hidden (`aaru-server-v2/internal/gamification/catalog.go`). Five MCP tools. Five statuses. English only.
- The live landing, about and privacy text, including the claims section 8 calls false.

### Inferred, so confirm before relying on it

| Item | Basis | How to confirm |
|---|---|---|
| Email sign-in fails for strangers | Infra comment on `EMAIL_FROM` and Resend's test-sender behaviour | Try "Continue with email" with an outside address |
| Google sign-in works on aaruapp.com | `GOOGLE_CLIENT_IDS` includes the web client id seen in `aaru-client/wrangler.jsonc` | One real sign-in |
| Trakt, MAL, Last.fm, TheSportsDB, Ticketmaster, Anthropic, APNs and web push keys are valid | Key names are present in the sealed secret; values not read | One real run of each; the API logs at boot |
| The cluster's Whisper serves Aaru | Settings are present; the network policy was not read | One spoken question |
| Assistant is in the latest TestFlight build | `release-apple.yml` "Fastlane beta" step succeeded for 1cf2ea5e | Open TestFlight |
| Personas and audience | `PRODUCT.md` and the older plans | Real user conversations |
| Competitor facts in `MARKETING.md` | Written from memory in 2026-09 | Fresh research |

### Needs confirmation (decisions for the owner)

1. **Is it time to promote at all?** The owner's own rule is no public launch before ten strangers have imported (`MARKETING.md` §8, §12). Are the first videos for recruiting those ten testers by hand, or for a public launch?
2. **Lead audience.** Cross-media trackers (the landing), Trakt and Letterboxd migrants (`MARKETING.md`), or agent users (`BUSINESS.md`'s "only real wedge")?
3. **The iPhone route.** Will there be a public TestFlight link, and when will the App Store and Mac builds follow?
4. **Email sign-in.** When will a verified sender replace the Resend test sender?
5. **Production web deploy.** Redeploy before any campaign, so the website matches the API and the privacy page covers the assistant?
6. **Landing fixes.** Remove Google Play and "Android to follow"; fix "four plain statuses" and the Mac claim.
7. **AI spend limit** on Aaru's Anthropic workspace, and the plan when it is hit.
8. **Browser extension.** Submit to the stores, or hide the "Install" step until then?
9. **Catalog artwork in ads.** Poster and cover art belongs to studios and publishers and reaches Aaru through TMDB and others. May it appear in paid ads?
10. **The brand poster.** Who made it, and is its imagery cleared for paid use (`rules/brand.md`)?
11. **The owl in ads.** May the owl move, speak or appear in new poses?
12. **Founder on camera, and naming the operator.** The policy names no one; the landing links @fatc88.
13. **Type for video graphics.** SF Pro's licence, or a named substitute.
14. **Stranger count.** Current numbers of real users and activations.
