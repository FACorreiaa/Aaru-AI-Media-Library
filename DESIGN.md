# Aaru — Design

Aaru is agentic-first. That does not mean a chat bubble stack over a movie app.

**The home is a workspace the agent can change**, not a poster grid with a chat drawer.
Chat is how you speak. The views below are what you look at.

## Design rule

The agent only emits **native Aaru components** — title card, season map, import ledger,
tonight strip. It does not invent random web UI.

That is the A2UI idea: trusted catalog, host-rendered, undoable.

Keep a **canvas** beside intent so work does not die in the scroll.

---

## 0. Welcome (signed out)

The app's landing screen, and the web landing page's twin. Mascot on its disc, wordmark, one
display headline, three plain pillars (one library, private by default, bring your history), then
Sign in with Apple and Continue with email pinned to the bottom on iPhone. Side by side on iPad
and Mac. No carousel, no feature tour, no "AI". `WelcomeView` in `aaru-ios`.

The web landing (`src/routes/index.tsx`, owner 2026-10-20) is centred: a privacy pill, the
display headline, Get started, then App Store and Google Play buttons at equal weight ("Coming
soon" until a listing exists; URLs in `src/lib/site.ts`). Below sits a still fan of real
posters (`PosterFan`) that fades into the page; it enters once and never sways. Then one card
per thing tracked (TV shows, movies, anime, books, music, sports), each with a small fan of
three covers (`KindCard`), imports, native apps, FAQ. The header and footer link to X. Art is
hotlinked from TMDB, Open Library and the Cover Art Archive (`src/lib/landing/art.ts`); sports
use type tiles. `WelcomeView` has not been brought in line yet.

## 1. The Field (home)

Open the app into a calm vertical canvas, not "Movies / Shows / Books" tabs.

Top: one composer.

- "Bring my Trakt."
- "What should we finish this week?"
- "Mark S03 of Andor watched."
- "Make a list of rainy-night books I own but never started."

Below that, **pinned artifacts** the agent keeps updating:

- **Now** — in progress (one show, one book, one movie)
- **Airs this week** — CAT-like calendar, generated from the library
- **Unfinished business** — dropped / stalled with a suggested resume point
- Last import job, collapsed

Poster grids exist, but they are an artifact you ask for ("show my 2024 films"), not the
default chrome.

Inspiration: Apple TV "Up Next" + Things 3 today list + Copilot canvas.
Mood: a lit room at night, navy with ice-blue light and amber edges, lots of air.

**Built 2026-10-21 (web, iPhone, iPad, Mac), in the Mindspace language below:** the page is
headed "The Field" with one line of when it is and what is live ("Tuesday evening · 3 in
progress · 2 airing today"). **Tonight** (§5) leads, then the user's rows, then Discover. On a
wide screen (web ≥1024px, iPad and Mac at regular width) a side column holds what Aaru is doing
for the user: requests waiting for an answer, the **last import** (collapsed `JobLedger`, the
owl while it matches, opens the import), the last 7 days, status counts, the recap banner and
the user's lists. On a phone the same blocks follow the rows. The nav label stays "Home".

**The composer, 2026-10-23 (AG-006, capture only):** one field under the heading, above Now
playing and Tonight: "Paste titles, a link or a screenshot", a picture button (the photo picker
on Apple, a file picker, paste or drop on the web) and Send, with "Nothing is added until you
approve what Aaru found." under it. Sending opens the capture's review; until it is approved or
dropped, it waits as a "Your capture" card at the top of "Waiting for you" (the owl while Aaru
reads it, then "Add 7 · 2 need a pick"). Past the free month's captures it says so (the Plus
paywall on Apple, a line on the web: Plus is bought in the Apple apps). It is not yet a chat with
the agent (AG-004).

**Aaru Plus, 2026-10-23 (BIL-003/004):** the paywall is a sheet: what Plus includes, one row per
plan with its App Store price and period, Restore Purchases, the renewal terms, and Terms and
Privacy links. It opens from the capture limit and from Settings → Account's "Aaru Plus"
section, which shows the state ("Active · renews 3 November", or this month's captures) and, on
iPhone and iPad, Manage Subscription. The web shows the same section with no button.

**Now playing and the week, 2026-10-21 (owner, SCR-008):** while a player plays, the
`NowPlayingCard` (§15) runs across the full width between the heading and Tonight, and Tonight
and Continue watching leave that show out. The last 7 days left the side column: it is a
horizontal strip in the main column under Tonight (four figures in a row, the week's bars with
their days, "Insights →"). The side column keeps requests, the last import, status counts, the
recap banner and lists.

## 2. Intent preview (before it writes)

Never let the agent mutate the library invisibly.

You say "import Trakt and clean duplicates." The view is a **plan card**:

- 412 history rows → 380 titles
- 14 unmatched
- 3 possible merges (same IMDb, different year)
- Autonomy dial: *ask me* / *fill empty only* / *overwrite if newer*

Approve, then it runs. This is the "before" half of agentic UX: intent, preview, permission.

## 3. Work ledger (while it runs)

Imports and bulk episode ticks are long jobs. Give them a **timeline**, not a spinner.

Each step is a row you can tap:

1. Talk to Trakt
2. Map IDs
3. Hydrate TMDB
4. Upsert library
5. Apply ratings

Partial failure stays visible. "14 unmatched" opens a queue the agent and you finish
together. GitHub's canvas lesson: durable state, human gates. Built for one row at a time (IMP-011): each unmatched row has "Find it", the
catalog search started on the row's own title and kind; the pick brings the file's status,
rating and episodes with it, into the plan before approval or as its own undoable action after.

Built for file and account imports (IMP-017, web + Apple): Read your file (or library) · Wait for
a free slot · Match each title to the catalog ("840 of 2,001" with a bar) · Check against your
shelf · Ready for you to review. Done steps carry a check, the current one a ring, the rest stay
muted. A retry shows as a pause with its reason, never as an error. Nothing loops; the bar moves
only when the count does. The page says you can leave, and a job still in line can be cancelled.

## 4. Title room (deep artifact)

One title is a room, not a settings form.

- Left or top: poster, status chips, `isOwned`, rating.
- Center: **season map** — a heat grid of episodes (Serializd energy, calmer). The agent can
  paint a season in one move, then you tap to correct two episodes.
- Right or bottom: notes, "why it's here" (Trakt history 2023-11-02), next air date.

The agent is allowed to drop extra cards into the room: cast you actually care about,
"you left off S02E04", "book pairings."

**Built 2026-10-20 (iPhone, iPad, Mac, web):** the season map is a grid with one cell per
episode in four states (watched, up next, aired, not aired yet); a tap ticks through the same
optimistic write as the list. Below it each season's list shows a still, the name, the air date
(with a time only when the catalog knows it) and a synopsis line. Tapping an episode opens the
**episode sheet**: still, `S1 · E8`, name, air date, runtime, synopsis, the tick, and
previous/next. Only the season holding the next episode starts open. A title that fails to load
says so with a retry, never an endless spinner.

**An album's room (MUS-001, 2026-10-21)** is an album page, not a season map: a big square
cover with almost no chrome, the title in the display face, the artist under it in muted, the year,
genre chips, the same status / rating / notes as any title, then the tracklist (number, name,
length in tabular figures; "Disc 1"… only when there is more than one). No playback and no
ticks: the tracklist is catalog data. Without one yet, a quiet "Tracklist not available yet".

**A manga's room (MNG-001, 2026-10-23)** is a book's room with chapter and volume in place of the
page: two number fields, each with its total when AniList knows it, saved together. The byline
is the story and art credits.

**Built 2026-10-21 (web, iPhone, iPad, Mac):** the room opens on a hero: the title's backdrop
under a veil that fades into Paper (or, without art, the room's own reed code, seeded by the
title id so each room has its rhythm), the poster standing over the hero's lower edge, the name
in the display face. One row of next steps sits under it: **Mark S4 · E3 watched** for a show with an
aired, unwatched episode, then the status in the kind's words. On a wide screen the title's
layer (About for films and books, the tracklist, the season map and seasons) is the main column
and the user's layer (rating, owned, page, notes; About for shows) a side column; on a phone
they stack, the user's layer first on Apple. The next cell on the season map stands on Paper in
a gold ring. Every write is the one the room already made.

## 5. Tonight

A nightly composed view. Not recommendations-as-a-product — a **short plan**.

> "You have 48 minutes. Episode of Slow Horses, or the last 60 pages of Piranesi."

Two cards, one reject, one "not tonight." The reject teaches the agent. This is the return
moment after an agent run.

**Pulled forward, client-composed (owner, 2026-10-21):** until M13, Tonight on the Field is
composed on the device from rows the Field already loads, with no new endpoint and no ranking:
the next episode at the top of Continue watching, else the first unwatched airing today; then
"Also tonight", one more from the other source, never the same show twice. The reason line is
only real fields (runtime, episodes left, "Last one aired", air time, premiere/finale). It has
Mark watched (the same write as the Continue card) and Open; no reject and no "not tonight"
until the agent composes it. Same rule on the web (`lib/home/tonight.ts`) and Apple
(`Home/Tonight.swift`).

**Server-composed, client fallback (2026-10-23, AG-005):** the Field now shows
`GET /v1/tonight` for the viewer's local day: shows in progress, today's airings, books in
progress and wishlist films, ranked on the server with template reasons. The last answer is
kept (Home's cache on Apple, `localStorage` on the web, cleared on sign-out), so Tonight opens
offline. The device composes it as above only when no answer for today exists. Each pick has
"Not tonight" (gone for the day) and "Not for me" (ranked lower for 14 days): buttons on the
web, a "…" menu and a context menu on Apple. The card moves on at once, then Tonight loads
again. Mark watched shows only when the pick is a show's next episode; beside it, "Season N
watched" (PROG-006, owner 2026-10-23) ticks every aired episode of that season, shown only while
episodes after the next one remain in it.

## 6. The shelf (library as query, not as app section)

Library is a **saved question**.

- "Shows I own that are in progress"
- "Books finished in 2025"
- "Movies with no rating"

Each shelf is a named artifact. The agent creates them. You can pin them to The Field.
Classic filters are how a shelf is edited, not how you enter the app.

Visual cue: Letterboxd lists + Ryot filters, presented as pages of reeds rather than a
spreadsheet.

**Now (APP-017, built 2026-10-21).** Library opens with what you are in the middle of, the
"Now" of §1 made real before The Field: **Watching** (shows, anime, films) and **Reading**
(books), newest activity first, as big cards, not posters in a grid. A video card is the
backdrop with the title on it; a book card is its cover. Each shows how far along it is ("4 of
10 episodes" with a bar, "35%", "Page 120") and the one next step: **Mark S1 · E5 watched**
ticks the next aired episode, **Update page** moves a book, **Mark read** / **Mark watched**
closes it (wording aligned 2026-10-21, UX-043/044). The filters sit under the page title,
above Now (2026-10-22). A kind chip narrows Now with the shelf; choosing any status hides it,
since the shelf is then that list. Each group shows its newest six, with "Show all N" to open
the rest in place. Below Now the shelf has its own heading, naming the filter ("Shows ·
Watching", "All titles") with a count; arriving with `?status=` or `?kind=` scrolls to it.
Cards scroll sideways on phones and sit in a grid wider. **Listening** (albums, cover and artist, **Listened** to close) joined on 2026-10-21. Books
carry Open Library's page count, so a page reads "Page 120 of 412" with its bar. Manga joined
Reading on 2026-10-23 (MNG-001): a portrait cover like a book, "Ch. 112 of 364 · Vol. 12" (the
totals only when AniList knows them), **Read ch. 113** as the next step and **Mark read** to
close it.

A **list** is the hand-made counterpart: membership in an order the user chose, titles in the
library or not. It fills from inside: "Add titles" opens search aimed at the list, and a hit
reads "On this list" once it is there. Every library row also offers "Add to list". A list row
says what the title is doing: show status (Returning, Ended…), the next episode and when it
airs, and the library status and progress when the title is on the shelf (LST-003).

## 7. Catch-up calendar

You came from Pogdesign CAT. Steal the *feeling*, not the site.

Month canvas of **your** airings only, shaped like Stremio's calendar: a month switcher with the
neighbouring months as buttons, poster thumbnails in each day (two small posters and a "+N" on
phones, three on wider screens), and an agenda beside the grid (below it on phones) grouped by
date. Agenda rows carry the poster, show, code and name, network · time and the badge; tapping
one opens the **episode sheet**: the still, the poster, when and where, the synopsis, a watched
toggle and "Open show". On a phone, tapping a day opens that day as a sheet.

Week, Month and **Missed** are three modes of one Calendar destination; weeks start on Monday.
Missed is the catch-up list: what aired in the last four weeks without a tick, one card per
show, oldest miss first, with how many episodes and how much time it adds up to. **Filters**
(hide watched, premieres or finales only, shows or anime) apply to every mode, live in the URL,
and show as removable chips. Every tick is a 44px round toggle that a pending write disables.
(CAL-002 web, CAL-003 iPhone, iPad and Mac, 2026-10-21: the same modes, rows, sheets and filters;
on Apple the filters are a toolbar menu and the episode sheet has medium and large detents.)
Agent highlight later: "three premieres, one finale, you are behind on
two."

ICS import lands here first, then the agent offers to add the missing shows to the library.

## 8. Import studio

A dedicated canvas for migrations. Chat is the brief. The canvas is the map.

Drop a Goodreads CSV, an IMDb ratings file, a CAT `.ics`, paste "here are the shows I follow."
Agent lays out three columns: **matched / needs eyes / unknown**. You drag a mismatch onto the
right TMDB title. That human correction is gold for later imports.

Seenr already does "paste a note, AI turns it into an import." Aaru should make that the
*main* onboarding, not a buried tool.

## 9. Undo ribbon

Every agent write has a 30-second (and later, history) undo.

> "Marked 18 episodes watched on The Bear."

Ribbon at the top. One tap reverts. Action audit is a first-class view, not a log file.

**Undo toast (PROG-005, 2026-10-22).** Until the ribbon exists, a bulk tap undoes from a toast
at the bottom: "Marked 62 episodes of Severance · Undo", about six seconds, a success haptic on
iOS, read out by VoiceOver and the web's live region. A running show says "Caught up on 18 aired
episodes · Undo"; nothing to tick says "Already caught up", with no Undo.

**Mark show watched.** A long press on a show's card (iOS: Library, Home's rows) or its card
menu on the web (⋯, right-click, long press) offers "Mark show watched"; a film offers "Mark
watched". It applies at once, with the toast above, never a dialog. Choosing Watched for a show
on its page does the same. A running show stays Watching and its page shows "Caught up" beside
the status.

## 10. Mac companion

On Mac, the agent lives in a **sidebar + inspector**, library in the middle
(Mail / Notes / Music pattern).

Menu bar: "log last episode", "what's on tonight", paste a list.

The Mac is where imports and shelves get built. iPhone is The Field + Tonight + check-offs.

What the Mac app does today (Apple audit, 2026-10-21, `docs/audit/apple.md`):

- **Window.** One `WindowGroup`, 1180 × 780 by default, `windowResizability(.contentMinSize)`
  over a 760 × 520 minimum. Settings is the Settings scene, sized to its content.
- **Menu bar.** File → New List (⌘N). Edit → Search Titles (⌘F, the catalog search sheet over
  any destination). View → Refresh (⌘R, the selected destination reloads), the standard sidebar
  and toolbar commands. Go → the eight sidebar rows (⌘1…⌘8). ⌘, opens Settings. A hardware
  keyboard on iPad gets the same shortcuts, with Settings in Go.
- **Settings scene.** Seven panes (§18), each the same page view iPhone and iPad push, each with
  its own stack for an import job or History.

## 11. Capture (paste anything, get a plan)

Recommendations arrive as mess. A text thread. A screenshot of somebody's list. A photo of a
shelf, spines only. A paragraph in a newsletter. Every other tracker makes you retype that
into a search field, one row at a time, and most of it never gets typed.

Capture is one target for all of it. Share sheet, paste, drop, photo.

> You paste a group chat. Aaru: "Nine titles. Seven matched, one needs eyes, one I cannot
> find." You fix the one, approve, done.

Import studio (§8) is the same idea for a 2,000-row CSV. Capture is the same idea for nine
lines of chat, and it is the version people use weekly rather than once. Under the hood it is
literally an import — same ledger, same three columns, same plan card — so it inherits undo
for free and adds no new furniture.

The feeling to protect: **it never writes what it guessed without showing you the guess.**
Extraction from a screenshot is a guess. One row or ninety, the `MatchTable` comes first.

**Built 2026-10-23:** the review is the import's own page, titled "Your capture", headed "Add 7 ·
2 need a pick", with **Approve** and **Not this**, "Find it" on unmatched rows, and the Undo toast
after Approve. Its back link and "Not this" return to Home. The "ready" notification opens it.
The Share Extension is not built yet.

## 12. Approvals (a plan from somewhere else)

Aaru is not the only place you talk to an agent. You are on a laptop, in some other chat,
and you say "catch me up on Andor in Aaru."

Your phone buzzes.

> **Claude · laptop** wants to mark 18 episodes watched on Andor.
> 18 episodes · S01E05 → S02E04 · nothing overwritten
> [ Approve ]  [ Not this ]

That is the whole feature. The outside agent gets to *propose*. The plan waits in The Field
like any other artifact. Approval happens here, in Aaru, on the same plan card a first-run
import uses — and afterwards it is one row in the ribbon, with the caller's name on it, one
tap from gone.

Nothing else in this category can do this, and the reason is boring: every write already
carries its own inverse. The trust comes from the plumbing, not from a promise.

**Built 2026-10-20.** Until The Field exists, waiting requests pin to the top of Home as
"Waiting for you", on web and Apple: the caller's name, the summary, a counts line ending
"nothing changes until you approve", the changes when there are several, then **Approve** and
**Not this**. The push reads "Laptop wants to change your library" and opens the request. A
request whose library moved meanwhile says so and applies nothing; ask the agent again.

The feeling to protect: **the buzz is a question, never a receipt.** The moment a notification
tells you what an agent already did, Aaru is somebody else's app.

## 13. Home rows (Phase 2)

The Field's pinned artifacts take a concrete shape borrowed from Trakt's web home: horizontal
rows of wide cards, one job per row.

- **Continue watching** (`ContinueRow`) — backdrop card per in-progress show or movie. Overlay
  carries runtime or time left ("1h 27m left"), a "Finale" dot when the next episode ends a
  season, and "N left · Xh" for what remains. Title, `S1 · E8 · Episode name` under it, a check
  to mark the next episode watched.
- **Start watching** (`StartRow`) — poster cards for wishlist titles with runtime, so the row
  answers "what can I start in two hours."
- **Calendar** (`CalendarRow`) — the next few airings of tracked shows and anime, badged
  `Today` / `New` / `In 3 hours` / `In 2 days`.

- **Discover** (`DiscoverRow`, DISC-001) — after the user's own rows, public poster rows from
  the catalogs: Trending shows, this season's anime ("Fall 2026 anime"), Trending movies, On
  the air, Trending anime, New shows, In theaters, Trending books, then New albums and Coming
  soon (MUS-002, square covers; an upcoming album wears its release day, "Tomorrow", "Oct 30"). A card not on the shelf is
  an add (tap: wishlist; hold or the chevron beside Add: a status or a list); a card on the shelf wears a check
  and opens the item. A new account sees a slim "Add a show to see what's next" header above
  them instead of an empty screen. The same rows for everyone; never "because you watched".

**Added 2026-10-20 (APP-013),** so Home is never blank:

- **Last 7 days** (GAM-006d, 2026-10-21; was "This month") — a quiet stats strip: seven small
  bars, one per day by time, with a muted track under empty days, then episodes · hours ·
  finished · active days. Tapping it opens Insights on 7 days. On the web it is a wide strip
  under Tonight since 2026-10-21 (§1): the four figures as number over word, always all four,
  and the bars with each day's initial; "Insights →" opens Insights. Shown at zero too ("Nothing
  tracked yet"), so a new account sees where its week will land.
- **Status counts** — one chip per status with its per-kind label and count; a tap opens
  Library filtered to it.
- **Unfinished business** (`UnfinishedRow`) — the §1 artifact made real: every dropped item and
  anything in progress untouched for 30 days, "Dropped" or "Paused 6 weeks", with "Resume at
  S2 · E3" for a show. Never a title already in Continue watching.
- **Lists** — chips for the user's lists plus "New list".
- **Listening** (MUS-001, 2026-10-21) — square album covers for albums in progress, after
  Continue watching; absent when there are none.

Album covers are **square everywhere** (Apple Music style), the same width as a poster in the
same row, with the artist in muted under the title and the year as the badge.

Discover on Home is DISC-001's rows above, not a separate teaser. On the web, Search opens in
place on Home and an add shows up in the rows without a reload.

Rows are the Field's artifacts, not new chrome. The composer still sits on top.

## 13a. Discover (pulled forward 2026-10-20)

Something to add without typing. The Discover tab/page (APP-012) is DISC-001's rows, the ones
Home shows under the user's own, as a full destination: Trending shows, this season's anime,
Trending movies, On the air, Trending anime, New shows, In theaters, Trending books. Each card
carries a kind badge and a date badge; a card the user already has (`libraryItemId`) reads "On
your shelf" and opens the item, anything else offers Add (with a status) and Add to list. TMDB,
AniList and Open Library credits sit in the footer.

It is catalog data, the same lists for everyone. It is **not** recommendations: no "because you
watched", no taste profile, nothing read from other users. A tab on iPhone, a sidebar
destination on iPad, Mac and the web (§18).

**Seasons (DISC-002, 2026-10-21).** A Today | Seasons control sits under the title (pinned under
the large title on iPhone, in the toolbar on the Mac). Seasons shows one season as an object:
its name in the display face as the headline ("Fall 2026"), "Oct – Dec · 84 anime" under it in
muted, a step to the season either side (a swipe across the name on iPhone), then the kind
switch (Anime · New shows · Returning · Movies) and a poster grid, popular first, with "Show
more" rather than endless scroll. A new season comes in from the side it lies on (about 200 ms,
entrance only; a fade with reduced motion). While a season loads, still placeholders at the
real poster size stand in: nothing shimmers. A provider that is down says so on its own kind.

**Concerts (MUS-003, 2026-10-21).** The control becomes Today | Seasons | Concerts; Concerts is
absent while the server has no concert provider. Two sections: "Your artists on tour" (artists of
the user's own albums, like the calendar, so not a recommendation) and "Near <city>" with "Use my
location" and a 25 · 50 · 100 km switch. A date-led list: each row opens with a ticket-stub date
block (the day large in the display face, month and weekday small), then the act, "venue ·
city" in muted, "distance · time", and "Tickets ↗" out to Ticketmaster. Aaru never sells, holds
or prices a ticket. Dates and times are the venue's, never converted. On iPhone and Mac a List |
Map switch shows the searched area as a circle on a map; the web is list only. "Use my location"
asks for an approximate position once (reduced accuracy on Apple) and says it is not saved; the
saved city lives in Settings → Friends & privacy → Location ("Concerts near"), with Remove. Placeholders at the real row size
while loading, no shimmer; a silent provider says so in one line.

## 13b. Insights (pulled forward 2026-10-20)

The Recap's numbers, browsable instead of played. `StatsPanel`: a 7 days / 30 days / month /
year / all time switch, totals, bars per bucket, by kind (films, shows, anime, books), the top titles, a
ratings histogram, and the longest run. "Play as story" hands a month or year to the Recap.
Since 2026-10-21 (§18) a destination in the sidebar's bottom group on the web, iPad and Mac;
on iPhone it opens from Home's stats strip and Library's More menu, not a tab.

The rolling windows (GAM-006d) add a line "Oct 15 – Oct 21 · Private to you", and each tile
shows its change against the window just before as an arrow and an absolute number (`↗ +3`,
`↘ −2 h`): accent when up, muted when down, never colour alone, hidden when nothing changed,
never a percentage. Their chart is time per day (so a film night shows), with a track under
empty days. They have no "Play as story" and no stepper.

Static: bars are drawn at their final height, nothing counts up. The Recap motion rules (§17)
still apply to anything that ever moves here.

Music (MUS-008, 2026-10-21) comes last, under the library's numbers, and shows even when nothing
was tracked: listening is not library activity. Two tiles (listens, hours) with the same change
rules, an Artists / Tracks / Albums switch over the top five, and "All listening ›" to the Music
page. That page is Recent and Top: rows of a 40pt cover (a ♪ while the album is unknown), the
track, "artist · album" and the time, under Today / Yesterday / date headings, fifty at a time;
Top is twenty rows for 7 days, 30 days, this year or all time. Wide screens show both side by
side; a phone switches Recent | Top. An album row is a link only where it leads somewhere.

## 14. Week grid (Phase 2)

The `CalendarMonth` (§7) answers "what did I miss." The week grid answers "what is on this
week," and it is the closest Aaru gets to copying Pogdesign CAT outright, because that page is
right.

- Seven dense day columns, today highlighted, paging by a day (← →) or a week (« », PageUp /
  PageDown), Today, and a date to jump to.
- One cell per episode: banner art, show title, `S01E05`, episode name, network · local time.
  Tapping the cell opens the episode sheet (§7); there is no hover-only tooltip.
- A round 44px tick on every cell marks it watched in place.
- State colours: watched (dimmed), premiere, finale, today, and new-season. Colours come from
  the brand palette, not CAT's yellow and red.
- Banner art is the show's backdrop (TMDB) or banner (AniList), then the poster, then a tint.
  Date-only air dates (TMDB) show the day without a time; anime from AniList has exact times.
- Your shows only. No global schedule.

On Mac and web the grid is the default calendar view. On iPhone and phone web it collapses to a
day strip (tall day pills) over that day's episodes as poster rows.

## 15. Now playing (Phase 2, live in Phase 3)

`NowPlayingCard`: art, `S1 · E8 · Episode`, a progress bar, "41m left", "Ends at 1:20 PM".
Tapping the bar flips between time left and end time. Set by a manual check-in in Phase 2 and
by scrobbles from Plex, Jellyfin or Stremio in Phase 3. The same data drives the Live Activity.

**Live 2026-10-21 (SCR-008):** fed by `GET /v1/me/now-playing` from Stremio's `player` events
and the browser extension. Players report only on start, pause and stop, so the client adds the
time since the last report while playing. A playing session counts until its end plus 10
minutes, a paused one for 30 minutes after the pause. The eyebrow names the state and the player
("Now playing · Stremio", "Paused · Disney+"); a pause shows time left only. Web: full width
across the top of the Field, asked again every 30 s while the tab is visible, with Mark watched
and Open. iPhone and Mac: the same card above Tonight. The Live Activity is pushed by the server
over APNs (push-to-start on a session's first start, updated on pause and resume, ended by the
stop: "Watched" for 8 s when it ticked), and the app starts it itself when it opens on a
session it has no activity for. A push-started activity has no poster until the app opens.
Nothing animates.

**Several at once, 2026-10-22 (SCR-009):** the card and the Live Activity hold up to three
things playing together: library episodes and movies, a YouTube video, then a track. The first
leads in full as above (a video with its 16:9 thumbnail, a track with its square cover whole on
the accent ground); the others follow as compact rows: art in its own shape (2:3 poster, 16:9
thumbnail, square cover, or the kind's glyph), the name, "subtitle · service", a thin bar and
time left when the length is known, "Paused". Episode and movie rows open the library item and
carry Mark watched; a video or track with a link opens it in a new tab. The Lock Screen stacks
the rows with their art aligned and the times in one column; the Dynamic Island shows the first
item's art on the left and the second's glyph on the right (its countdown when it plays alone),
and the expanded island the first in full over two rows. A track's time is a plain countdown;
it never flips to an end time.

**Settings groups, 2026-10-21** (owner): five groups (Account, Imports & export, Connected apps,
Insights & recaps, About). Superseded the same day by the eight pages of §18.

**Stremio, built 2026-10-20.** Settings has a Stremio section on web, iPhone and Mac: connect,
then the install links (Open in Stremio, Install on Stremio Web, Copy) show once, because they
carry the secret. Live links list their last use and a Revoke. Writing back to the library
beyond "watched" is an opt-in at connect time. Stremio's events land as journaled actions
named "Stremio: …", so the undo ribbon and history treat them like a tap. What Stremio plays
shows as the Now playing card (§15, SCR-008). Under the intro, a collapsed "How to set it
up" lists the install steps, what Stremio's marks do here, where it works, and that a lost link is
revoked and made again; the same text on web and Apple.

Settings → Import offers **Import from Stremio** (IMP-016): a sheet (web: an inline panel)
with the code in large monospace, an "Approve on stremio.com" button and a QR for approving
from another device, and a quiet "Waiting for approval…" line. It polls on its own and, once
approved, opens the import's plan, which is approved like any other import. Nothing is written
before that approval.

**Connections, built 2026-10-20** (OUT-004). Settings has a Connections section on web, iPhone
and Mac for AI agents that reach the library over MCP. Pick the agent (Claude Code, Codex,
Hermes, Gemini CLI, any other MCP client) and its setup steps show at once, with a placeholder
where the token goes; every block has Copy. Name it, choose **Allow changes** (off by default:
one item at a time, as a tap would; never a removal or many items at once) and **Allow imports**
(off by default: it may hand Aaru a list, which you review as any import), and connect: the same
steps come back with the token filled in, shown once, and the sheet will not swipe away until
Done. Last comes a message to paste into the agent so it checks itself. Live connections list
their agent, what they may do and their last use, with a confirmed Revoke. Changes they make
land as journaled actions named after the connection ("Claude Code: marked S01E01 of X
watched"), so history and undo treat them like a tap.

**Claude** is first in the list and has no token: its steps say to add Aaru in Claude
(Settings → Connectors → Add custom connector, with the URL), and Claude sends you to Aaru's
**consent page**. That page names the app and, in bold, the host it will return you to (apps
name themselves; the host they cannot fake), then a name for the history, **Allow changes**
(off), and **Allow** / **Not now**. A signed-out visitor signs in first and lands back on it.

**Browser extension, 2026-10-21** (SCR-007, owner's choices). It is the last choice in the same
Connections picker, not a section of its own. Choosing it shows no token: one sentence on what it
does (finish an episode or a film on Netflix, Disney+ or Prime Video in your browser and it is
marked watched; it can't read your library), three numbered steps (install for Chrome or Firefox;
click Aaru in the toolbar, then Connect; approve on the page it opens) and the store buttons once
they are listed. On iPhone and Mac the row "Browser extension" opens a sheet with the same
sentence and steps; connecting happens in the desktop browser. Connected browsers list with the
others ("Chrome on macOS · Marks what you watch · used 2 h ago"), with Revoke.

Connecting is **one click, no secret shown**: the extension opens `/connect/extension`, styled
like the consent page — "Connect Chrome on macOS to Aaru?", the same sentence, **Approve** /
**Not now**. Approve stays disabled until the extension answers on the page, so a browser
without it is told to install it instead of minting a token nobody holds; a token the extension
does not take within five seconds is revoked. Then: "Connected. You can close this tab."

The extension draws nothing inside the streaming sites. Its toolbar badge is the only signal:
✓ matched, ? not matched, ! connect again. Its popup shows what is playing now and what Aaru
matched it to, the last few plays with their result (marked, finished, not matched), and
Connected · Disconnect, in Aaru's paper and ink with the display face for the title.

## 16. Widgets (Phase 2)

Widgets are where a tracker earns a daily glance. Sequel ships the richest set and the only
interactive mark-watched widget seen in the category. Aaru matches that and adds what nobody
ships.

- **Up Next** (S / M / L) — next unwatched episode per show. M and L carry an interactive
  "mark watched" button (App Intent, same write path as a tap).
- **Airing countdown** + Lock Screen accessories — next airing of a tracked show or anime.
- **Week** (L / XL) — the week grid in miniature, CAT style.
- **Now playing** Live Activity (SCR-009) — Lock Screen and Dynamic Island, up to three rows
  (episodes, movies, a YouTube video, a track), progress plus "Ends at". "Now watching" (one
  episode) remains for a check-in started by hand.
- **Listening** (S / M, MUS-001) — square covers of albums in progress; a tap opens the album.
- **Streak** (WID-007, pulled forward 2026-10-22) — small and Lock Screen accessory: a flame,
  the day count and the last seven days as bars. It flips at local midnight from the snapshot
  with the app closed, using AaruCore's `Streak` rule.
- **macOS** — the same widgets on the desktop and in Notification Center. Almost no tracker
  ships Mac widgets.

Widgets read a snapshot the app writes. They never become a second client with its own logic.

## 17. Social surfaces (Phases 4–6)

Private by default stays. Everything below is opt-in, friends-only by default, and does not
ship before the Phase 2 gate.

- **Friend stories** (`FriendStories`, Phase 4) — Trakt's "Today" pattern: a row of friend
  avatars, tap into a full-height card per title a friend watched today ("Kevin · Watched S2 ·
  E9 · 12:11 PM"), with a bookmark to add it to your wishlist.
- **Profile and stats** (`ProfilePanel`, pulled forward 2026-10-22 without badges) — MAL-style
  all-time numbers, private to you: a medallion at the leading end of Home's toolbar (iOS, as a
  sheet) and of Home's heading (web, `/app/profile`) opens it. In order: name, @handle and "In
  Aaru since"; the time in days and hours in the display face, with hours and episodes under;
  four tiles (shows watched · watching, anime, films, books read); where the time went (TV,
  anime, films, one stacked bar); the top eight genres; the three titles with the most time;
  networks; mean score and the ratings histogram; Favorites; then Insights and Recap. It counts
  the library as it is, undated ticks included, and says so ("Includes episodes without a watch
  date"). Static, like §13b. Badges (`BadgeShelf`) live on Achievements (below).
- **Favorites** (`FavoritesRow`, FAV-001, owner 2026-10-23) — a top 10 per kind (Films, Shows,
  Anime, Manga, Books, Music), any title from the catalog, first is the favorite. Picked in
  Settings → Account; on the profile, one numbered row of covers per kind with something in it,
  and "Edit" back to Settings (with no favorites, one line saying where to pick them). The only
  part of the profile a friend also sees: on their view of you, after Recently finished, while
  you share your library.
- **Badges** (`BadgeShelf`, pulled forward 2026-10-22) — discovery badges and milestone badges,
  tiered. See "Achievements" below.
- **Leaderboard** (pulled forward 2026-10-22) — friends only, weekly, opt-in. Never global.
- **Watch channel** (`WatchPanel`, with groups since 2026-10-20; was the Phase 6 Room) — watch
  together inside a group: countdown to "press play", who is in, reactions, drift from
  scrobbles ("Ana is 2 min ahead"), and "Mark watched for me" at the end.
- **Conversations** (`ConversationView`, Phase 6) — end-to-end encrypted DMs. A lock and a
  safety-number check live in the header, not in a settings screen.

The feeling to protect: **social is a room you invite people into, not a feed you are fed.**

### Friends and profiles (SOC-001/003, pulled forward 2026-10-21)

Friends is its own page on the web and its own sidebar destination on iPad and Mac, between
Lists and Groups. On iPhone the five tabs are full (§18), so Groups opens it from a Friends
button in its toolbar, and Settings → Friends & privacy links to it (Apple audit, 2026-10-22,
APL-043). It opens on Board; Lately is its second view (BOARD-002, below). Lately is one quiet row
per friend, title and day ("Ana watched 3 episodes, up to S1 · E3 Severance", "Today"), with the
poster, and Earlier for more. No unread badge and no push: you visit it. Below come Invite,
requests, friends and blocks.

A friend's profile is shelf first, like visiting someone's shelf. A monogram, their name in the
display face, "@ana · Friends since October 2026" and "42 films · 12 shows · 8 books". Then
Watching (covers with "S2 · E4" or "Page 120"), a "You both" card (titles you both want, how many
you both finished, what they loved that you haven't), and Recently finished with their stars. A
friend who hides their library shows only the header and one line saying so.

Interactions stay small (SOC-006/007). A friend's row in Lately takes one of six reactions
(❤️ 😂 😮 😭 🔥 👏) from a small "+" (a menu on Apple); counts sit under the row, yours ringed in
accent, and your own rows show what friends left. A title page and a friend's profile offer
Recommend: pick friends or a title, add a note of up to 140 characters. What friends sent you sits
at the top of Friends, "For you from friends", with Add to Plan to watch and Dismiss. A profile
also offers Invite to a group, through the group invites that already exist.

### Invites (SOC-002, pulled forward 2026-10-21)

A friend invite is a letter, not a growth hack. The page or sheet it opens shows the mascot
medallion, "{Name} invited you to Aaru." in the display face, their handle, and, when the
invite carries a title, its poster with "Watch Arrival with me." and a switch to add it to Plan
to watch (on by default; the friend's tap is the consent). One ink button: Join Aaru when signed
out, Add {Name} as a friend when signed in. One line under it: your library stays private,
only friends see it. A spent, expired or revoked link says so plainly, with no detail about why.

The sender invites from Friends: "Invite a friend", or "Invite to watch something together"
through the title picker. The link opens the share sheet (copied to the clipboard on desktop
web), and open invites list what they say, the days left, and Revoke.

### Board (BOARD-002, 2026-10-23)

The Board lives on Friends, not in a Social tab (owner, 2026-10-23; the spec's tab is dropped).
Friends opens on **Board**; a `Board | Lately` segmented control holds Lately (For you from
friends, activity, leaderboard, Invite, requests, friends). No nav rename, Groups untouched.

- **Composer.** An inline box at the top of Board that grows on focus: no floating button, no
  dialog. It offers + Title, half stars, the spoiler choice, and, once a title is chosen, a
  one-line review effect ("Adds Severance to Watched, ★4½"; "Watched, or Watching if it's still
  airing" for a show; "Updates your rating. Its status stays." for a title already in the
  library). `@` suggests your friends; there is no `@aaru` until BOARD-004. It also starts
  with a title from `/app/friends?title=<library item id>`, which is where "Write about this" goes.
- **Post rows.** Author, day, words, the attached title with its stars, Upvote and the comment
  count. The poster is not a link: title pages are library items and a friend's title is
  usually not yours, so friends' posts carry "Add to my library" instead. A spoiler sits behind
  `SpoilerVeil`; the author never sees a veil.
- **Recent / Top this week.** Recent is the default and pages with "Show older"; Top this week is
  one ranked page.
- **Empty.** The owl: no friends points to Invite (in Lately); friends with no posts says it is
  quiet. The composer stays either way.
- **Post page** (`/app/friends/posts/$postId`). The post, the upvoters' names beside the Upvote
  button, then the thread: comments with one level of replies. Reply is a visible button; when
  answering a reply it prefills `@name`. A deleted comment with replies reads "Comment deleted"
  in muted text with its replies still under it. Menus: Edit, Delete and Report on a post;
  Delete sits in a comment's ⋯ menu.
- **From friends on a title.** After the notes on a title page: up to five post rows about this
  title and "Write about this" (to Friends with the title in the composer). Hidden when there
  are no posts and no friends.

### Achievements (GAM-001…005, WID-007, pulled forward 2026-10-22)

Achievements are a shelf of medallions you fill by living with your library, not a game layered
over it. Calm first: nothing shouts, nothing counts down at you.

- **Where it lives.** Achievements is not a destination (like Recap and Listens). It opens from
  the Home strip (`StreakBar` with the level), the "You" card at the top of Friends, and
  Insights. Web: `/app/achievements`. Apple: pushed from those three.
- **The page.** Level and points to the next level on top, then `StreakBar`, then the badges by
  family (Films, Shows, Anime, Books, Music, Ratings, Lists, Imports, Discovery, Streaks,
  Social). Earned medallions first in each family, then the rest with "62 / 100" under them.
  A hidden badge not yet earned is a blank medallion reading "???" with no hint. "How you
  earned it" opens the points ledger, newest first.
- **Medallions.** A round mark with the badge's glyph. Tier 1 a Stone ring, tier 2 an Ink ring,
  tier 3 a gold hairline, tier 4 a double gold hairline (the Mindspace gold rule: gold is edge
  light and never fills). Names in the display face; tier as "Bronze · Silver · Gold · Platinum" in a
  small eyebrow. Unearned medallions are Stone at reduced contrast that still passes AA for
  their text.
- **The unlock.** A quiet toast at the bottom (web) or top (Apple): the medallion, "Night Owl ·
  earned", tap to open the shelf. A success haptic on iPhone. Reaching a badge's top tier gets
  one full card, once, with the medallion settling into place (`motion/mini` on the web, a
  spring on Apple; a cross-fade under Reduce Motion). Several at once collapse into one toast
  ("3 badges earned"); an import or the first-run backfill is always one summary ("Your history
  earned you 14 badges"). No push.
- **On a friend's profile.** Under the header: level and a single row of their most recent
  badges, "See all" for the rest (`BadgeShelf`). Hidden when they turned the switch off; badges
  about notes and owned items are never shown.
- **The board.** On Friends, "This week": you and friends who joined, ranked by this week's
  points, your row marked. Before you join, one card explains it and offers "Join the board".
  No global board, no all-time board.

### Groups (GRP-004/005, pulled forward 2026-10-20)

A group is a small, private place where friends talk about what they watch and read. It is
shaped like a Discord server, with Aaru's calm: a few people, a few channels, and titles as the
thing being talked about.

**Layout.**
- **Desktop web and Mac:** four columns. `GroupRail` (monogram circles, an unread dot, a
  mention count, `+` to create), `ChannelList` (group name with its menu: invite, settings,
  mute mentions, leave; channels grouped by kind), the channel (`MessageList` with its composer), and
  `MemberList`, which folds away.
- **Tablet web and iPad:** the rail and channels share one sidebar or drawer.
- **iPhone and phone web:** a stack, groups → channels → chat. Members open as a sheet from the
  header.

**The channel.**
- The header carries the name, the topic and a quiet "Not end-to-end" chip. Never hide it.
- Messages are flat rows, not bubbles. A run by one author within five minutes shares one
  name and monogram. Days get dividers, and a thin accent line marks where you stopped reading.
  Scroll stays pinned to the bottom, and "Jump to present" appears when you scroll up.
- Each kind has its own header. `title` shows the `TitleCard` and, for members who opted in,
  where they are. `shelf` shows the shared list. `watch` shows the `WatchPanel`. `text` shows
  only the topic.
- A message the reader is not caught up to sits under a `SpoilerVeil`: blurred, with "S2 · E5"
  and a tap to reveal. It never shows a spoiler by default.

**Composer.** One box, auto-growing. Enter sends and Shift+Enter adds a line. `@` suggests
members, with Aaru first, wearing the owl. A sent message appears at once, dimmed until
the server confirms, and gets a retry if it fails.

**Aaru in a group.** Aaru speaks only when tagged, as a member row with the medallion. While
it works, the owl breathes in its row ("Aaru is thinking…"), never bouncing dots. Its answer
is short text plus catalog cards (`TitleCard`, `CalendarRow`, `Shelf`). Every button on a card
acts for whoever taps it. Aaru never adds anything for the group on its own.

**Empty and first run.** No groups yet: one sentence, "Make a place to talk with friends,"
plus Create, plus any pending invites. A new group opens on `#general` with an invite prompt
in the channel.

### Recap (`RecapStory`, GAM-006a, pulled forward 2026-10-16)

Spotify Wrapped's shape, Aaru's calm. One full-screen card at a time: intro, time watched,
episodes with a month (or day) bar chart, the top title, the top five, what was finished, the
longest run of days, ratings, the first and last title, and a summary that shares an image.
A card with nothing to say is left out, and an empty period gets a sentence, not a story.
Backdrops cycle Ink, accent and Surface; type is the display face.

The Year in Review (GAM-006e, 2026-10-21) adds, for a year only: the biggest day after the
episodes chart; a soft glow of the top title's own poster behind it (blurred, on screen only);
the top three genres after the top five (a month gets this card too); where the time went by
kind; and a persona card before the summary, one of six words the server picks by rule from
the user's own numbers (The Binger, The Bookworm, The Anime Devotee, The Completionist, The
Explorer, The Steady One; copy is the owner's to approve). Year order: intro · time · episodes ·
biggest day · top · top five · genres · kinds · finished · run · ratings · bookends · persona ·
summary. The share image adds the top genre and the persona, stepping its type down a size past
five lines; still no posters.

"On repeat" (MUS-008, 2026-10-21) follows the top five, month or year, only when the period has
listens: the top artist large, "N plays · H hours", and that artist's three most played tracks.
The share image and the persona ignore music, and a period with listens but no library activity
still gets no story.

Motion rules (the first written ones; they hold for any later surface):
- Entrances only. Elements rise in once on a short stagger, numbers count up once, bars grow
  from the baseline once. Nothing loops, pulses or bounces after it lands.
- Cards advance on their own every 6 s; a hold pauses, a tap on the left third goes back.
  Keyboard: arrows, space, Esc.
- **Reduce Motion** (iOS setting, `prefers-reduced-motion` on the web): no count-up, no growth,
  no auto-advance; cards cross-fade and wait for a tap.
- The share image carries only the user's own numbers and the brand, no posters, so the web
  canvas and the Apple renderer draw the same card. Nothing is shared without a tap.

On the web, one component library, then performance:
- **shadcn-solid on Kobalte, every component (owner, 2026-10-21).** This reverses the
  2026-10-20 "native HTML first, Kobalte measured and dropped" rule. All 46 shadcn-solid
  components live as source in `aaru-client/src/components/ui` (Kobalte, plus corvu, embla,
  cmdk-solid, somoto, unovis and solid-table where the registry uses them) and are imported
  only through the `~/components/ui` barrel. One `cn` (`tailwind-merge` + `clsx`, in
  `~/lib/utils`), `cva`/`cx` as the registry ships them (`~/lib/cva`). shadcn's CSS variables
  are Aaru's tokens, so `bg-primary` is the accent and a menu's highlighted row is accent with
  on-accent text, the way a system menu highlights; Aaru's own looks (pill buttons at 44 pt,
  `quiet`/`ink`/`soft`, segment chips) are variants on those components.
- **Enter and exit from `tw-animate-css`.** Kobalte overlays animate with its
  `data-[expanded]:animate-in` / `data-[closed]:animate-out` classes. With reduced motion a
  global rule in `styles.css` turns every one of them off (and the components' transitions),
  so Kobalte unmounts at once. Page entrances stay CSS keyframes.
- **Measured (2026-10-21, gzip):** every page's shared JS 72.0 → 83.7 KB (+11.7), `/app`
  95.3 → 115.4, `/app_/week` 88.8 → 111.5, `/app_/settings` 75.4 → 95.5, `/app_/title/$id`
  88.3 → 125.4 (the heaviest, with Kobalte's ToggleGroup, Switch, Dialog and somoto), all JS
  247.5 → 291.5, CSS 13.9 → 25.2. Accepted by the owner. Without `"sideEffects"` in
  `package.json` the barrel did not tree-shake and every page carried 152 KB; keep it.
- **Motion only for what CSS cannot do:** an exit before an element leaves, siblings sliding
  into the gap (FLIP), direction-aware swaps, and one short scale pop when the user ticks an
  episode (never on load). Through `src/lib/motion.ts` on `motion/mini`, only `transform` and
  `opacity`, and nothing at all with reduced motion. Pages that only ask whether motion is
  reduced import `src/lib/reduced-motion.ts`, so they do not load `motion/mini`. Every
  animation follows a tap, so `motion/mini` is never preloaded: it loads when the browser is idle.
- `npm run size` holds every route to `size-budget.json` in CI.
- **One choice of a few is a radio group.** Every one-of-N switch (a view, a kind, a period, a
  layout, a status picker) is `Segmented` (`src/components/Segmented.tsx`, `pill` or `chip`) on
  shadcn-solid's SegmentedControl: "radio, 2 of 3", arrows move the choice, a second tap never
  clears it. There is no ToggleGroup; a real on/off is a Switch or a Checkbox.
- **Overlays play their exit.** A dialog, sheet or drawer takes `open` and stays mounted on its
  last value (`lastShown` in `src/lib/presence.ts`) while Kobalte plays the close, then the page
  lets it go. None is mounted only while open.
- **Raw controls are a lint error.** `button`, `input`, `select`, `textarea` and `dialog` come
  from the barrel. The one exception is the router's default error page, which spells out the
  primary button so every page's first load does not carry Kobalte and tailwind-merge; for the
  same reason `cardClass` sits in a module with no imports.
- **Measured after step 2 (2026-10-22, gzip, against `main` with its query cache):** shared
  77.4 → 79.1 KB, the landing page 86.0 → 88.7. A signed-in page's first load (shell included,
  cached across navigations): Home 99.1 → 156.7, Title 93.0 → 161.4, Calendar 92.2 → 140.1.
  The per-route table and the follow-ups are in `docs/audit/web.md`.

## 18. Navigation and Settings (owner, 2026-10-21)

Same names, same order, on every platform. Findings that led here and the work list for each
client: `docs/audit/ux.md`.

**Destinations.** Home · Discover · Library · Calendar · Lists · Groups, then, set apart at the
bottom, Insights and Settings.

- **Web.** One shell for every `/app` page. At 1024px and up a persistent left sidebar
  (collapsible to icons): the wordmark, Search (⌘K; opens in place on every page), the six
  destinations with Friends between Lists and Groups (its own page since SOC-003, owner
  2026-10-21; it opens on Board, and Lately is its second view), a gap, Insights, Settings,
  and last the account row (name and @handle, opens Settings → Account). Groups carries the
  mention count. Below 1024px a top bar (wordmark,
  Search, menu) opens the same sidebar as a sheet. No page draws its own header or nav. Detail
  pages (a title, a list, an import, a channel) sit inside the shell with a back link that
  names where you came from. Sign out lives on Account only.
- **iPad.** The `sidebarAdaptable` sidebar: the seven (Friends between Lists and Groups), then a
  bottom section with Insights and Settings.
- **Mac.** The same sidebar without Settings: Settings is the Settings scene (⌘, and the app
  menu) and nothing else. A Go menu switches the eight rows with ⌘1…⌘8.
- **iPhone.** The tab bar holds five: Home · Discover · Library · Calendar · Groups. A sixth tab
  would push Lists, Groups and its badge behind More. Lists opens from Library (a "Lists" row on
  top and in the toolbar) and from Home's lists; Friends from a Friends button in Groups'
  toolbar and from Settings → Friends & privacy; Insights from Home's Last 7 days and Library's
  More menu; Settings from an account button (`person.crop.circle`, top trailing on Home and
  Library), presented as a sheet with Done.

**Names.** Calendar is the destination; Week, Month and Missed are its modes. The web URL is
`/app/calendar` (`/app/week` redirects). Home's nav label stays Home and its page heading "The
Field" (§1). Recap is not a destination: Insights plays it ("Play as story"), Home offers it in
its window, Your data keeps the shortcuts. The listen log is **Listens** ("All listens ›" from
Insights and Library's More menu), never "Music", which is the albums kind. An agent's plan is
"Waiting for you" on Home and "Request" when a push opens one. In groups, a `shelf` channel
reads **List** and a Room reads **Watch party**: UI labels only, the stored kinds and code names
stay `shelf` and `watch` / Room (owner, 2026-10-21).

**Settings: eight pages, in this order.** Each is its own page; none scrolls into the next. A
new import source or connected app joins its page; it never gets a page of its own.

| # | Page | Web slug | Sections, in order |
| --- | --- | --- | --- |
| 1 | Account | `account` | Name and handle (one editor) · Favorites (a top 10 per kind, FAV-001) · Signed in with, Link Google · Aaru Plus (state; buy and manage on Apple only) · On this device: Appearance (System / Light / Dark) · Sign out |
| 2 | Friends & privacy | `friends` | Add a friend · Asking you · Waiting on · Friends · Blocked · Show my badges and level to friends · Join the weekly friends board (2026-10-22) · Location: Concerts near, Remove (only while concerts are on). Footer: "Friends find you by your exact handle. Nobody can search or browse for you, and your library stays private." |
| 3 | Notifications | `notifications` | New episodes · Mentions in groups · Group invites · this browser's alerts (web). Footer: "Requests from your connected agents always alert you." The switches are per account, so the Mac shows them too: "Alerts go to your iPhone and your browsers." |
| 4 | Import | `import` | Trakt · Bring your history, in `CLAUDE.md`'s import order: Stremio history, IMDb, Letterboxd, Goodreads, Pogdesign CAT, Netflix, MyAnimeList, AniList, Any other CSV · Imports (the jobs; "No imports yet." when none) |
| 5 | Connections | `connections` | Agents: the picker (Claude, Claude Code, Codex, Hermes, Gemini CLI, other MCP client, Browser extension) and live connections · Stremio: the addon, with "Import your Stremio history" linking to Import · Music: scrobblers, the last listen → Listens. One verb: Disconnect |
| 6 | Your data | `data` | Recaps: this year, last month, last year · History: every journaled action, newest first, by whom (you, an import, a connection), with Undo · Export: Everything (JSON), Library spreadsheet (CSV) |
| 7 | About | `about` | Wordmark, version, channel (Apple) · Credits · Privacy policy, About Aaru, Contact |
| 8 | Delete account | `delete` | One sentence on what goes, a link to Your data → Export, **Delete account** in danger styling; confirm "Delete account?" with **Delete account and library** / Keep it |

Where each existing piece goes:

| Page | Web (`aaru-client/src`) | Apple (`aaru-ios/Aaru`) |
| --- | --- | --- |
| Account | `AccountPage`: `ProfileEditor` (handle and name), `FavoritesEditor` (kind chips, move up/down, remove, Add through `TitlePicker`), Signed in with + Link Google, Aaru Plus (`plusLine`), `AppearanceSection`, Sign out | `AccountSettings` first section; `PlusSection` + `PlusPaywall` (`Aaru/Plus`); `ProfileEditor` from `Social/FriendsView.swift`; `AppearancePicker` (off the Settings root and the Mac "General" pane) |
| Friends & privacy | `FriendsCard` (handle, the way to `/app/friends`, Show my library to friends); `ConcertPlaceSection`. The friend lists (`FriendsSection`, with `InviteFriends`) live on `/app/friends` | `FriendsPage` (`Social/FriendsView.swift`): handle, a Friends row that opens Friends (`router.showFriends()`), Show my library to friends; `ConcertPlaceSection`. The friend lists, invites and requests live on Friends (`FriendsScreen`), as on the web |
| Notifications | `NotificationsSection` | `NotificationsSection`, out of `AccountSettings`, on iOS and Mac |
| Import | `ImportsPage`: `TraktImport`, `StremioHistoryImport`, `FILE_SOURCES` tiles, `CatImport`, the AniList form, the jobs list → `/app/imports/$id`. Trakt returns to `/app/settings/import?trakt=` | `ImportsSettings` without `ExportDataSection`: `TraktSection`, the history section, `CATImportSheet`, `StremioHistoryImport`, the jobs → `ImportDetailView` |
| Connections | `ConnectionsSection`, `StremioSection`, `MusicSection` | `ConnectionsSection` (+ `ConnectionSetupView`, `BrowserExtensionView`), `StremioSection`, `MusicSection` (from `ConnectedAppsSettings`) |
| Your data | `_shell.app_.settings.data`: recap shortcuts, History (`/v1/actions`, Undo per action), Export | recap shortcuts (`RecapDeck`'s, now also in Library's menu); `ExportDataSection`; History (new) |
| About | `_shell.app_.settings.about`: wordmark, `Credits`, links | `AboutView` without the delete section |
| Delete account | `_shell.app_.settings.delete` with `ConfirmDialog` | `AboutView`'s delete section and dialog |

**Presentation.**

- **Web.** `/app/settings/<slug>` under the settings layout. A desktop sub-nav lists the eight,
  Delete account last after a divider in danger text; `/app/settings` redirects to `account`.
  A phone shows the list with one hint line per page and each page has "‹ Settings". Old slugs
  redirect: `imports` → `import`, `connected` → `connections`, `recaps` → `data`.
- **iPhone and iPad.** The system Settings shape: a grouped list of `NavigationLink`s, each
  symbol in a small tinted square. The account row on top (name, how you sign in) opens
  Account; then Friends & privacy (`person.2.fill`), Notifications (`bell.badge.fill`); then
  Import (`tray.and.arrow.down.fill`), Connections (`app.connected.to.app.below.fill`), Your data
  (`externaldrive.fill`); then About (`info`); then Delete account alone, its title in danger.
  `aaru://settings/<slug>` opens a page, so an empty state can send you to its fix.
- **Mac.** The Settings scene is a `TabView` of seven panes in the same order: Account, Friends
  & privacy, Notifications, Import, Connections, Your data, About. Delete account sits at the
  bottom of the Account pane under a divider; a pane holding one destructive button is not a
  Mac pane.

**What changed from the plan, and why.**
- iPhone keeps five tabs (above). Lists, not Groups, moves: the Groups badge must stay visible,
  and a list is a view of the library. Owner confirmed, 2026-10-21.
- Appearance had no page: it joins Account as "On this device", and the Mac "General" pane goes.
- "Concerts near" moves from Account to Friends & privacy → Location: it is the only place Aaru
  stores where you are.
- Connections also holds the Stremio addon and music scrobblers: they reach Aaru with a token,
  as agents do. Stremio *history* stays in Import.
- Insights leaves Settings for the sidebar. Your data keeps the recaps as shortcuts and gains
  History, which every "undo it from your history" line already promises. History (with Undo)
  and Remove from library on the title page are built in this pass on web and Apple (owner,
  2026-10-21).
- TV Time joins Import, in its `CLAUDE.md` place, when its import lands (separate PR, with a
  Bingers import).
- On the Mac, Delete account folds into Account and Settings leaves the sidebar.
- The web Calendar route follows its name.

**Apple, as built (audit, 2026-10-21, `docs/audit/apple.md`).**

- **Shell.** iPhone: the five tabs and nothing else in the tab bar (no More; Lists inside Library,
  Friends inside Groups), an account button (`person.crop.circle`, top trailing on
  Home and Library) that presents Settings as a sheet with Done. iPad and Mac:
  `.sidebarAdaptable` with every destination, Insights (and Settings on iPad) in a bottom
  section. One catalog search sheet at the root, opened by each screen's Search button and ⌘F.
- **States.** A first load that fails shows `LoadFailedView` (the reason and Try again), never an
  empty state; an empty state shows only after a load succeeded. Panels above a group chat use
  the compact `PanelLoadFailed`. Later failures keep what is on screen and show the
  `ProblemBanner`, a button that dismisses.
- **History.** Your data → History: the journal newest first, who made each change (you, an
  import, a connection, Aaru), when, and Undo with a confirm; undone rows are struck through.
  An applied import or agent request links "See it in History" / "Open History".
- **Remove from library.** Library's context menu and the title room's More menu, confirmed:
  "Its status, rating, notes and progress go with it. You can undo this in Settings → Your
  data → History." Afterwards a ribbon offers "Undo in History".
- **Library.** On iPhone a Lists row tops the grid and the rows, and the toolbar has a Lists
  button. Layout reads Grid / Rows; More holds Insights, Listens and Recaps. A new account sees
  "Your library is empty" with Search and "Bring your history"; with filters on, "No titles
  match these filters" with Clear filters.
- **Lists.** A split view on iPad and Mac ("Choose a list" until one is picked), a stack at
  compact width. Deleting a list is confirmed. Members not in the library have an Add control
  (tap: Plan to …, hold: pick a status). The picker is titled "Add “X” to a list" and marks the
  lists that already hold it.
- **Calendar.** `CalendarEmptyState` on every view, with Clear filters when filters hide
  airings. The episode sheet has Done. On iPhone the Week / Month / Missed switch sits under
  the bar, which holds Today and the week arrows. On iPad, where the bar is shared with the
  tab bar, a row over the grid steps by week and day. The Mac's toolbar holds all five. Keys:
  ⌥⌘←/→ week, ⌘←/→ day or month, ⌘T today.
- **Home.** One empty headline, "Add something to see what's next", with Search, Browse
  Discover and "Bring your history". Airing soon opens the episode sheet, with "Open show".
  One column below 760pt. The Live Activity item reads "Watching now…" here and in the title
  room's More menu, which also holds "Discuss in a group…" and "Remove from library…". Albums
  are not in Start watching.
- **Groups.** The `shelf` channel kind reads **List** (`list.bullet.rectangle.portrait`), the
  `watch` kind **Watch party**; code names stay. The shared list shows the channel header with
  "Not end-to-end", and the header's popover adds the `@aaru` line when the group has it.
  Discuss in a group lists every group: Open, Start (managers) or "An admin can start one."
  The owner's menu has "Leave group…", which explains handing the group on first. In the split
  view Members is always the inspector.
- **Words.** One episode code, "S1 · E8"; "S01E05" only in the week grid's cells. Discover's
  credit is "Rows from" the providers on screen, and no error names a vendor. Listens is
  "Listens", linked as "All listens ›", with 7 days / 30 days / Year / All time and a
  "Connect a scrobbler" button when empty.

---

## Component catalog the agent may emit

Build these as SwiftUI views. The model only returns their names and props.

| Component | Job |
| --- | --- |
| `TitleCard` | Add / status / owned / rating |
| `SeasonMap` | Episode heat + bulk tick |
| `PlanCard` | Preview of a mutation |
| `JobLedger` | Import or bulk progress |
| `TonightStrip` | 1–3 next actions |
| `Shelf` | Filtered library page |
| `CalendarMonth` | Your airings |
| `MatchTable` | Import reconciliation |
| `UndoRibbon` | Last agent write |
| `WeekGrid` | Seven-day airing grid, check in place (Phase 2) |
| `ContinueRow` | In-progress titles with time left (Phase 2) |
| `StartRow` | Wishlist titles with runtime (Phase 2) |
| `CalendarRow` | Next airings with relative badges (Phase 2) |
| `NowPlayingCard` | Current watch, progress, ends at (Phase 2) |
| `DiscoverRow` | Public provider rows to add from, not library items (DISC-001, 2026-10-20) |
| `UnfinishedRow` | Dropped or stalled items with a resume point (2026-10-20) |
| `StreakBar` | Current streak and week ticks (Phase 5) |
| `FriendStories` | Friends' watches today (Phase 4) |
| `BadgeShelf` | Earned badges (Phase 5) |
| `StatsPanel` | Insights: month, year or all-time numbers (GAM-006c, 2026-10-20) |
| `ProfilePanel` | Profile: all-time numbers from the library as it is (GAM-006b, 2026-10-22) |
| `RecapStory` | A month or year as a story (GAM-006a) |
| `WatchPanel` | Watch-together session in a group (was `RoomPanel`) |
| `ConversationView` | E2E conversation (Phase 6) |

`VIEWS.md` is the authoritative list, with props and the reason each one was added.

If the model wants something else, refuse and pick the nearest catalog piece. That keeps Aaru
looking like Aaru.

---

## Visual references (steal tone, not layout)

| Look at | Take this |
| --- | --- |
| Apple Music / TV | Up Next, now playing, huge artwork, almost no chrome |
| Letterboxd | Diary as a feeling, lists as identity |
| Serializd | Season/episode as the real unit |
| Things 3 / Craft | Calm density, one obvious compose box |
| Pogdesign CAT | Month-as-object, your shows only; the dense week grid with a check per cell |
| Trakt (web, 2025 redesign) | Continue / Start rows, time-left and "Finale" badges, streak bar, "Today" friend stories, now-playing card |
| MyAnimeList / AniDB | Profile stats as identity; anime as its own catalog with precise episode data |
| Sequel | Widget range, interactive mark-watched |
| Cursor / Copilot canvases | Plan → work → artifact, not chat log |
| Linear | Command palette as a peer of the mouse |

### Brand (owl poster, owner 2026-10-22)

The standard is the poster `docs/brand/source/owl-poster.png` ("Aaru Owl: Your stories. Your
world."). It supersedes the teal bird, the reeds and the heron. Every client follows it; when a
branch conflicts with main on a brand file (`design/tokens.json`, the generated tokens, colour
sets, brand assets), main wins.

- **Palette.** Night navy (`paper` dark `#0e141e`), silver-white ink, **ice blue** as the accent
  (the hologram's colour: actions, links, selection, focus) and **amber** as `gold` (the star and
  the owl's glow: edge light only). Light mode is derived from it: silver-white paper, navy ink,
  deeper blue and amber that pass AA. Dark-first in the art; both follow the system unless the
  Appearance setting pins one.
- **Type.** The system sans for everything (SF Pro on Apple, `system-ui` on the web), headings
  set apart by weight and size. No bundled or serif faces. The wordmark is the poster's geometric
  "Aaru", used as artwork, never set in a font.
- **Mark and icon.** The A with the amber star and the swoosh. The app icon is that mark on
  night navy.
- **Mascot.** The white and amber robot owl, always on the `night` disc (the poster's sky, the
  same in both appearances, so the white owl reads). Its head on the same disc is the agent's
  mark (`OwlMark` on the web, `Image(.owlMark)` on Apple): it breathes slowly while Aaru works
  and holds still under Reduce Motion.
- **Where the owl lives (owner, 2026-10-23).** Signed-out surfaces, and in the app: beside
  "The Field" on Home, in screen-level empty states (`OwlEmpty` / `OwlUnavailableView`, never
  inside a picker, a filter result or a settings row), on errors, the 404 and the load-failed
  view, on the recap cover, on an earned badge. Never on a plan card, which an outside
  connection wrote.
- **Poses.** Standing (the poster's owl) by default; **curious** when nothing matches (search,
  the 404), **sleeping** when nothing airs or you are caught up, **celebrating** for a
  milestone (the badge reveal, the unlock summary). One owl, four poses: never a new
  character, and no pose is invented in code. Two motions, never both at once: the
  **breath** means Aaru is working; **idle** (a slow float and an amber glow behind the eyes) is
  the owl at rest, on Home and empty states only. Errors and recap cards stay still. Under
  Reduce Motion the owl never moves.
- **Tagline.** "Your stories. Your world."
- **Enforced.** `.github/workflows/ci-brand.yml` runs `scripts/generate-tokens.mjs --check` and
  `scripts/brand-guard.sh`: no colour literals outside the generated tokens, no serif or bundled
  faces in any client.

Assets and how they are made: `docs/brand/README.md`. Colour tokens (`Paper`, `Surface`,
`Stone`, `Ink`, `Muted`, `Medallion`, `Night`, accent, `OnAccent`, `Gold`, `Line`,
`LineStrong`, `Scrim`, `OnScrim`, `Danger`) are generated into the asset catalogs,
`aaru-client/src/tokens.css`, the extension's popup and the PWA manifest's two colours from one
file, `design/tokens.json`. There is one amber: the `agent` token merged into `gold` on
2026-10-23 (the two were 1.1:1 apart). By night the hairlines (`line`, `line-strong`) are ice
blue, the poster's hologram edge, so a card separates from the page without a shadow; by day
they are navy ink. `scrim` is a navy veil in both appearances (over artwork, behind floating
layers) and `on-scrim` the light text on it. `medallion` is the silver disc under avatars and
kind marks; the owl sits on `night`. The marks and icons come from `docs/brand/owl_poster.py` (BRD-002), the owl
and its head from `docs/brand/owl_mascot.py` (BRD-003). The guard rejects the retired heron and
reed mark by name.

### Mindspace (visual language, 2026-10-21; palette and type replaced 2026-10-22)

Aaru is a constructed room for stories, lit at night: navy dark, ice-blue light, amber edges.
Calm and editorial first; the uncanny is a texture, never an effect. No glitching or "broken
AI" UI.

- **One token source.** `design/tokens.json` holds every colour, light and dark, plus the
  pairs that must pass WCAG AA (4.5 text, 3 non-text). `scripts/generate-tokens.mjs` writes
  `aaru-client/src/tokens.css`, `src/lib/tokens.gen.ts`, the extension's popup tokens and badge
  values, and the colour sets in both Apple asset catalogs, and fails on a pair below AA; CI runs
  it with `--check`. A translucent token is checked as the colour it composites to. **Gold**
  (amber) is edge light only: hairlines, the next-up ring, stars, the active-nav mark, the
  owl's glow while Aaru works and the dot on a plan card. It never fills a surface and never
  carries text. Text on an accent fill is **on-accent**, never white (2.4:1 on the dark
  accent). No pure black.
- **One scale source (2026-10-23).** The same file holds the radii (card 20, panel 14, field
  10, row 8, thumb 6, pill), the tint steps (tint 0.08, wash 0.15, ghost 0.25, half 0.5),
  the motion (fast 150, base 240, slow 420 ms; one ease-out curve, `cubic-bezier(0.2, 0.7,
  0.2, 1)`) and the 4 pt spacing grid (4, 8, 12, 16, 20, 24, 32, 40, 48). The generator
  writes them as `aaru-client/src/tokens.theme.css` (`rounded-card` … `rounded-pill`,
  Tailwind's `sm`…`xl` remapped to thumb/row/field/panel, `ease-aaru`), `--motion-*` and
  `--alpha-*` variables, `RADIUS`/`ALPHA`/`MOTION` in `tokens.gen.ts`, and
  `AaruRadius`/`AaruAlpha`/`AaruMotion`/`AaruSpace` in `Tokens.gen.swift` for the app and the
  widgets. A radius, tint, duration or padding outside the scale is a review comment. Apple
  corners are always `.continuous`. Web spacing is Tailwind's 4 px scale. Widgets read the same colour sets (their own catalog carries every role) and mark their glyph and title `widgetAccentable`, so the tinted Home Screen and vibrant Lock Screen modes still read.
- **Elevation.** Flat: Paper, Surface and Stone separate by tint and hairline, never by
  shadow. One `lift` (a line-strong ring and a soft navy shadow) belongs to layers that float:
  menus, popovers, dialogs, drawers, toasts, a dragged card. Gradients exist only as a glow
  (accent or gold, radial, fading to transparent) or a scrim. Never a gradient fill or gradient
  text, never glass by default.
- **Appearance.** System, Light or Dark, per device. The web keeps it in the `aaru_appearance`
  cookie and renders `<html data-theme>` on the server, so nothing flashes; Apple keeps it in
  `@AppStorage("appearance")` and applies `preferredColorScheme`. Widgets follow the system. The PWA manifest's two colours are the dark paper (an installed app's splash is one colour, so it is dark-first in both appearances); the browser's `theme-color` follows the paper.
- **Type.** The system sans. Titles and headings use `--font-display` on the web and
  `Font.aaruDisplay(_:)` on Apple (relative to a text style, so Dynamic Type scales it); widgets
  use `Font.widgetDisplay` for their one heading. Small uppercase eyebrows (tracked 1.5) over
  sections. Dates, `S·E` codes, counts and ratings use tabular figures. On the web the
  eyebrow is the `.eyebrow` class and nothing else (12 px, 600, 0.12 em; `text-2xs` for the
  smallest); the sizes are Tailwind's plus `text-2xs` (11 px, badges) and `text-md` (15 px,
  message bodies), never an arbitrary `text-[…]`; tracking is `tracking-tight` on display
  text, `tracking-wide` on shortcut hints, and the eyebrow's. Motion durations and the curve
  come from the motion tokens; the landing hero's 700 ms `rise` is the one longer entrance,
  and the signed-in app has no page-load choreography. Under Reduce Motion every transition
  is instant and every entrance is a cross-fade; only the loading spinner still turns.
- **Badges.** Premiere and new season are accent, Finale is ink, both under Paper text (the web's
  `accent` and `ink` badge tones). Gold never carries small text.
- **Texture, on the Field and the Title room only.** Two faint pinstripes of different pitch
  (the room's "code"; the Title room seeds them from the title id), film grain on the web, a
  daypart wash that is warmer at dusk and cooler at night (`data-daypart`, set once before
  paint), a gold top edge on the one or two focal pieces (`edge-lit` / `.edgeLit()`), and a
  soft blue/amber chromatic edge on the focal art (`fringe`, web). All static: nothing animates.
  All gone under increased contrast, forced colours or Reduce Transparency. Every other screen
  is flat Paper with hairlines.
- **Agent presence.** Quiet: the owl's head on the night disc beside "Waiting for
  you" or an import that is matching, only while something is in progress, and still under Reduce
  Motion.

Research basis (2026-10-09): the user's screenshots of Trakt web home, Trakt "Today" stories
and the Pogdesign CAT weekly schedule, plus web research on tracker widgets and social
features. ScreensDesign was not used: its research tools need a Pro plan (DSN-001).

---

## Do not

- Make chat the only surface. Agents that only talk feel like support bots.
- Default to a 5-tab "Search / Movies / Shows / Books / Settings" movie app with an AI tab.
- Let the agent dump markdown tables of 400 titles. Emit a `Shelf`.
- Auto-write the library without a plan card on first-run imports.
- Copy ChatGPT's bubble stack. Aaru should feel like walking a field, not sitting in a ticket
  queue.
- Let an outside agent change the library without an approval inside Aaru. A push that says
  "done" instead of "may I" is the whole trust story, lost.
- Let capture skip the `MatchTable`. Extracted rows are guesses and are shown as guesses,
  even when there is only one.
- Ship social surfaces before the Phase 2 gate without a recorded owner's exception, or make
  any of them public by default. Private stays the default; friends are invited, never
  inferred. Groups have no invite links and no directory.
- Let Aaru speak in a group without being tagged, or blur a group message (server-visible)
  with a DM (end-to-end) in copy, icons or code.
- Build a global feed or a global leaderboard. Friends only.
- Award points for anything a user can undo and redo for profit. Points follow the ledger,
  not the tap.

---

## Next docs

- `VIEWS.md` — surfaces + component catalog, in build order.
- `ARCHITECTURE.md` §"Agent tools" maps each view to a server tool: `search_titles`,
  `read_library`, `plan_import`, `apply_library_patch`, `list_airs`. §"Outbound agent
  surfaces" covers App Intents, MCP, tokens, and remote approval.
- `docs/superpowers/specs/2026-09-07-agentic-surfaces-design.md` — why §11 and §12 exist and
  what they deliberately do not add.
