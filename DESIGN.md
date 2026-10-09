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
Mood: reed field at dusk, teal/gold, lots of air.

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
together. GitHub's canvas lesson: durable state, human gates.

## 4. Title room (deep artifact)

One title is a room, not a settings form.

- Left or top: poster, status chips, `isOwned`, rating.
- Center: **season map** — a heat grid of episodes (Serializd energy, calmer). The agent can
  paint a season in one move, then you tap to correct two episodes.
- Right or bottom: notes, "why it's here" (Trakt history 2023-11-02), next air date.

The agent is allowed to drop extra cards into the room: cast you actually care about,
"you left off S02E04", "book pairings."

## 5. Tonight

A nightly composed view. Not recommendations-as-a-product — a **short plan**.

> "You have 48 minutes. Episode of Slow Horses, or the last 60 pages of Piranesi."

Two cards, one reject, one "not tonight." The reject teaches the agent. This is the return
moment after an agent run.

## 6. The shelf (library as query, not as app section)

Library is a **saved question**.

- "Shows I own that are in progress"
- "Books finished in 2025"
- "Movies with no rating"

Each shelf is a named artifact. The agent creates them. You can pin them to The Field.
Classic filters are how a shelf is edited, not how you enter the app.

Visual cue: Letterboxd lists + Ryot filters, presented as pages of reeds rather than a
spreadsheet.

## 7. Catch-up calendar

You came from Pogdesign CAT. Steal the *feeling*, not the site.

Month canvas of **your** airings only. Agent highlight: "three premieres, one finale, you are
behind on two." Tap a day → episode cards with a single "watched" check.

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

## 10. Mac companion

On Mac, the agent lives in a **sidebar + inspector**, library in the middle
(Mail / Notes / Music pattern).

Menu bar: "log last episode", "what's on tonight", paste a list.

The Mac is where imports and shelves get built. iPhone is The Field + Tonight + check-offs.

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

Rows are the Field's artifacts, not new chrome. The composer still sits on top.

## 14. Week grid (Phase 2)

The `CalendarMonth` (§7) answers "what did I miss." The week grid answers "what is on this
week," and it is the closest Aaru gets to copying Pogdesign CAT outright, because that page is
right.

- Seven dense day columns, today highlighted, previous / next day paging.
- One cell per episode: banner art, show title, `S01E05`, episode name, network · local time.
- A checkbox on every cell marks it watched in place.
- State colours: watched (dimmed), premiere, finale, today, and new-season. Colours come from
  the brand palette, not CAT's yellow and red.
- Your shows only. No global schedule.

On Mac and web the grid is the default calendar view. On iPhone it collapses to a day list with
the same cells.

## 15. Now playing (Phase 2, live in Phase 3)

`NowPlayingCard`: art, `S1 · E8 · Episode`, a progress bar, "41m left", "Ends at 1:20 PM".
Tapping the bar flips between time left and end time. Set by a manual check-in in Phase 2 and
by scrobbles from Plex, Jellyfin or Stremio in Phase 3. The same data drives the Live Activity.

## 16. Widgets (Phase 2)

Widgets are where a tracker earns a daily glance. Sequel ships the richest set and the only
interactive mark-watched widget seen in the category. Aaru matches that and adds what nobody
ships.

- **Up Next** (S / M / L) — next unwatched episode per show. M and L carry an interactive
  "mark watched" button (App Intent, same write path as a tap).
- **Airing countdown** + Lock Screen accessories — next airing of a tracked show or anime.
- **Week** (L / XL) — the week grid in miniature, CAT style.
- **Now watching** Live Activity — Lock Screen and Dynamic Island, progress plus "Ends at".
- **Streak** (Phase 5) — current streak and this week's ticks.
- **macOS** — the same widgets on the desktop and in Notification Center. Almost no tracker
  ships Mac widgets.

Widgets read a snapshot the app writes. They never become a second client with its own logic.

## 17. Social surfaces (Phases 4–6)

Private by default stays. Everything below is opt-in, friends-only by default, and does not
ship before the Phase 2 gate.

- **Friend stories** (`FriendStories`, Phase 4) — Trakt's "Today" pattern: a row of friend
  avatars, tap into a full-height card per title a friend watched today ("Kevin · Watched S2 ·
  E9 · 12:11 PM"), with a bookmark to add it to your wishlist.
- **Profile and stats** (`StatsPanel`, Phase 5) — MAL-style numbers: days watched, episodes,
  mean score, genre and format breakdown, Year in Review.
- **Badges** (`BadgeShelf`, Phase 5) — discovery badges and milestone badges, tiered.
- **Leaderboard** (Phase 5) — friends only, weekly, opt-in. Never global.
- **Room** (`RoomPanel`, Phase 6) — watch together: countdown to "press play", who is in,
  reactions, drift from scrobbles ("Ana is 2 min ahead"), shared check-off at the end.
- **Conversations** (`ConversationView`, Phase 6) — end-to-end encrypted DMs. A lock and a
  safety-number check live in the header, not in a settings screen.

The feeling to protect: **social is a room you invite people into, not a feed you are fed.**

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
| `StreakBar` | Current streak and week ticks (Phase 5) |
| `FriendStories` | Friends' watches today (Phase 4) |
| `BadgeShelf` | Earned badges (Phase 5) |
| `StatsPanel` | Profile numbers (Phase 5) |
| `RoomPanel` | Watch-together room (Phase 6) |
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

Brand: teal → gold, paper-white or deep reed-green dark mode. The heron only as a quiet mark
when the agent is working (breathing reed, not a bouncing dots spinner).

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
- Ship social surfaces before the Phase 2 gate, or make any of them public by default. Private
  stays the default; friends are invited, never inferred.
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
