# Aaru video playbook

How to produce Aaru videos without showing anything false. Pair this with `../features.md` (what each feature does and its limits), `../strategy.md` (messages) and `brand.md` (look and voice). Checked on 2026-11-06. **No capture in this document has been run yet, and no screen was rendered for this review, rehearse before filming.** Every command and label below is read from source.

## Rules that never bend

1. **Product functionality is shown with real screens.** Higgsfield is for supporting scenes and presenters. Never use it to generate or fake app UI, a phone screen, a notification, the extension popup or the owl.
2. **AI output on screen must be real.** Every capture result, assistant reply, plan card and `@aaru` message must come from a real model run, and the manifest says so. The SwiftUI preview samples (`aaru-ios/Aaru/Home/HomeSample.swift`, `Calendar/CalendarSample.swift`, `Title/AlbumSample.swift`, `AaruWidgets/WidgetSample.swift`) and any stub-model run are for checking layout only, never for final footage.
3. **No fake customers.** An AI presenter is a presenter. It must not claim to be a user or describe personal results ("I tracked 400 films"). No invented testimonials or statistics. Follow each platform's rules on labelling AI-generated people.
4. **Synthetic data only.** No real names, emails, avatars or chats. Write the group chat for capture shots yourself. Don't use the owner's account or any account that has a real Trakt, MyAnimeList or Stremio history.
5. **Spend needs approval.** Get approval before Higgsfield credits, real-model runs on Aaru's Anthropic workspace, a paid TheSportsDB key, or a streaming subscription bought for a shoot.
6. **Nothing is published without explicit authorization.**
7. **Only `verified` features go in as available.** Check the "Do not market" table in `features.md` first. iPhone, iPad and Mac are "in beta" at most, and never a call to action.
8. **Film the build a stranger gets, and say which one.** The public website, the beta website, the API and the TestFlight build are four different commits (`features.md`, "Who can reach each surface"). Record the surface and commit of every clip in the manifest.

## Existing assets: reusable or retired

No promotional video exists anywhere in the repository (no `.mp4`, `.mov`, `.webm` or `.gif`), and there is no `higgsfield/` folder. The image assets are:

| Asset | Verdict | Reason |
|---|---|---|
| `docs/brand/source/owl-poster.png` | **Reusable, organic only** | The current brand standard. Its maker and the rights to its imagery (including the anime-style character art) are unconfirmed, so no paid use until the owner confirms (`brand.md`). Never present its hologram as the product |
| `aaru-client/public/og.jpg` | **Reusable** | The poster cropped, already public as the site's share image. Same caveat for paid use |
| Owl, poses and owl head in `aaru-client/src/assets/brand/` and the Apple asset catalog | **Reusable** within the pose rules in `brand.md` | Owner approved 2026-10-22/23. Small: keep well under full-frame |
| App icon set (`AppIcon`), A-mark and wordmark SVGs | **Reusable** | Owner approved the icon 2026-10-22 |
| `AppIconBeta` (navy "BETA" band) | **Retired for marketing** | Says beta on screen |
| `docs/audit/apple-shots/*.jpg` | **Retired** | 2026-10-21 shots in the old brand: serif headings, beige palette, an old tab bar |
| `docs/brand/out/icon/`, `docs/brand/out/reeds/`, `source/mascot*.jpg/png`, `reed-lockup.jpg`, `wordmark.jpg`, `app-icon.jpg` | **Retired** | Teal bird, reeds and old wordmark, replaced by the owl brand on 2026-10-22 |
| The landing hero's poster fan | **Reusable as a live screen** | It is real product UI, but it is made of studio artwork: see "Catalog artwork" below |

**Catalog artwork.** Nearly every Aaru screen shows posters, backdrops and covers that belong to studios, publishers and labels, served through TMDB, Open Library and the Cover Art Archive. Credit TMDB as `brand.md` requires. Whether those images may appear in **paid** ads is an open owner decision (`../strategy.md`, section 9). For organic posts, build the demo library from titles whose artwork is least sensitive, and never make one copyrighted poster the hero of a frame.

## What's missing before a first shoot

| Gap | Why it matters | Smallest fix |
|---|---|---|
| **Go / no-go and lead audience** | The owner's rule is no public launch before ten strangers have imported (`MARKETING.md` §12). It decides whether the first videos recruit testers or launch | Owner decision (`../strategy.md`, section 9) |
| **Production web is behind `main`** | aaruapp.com (6d5944fe, 2026-10-29) shows a stale Plus upsell and capture quota line, and lacks the assistant, Match all and the new Books page | Owner dispatches `web-deploy.yml` for production, or film only what 6d5944fe shows |
| **The local checkout is behind `origin/main`** | Local `main` is cb3fa704; a web recording from it misses the assistant card | The owner updates the checkout, or a capture agent works in a separate worktree at the named commit, with permission |
| **No seed script or demo account** | Nothing creates a populated library (`aaru-server-v2/scripts/` has only `generate-api.sh`) | Use the product's own import: a **synthetic** Letterboxd or IMDb CSV of 60–100 titles across kinds, plus a MAL XML for anime, imported through the UI. Keep the fixture files under `marketing/assets/fixtures/` |
| **No local sign-in shortcut** | Email sign-in needs `RESEND_API_KEY` and reaches only the Resend account owner; Google needs a client id allowed on localhost; no dev bypass exists | Owner picks one: their Resend address for a demo account, a localhost Google client, or inserting a session by SQL into the local database (untested) |
| **No fake model** | Capture, the assistant, Match all and `@aaru` answer 503 without `ANTHROPIC_API_KEY`. `BACKLOG.md` mentions a "stub model", but none is committed | Tier B shots need a real key and spend approval. A stub behind `ANTHROPIC_BASE_URL` is for rehearsal only (rule 2) |
| **Voice locally** | The cluster's Whisper is not reachable from a laptop, and the root `CLAUDE.md` forbids paid speech APIs | A local OpenAI-compatible Whisper on `TRANSCRIPTION_BASE_URL`, or film voice on TestFlight against production with a dedicated demo account, with approval |
| **TMDB key to boot** | The API refuses to start without `TMDB_API_KEY` | A free TMDB key of the owner's |
| **No iOS capture hooks** | No UI test target, no launch arguments, no demo mode in `aaru-ios` | Film by hand on the simulator, or the owner approves a film-only UI test target (an app code change) |
| **Debug and Beta identity** | Debug shows "Aaru Dev" and the BETA icon; Beta shows "Aaru Beta"; the Welcome screen shows "`<channel> · <host> · API ok`" in both | Sign in before recording and never show the Home Screen icon from these builds. A clean Release build has never been installed (`BACKLOG.md` REL-003) |
| **Extension build is stale** | `.output/` dates from 2026-10-21, with an old description and no YouTube support | Rebuild with `npm run dev` before any take |
| **Streaming players for the extension** | Netflix, Disney+ and Prime Video need a paid subscription, and their own terms may restrict showing their player | YouTube only for now; the owner decides on the others |
| **AI spend limit** | Real-model takes and campaign traffic share Aaru's Anthropic workspace, whose limit is unknown | Owner checks and sets it |
| **Brand masters** | The owl and marks come from one 1536×1024 poster | Keep the owl small; ask for masters before large-format use |

## Capture environments

| Need | Use | Notes |
|---|---|---|
| Web, no AI | Postgres on `:5432`, API on `:8080`, web on `:3000` | Tier A. See the setup below |
| Web or Apple, with real AI | Same local stack plus `ANTHROPIC_API_KEY` | Requires spend approval. Model `claude-haiku-5-5`; the adapter sends no sampling settings or prefill, so don't add any |
| iPhone/iPad in-app | Simulator, Debug build, local API | Debug's API base is `http://localhost:8080` (`aaru-ios/Config/*.xcconfig`, `AppEnvironment.swift`). iOS 18 or later |
| Mac in-app | Debug build run from Xcode, local API | Window opens at 1180×780 (minimum 760×520) |
| Browser extension | Chrome (or Firefox) with a **dedicated profile**, dev build pointed at the local stack | Only a development build may reach `localhost` |
| Lock Screen, Dynamic Island, widgets on device, real voice, real push | Physical iPhone with TestFlight "Aaru Beta", a **new demo account on production** | Touches production, so ask first. The Home Screen icon carries the BETA band |

**Local stack setup** (from `aaru-server-v2/docker-compose.yml`, `internal/config/config.go`, `aaru-client/README.md`; rehearse it, it was not run for this review):

```bash
# Database
cd aaru-server-v2 && docker compose up -d          # postgres:17 on 5432, user hb / testing123

# API (server commit: 9c0848e, identical to main for aaru-server-v2)
export POSTGRES_USER=hb POSTGRES_PASSWORD=testing123 POSTGRES_DATABASE=hb
export TMDB_API_KEY=<owner's free key>
export PUBLIC_BASE_URL=http://localhost:8080 WEB_BASE_URL=http://localhost:3000
export REALTIME_ORIGINS=http://localhost:3000       # or groups' live updates are refused
# Defaults point at production (api.aaruapp.com, aaruapp.com, cookie domain aaruapp.com):
# override OAUTH_COOKIE_DOMAIN too if you film agent connections (local value inferred, test it).
# Tier B only, after approval: export ANTHROPIC_API_KEY=...
go run ./cmd/aaru --db-migrate && go run ./cmd/aaru # 127.0.0.1:8080, metrics on 9090

# Web (6d5944fe for aaruapp.com shots, main for beta shots)
cd aaru-client
printf 'API_BASE_URL=http://localhost:8080\nCHANNEL=dev\n' > .dev.vars
npm run dev                                         # http://localhost:3000

# Extension, development build against the local stack
cd aaru-extension
WXT_API_BASE=http://localhost:8080 WXT_WEB_BASE=http://localhost:3000 npm run dev
```

Keys you can leave unset locally, and what disappears: Resend (email sign-in), Trakt and MAL (those connections), Last.fm (that import), TheSportsDB (the Sports tab hides), Ticketmaster (Concerts hides), VAPID and APNs (push), Anthropic (capture text and images, assistant, `@aaru`, Match all), transcription (the mic hides).

## Recording recipes

**Web**

1. No browser automation is installed in `aaru-client` (no Playwright, no e2e tests). Use the browser automation available in the session, or ask before installing a capture tool (check any new dependency first).
2. Desktop viewport **1440×900**: the sidebar appears from 1024 px. A phone-width web take uses **390×844**, which switches to the top bar and "Menu".
3. Seed by importing the synthetic CSVs through Settings > Import (this is also shot A3). Give the demo account a plain name and handle: the sidebar footer shows both on every screen.
4. Pin Settings > Account > Appearance to Dark. Load each page once before recording, so poster images are cached.
5. Add pacing. A real person reads a review screen slowly; hold on each state for at least two seconds.

**iPhone/iPad simulator**

1. Build: `xcodebuild build -project aaru-ios/Aaru.xcodeproj -scheme Aaru -destination 'platform=iOS Simulator,name=<device>'` (the `CLAUDE.md` command uses a generic destination; pick a named simulator to run). Signing as in the project.
2. `xcrun simctl ui booted appearance dark`, then `xcrun simctl status_bar booted override --time 9:41 --batteryState discharged --batteryLevel 100`.
3. `xcrun simctl io booted recordVideo --codec h264 out.mp4`, and stop it with Ctrl-C.
4. Sign in first, so the Welcome screen's debug caption never appears. Drive by hand: there are no UI tests or launch arguments.
5. `xcrun simctl push` can rehearse a notification's look, but **final footage of a push must come from a real server event** (an airing, a real agent plan), or it is a faked notification (rule 1).

**Mac**

1. Run the Debug build from Xcode. Use the default 1180×780 window on a clean desktop.
2. Record with `screencapture -v -R<x,y,w,h> out.mov` or QuickTime. Hide the Dock and menu-bar extras.
3. Mac is not distributed, so Mac footage cannot carry a call to action.

**Browser extension**

1. Use a fresh Chrome profile with no other extensions and no bookmarks bar.
2. `npm run dev` opens Chrome with the extension loaded. Alternatively `npm run build` and "Load unpacked" from `aaru-extension/.output/chrome-mv3` (Firefox: about:debugging > Load Temporary Add-on > `.output/firefox-mv3/manifest.json`), but a production build cannot reach `localhost`.
3. Connect: popup "Connect" > the tab "Connect … to Aaru?" > "Approve".
4. Tier A: a YouTube `/watch` video shows "Now · YouTube" and "✓ Playing in Aaru". A "- Topic" channel's song past half or 4 minutes becomes a listen.
5. The popup is small: record it at 2× and crop, or use the browser's zoom. The toolbar badge shows ✓, ? or !.

**Output sizes.** Vertical 1080×1920 for short-form, landscape 1920×1080 where useful, and square or 4:5 only if a platform calls for it. iPhone captures are naturally vertical. Web shots need a framed or cropped treatment for vertical; reframe, don't just centre-crop (prompt `08`).

## Clear these before every recording

- [ ] Dark appearance pinned. Reduce Motion **off**, Increase Contrast **off**, Reduce Transparency **off** (otherwise the owl stills and the texture disappears).
- [ ] Demo name, handle and avatar set. No real email in Settings > Account ("Signed in with").
- [ ] "Waiting for you" on Home is empty, unless filming a capture or agent plan.
- [ ] No "Aaru Dev", "Aaru Beta", BETA icon or Welcome debug caption in view.
- [ ] On the production web build (6d5944fe), keep out of frame: the Plus lines in Settings > Account and under the capture box; the "Install Aaru for Chrome or Firefox" step; the landing's Google Play badge and "four plain statuses".
- [ ] No spoilers: avoid episode titles and overviews for shows still airing, and use titles not yet finished by the viewer at your own discretion.
- [ ] The calendar and On air depend on the real week. Shoot within the week your seeded shows air, and note the date in the manifest.
- [ ] Toasts cleared before a take starts; reset the state between takes (Undo, or re-seed).
- [ ] Credits ready: the TMDB notice on any title-heavy video; TVmaze and JustWatch when On air appears; the Trakt notice when Trakt appears.
- [ ] For AI shots: the run is real, the prompt and reply are saved next to the clip, and the cost is logged.

## Shot bank

Feature numbers refer to `features.md`. **Tier A** needs no AI and no paid service and can be recorded first. **Tier B** needs a real model or a paid API or service. **Tier C** needs a physical device.

| ID | Shot | # | Platform | Length | Tier |
|---|---|---|---|---|---|
| A1 | Search one word that hits several kinds, "Add with status" | 1 | Web | 12 s | A |
| A2 | Library kind chips sweep All > Films > Books > Music, grid | 1 | Web | 10 s | A |
| A3 | Drop a CSV, review fills, "Not matched", "Find it", "Approve and import", Undo toast | 11 | Web | 25 s | A |
| A4 | Home "The Field", slow scroll from Tonight to Unfinished business | 5 | Web | 15 s | A |
| A5 | "Mark S2E4 watched", the next episode slides in, Undo toast | 3 | Web or iPhone sim | 10 s | A |
| A6 | Calendar Week, "Group by" Channel, Month, Missed | 8 | Web | 15 s | A (shoot in an airing week) |
| A7 | Discover > On air, channel by channel, one "Add" | 7 | Web | 12 s | A (credits on screen) |
| A8 | The same status chips reading Watching / Reading / Listening | 2 | Web | 12 s | A |
| A9 | Settings > Your data > History, Undo one action | 41 | Web | 8 s | A |
| A10 | "Library spreadsheet (CSV)", the file opens in a spreadsheet | 42 | Web | 10 s | A |
| A11 | Insights period chips, 7 days to Year | 29 | Web | 10 s | A (needs days of live ticks) |
| A12 | Recap story cards through to the persona, "Share as an image" | 30 | Web | 12 s | A (needs a month of live ticks) |
| A13 | iPhone Home and tab bar, tick from Continue watching | 5, 3 | iPhone sim | 15 s | A |
| A14 | "Up Next" widget, tap the check, next episode | 38 | iPhone sim | 8 s | A (test first) |
| A15 | MAL XML import lands a long show with its seasons ticked | 13 | Web | 15 s | A |
| A16 | Extension popup on YouTube, then Home's Now playing card | 25, 28 | Chrome dev build + web | 12 s | A (experimental; not for CTA) |
| A17 | Mac window, ⌘1…⌘5 through the sidebar | 39 | Mac | 10 s | A (no CTA possible) |
| B1 | Paste a written chat, "Your capture", "Add 7 · 2 need a pick", Approve | 16 | Beta web or web | 20 s | B |
| B2 | Owl, ask in a sentence, plan card, Approve, screen behind updates | 22 | iPhone sim or beta web | 20 s | B |
| B3 | Claude asks to change the library; "Waiting for you", Approve; History shows Claude | 23 | Claude + web | 25 s | B (verify the connector first) |
| B4 | "Match all" on an import's leftovers, untick one, Approve | 15 | Beta web | 15 s | B |
| B5 | Ask for a reading order; "Saved in order as the list …" | 17 | Beta web | 15 s | B |
| B6 | An episode ends on Netflix; badge ✓; Home shows the next one | 25 | Chrome + paid subscription | 15 s | B (owner decides on the service's terms) |
| B7 | Sports Schedule with a live score | 21 | Web | 10 s | B (paid key) |
| C1 | Long-press the owl, speak, the reply is read aloud | 22 | iPhone | 15 s | B + C |
| C2 | Lock Screen Live Activity, "Mark watched" | 28 | iPhone (Dynamic Island: a Pro model) | 12 s | C |
| C3 | "Up Next" widget on a real Home Screen | 38 | iPhone | 8 s | C |
| C4 | Push "Claude wants to change your library", Approve on the phone | 23 | iPhone + laptop | 15 s | B + C |
| C5 | A real airing alert for a seeded show | 9 | iPhone | 8 s | C (wait for an airing) |

**Cheapest first cut:** a silent 30-second reel from A3, A4, A5, A6 and A10. No spend, no phone, production-web features only.

## Formats

Every format needs a script, storyboard and shot list approved before generation. These are starting points, not approved scripts. All of them end on the web: "aaruapp.com". None says iPhone or Mac is available.

### 1. Full application showcase (45–60 s)

| Time | Beat | Picture | Words |
|---|---|---|---|
| 0–4 | Hook | Night navy, the wordmark, one amber edge | "Your shows are in one app. Your books are in another." |
| 4–12 | One library | A1, then A2 | "Aaru keeps films, shows, anime, manga, books and albums in one private library." |
| 12–26 | Bring your history | A3 | "Bring your history from Letterboxd, IMDb or Goodreads. You see every match before it's saved, and you can undo it in one step." |
| 26–36 | What's next | A4, then A5 | "Home shows what you're in the middle of. One tap keeps your place." |
| 36–46 | This week | A6 | "And the calendar shows every episode from your shows, this week." |
| 46–54 | Private, and yours | A10 | "Nobody sees your library unless you invite them. Export it whenever you like." |
| 54–60 | End | Owl on the night disc, wordmark, tagline, URL | "Aaru. Your stories. Your world. Free today, at aaruapp.com." TMDB notice on screen. |

### 2. AI presenter / UGC advertisement (30–45 s)

The presenter speaks in the second person about the viewer's situation, and real screen recordings show the product. Draft:

> Your shows are in one app, your films in another, and your books somewhere you haven't opened since spring.
>
> Aaru puts all of it in one private library.
>
> Bring your Letterboxd or IMDb export. Aaru matches every row and shows you the result before anything is saved. If it's wrong, undo it in one step.
>
> Then Home just shows you what's next: the episode you're on, what airs this week.
>
> Nobody sees it unless you invite them. It's free today, on the web, at aaruapp.com.

Picture: presenter on a sofa in a dim room at night, cutting to A3, A4 and A6. Generated scenes must contain no fake phone or laptop UI: composite real recordings instead. Add the TMDB notice. Stop if the presenter gains a personal backstory or results ("I moved 2,000 films").

The owner on camera would be stronger and more honest than any generated presenter, if willing (`../strategy.md`, section 9).

### 3. Individual feature demos (15–30 s)

Use the "Video concept" on each feature in `features.md`. Suggested order: Import with review (11), Home (5), Calendar (8), episode tick and Undo (3), export (42). Then, once tested with a real model: Capture (16), the assistant (22) once production web has it, and the Claude connector (23) for developer channels.

Each demo covers one problem and one benefit, and ends on the CTA.

### 4. Short teaser (10–15 s)

Option A, no AI: A3 compressed to its two best seconds (rows turning to "Will be added"), then A4's Home. Text: "Bring your history. Check it first." End card.

Option B, no AI: A6. The Week grid fills with your shows, "Group by Channel". Text: "Every episode from your shows, this week." End card.

## Using Higgsfield

Fits: presenter footage, a mood shot (a dim living room at night, a city behind glass, a desk lamp over a stack of books and a remote), transitions, thumbnails. Doesn't fit: anything that shows the Aaru interface, a device screen, a notification, or the owl (any new owl image or motion needs the owner's approval first, `brand.md`).

**Check first:** whether Higgsfield is approved for Aaru at all. For the owl poses the owner chose "a free generator other than Higgsfield" (`BACKLOG.md`, 2026-10-23). Inspect what Higgsfield tools are actually available in the session; logging in is the owner's to do. Quote the credit cost before spending.

**Palette prompt** (name it in every prompt):

> Night-time interior, calm and cinematic. Deep night navy (#0e141e, #16233a) dominant, silver-white highlights (#e7ebf1), cool ice-blue light (#6aaeea) as the main light source, a thin warm amber edge light (#e0904f) used sparingly. Quiet, precise, dark depth, soft focus city lights behind glass. No neon, no magenta, no teal, no red, no glitch effects, no scanlines, no HUD overlays, no text, no logos, no screens with readable content.

## Asset manifest

Keep it at `assets/manifest.md`, with final assets in `assets/` and the synthetic seed files in `assets/fixtures/`. Create it with the first real asset. Keep large recordings out of Git unless the repo deliberately uses LFS. One row per file:

| File | Video or shot ID | Feature # | Surface (web prod / beta web / iPhone sim / iPhone device / Mac / extension) | Client commit | API commit | Data source (fixture file, demo account) | Real AI? (run id, cost) | Licences and credits (TMDB, catalog artwork, music) | Approved by, date |
|---|---|---|---|---|---|---|---|---|---|

Re-check a clip whenever the feature changes, and whenever the production web Worker is redeployed.

## Quality control

Run this before asking for approval:

- [ ] Every demonstrated feature is `verified` in `features.md`, or the stated limit is respected and said.
- [ ] Every clip's surface and commit are in the manifest, and the clip matches what that surface shows a stranger today.
- [ ] All on-screen AI output came from a real run, and the manifest says so.
- [ ] UI text is current: no "Aaru Dev" or "Aaru Beta", no BETA icon, no Plus upsell, no "four plain statuses", no Google Play badge, no retired teal bird, reeds or serif.
- [ ] No sensitive information, real people, real chats or real account details.
- [ ] Words match the limits: "free today", "private by default", "you approve", "imports from". Never "encrypted", "unlimited", "on the App Store", "on Android" or "AI-powered".
- [ ] iPhone, iPad and Mac are described as beta at most, and never as the call to action.
- [ ] Gold appears only as edge light; no white text on ice blue; the owl sits on the night disc in an approved pose.
- [ ] Audio, captions and visuals are in sync. Captions are in English (the product is English only).
- [ ] The TMDB notice and any other required credits are present.
- [ ] Social package ready: hook, caption, CTA, hashtags, vertical and landscape cuts, thumbnail idea, calendar row.
- [ ] Owner approved it. **Published only with explicit authorization.**
