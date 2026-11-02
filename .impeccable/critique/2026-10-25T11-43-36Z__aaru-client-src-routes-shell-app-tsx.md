---
target: the Field (web home)
total_score: 23
p0_count: 0
p1_count: 3
timestamp: 2026-10-25T11-43-36Z
slug: aaru-client-src-routes-shell-app-tsx
---
# Critique: The Field (web home)

Target: `aaru-client/src/routes/_shell.app.tsx`, live at beta.aaruapp.com/app (owner account, light + dark, ~1205–1316 px; mobile judged from code).

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 2 | Last 7 days shows 3887 episodes · 3915h in one week (>168h); streak line truncated "Tick somethi…" |
| 2 | Match System / Real World | 3 | Raw import filename `animelist_1792767196_-_428412.xml`; ALL-CAPS provider episode names |
| 3 | User Control and Freedom | 2 | No undo on Home's Mark watched, Season N watched, Not tonight, Not for me |
| 4 | Consistency and Standards | 2 | Sidebar mixes card recipes (radius 20 vs 14, eyebrow outside vs inside) and three chip styles |
| 5 | Error Prevention | 2 | Season N watched (bulk) sits under Mark watched at near-equal weight |
| 6 | Recognition Rather Than Recall | 3 | Not tonight / Not for me read as text, effect unexplained |
| 7 | Flexibility and Efficiency | 2 | 925 tab stops; 19 Tabs to Tonight tick; no row skip |
| 8 | Aesthetic and Minimalist Design | 2 | 16 rows, 10 of them Discover catalog, ~6,400 px |
| 9 | Error Recovery | 3 | Optimistic rollback + inline Alert; server messages passed raw |
| 10 | Help and Documentation | 2 | Composer hint great; streak, Not for me, week bars unexplained |
| **Total** | | **23/40** | **Acceptable** |

## Anti-Patterns Verdict

LLM: split. Top ~900 px is Aaru (owl + The Field, lit Tonight card, dark-mode room). Below, 10 Discover rows styled like the user's own rows turn the Field into the generic poster-grid tracker PRODUCT.md rejects. Week strip is the hero-metric pattern. Light mode loses the room texture and reads as grey-blue SaaS.

Deterministic: detect.mjs on 15 files + components/ui → 0 findings (exit 0, also with --no-config; canary confirmed TSX scanning). Regex-only on TSX, so composition-level slop (row sameness, metric strip) is invisible to it. Browser overlay did not run (localhost request from beta hung, likely Chrome Local Network Access prompt).

## What's Working

1. Tonight card: one lit focal piece, reason line from real data, labelled actions. Answers "what next for me" first.
2. Trust copy at high stakes: composer "Nothing is added until you approve what Aaru found", PlanCard approve-with-undo.
3. Token/a11y discipline: dark muted text 6.9–7.6:1, visible 2px focus ring, skip link, labelled regions, texture off under prefers-contrast/forced-colors.

## Priority Issues

1. [P1] Week strip reports impossible activity (3887 eps / 3915h in 7 days). Discredits every figure. Fix: exclude imported/restored ticks from the 7-day stats as Recap does; if an import landed, say so. Command: harden.
2. [P1] Home writes have no undo (`_shell.app.tsx` setEpisode ~336, markWatched 536, markSeasonWatched 590, sendTonightFeedback ~403). DESIGN §9 promises the toast. Fix: offerUndo after each; "Set aside for today · Undo" for verdicts. Command: harden.
3. [P1] Home is video-only in a six-kind library: Continue/Start *watching*, week counts episodes; no Reading row for books/manga. Breaks Principle 5. Fix: Reading row (chapter/volume/page), strip follows kinds used. Command: shape.
4. [P2] Discover swamps the Field: 10 catalog rows, same styling, 925 tab stops, Continue renders 49 cards. Fix: section break before Discover, 2–3 rows by user's kinds + "More on Discover", cap Continue ~12, skip-row link. Command: distill.
5. [P2] Tonight action row overloaded (5 buttons; stacks 5-high at ~1205 px beside cropped portrait). Fix: Mark watched + Open visible, rest in "…" menu; Not for me states its effect; art above text under ~1280 px. Command: distill.
6. [P3] Sidebar polish: one card recipe, one chip style, friendly import label, wrap streak line, ProgressStrip.tsx:18 aria-label hides streak. Command: polish.

## Persona Red Flags

- Alex: 925 tab stops, 19 Tabs to Tonight tick, ~147 stops through Continue, no tick shortcut.
- Sam: streak hidden by aria-label (ProgressStrip.tsx:18); week bars aria-hidden with no text; "List…" ambiguous; each row scroller an extra tabstop; at 200% zoom sidebar content falls below all rows.
- Casey (code): no bottom nav, Search/Menu top-right (AppShell.tsx:523); Tonight's 5 buttons wrap with Season watched beside Mark watched, no undo; 36px Continue tick (HomeRows.tsx:211).
- Mika (cross-media tracker): book/manga in progress have no Home row; "204 in progress" across kinds; Continue "Blue Box S1·E1·29 left" vs Coming up "E29 · Today" collide unexplained.

## Minor Observations

- Row arrows stay enabled with nothing to scroll (HomeRows.tsx:64).
- Blank covers without placeholder until load.
- PlanCard.tsx:56 lists every change uncapped in a 20rem sidebar.
- Profile shown twice (header medallion + sidebar footer).
- "Tick something today to keep it" is streak pressure vs. Vision "proposes, never pushes".
- Light-mode amber edge reads as faint orange border.

## Questions to Consider

- If Tonight is the return moment, why is the composer above it?
- Should "204 in progress" be the Field's first sentence?
- What would the Field lose if Discover lived only on the Discover tab?
