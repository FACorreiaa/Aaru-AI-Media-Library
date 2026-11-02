---
target: "web Home (the Field), re-run after #202-#214"
total_score: 25
p0_count: 0
p1_count: 1
timestamp: 2026-10-28T19-12-20Z
slug: aaru-client-src-routes-shell-app-tsx
---
## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 3 | Subline, import state and undo toasts good. The week still shows 3826 episodes and 3873h, left over from season ticks dated before #202; it rolls out of the window by about 1 Nov |
| 2 | Match System / Real World | 2 | "Start watching" holds wishlist books and manga; the week figures read as impossible; "The Field" heading vs "Home" in the nav |
| 3 | User Control and Freedom | 3 | Undo on every tick and verdict; verdicts explained before choosing |
| 4 | Consistency and Standards | 2 | Two heading systems (12 px eyebrow h2 vs 24 px display h2); two 7-day bar charts on one screen; link styles vary ("All 49", "See calendar", "Insights →") |
| 5 | Error Prevention | 3 | Season tick tucked in "…"; verdicts say their effect; capture waits for approval |
| 6 | Recognition Rather Than Recall | 3 | Clear labels; the card "…" shows on hover/focus only, but the tick stays visible |
| 7 | Flexibility and Efficiency | 2 | ⌘K and the row Skip help, but 24 tab stops reach Continue watching via the side column, and there is no "mark next" key |
| 8 | Aesthetic and Minimalist Design | 2 | About 11 blocks before Discover; the week drawn twice; the last row, Trending shows, is all "In your library" |
| 9 | Error Recovery | 3 | A failed tick reverts the card and shows an Alert; some messages are the raw error |
| 10 | Help and Documentation | 2 | Inline help is good (composer, verdicts); nothing explains the gold dot, levels and points, or "unmatched" |
| **Total** | | **25/40** | **Acceptable** (up from 23) |

## Anti-Patterns Verdict

**LLM assessment:** mostly not slop.
- The copy is specific and calm: "Today is still open", "Set aside for today", "From MyAnimeList · Imported, 4 unmatched".
- Tonight is a real focal object.
- Three tells remain:
  - The uppercase eyebrow sits on 8 or more blocks.
  - The week strip is the hero-metric template: four display numbers beside bars.
  - `.fringe` (styles.css:509) pairs a 1 px ring with a 48 px soft shadow.
- Below the Discover break, the poster rows with Add / ⌄ / List… still lean towards the generic poster-grid tracker.
- In light mode at dusk the nocturnal brand barely registers.

**Deterministic scan:** `detect.mjs` over `_shell.app.tsx`, the Home components, `achievements/` and `shell/` found 0 findings (exit 0). It caught nothing the review missed, and it missed the eyebrow density, the hero metric and the ring-plus-shadow pairing.

**Visual overlays:** none. The mutation preflight passed, but loading `localhost:8400/detect.js` from the HTTPS page timed out after 10 s, as on the last run (Chrome's Local Network Access gate). No prompt was accepted.

## Overall Impression

Better than three days ago.
- Tonight's two actions plus an explained "…", the Reading and Undo work, the three Discover rows behind a break, and the side column's one recipe all landed.
- The page now fails on structure, not content:
  - keyboard and heading order run through the side column before the user's rows;
  - the composer still sits above the one thing Tonight asks.
- Biggest opportunity: make the DOM order match the reading order, and let Tonight own the top.

## What's Working

1. **Tonight's "…" menu** (TonightStrip.tsx:104-146). Each verdict states its consequence ("Ranked lower for 14 days"), and the season tick is out of the primary row. Two visible actions, honest and undoable.
2. **Keyboard scaffolding on rows** (HomeRows.tsx:55-103). The "Skip <row>" on focus, focusable scroll regions named by their heading, and full tick names ("Mark Avatar: Seven Havens S1 · E1 watched").
3. **Copy discipline.** No streak pressure, sources named instead of file names, and one subline that says where you are. PRODUCT.md's voice, shipped.

## Priority Issues

**[P1] Keyboard focus is clipped and runs out of reading order**
- **What:**
  - Tonight's title link sits inside `h3.line-clamp-2` (overflow hidden), which clips its focus ring to a 1 px sliver (seen live; WCAG 2.4.7).
  - The side column (`contents` + `order-*`) comes first in the DOM, so Tab and the heading outline cover Achievements, Last import, five status chips and the lists (24 stops) before Continue watching (2.4.3).
  - The row Skip lands on an invisible span, and it is announced before the heading it skips.
- **Why it matters:** keyboard and screen-reader users meet the periphery first and lose sight of focus on the focal card.
- **Fix:**
  - Move `line-clamp` to an inner span, or use an inset ring.
  - Render the rows before the side column and place the column with grid.
  - Put Skip after the heading, and give its target a visible focus.
- **Suggested command:** `$impeccable harden`
- **Where:** TonightStrip.tsx:67-74, _shell.app.tsx:766-980, HomeRows.tsx:55-103

**[P2] The week is drawn twice and outshouts Tonight**
- **What:**
  - The week strip's numbers (`text-3xl`, WeekStripCard.tsx:36) equal Tonight's title size.
  - The side column's StreakBar draws a second 7-day chart about 400 px away.
  - The current 3873h comes from season ticks dated before #202 (going forward only, owner 2026-10-25). It leaves the window by about 1 Nov, but until then it reads as broken.
- **Why it matters:** the valley right after the peak, and the same week shown twice.
- **Fix:**
  - Drop the bars from one of the two, or fold the streak ticks into the week strip.
  - Bring the figures below the title size.
  - Optionally, a one-off backfill of the old season ticks to undated.
- **Suggested command:** `$impeccable distill`
- **Where:** WeekStripCard.tsx:31-66, achievements/StreakBar.tsx:45-67

**[P2] The composer takes the prime slot; Tonight is under-labelled**
- **What:** a full-width capture field and helper sit between the heading and Tonight, and Tonight's label is the smallest type on the page.
- **Why it matters:** Principle 1, "Where you are, not what exists". Capture is occasional (3 a month on free); ticking is nightly.
- **Fix:**
  - Collapse the composer to one slim line until focused, or move it under Tonight once the library has items.
  - Let the card be the heading.
- **Suggested command:** `$impeccable layout`
- **Where:** _shell.app.tsx:731, CaptureComposer.tsx:107-179, TonightStrip.tsx:44-47

**[P2] Cross-media grammar still breaks on Home**
- **What:**
  - `startWatching` returns every wishlist kind (PostgresScheduleStore.swift:94-101), and the client drops only albums, so wishlist books and manga sit under "Start watching" with no detail line.
  - The week strip hides pages and chapters whenever anything was watched.
  - With nothing in progress to read, Home never mentions books or manga.
- **Why it matters:** Principle 5, "One library, many kinds".
- **Fix:**
  - Keep Start watching to films, shows and anime, and add "Start reading" (or a reading figure in the week) when reading happened.
- **Suggested command:** `$impeccable clarify`
- **Where:** _shell.app.tsx:196-199 and 957-965, lib/home/model.ts:199-213

**[P3] Discover on Home: flat headings, owned rows, small targets**
- **What:**
  - "Discover" and its rows are all h2.
  - The live "Trending shows" row was 100% owned.
  - An owned card shows both ✓ and "In your library".
  - "List…" is 31×16 px.
- **Fix:**
  - Give `Row` a heading level (h3 under Discover).
  - Skip a row that is mostly owned, so the pick moves on.
  - Keep one owned marker.
  - Give "List…" `min-h-6` or more.
- **Suggested command:** `$impeccable polish`
- **Where:** HomeRows.tsx:65 and 470-505, lib/home/model.ts (`homeDiscover`)

## Persona Red Flags

**Alex (keyboard power user)**
- 24 Tab stops to Continue watching, 143 to Discover, 328 in all.
- No key for mark-next on Tonight or Continue.
- The Skip target is invisible.
- The Tonight title focus ring is clipped.

**Sam (screen reader, keyboard, 200% zoom)**
- The heading outline lists the side column before the user's rows, and the Discover rows are siblings of "Discover".
- Skip is announced before its heading.
- "3873h watched" is read without context.
- The composer has only a placeholder as its visible label.
- All 104 posters are `alt=""`, which is fine beside visible titles.

**Mika (cross-media tracker)**
- Wishlist books and manga appear under "Start watching".
- No reading acknowledgement when nothing is in progress.
- Home's Discover rows were anime, movies and shows only, matching the kinds kept.
- Books and Manga sit under "More" in the nav.
- Tonight has no reading action.

## Minor Observations

- The composer placeholder "Paste titles, a link or a screenshot" in a textarea; the idle Send pill looks broken in light mode.
- "Also tonight" is a second eyebrow inside the focal card; ALL-CAPS episode names ("ITEM") read like codes.
- The Continue tick is 36 px, under DESIGN's 44 px for a finger.
- The side column ends at about 600 px and leaves an empty rail down a 3600 px page.
- `edge-lit` + `fringe` + `veil` stack three effects on one card.
- "All 49" is ambiguous; "All 49 watching" reads better.

## Questions to Consider

- If Tonight is the one thing, why does a once-a-month capture field sit above it every evening?
- Does an account with 145 shows in progress need the level bar on Home, or is it the one gamified object diluting calm power?
- Should a public row show at all when nearly everything in it is already on the shelf?
