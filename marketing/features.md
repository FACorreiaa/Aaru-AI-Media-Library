# Aaru: feature inventory

Last verified: 2026-11-06, against `aaru-server-v2` 9c0848e (the API image production runs), `aaru-client` 6d5944fe (the production Worker, aaruapp.com) and 1cf2ea5e (the beta Worker, beta.aaruapp.com), `aaru-ios` 1cf2ea5e (the latest internal TestFlight build), and `aaru-extension` 1cf2ea5e (not published).

Use this document to pick features, write scripts and plan recordings. Positioning lives in `strategy.md`, and capture tooling lives in `rules/video-playbook.md`.

## How to read this

**Status** describes what a real user can do in production today.

| Status | Meaning |
|---|---|
| `verified` | Code is in the production build of that surface, production settings allow it, and a user can reach it from the UI. Read in source: **no screen was rendered for this review**, so rehearse before filming. |
| `partial` | Works, with a limit stated on the feature. Follow the limit in any copy. |
| `experimental` | Built and reachable, but with no evidence it works on a real model, a real account or a real device, or it is reachable only on a beta surface. Test before promising. |
| `planned` | Not available. Never market it. See "Do not market" below. |

**Who can reach each surface.** This matters more than status for Aaru:

| Label | Surface | Who can use it today |
|---|---|---|
| **Web** | aaruapp.com, production Worker from 6d5944fe (2026-10-29) | Anyone. Google sign-in works; email sign-in very likely does not for strangers (`strategy.md`, section 8) |
| **Beta web** | beta.aaruapp.com, `main` | Anyone who knows the address. Same API and data |
| **iPhone/iPad** | "Aaru Beta" on TestFlight, from `main` | **Internal testers only.** No public link, no App Store |
| **Mac** | Same app, macOS 15 | **Nobody**: not uploaded anywhere |
| **Extension** | Chrome and Firefox, MV3 | **Nobody** without a local build: not in any store |
| **API** | api.aaruapp.com, 9c0848e | Agents, Stremio and scrobblers that connect with a token |

A feature that lives only on iPhone/iPad or Mac can be filmed, but a viewer cannot get it. Say "in beta on iPhone" at most, and never use it as a call to action.

**Priority** reflects customer value and how well it shows on screen, not technical effort.

**Live AI** in a recording means the shot needs a real model (Anthropic, `claude-haiku-5-5`). There is **no fake model** for local runs, so AI features answer 503 without a key. Using a real model costs money, so get approval first (`rules/video-playbook.md`).

**Paths** start from the workspace root, `~/Work/production/apps/aaru/`. In the path lists, `server/` means `aaru-server-v2/`, `web/` means `aaru-client/src/` (read at 6d5944fe unless "main" is said), `apple/` means `aaru-ios/`, and `ext/` means `aaru-extension/`.

**Feature names differ by platform.** Use the name the viewer will see on screen.

| Concept | Web label | iPhone/iPad | Mac |
|---|---|---|---|
| Open the assistant | Owl, "Ask Aaru", ⌘J (beta web only) | Owl in the top bar; tap to type, long-press to talk | Owl, or ⌘K "Ask Aaru" |
| Search | "Search", ⌘K | Search in the top bar | "Search Titles", ⌘F |
| Voice button | "Ask by voice" / "Done talking" (beta web) | "Talk to Aaru" / "Stop and send" | Same as iPhone |
| Settings | Sidebar > Settings | Account button, top right | Settings window, ⌘, |
| Lists | Sidebar > Lists | Library > "Lists" | Sidebar > Lists |
| Insights | Sidebar > Insights | Library > More menu > "Insights" | Sidebar > Insights |
| Friends | Sidebar > Friends | Inside Groups | Sidebar > Friends |
| Groups, Books, Manga, Music, Sports | Sidebar > More | More tab | Sidebar > More |
| Home row of upcoming episodes | "Coming up" | "Airing soon" | "Airing soon" |
| Home row of stalled titles | "Unfinished business" | "Unfinished" | "Unfinished" |
| Approve an outside plan | Approve / Not this | Approve / Not this | Approve / Not this |

---

## The five features to lead with

| # | Feature | Why |
|---|---|---|
| 1 | [Bring your history, reviewed first](#11-file-imports-with-review) | It is the front door and the trust story in one screen: matched rows, a "Find it", Approve, Undo. No AI needed |
| 2 | [One library for six kinds](#1-one-library-for-six-kinds) | The chosen claim, shown in a single search and a mixed library |
| 3 | [Home: The Field](#5-home-the-field) | "Where you are, not what exists": what is next, ticked in one tap, on the best-looking screen |
| 4 | [Calendar and On air](#8-calendar-week-month-missed) | Instantly understood, dense in the good way, filmable with no AI |
| 5 | [Capture: paste anything, get a plan](#16-capture-paste-anything-get-a-plan) | The "30-second video" `MARKETING.md` always wanted. **Needs a real model and a rehearsal first**: it has never been shown working on camera |

---

## Do not market

These appear in old docs, in public copy or in the code, but a user cannot use them today.

| Item | Actual state | Evidence |
|---|---|---|
| **App Store app, "Download on the App Store"** | Not released. TestFlight is internal only, with no public link. | `apple/fastlane/Fastfile` (`distribute_external: false`); App Store lookup empty |
| **Mac app** | Builds, but is not uploaded anywhere. The landing page's "private beta on iPhone, Mac and the web" is wrong about Mac. | `apple/fastlane/Fastfile` (`PLATFORMS = %w[ios]`) |
| **Android, Google Play** | No client exists. The landing page shows a Google Play badge and "Android to follow". | No Android code in the repo; `web/components/StoreButtons.tsx` |
| **Browser extension from a store** | Built, not submitted. Readers never checked on live players. Show it only as "coming", if at all. | `web/lib/agents/extension.ts` (`EXTENSION_STORES = []`); `BACKLOG.md` SCR-007 |
| **End-to-end encrypted messages (DMs)** | Not built. Group messages are server-visible. Never say "encrypted". | `BACKLOG.md` DM-001…005 "Open"; no libsignal code |
| **SharePlay, online presence** | Not built. Groups have typing indicators only. | `BACKLOG.md` ROOM-003, RT-001, GRP-017 |
| **Plex and Jellyfin video tracking** | No webhook code. Jellyfin appears only as a music scrobbler. | `BACKLOG.md` SCR-002 "Open" |
| **Push to Trakt or AniList** | Not built. Only MyAnimeList is kept in step. | `BACKLOG.md` SCR-004, SCR-006 |
| **Bring your own AI key** | Not built, though `CLAUDE.md` says "user key supported". | `BACKLOG.md` AG-007 "no own key yet" |
| **Aaru Plus, any price, Import Pass, Founding, Household** | Nothing can be bought. Plus has StoreKit ids but no products and an unreachable paywall. | `apple/Aaru/Plus/PlusSection.swift`; `BACKLOG.md` BIL-005 |
| **Siri, Shortcuts, Spotlight, share extension** | Not built. The only App Intents are hidden ones behind widget and Live Activity buttons. | `apple/Shared/MarkEpisodeWatchedIntent.swift` (`isDiscoverable = false`); `BACKLOG.md` OUT-003, AG-006 |
| **Undo ribbon** (`DESIGN.md` §9) | Not built as a ribbon. Undo exists as toasts, in History, and inside the assistant card. Say "Undo", not "the undo ribbon". | `BACKLOG.md`, "Known gaps no item owns yet" |
| **Personalised recommendations** | None by design. Discover is "the same for everyone". Only the assistant suggests, when asked. | `CLAUDE.md`, "Out of scope" |
| **Free converter tools, open match ledger** | Never built. | No `match_aliases` code; `MARKETING.md` §3.3, §4 |
| **Friend finding by email, Trakt or AniList; suggestions** | Not built. Friends are found by handle or invite link. | `BACKLOG.md` SOC-009…011 |
| **Group replies, images in groups** | Not built. | `BACKLOG.md` GRP-014…016 |
| **Languages other than English** | Every surface is English only. | `web/routes/__root.tsx` (`lang="en"`); `apple` `knownRegions = (en, Base)` |
| **"Four plain statuses"** | There are five: On hold was added. | `web/lib/library/model.ts`; `BACKLOG.md` LIB-007 |
| **Unlimited AI** | 30 assistant questions (shared with @aaru) and 30 captures a day per account. | `server/internal/groups/agent.go`, `server/internal/imports/capture.go` |
| **Concerts everywhere** | Ticketmaster lists nothing in Portugal. | `BACKLOG.md` MUS-003, MUS-009 |
| **"Offline"** as a headline | Apple Home, Calendar and Discover open from the last load; the web does not. | `apple/Aaru/Home/HomeCache.swift` |

---

## Platform differences

**iPhone/iPad only (internal TestFlight):** widgets on the Lock Screen (accessory sizes), Live Activities and the Dynamic Island, push notifications, long-press-to-talk on the owl, read-aloud with the device's voice, Sign in with Apple, the "Watching now…" button.

**Mac only (not distributed):** the menu bar commands ("New List" ⌘N, "Ask Aaru" ⌘K, "Search Titles" ⌘F, "Refresh" ⌘R, the "Go" menu), desktop widgets, the Settings window.

**Web only:** web push in the browser, the extension connect page, the OAuth consent page for agents, export download, the landing page.

**Beta web and TestFlight only, not on aaruapp.com:** the assistant card, Match all, the new Books page (Read this year, Import books, On hold and Read shelves), book capture and "ask for books".

**Everything else is on web, iPhone/iPad and Mac**, with the layouts and labels shown above.

---

# A. The library

## 1. One library for six kinds

- **What it does.** One search across films, shows, anime, manga, books and albums, and one library that holds them all, filtered by kind and status, as a grid or rows.
- **Problem.** Every tracker holds one kind, so a person's stories are split across five apps.
- **Benefit.** One place for everything you follow.
- **Platforms.** Web, iPhone/iPad, Mac.
- **Workflow.** 1) Search (⌘K on web). 2) Pick a kind tab: All / Films / Shows / Anime / Manga / Books / Music. 3) "Add" or "Add with status". 4) Open Library: chips All / Films / Shows / Anime / Manga / Books / Music, Grid / Rows.
- **Location.** Web: sidebar > Search, sidebar > Library. iPhone: Library tab. Mac: sidebar > Library.
- **Code.** `web/components/SearchPanel.tsx`, `web/routes/_shell.app_.library.tsx`, `web/lib/library/model.ts`, `apple/Aaru/Search/`, `apple/Aaru/Library/LibraryView.swift`, `server/internal/catalog/`, `server/internal/library/`.
- **Status.** `verified`. Catalogs: TMDB (film, TV), AniList (anime, manga), Open Library (books), MusicBrainz (albums). Albums take status, rating and notes only. Sports is **not** a library kind.
- **Priority.** High. It is the claim itself.
- **Headline.** "All of it, in one library."
- **Recording.** Tier A. A seeded library of 40+ titles across all six kinds. Search one word that hits several kinds, add one with a status, then flick the Library kind chips.
- **Video concept (20 s).** Five app icons on a dark desk fade out one by one. Cut to Aaru's Library: the same titles side by side, then the kind chips sweep from Films to Music. End on "One calm library."

## 2. Status, rating, notes and progress (the title page)

- **What it does.** Each title page holds the status (per-kind words), a rating, a private note, progress (episodes; page, chapter or volume for books and manga), an "Owned" switch and "Add to list".
- **Problem.** Trackers either force one vocabulary on every kind or bury the controls.
- **Benefit.** The right words for each kind, and your own notes next to it.
- **Platforms.** Web, iPhone/iPad, Mac.
- **Workflow.** 1) Open a title. 2) Pick a status chip (for a show: Plan to watch / Watching / On hold / Watched / Dropped). 3) Rate it. 4) Write in "Anything worth remembering", "Save note". 5) For a book, "Save progress" by page.
- **Location.** Any title (`/app/title/$id` on web).
- **Code.** `web/routes/_shell.app_.title.$id.tsx`, `web/lib/library/model.ts`, `apple/Aaru/Title/`, `server/internal/library/`.
- **Status.** `verified`. On hold keeps a title out of Now, Up Next, Tonight, the week and airing alerts (LIB-007).
- **Priority.** Medium. Supporting shot.
- **Headline.** "Each kind keeps its own words."
- **Recording.** Tier A. One show and one book, back to back, to show the status words change.
- **Video concept (12 s).** Split screen: a show reading "Watching", a book reading "Reading", an album reading "Listening". Same chips, different words.

## 3. Episode tracking with Undo

- **What it does.** Tick an episode, mark a season or a whole show watched, and see the next episode at once. A toast offers Undo. A finished show reopens when a new episode airs (beta web and TestFlight; production web lacks that last fix).
- **Problem.** Ticking 40 episodes one at a time is the chore that makes people stop tracking.
- **Benefit.** One tap keeps your place, and a wrong tap is one Undo away.
- **Platforms.** Web, iPhone/iPad, Mac. Widgets and Live Activities add a "Mark watched" button on iPhone.
- **Workflow.** 1) On Home or the title, "Mark S1E2 watched". 2) The toast shows Undo. 3) The next episode takes its place. 4) Season map for a whole season.
- **Location.** Home rows, title page, calendar sheets.
- **Code.** `web/components/mark-watched.ts`, `web/components/undo-toast.ts`, `web/components/SeasonMap.tsx`, `server/internal/library/`, `server/internal/schedule/`.
- **Status.** `verified`. Undo is a toast, not a ribbon.
- **Priority.** High. The daily action, and the Undo is a trust beat.
- **Headline.** "One tap keeps your place."
- **Recording.** Tier A. A show mid-season, tick, the toast, Undo, tick again.
- **Video concept (10 s).** Close on "Mark S2E4 watched". Tap. The card flips to E5. The Undo toast slides in and fades.

## 4. Lists

- **What it does.** Make named lists, add any library title, reorder, rename, delete.
- **Problem.** Themes, marathons and book clubs don't fit a status.
- **Benefit.** Your own collections across kinds.
- **Platforms.** Web, iPhone/iPad, Mac.
- **Workflow.** 1) Lists > "Name a new list" > "Create". 2) "Add titles". 3) Reorder.
- **Location.** Web: sidebar > Lists. iPhone: Library > "Lists". Mac: sidebar > Lists, or ⌘N.
- **Code.** `web/routes/_shell.app_.lists.index.tsx`, `web/routes/_shell.app_.lists.$id.tsx`, `apple/Aaru/Lists/`.
- **Status.** `verified`. Shelves (saved filters) exist in the data model, but no screen lets a user make one: don't say "smart shelves".
- **Priority.** Low.
- **Headline.** "A list for every marathon."
- **Recording.** Tier A. A cross-kind list: two films, a show and the book it came from.
- **Video concept (10 s).** "Dune, every version": the book, two films, a show, in one list.

# B. What's next

## 5. Home: The Field

- **What it does.** Home, headed "The Field" beside the owl, answers "what is next for me": Tonight, "Waiting for you", Continue watching, Reading, Listening, Coming up, Start watching, Unfinished business, Last 7 days, your lists and three Discover rows.
- **Problem.** Trackers open on a catalog, not on where you are.
- **Benefit.** One look tells you what to watch, read or play next.
- **Platforms.** Web, iPhone/iPad, Mac (row names differ, see the label table).
- **Workflow.** 1) Open Aaru. 2) Read Continue watching. 3) Tick from the row. 4) Scroll to Coming up, "See calendar".
- **Location.** Web: sidebar > Home. Apple: Home tab or sidebar.
- **Code.** `web/routes/_shell.app.tsx`, `web/components/HomeRows.tsx`, `apple/Aaru/Home/HomeScreen.swift`, `apple/Aaru/Home/HomeSections.swift`.
- **Status.** `verified`. A new account sees "Add something to see what’s next" until it has titles. The idle owl and the texture show only here and on title pages.
- **Priority.** High. The best-looking screen, filmable with no AI.
- **Headline.** "Where you are, not what exists."
- **Recording.** Tier A. Seeded library with 4+ shows mid-season, a book and an album in progress, and a few titles stalled for weeks. Dark appearance, Reduce Motion off. Slow scroll top to bottom.
- **Video concept (15 s).** Night. A phone face-down on a sofa arm turns over. Aaru's Home: The Field, the owl breathing, Continue watching. A thumb ticks one episode. "Always know what's next."

## 6. Tonight

- **What it does.** A small strip on Home that offers one thing for tonight, with "Mark watched", "Open", and "Not tonight" or "Not for me". Its reasons are templates, not a model call.
- **Problem.** Too many things in progress, no decision.
- **Benefit.** One suggestion from your own library, dismissed in a tap.
- **Platforms.** Web, iPhone/iPad, Mac.
- **Workflow.** 1) Home. 2) Read the Tonight card. 3) Open it, or "Not tonight".
- **Location.** Top of Home.
- **Code.** `web/components/TonightStrip.tsx`, `apple/Aaru/Home/TonightCard.swift`, `server/internal/tonight/`.
- **Status.** `experimental`. "Not seen on a device; reject never checked across a night" (`BACKLOG.md` AG-005).
- **Priority.** Medium.
- **Headline.** "Tonight, from what you already have."
- **Recording.** Tier A. Rehearse that a seeded account produces a card.
- **Video concept (10 s).** The Tonight card, "Not tonight", a second card. No voiceover.

## 7. Discover and On air

- **What it does.** Discover has Today (trending, on the air, new shows, in theaters, this season's anime), On air (the week's new episodes grouped by channel, with where to stream in your country) and Seasons. Books, Manga and Music pages have their own rows.
- **Problem.** Knowing what is airing this week across channels and services.
- **Benefit.** The week at a glance, and one tap to add.
- **Platforms.** Web, iPhone/iPad, Mac.
- **Workflow.** 1) Discover. 2) Today / On air / Seasons. 3) "Add" on a card.
- **Location.** Web: sidebar > Discover. Apple: Discover tab or sidebar.
- **Code.** `web/routes/_shell.app_.discover.tsx`, `web/components/OnAirGuide.tsx`, `web/components/DiscoverRows.tsx`, `apple/Aaru/Discover/`, `server/internal/catalog/`.
- **Status.** `verified` for Today; `partial` for On air: air times from TVmaze and providers from JustWatch were "checked with stubs only" (`BACKLOG.md` DISC-003). It is the same for everyone and is not a recommendation.
- **Priority.** Medium.
- **Headline.** "What's on this week, by where it airs."
- **Recording.** Tier A. Credit TMDB, TVmaze and JustWatch on screen (`rules/brand.md`).
- **Video concept (12 s).** On air scrolls channel by channel; one show is added; it appears in Coming up.

## 8. Calendar: Week, Month, Missed

- **What it does.** A calendar of your own shows: Week (a grid, or a day pager on iPhone), Month (posters and an agenda) and Missed. "Group by" Day or Channel, and filters.
- **Problem.** Pogdesign CAT-style calendars show everything except your own shows, and episodes slip by.
- **Benefit.** Every episode from your shows, this week, and what you missed.
- **Platforms.** Web, iPhone/iPad, Mac.
- **Workflow.** 1) Calendar. 2) Week. 3) Open an episode sheet, tick it. 4) Month. 5) Missed.
- **Location.** Web: sidebar > Calendar. Apple: Calendar tab or sidebar.
- **Code.** `web/routes/_shell.app_.calendar.tsx`, `web/components/WeekGrid.tsx`, `web/components/MonthCalendar.tsx`, `apple/Aaru/Calendar/`, `server/internal/schedule/`.
- **Status.** `verified` on web. On Apple, "not seen on a device" (`BACKLOG.md` CAL-003, CAL-005).
- **Priority.** High. It is the reason CAT and TV Time users stayed with their old apps.
- **Headline.** "Every episode from your shows, this week."
- **Recording.** Tier A. Seed 10–20 shows currently airing so the week is full. Week, then Month, then Missed.
- **Video concept (15 s).** A paper week planner, crossed out. Cut to the Week grid filling with your shows. Switch to "Group by Channel".

## 9. Airing alerts

- **What it does.** A push when a new episode of a show you follow airs, on iPhone and in browsers. Switches for "New episodes", "Mentions in groups" and "Group invites".
- **Problem.** You find out a show is back weeks late.
- **Benefit.** A quiet heads-up for your own shows only.
- **Platforms.** iPhone/iPad (APNs), Web (web push, "Turn on alerts in this browser"). Mac: "Alerts go to your iPhone and your browsers."
- **Workflow.** 1) Settings > Notifications. 2) Turn on "New episodes". 3) Wait for an airing.
- **Location.** Settings > Notifications.
- **Code.** `server/internal/push/`, `web/components/NotificationsSection.tsx`, `apple/Aaru/Push/PushRegistrar.swift`, `apple/Aaru/Settings/Pages/NotificationsPage.swift`.
- **Status.** `partial`. Keys are present in production; no evidence of a recorded real push. iPhone requires TestFlight.
- **Priority.** Low on screen.
- **Headline.** "Back this week."
- **Recording.** Tier C for a real push. Don't fake a notification banner.
- **Video concept.** None recommended until a real push is captured.

# C. Bring your history

## 10. Trakt import

- **What it does.** Connect Trakt with OAuth and import watched history, ratings and progress.
- **Problem.** Years of Trakt history.
- **Benefit.** Bring it in one run.
- **Platforms.** Web, iPhone/iPad, Mac.
- **Workflow.** 1) Settings > Import > Trakt > "Connect Trakt". 2) Approve on Trakt. 3) "Import from Trakt". 4) Review and approve.
- **Location.** Settings > Import.
- **Code.** `server/internal/trakt/`, `web/components/TraktImport.tsx`.
- **Status.** `experimental`. "No real Trakt account connected yet"; "Stub Trakt only" (`BACKLOG.md` IMP-002, IMP-003). Show the notice "Aaru uses Trakt but is not endorsed or certified by Trakt."
- **Priority.** High once tested; Trakt users are the top segment in `MARKETING.md`.
- **Headline.** "Your Trakt history, reviewed before it lands."
- **Recording.** Needs a real Trakt account with synthetic history, owned for the demo. Rehearse first.
- **Video concept.** None until a real run succeeds.

## 11. File imports with review

- **What it does.** Upload an export from IMDb, Letterboxd, Goodreads, Pogdesign CAT (list, ICS file or iCal link), Netflix, TV Time, MyAnimeList (XML) or any other CSV, or name an AniList user. Aaru matches every row first and shows the plan: "Not matched", "Will be added", "Will be filled in". "Find it" fixes a miss. "Approve and import" lands it as one action; "Undo this import" takes it back.
- **Problem.** Imports that silently drop or mis-merge rows. "An import that silently drops 8% of a 2,000-film history is the single fastest way to lose a Letterboxd user" (`MARKETING.md` §1).
- **Benefit.** You see every match before anything is saved.
- **Platforms.** Web, iPhone/iPad, Mac.
- **Workflow.** 1) Settings > Import > "Bring your history". 2) "Import from Letterboxd". 3) Pick the file. 4) Read the review. 5) "Find it" on one row. 6) "Approve and import". 7) Undo toast, or "Undo this import" later.
- **Location.** Settings > Import; review at `/app/imports/$id`.
- **Code.** `server/internal/imports/`, `web/lib/imports/model.ts`, `web/components/ImportSources.tsx`, `web/routes/_shell.app_.imports.$id.tsx`, `web/components/ResolveRowDialog.tsx`, `apple/Aaru/Review/`.
- **Status.** `partial`. IMDb, Letterboxd, MyAnimeList and AniList parsers are done and tested (`BACKLOG.md` IMP-006…008, IMP-013…014). Goodreads, Netflix, TV Time and CAT have **never run on a real export** (IMP-009, -010, -012, -018, -020): say "imports from" only. Imports never move a status backward or past one you chose yourself. Files up to 5 MB.
- **Priority.** High. Lead feature 1.
- **Headline.** "Bring your history. Check it first."
- **Recording.** Tier A. A **synthetic** Letterboxd or IMDb CSV of 60–100 public titles, with two deliberate misspellings so "Not matched" and "Find it" appear. This import is also the seed for every other shot (`rules/video-playbook.md`).
- **Video concept (25 s).** A file is dragged in. The review fills: "Will be added" ticks down the page, two rows say "Not matched". "Find it", pick, "Approve and import". Cut to Library, full. End on the Undo toast: "Changed your mind? One step."

## 12. Stremio history by code

- **What it does.** Show a code and QR in Aaru, enter it in Stremio, and Aaru reads the Stremio library once, then logs out. The key is never stored.
- **Problem.** Stremio users have no export file.
- **Benefit.** History in without a password.
- **Platforms.** Web, iPhone/iPad, Mac.
- **Workflow.** 1) Settings > Import > "Import from Stremio" > "Import my Stremio history". 2) Enter the code in Stremio. 3) Review the plan.
- **Location.** Settings > Import.
- **Code.** `server/internal/imports/stremio.go`, `server/internal/stremioapi/`, `web/components/StremioHistoryImport.tsx`.
- **Status.** `experimental`. "No real account library" (`BACKLOG.md` IMP-016).
- **Priority.** Low.
- **Headline.** "From Stremio with a code."
- **Recording.** Needs a Stremio account owned for the demo.
- **Video concept.** None until tested.

## 13. Anime: MyAnimeList and AniList

- **What it does.** Anime is first-class, from AniList, mapped season by season to TMDB shows. Import a MAL XML export or an AniList list by username. Connect MyAnimeList to keep it in step: progress goes out, and Aaru reads the MAL list back on open and every 6 hours.
- **Problem.** Anime seasons map badly between sites, and general trackers treat anime as an afterthought.
- **Benefit.** Your anime list, with seasons that line up, kept in step with MAL.
- **Platforms.** Web, iPhone/iPad, Mac.
- **Workflow.** 1) Settings > Import > MyAnimeList or AniList. 2) Review. 3) Settings > Connections > MyAnimeList > "Connect MyAnimeList".
- **Location.** Settings > Import, Settings > Connections.
- **Code.** `server/internal/mal/`, `server/internal/imports/`, `web/components/MALSection.tsx`.
- **Status.** `verified` for import (tested; a 2,001-entry MAL export ran locally, `BACKLOG.md` IMP-017). `experimental` for MAL sync (SCR-005, SCR-010 "Built, unverified"). Manga is not pushed to MAL.
- **Priority.** Medium-high for anime audiences.
- **Headline.** "Anime, season by season."
- **Recording.** Tier A for import with a synthetic MAL XML. MAL sync needs a MAL account owned for the demo.
- **Video concept (15 s).** A MAL XML drops in; a long-running show lands as one show with its seasons ticked correctly.

## 14. Music history imports

- **What it does.** Bring listening history from Last.fm or ListenBrainz (by username), a Spotify extended streaming history, or Google Takeout's YouTube history. It fills the listening log for Insights and the Recap, never the library.
- **Problem.** Years of listening sit in another service.
- **Benefit.** Your music year, next to your films and books.
- **Platforms.** Web, iPhone/iPad, Mac.
- **Workflow.** Settings > Import > "Music history".
- **Location.** Settings > Import.
- **Code.** `server/internal/music/`, `server/internal/imports/`.
- **Status.** `experimental`. "Parsers checked against stubs" (`BACKLOG.md` MUS-004).
- **Priority.** Low.
- **Headline.** Do not headline this yet.
- **Recording.** None until tested.
- **Video concept.** None recommended.

## 15. Match all (beta)

- **What it does.** In an import's review, "Match all" proposes best guesses for every unmatched row, which you tick or untick before approving.
- **Problem.** Fixing 50 misses one at a time.
- **Benefit.** One pass over the leftovers, still reviewed.
- **Platforms.** Beta web, iPhone/iPad. **Not on aaruapp.com.**
- **Workflow.** 1) Open an import with misses. 2) "Match all". 3) "Check the guesses below." 4) Untick. 5) Approve.
- **Location.** Import review.
- **Code.** `server/internal/imports/matchall.go`, `server/internal/catalog/guess.go`, `aaru-client/src/routes/_shell.app_.imports.$id.tsx` (main), `apple/Aaru/Capture/MatchAllButton.swift`.
- **Status.** `experimental`. Tried locally with a stub model only (`BACKLOG.md` IMP-021).
- **Priority.** Medium, after the production web is redeployed.
- **Headline.** "Fifty misses, one pass, your call."
- **Recording.** Tier B (it uses the model). Beta web only.
- **Video concept.** Add after lead feature 1 once production web has it.

## 16. Capture: paste anything, get a plan

- **What it does.** Paste a chat (up to 100,000 characters), up to 5 screenshots, or a TMDB, AniList or Open Library link into the box on Home. Aaru reads it, matches the titles, and opens "Your capture" with **Approve** and **Not this**. Nothing is added until you approve.
- **Problem.** Recommendations arrive as mess: a group chat, a screenshot, a photo of a list. Nobody retypes them.
- **Benefit.** The list in the chat becomes your list in one approval.
- **Platforms.** Web, iPhone/iPad, Mac.
- **Workflow.** 1) Home: "Paste titles, a link or a screenshot". 2) "Send". 3) "Waiting for you": "Your capture … Review". 4) "Add 7 · 2 need a pick". 5) "Find it". 6) Approve. 7) Undo toast.
- **Location.** Home composer.
- **Code.** `server/internal/capture/`, `server/internal/imports/capture.go`, `web/components/CaptureComposer.tsx`, `web/components/CaptureCard.tsx`, `apple/Aaru/Capture/`.
- **Status.** `experimental`. On in production (it needs the model; links work without it). Never shown working in a recorded run (`BACKLOG.md` AG-006 "Built, unverified"). 30 a day per account. **The production web still shows a monthly-quota line and a Plus upsell under the box**; film it on beta web or after a redeploy. The input is sent to Anthropic and deleted once read, within an hour (`docs/privacy.md`). Links are parsed, never fetched.
- **Priority.** High. Lead feature 5, after a rehearsal.
- **Headline.** "Paste the chat. Approve the list."
- **Recording.** Live AI, Tier B. A **written-for-the-shoot** group chat with 9 public titles and one misspelt one. Never a real chat.
- **Video concept (20 s).** A phone screenshot of a friends' chat full of "you HAVE to watch…". Paste. "Add 7 · 2 need a pick." Find it, Approve. The titles land on Home.

## 17. Book capture and "ask for books" (beta)

- **What it does.** On the Books page, or from the owl, paste a book list or ask for one ("X-Men books in reading order"). Aaru answers with titles to review, and an order is saved as a list on approve.
- **Problem.** Reading orders and book lists live in chats and forum posts.
- **Benefit.** A reading order, reviewed and saved in order.
- **Platforms.** Beta web, iPhone/iPad. Not on aaruapp.com.
- **Workflow.** 1) Books > "Import books". 2) Paste, or type a request. 3) Review: "Saved in order as the list “…”". 4) Approve.
- **Location.** Books page; assistant card ("Review the list").
- **Code.** `server/internal/capture/`, `aaru-client/src/components/kind/BooksTop.tsx` (main), `aaru-client/src/components/CaptureComposer.tsx` (main).
- **Status.** `experimental`. "Stub model only" (`BACKLOG.md` BOOK-001, BOOK-003). A request for titles is a suggestion, always reviewed.
- **Priority.** Medium.
- **Headline.** "Ask for a reading order. Keep it as a list."
- **Recording.** Tier B, beta web.
- **Video concept.** Later, once tested.

# D. Kind pages

## 18. Books

- **What it does.** A Books page with your reading shelf and Open Library's weekly trending. On beta and TestFlight it adds "Read this year", "Import books", On hold and Read shelves and subject rows (Classics, Science fiction, Science, Business).
- **Problem.** Book trackers live apart from everything else.
- **Benefit.** Books next to the show they became.
- **Platforms.** Web (basic), beta web and iPhone/iPad (full), Mac.
- **Workflow.** Sidebar > More > Books.
- **Location.** Web: sidebar > More > Books. iPhone: More > Books.
- **Code.** `web/routes/_shell.app_.books.tsx`, `aaru-client/src/components/kind/BooksTop.tsx` (main), `apple/Aaru/Kinds/`.
- **Status.** `verified` (basic page on web). `experimental` for the beta additions.
- **Priority.** Medium for Goodreads leavers.
- **Headline.** "Your reading pile, next to everything else."
- **Recording.** Tier A on beta web.
- **Video concept (10 s).** A book and its adaptation, side by side, both "In progress".

## 19. Manga

- **What it does.** Manga, manhwa, manhua, one-shots and light novels from AniList, with chapter and volume progress, imported from MAL or AniList manga lists.
- **Problem.** Manga is usually lumped in with books or anime.
- **Benefit.** Chapters and volumes, tracked as manga.
- **Platforms.** Web, iPhone/iPad, Mac.
- **Workflow.** Sidebar > More > Manga; "Save progress" by chapter.
- **Location.** Sidebar > More > Manga.
- **Code.** `web/routes/_shell.app_.manga.tsx`, `server/internal/catalog/`, `apple/Aaru/Kinds/`.
- **Status.** `verified` for the page and progress; manga imports have had "no real MAL manga export or AniList manga list run yet" (`BACKLOG.md` MNG-002). No fallback while AniList is down.
- **Priority.** Low-medium.
- **Headline.** "Chapter 112, remembered."
- **Recording.** Tier A.
- **Video concept.** Part of the six-kinds montage.

## 20. Music: albums, concerts, listens

- **What it does.** Track albums and EPs (status, rating, notes). See new albums and coming soon. Concerts: "Your artists on tour" and "Near you" / "Anywhere" from Ticketmaster, tickets linked out. Listens from scrobblers and history imports.
- **Problem.** Music trackers rarely sit with films and books.
- **Benefit.** The albums you keep coming back to, and when your artists play nearby.
- **Platforms.** Web, iPhone/iPad, Mac. Apple segments: Albums / Concerts / Listens.
- **Workflow.** 1) More > Music. 2) Add an album. 3) Concerts > "Use my location".
- **Location.** Sidebar > More > Music.
- **Code.** `web/routes/_shell.app_.music.tsx`, `web/components/ConcertList.tsx`, `server/internal/music/`, `server/internal/concerts/`.
- **Status.** `partial`. Albums `verified`. Concerts work only where Ticketmaster lists events, and "Ticketmaster lists nothing in Portugal" (MUS-003). Location is rounded and never stored. Tracklists can say "Tracklist not available yet".
- **Priority.** Low-medium.
- **Headline.** "Your albums, and who's on tour."
- **Recording.** Tier A for albums. Concerts need a Ticketmaster key (free) and a city with listings.
- **Video concept (10 s).** An album marked "Listening", then the artist's next date nearby.

## 21. Sports

- **What it does.** Follow leagues, teams and players, and see live scores, fixtures, results and where to watch. Separate from the library: never a title, never shown to friends.
- **Problem.** The matches you follow live in a separate app from everything else you watch.
- **Benefit.** "Live scores, fixtures and results for what you follow."
- **Platforms.** Web, iPhone/iPad, Mac, only while the server has a provider.
- **Workflow.** 1) More > Sports. 2) "Find leagues and teams". 3) "Follow". 4) Schedule.
- **Location.** Sidebar > More > Sports (hidden when off).
- **Code.** `web/routes/_shell.app_.sports.tsx`, `web/components/sports/`, `server/internal/sports/`, `apple/Aaru/Sports/`.
- **Status.** `verified`, with TheSportsDB's premium key present in production. Not part of the six kinds.
- **Priority.** Low. Off-message for the core claim.
- **Headline.** Do not headline this.
- **Recording.** Tier B locally (paid TheSportsDB key).
- **Video concept.** None recommended for the first campaign.

# E. Aaru, the assistant, and agents

## 22. The assistant card (owl)

- **What it does.** The owl's head in the top bar opens a floating card over the current screen. Type or talk to "Aaru" about your library, what's airing, or anything you track. Replies stream ("Aaru is thinking…") and can carry title cards, a one-item change with Undo, or a plan with Approve. Spoken questions are transcribed on Aaru's own server; replies are read aloud with an on-device voice after a spoken question, unless muted.
- **Problem.** Changing many things at once takes many taps.
- **Benefit.** Ask in a sentence; approve the result.
- **Platforms.** **Beta web, iPhone/iPad (TestFlight).** Mac code exists. **Not on aaruapp.com.**
- **Workflow.** 1) Tap the owl (long-press to talk on iPhone). 2) "What's left of Severance?" 3) Read the reply. 4) "Mark the rest of season one watched." 5) Approve the plan, or Undo the single change.
- **Location.** Top bar of every main screen and title pages.
- **Code.** `server/internal/agent/chat.go`, `server/internal/transcription/`, `server/internal/httpapi/chat.go`, `apple/Aaru/Assistant/`, `aaru-client/src/components/assistant/` (main).
- **Status.** `experimental`. Live on the API (`claude-haiku-5-5`, low effort; Whisper for voice). Free; 30 questions a day shared with @aaru; voice 40 an hour. Chats are kept until "Delete my chats with Aaru". Not yet in the production web; the production privacy page doesn't describe it yet.
- **Priority.** High once production web has it, but **never the headline** (strategy rule 4). Show it doing bookkeeping, not chatting.
- **Headline.** "Ask once. Approve once."
- **Recording.** Live AI, Tier B. iPhone simulator or beta web. Real voice needs a real microphone (Tier C on a device).
- **Video concept (20 s).** Long-press the owl. "I finished season one of Andor last night." The card answers with the season and a plan: "Mark 12 episodes watched." Approve. The screen behind updates. Three sentences and a result, never a chat log (`MARKETING.md` §3.2).

## 23. Connect Claude and other agents (MCP)

- **What it does.** Add Aaru to Claude as a custom connector (Settings > Connectors > Add custom connector, URL `https://api.aaruapp.com/v1/mcp`), or connect Claude Code, Codex, Hermes, Gemini CLI or any MCP client with a token. Five tools: `search_titles`, `read_library`, `list_airs`, `apply_library_patch`, `plan_import`. One small change applies like a tap and can be undone; anything larger, and any removal, becomes a plan. Your phone or browser asks: "{agent} wants to change your library", Approve or Not this.
- **Problem.** Your assistant can't see your library, and one that edits it unchecked is frightening.
- **Benefit.** Your agent proposes; you approve inside Aaru.
- **Platforms.** API. Set up on Web (Settings > Connections > Agents) or iPhone (Settings > Connections > Agents > "Connect an agent"). Approval on web, iPhone, Mac.
- **Workflow.** 1) Settings > Connections > Agents > Claude. 2) Optionally "Allow changes". 3) Follow the steps. 4) In Claude: "Catch me up on Andor in Aaru." 5) Aaru: "Waiting for you", Approve.
- **Location.** Settings > Connections. Consent: `/oauth/consent`.
- **Code.** `server/internal/mcp/`, `server/internal/oauth/`, `server/internal/plans/`, `server/internal/httpapi/agent_setup.go`, `web/components/ConnectionsSection.tsx`, `web/components/PlanCard.tsx`, `web/routes/oauth.consent.tsx`.
- **Status.** `experimental`. Live on the API, "Claude connector unverified against claude.ai" (`BACKLOG.md` OUT-004). Read-only by default. Requests with a browser `Origin` header are refused. 120 requests a minute per token. Plans expire after 24 hours.
- **Priority.** High for developer and agent audiences, low for general consumers. `BUSINESS.md` calls it "the only real wedge"; `DESIGN.md` §12 calls it "the demo nobody else can film".
- **Headline.** "The buzz is a question, never a receipt."
- **Recording.** Tier B: the outside agent is a real model, and the connector must be verified first. Laptop plus phone or second window.
- **Video concept (25 s).** Laptop: "Mark the rest of Andor season one watched in Aaru." The phone lights up: "Claude wants to change your library. 12 episodes · nothing overwritten." A thumb taps Approve. History shows it, with Claude's name and an Undo.

## 24. @aaru in groups

- **What it does.** In a group channel, mention `@aaru` and it answers in the channel, reading the last 30 messages and, when relevant, your own library. It speaks only when tagged.
- **Problem.** A group picking something to watch together.
- **Benefit.** A quick answer for the group without leaving the chat.
- **Platforms.** Web, iPhone/iPad, Mac.
- **Workflow.** 1) Groups > a channel. 2) "@aaru what should we start on Friday?" 3) The reply carries the "Assistant" badge.
- **Location.** Group channels.
- **Code.** `server/internal/groups/agent.go`, `server/internal/agent/reply.go`, `web/components/groups/`.
- **Status.** `experimental`. On in production; "two-browser / device check not recorded" (`BACKLOG.md` GRP-010, GRP-011). 10 replies an hour per group. Group messages are server-visible.
- **Priority.** Low.
- **Headline.** Do not headline this.
- **Recording.** Tier B, two demo accounts.
- **Video concept.** None for the first campaign.

# F. Automatic tracking

## 25. Browser extension

- **What it does.** On Netflix, Disney+ and Prime Video it reads the title and episode from the player and marks it watched in Aaru at 80% or more. On YouTube it shows the video as Now playing, and a "- Topic" channel's song past half or 4 minutes counts as a listen. The popup shows "Now · Netflix", the match ("✓ Matched: Severance (2022)") and a short "Recent" list.
- **Problem.** Remembering to tick what you just finished.
- **Benefit.** Finish an episode, and it's ticked.
- **Platforms.** Extension (Chrome, Firefox), connected from Web. Token is scrobble-only and cannot read the library.
- **Workflow.** 1) Popup "Connect". 2) A tab opens "Connect Chrome on macOS to Aaru?" 3) "Approve". 4) Watch. 5) The badge shows ✓.
- **Location.** Toolbar; Settings > Connections > Agents > "Browser extension".
- **Code.** `ext/src/sites/`, `ext/src/entrypoints/popup/main.ts`, `ext/src/lib/session.ts`, `web/routes/connect.extension.tsx`, `server/internal/scrobble/`.
- **Status.** `experimental`. Not in any store; "site selectors not yet checked on the live players" (`BACKLOG.md` SCR-007, SCR-009, SCR-011). The built `.output/` is stale (2026-10-21) and must be rebuilt.
- **Priority.** Medium, later. Don't market as installable.
- **Headline.** Do not headline until it is in a store.
- **Recording.** YouTube: Tier A. Netflix, Disney+, Prime Video: a paid subscription owned for the demo, and the streaming service's own terms for showing their player (**needs confirmation**).
- **Video concept (15 s), for after store listing.** An episode's end credits roll in a browser; the toolbar badge turns ✓; Aaru's Home shows the next episode.

## 26. Stremio addon

- **What it does.** Install Aaru as a Stremio addon: catalogs "Aaru · Continue watching", "Aaru · Next 7 days", "Aaru · Plan to watch", and playback in Stremio ticks episodes and films in Aaru. No streams.
- **Problem.** Stremio users track by hand.
- **Benefit.** Your Aaru rows inside Stremio, and ticks without tapping.
- **Platforms.** API; set up on Web or Apple (Settings > Connections > Stremio > "Connect Stremio").
- **Workflow.** 1) "Connect Stremio". 2) "Open in Stremio" or "Install on Stremio Web". 3) Watch.
- **Location.** Settings > Connections.
- **Code.** `server/internal/stremio/`, `web/components/StremioSection.tsx`.
- **Status.** `experimental`. "Verified in Stremio Web on local server; playback events not tried" (`BACKLOG.md` SCR-003).
- **Priority.** Low.
- **Headline.** Do not headline this.
- **Recording.** Stremio Web catalogs only, Tier A.
- **Video concept.** None recommended.

## 27. Music scrobblers

- **What it does.** Point Web Scrobbler, Pano Scrobbler, Navidrome or Jellyfin's ListenBrainz plugin at Aaru with a music token; plays become listens and "playing now" feeds Now playing.
- **Problem.** Listening history goes to someone else's service.
- **Benefit.** Your listens in your own library.
- **Platforms.** API; set up on Web or Apple (Settings > Connections > Music).
- **Workflow.** Settings > Connections > Music > "Connect Web Scrobbler"; follow the steps.
- **Location.** Settings > Connections.
- **Code.** `server/internal/music/`, `server/internal/httpapi/scrobble_routes.go`, `web/components/MusicSection.tsx`.
- **Status.** `experimental`. "Not tried with a real scrobbler" (`BACKLOG.md` MUS-005, MUS-007).
- **Priority.** Low.
- **Headline.** Do not headline this.
- **Recording.** None until tested.
- **Video concept.** None recommended.

## 28. Now playing and Live Activities

- **What it does.** What a connected player reports (extension, Stremio, scrobblers) shows as a Now playing card on Home, and on iPhone as a "Now playing" Live Activity on the Lock Screen and Dynamic Island, with "Mark watched". A "Watching now…" button starts a local "Now watching" Live Activity by hand.
- **Problem.** "Did I finish that?"
- **Benefit.** The episode on your Lock Screen, one tap to mark it.
- **Platforms.** Web and Apple (card), iPhone only (Live Activities).
- **Workflow.** 1) Continue watching > "Watching now…". 2) Lock the phone. 3) "Mark watched".
- **Location.** Home; title page episode menu.
- **Code.** `web/components/NowPlayingCard.tsx`, `apple/AaruWidgets/NowPlayingLiveActivity.swift`, `apple/Shared/NowWatching.swift`, `server/internal/scrobble/`.
- **Status.** `experimental`. Live Activities "not seen on a device" (`BACKLOG.md` WID-005, SCR-008, SCR-009). iPhone is TestFlight-only.
- **Priority.** Medium as an iPhone beat, later.
- **Headline.** "On your Lock Screen, one tap from done."
- **Recording.** Tier C (physical iPhone, Release-like build) for the Dynamic Island. The local "Watching now…" Live Activity can be tried in the simulator first.
- **Video concept (12 s).** Lock Screen at night: "Severance · S2 E4 · 12 min left". Tap "Mark watched". The activity ends.

# G. Looking back

## 29. Insights

- **What it does.** Time per day, episodes, by kind, "Most time with", ratings and longest run, over 7 days, 30 days, a month, a year or all time.
- **Problem.** Other trackers paywall your own statistics (`MARKETING.md` §3.4, unverified).
- **Benefit.** Your numbers, free.
- **Platforms.** Web, iPhone/iPad, Mac.
- **Workflow.** Insights > pick a period > "Play as a story".
- **Location.** Web: sidebar > Insights. iPhone: Library > More > "Insights".
- **Code.** `web/routes/_shell.app_.insights.tsx`, `web/components/StatsPanel.tsx`, `server/internal/stats/`, `apple/Aaru/Insights/`.
- **Status.** `verified`. Imported history counts on its own day; whole seasons marked watched are not activity.
- **Priority.** Medium.
- **Headline.** "Your numbers, never behind a paywall."
- **Recording.** Tier A, but stats come from **live** ticks over days. Seed by ticking across several days, or film after a week of real demo use.
- **Video concept (10 s).** Period chips flick from 7 days to Year; the "By kind" bars rebuild.

## 30. Recap

- **What it does.** A month or year played as a story: "Your recap", "Time with stories", "Your biggest day", "On repeat", "Your genres", "Bookends", and a persona such as "The Binger" or "The Bookworm". "Share as an image".
- **Problem.** Year-in-review is usually a paid extra or another app's.
- **Benefit.** Your year, from your own library, to share if you want.
- **Platforms.** Web, iPhone/iPad, Mac.
- **Workflow.** Home "Your recap is ready" > "Play", or Insights > "Play as a story".
- **Location.** `/app/recap`.
- **Code.** `web/components/recap/RecapCards.tsx`, `web/lib/recap/deck.ts`, `apple/Aaru/Recap/`, `server/internal/stats/`.
- **Status.** `verified` on web. "Apple story never run on device"; "Persona copy awaits the owner" (`BACKLOG.md` GAM-006a, GAM-006e).
- **Priority.** Medium-high in December, as a share loop (`MARKETING.md` §7).
- **Headline.** "Your year in stories."
- **Recording.** Tier A, with a month of seeded live activity.
- **Video concept (12 s).** Story cards tap through to the persona card; "Share as an image".

## 31. Achievements: points, levels, streaks, badges

- **What it does.** Points for live activity, levels, a streak of days with progress, 62 badges (9 hidden until earned), and a weekly friends-only board you opt into. A streak widget on iPhone.
- **Problem.** Motivation without a public leaderboard.
- **Benefit.** Quiet progress, friends only.
- **Platforms.** Web, iPhone/iPad, Mac.
- **Workflow.** Insights > "Achievements →".
- **Location.** `/app/achievements`.
- **Code.** `server/internal/gamification/catalog.go`, `server/internal/gamification/points.go`, `web/components/achievements/`, `apple/Aaru/Achievements/`.
- **Status.** `experimental`. "Owner judges design; TestFlight" (`BACKLOG.md` GAM-001…005). Imports count for milestone badges, not points. No global board, ever.
- **Priority.** Low. Off the calm brand if overplayed.
- **Headline.** Do not headline this.
- **Recording.** Tier A, once the owner has judged the design.
- **Video concept.** A single earned-badge reveal with the celebrating owl, if approved.

## 32. Profile and favorites

- **What it does.** A profile with an avatar, time watched, genres, most watched and "Where you watch", plus an ordered top 10 per kind. Seen by friends only.
- **Problem.** Showing taste without a public page.
- **Benefit.** A profile for the people you chose.
- **Platforms.** Web, iPhone/iPad, Mac.
- **Workflow.** Avatar on Home > "Edit profile".
- **Location.** `/app/profile`.
- **Code.** `web/components/ProfilePanel.tsx`, `web/components/FavoritesRow.tsx`, `server/internal/social/favorites.go`.
- **Status.** `experimental`. "Not run on a device or in a browser" (`BACKLOG.md` FAV-001).
- **Priority.** Low.
- **Headline.** Do not headline this.
- **Recording.** Tier A.
- **Video concept.** None recommended.

# H. Friends (opt-in)

## 33. Friends, invites and Lately

- **What it does.** Mutual friends only. Add by handle or a one-use invite link (14 days). "Lately" shows friends' recent ticks and finishes, with six emoji reactions. Recommend a title to friends. Block and report.
- **Problem.** Social trackers make you public to be social.
- **Benefit.** Your circle, and nobody else.
- **Platforms.** Web, iPhone/iPad, Mac.
- **Workflow.** 1) Friends > "Invite a friend" > "Make an invite link". 2) The friend opens it. 3) Lately. 4) "Recommend".
- **Location.** Web: sidebar > Friends. iPhone: inside Groups.
- **Code.** `server/internal/social/`, `web/routes/_shell.app_.friends.index.tsx`, `web/components/InviteFriends.tsx`, `web/components/Recommendations.tsx`.
- **Status.** `experimental`. "Built, unverified" (`BACKLOG.md` SOC-002, SOC-006, SOC-007). There is no one-way follow.
- **Priority.** Low for the first videos; private-first is the message, not social.
- **Headline.** "Friends, never followers."
- **Recording.** Tier A, two demo accounts in two windows.
- **Video concept.** None for the first campaign.

## 34. Board

- **What it does.** A friends-only stream of posts: free text or a title with a rating and a spoiler stamp, with comments and upvotes. "Recent" / "Top this week".
- **Problem.** Talking about a show without a public review site.
- **Benefit.** A wall only your friends can read.
- **Platforms.** Web; iPhone/iPad on `main` (inferred in the current TestFlight build).
- **Workflow.** Friends > Board > "Write something…" > "Post".
- **Location.** Friends > Board.
- **Code.** `server/internal/boards/`, `web/components/board/`, `apple/Aaru/Board/`.
- **Status.** `experimental`. "Not looked at in a browser" (`BACKLOG.md` BOARD-002).
- **Priority.** Low.
- **Headline.** Do not headline this.
- **Recording.** None for the first campaign.
- **Video concept.** None recommended.

## 35. Groups and channels

- **What it does.** Friends-only groups (up to 50) with `#general` and channels of four kinds: Text, Title (one title with a spoiler guard), Watch party, and List (one the group edits). Every channel says "not end-to-end".
- **Problem.** Group chats lose track of what the group is watching.
- **Benefit.** A place per show, a shared list, and no spoilers.
- **Platforms.** Web, iPhone/iPad, Mac.
- **Workflow.** Groups > "New group" > invite friends > add a channel.
- **Location.** Web: sidebar > More > Groups. iPhone: More > Groups.
- **Code.** `server/internal/groups/`, `server/internal/realtime/`, `web/routes/_shell.app_.groups.*`, `web/components/groups/`, `apple/Aaru/Groups/`.
- **Status.** `experimental`. "Two-browser check not recorded" (`BACKLOG.md` GRP-001…009). No invite links for groups, no images, no replies.
- **Priority.** Low.
- **Headline.** Do not headline this.
- **Recording.** Tier A, two demo accounts.
- **Video concept.** None for the first campaign.

## 36. Watch party

- **What it does.** In a Watch party channel: "Start a watch party", ready check, "Start countdown", reactions, and "Mark watched for me". Aaru does not control anyone's player.
- **Problem.** Watching together apart.
- **Benefit.** Start at the same second.
- **Platforms.** Web, iPhone/iPad, Mac.
- **Workflow.** Channel > "Start a watch party" > "Open the lobby" > "Start countdown".
- **Location.** A group's Watch party channel.
- **Code.** `web/components/groups/WatchPanel.tsx`, `server/internal/groups/`.
- **Status.** `experimental` (`BACKLOG.md` GRP-009).
- **Priority.** Low.
- **Headline.** Do not headline this. Never imply playback sync or SharePlay.
- **Recording.** None for the first campaign.
- **Video concept.** None recommended.

## 37. Share links

- **What it does.** A public link (`aaruapp.com/s/{code}`) to one title, match or concert. Anyone can open it; only your friends see who sent it and the note.
- **Problem.** Sharing a title without sharing your library.
- **Benefit.** Share one thing, nothing more.
- **Platforms.** Web, iPhone/iPad, Mac.
- **Workflow.** Title page > "Share".
- **Location.** Title page, catalog preview.
- **Code.** `server/internal/shares/`, `web/components/ShareDialog.tsx`, `web/routes/s.$code.tsx`.
- **Status.** `experimental` (`BACKLOG.md` SHR-002).
- **Priority.** Low.
- **Headline.** Do not headline this.
- **Recording.** Tier A.
- **Video concept.** None recommended.

# I. Apple only

## 38. Widgets

- **What it does.** "Up Next" (check off an episode without opening Aaru), "Next Episode" (a countdown), "This Week", "Listening" and "Streak". Lock Screen sizes on iPhone.
- **Problem.** Opening the app to see what's next.
- **Benefit.** What's next on your Home Screen.
- **Platforms.** iPhone/iPad (TestFlight), Mac (desktop sizes, not distributed).
- **Workflow.** Add widget > Aaru > Up Next; tap the check.
- **Location.** Home Screen, Lock Screen.
- **Code.** `apple/AaruWidgets/`, `apple/Shared/MarkEpisodeWatchedIntent.swift`.
- **Status.** `experimental`. "Not seen on a device" (`BACKLOG.md` WID-001…007).
- **Priority.** Medium as an iPhone beat once public.
- **Headline.** "Check one off without opening Aaru."
- **Recording.** Simulator first (Tier A), then a device (Tier C).
- **Video concept (8 s).** A Home Screen at night; a thumb taps the check on "Up Next"; the next episode slides in.

## 39. Mac app

- **What it does.** The same app in a Mac window, with a sidebar, menu bar commands and desktop widgets.
- **Problem.** A real Mac client is rare in this category (`MARKETING.md` §7).
- **Benefit.** Your library at the desk.
- **Platforms.** Mac.
- **Workflow.** ⌘1…⌘9 to switch sections, ⌘K to ask, ⌘F to search.
- **Location.** Mac app.
- **Code.** `apple/Aaru/Navigation/AaruCommands.swift`, `apple/Aaru/AaruApp.swift`.
- **Status.** `planned` for marketing: not distributed (`apple/fastlane/Fastfile`).
- **Priority.** High for Apple indie press, later.
- **Headline.** Do not use until there is a way to get it.
- **Recording.** Debug build on a Mac is possible, but holds no call to action.
- **Video concept.** None until distributed.

# J. Trust and control

## 40. Private by default

- **What it does.** A new account has no visible surface. No public profile, no feed, no ads. Friends are mutual; groups are friends-only; your badges and level are shown to friends behind a switch; the weekly board is opt-in.
- **Problem.** Most trackers are public by default.
- **Benefit.** A library nobody else can see.
- **Platforms.** Web, iPhone/iPad, Mac.
- **Workflow.** Settings > Friends & privacy.
- **Location.** Settings > Friends & privacy.
- **Code.** `server/internal/social/`, `web/routes/_shell.app_.settings.friends.tsx`, `docs/privacy.md`.
- **Status.** `verified`. Group messages are server-visible.
- **Priority.** High as a message, low as a shot.
- **Headline.** "Private by default. No ads, no feed."
- **Recording.** Settings > Friends & privacy, a slow pan.
- **Video concept (8 s).** An empty profile page, then the line "Nobody sees your library unless you invite them."

## 41. Undo and History

- **What it does.** Every change to the library, yours, an import's or a connection's, is listed newest first with who made it, and "Undo puts it back."
- **Problem.** Bulk changes you can't take back.
- **Benefit.** Every change has a way back.
- **Platforms.** Web, iPhone/iPad, Mac.
- **Workflow.** Settings > Your data > History > "Undo".
- **Location.** Settings > Your data.
- **Code.** `web/routes/_shell.app_.settings.data.tsx`, `web/lib/history/model.ts`, `server/internal/library/` (actions).
- **Status.** `verified`.
- **Priority.** Medium. The trust beat behind imports and agents.
- **Headline.** "Every change has a way back."
- **Recording.** Tier A, after an import and a few ticks.
- **Video concept (8 s).** History: "Letterboxd import", "You", "Claude". Tap Undo on one. "Undone".

## 42. Export and delete

- **What it does.** Export "Everything (JSON)" or a "Library spreadsheet (CSV)" that Aaru can import back. Delete the account and library in Settings.
- **Problem.** Being locked in.
- **Benefit.** Leave whenever you like.
- **Platforms.** Web (download), iPhone/iPad, Mac.
- **Workflow.** Settings > Your data > Export. Settings > Delete account > "Delete account and library".
- **Location.** Settings > Your data; Settings > Delete account.
- **Code.** `server/internal/export/export.go`, `server/internal/auth/store.go`, `web/routes/app_.export.ts`, `web/routes/_shell.app_.settings.delete.tsx`.
- **Status.** `verified`. The JSON leaves out daily usage counts, undo history, proposed plans and import records (`docs/privacy.md`). Say "your library and everything you added", not "every byte".
- **Priority.** High as a message (`MARKETING.md` moat 1, "exit door as brand").
- **Headline.** "Export will never be a paid feature." (live FAQ copy)
- **Recording.** Tier A. Download the CSV and open it in a spreadsheet, demo account only.
- **Video concept (10 s).** Tap "Library spreadsheet (CSV)". A spreadsheet opens with your titles. "Yours. Always."

## 43. Appearance

- **What it does.** System, Light or Dark, per device. Dark is the brand's home.
- **Problem.** Tracking happens at night.
- **Benefit.** Calm in a dim room.
- **Platforms.** Web, iPhone/iPad, Mac.
- **Workflow.** Settings > Account > Appearance.
- **Location.** Settings > Account.
- **Code.** `web/components/AppearanceSection.tsx`, `apple/Aaru/Design/Appearance.swift`.
- **Status.** `verified`.
- **Priority.** Low.
- **Headline.** Do not headline this.
- **Recording.** Pin Dark for every shoot.
- **Video concept.** None.

---

# Evidence and assumptions

- **Source.** Each surface was read at its production commit with `git show`: the server at 9c0848e (identical to `main` for `aaru-server-v2`), the production web at 6d5944fe, the Apple app, extension and beta web at `origin/main` 1cf2ea5e. The local checkout's `main` is at cb3fa704, behind `origin/main`, so a recording from the local tree today would miss the web assistant. Production settings came from infra `origin/main` (e838769). `README.md`, the stack table in `CLAUDE.md`, and the status table in `BACKLOG.md` are partly out of date; prefer this file.
- **Not rendered.** No screen was rendered for this review, rehearse before filming. No recording or AI call was run. Filming sequences and expected labels are read from code.
- **"Built, unverified"** in `BACKLOG.md` means code exists but no device run, real account or stranger has confirmed it. Most of those items are `experimental` here.
- **Production settings.** Which features are on comes from `server/internal/config/config.go` and the key names in infra's sealed `aaru-env`. Nothing was decrypted, so a present key may still be invalid.
- **Reachability** comes from navigation code and route lists. Links inside pushes or assistant replies wouldn't show up.
- **Labels in quotation marks** are UI strings from code at the commit named; labels can change with the next deploy. Recheck the exact words on the build you film.
- **Counts in UI copy** (30 a day, 62 badges, 5 tools) are limits and catalog sizes, not usage. Never present them as performance or adoption claims.

**Keep this file current.** Per `Claude.md`, when a user-facing feature ships or changes, update its entry here and move anything newly live out of "Do not market". When the production web Worker is redeployed, re-check every "beta web only" note.
