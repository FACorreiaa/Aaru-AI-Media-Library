# Aaru views

Surfaces and the component catalog. `DESIGN.md` says what Aaru should feel like; this file
says what gets built, what each surface is allowed to emit, and which server routes back it.

Rules from `CLAUDE.md` bound everything here: private by default, catalog layer and library
layer stay separate, no vendor JSON across the API boundary, imports are one-way jobs. Social
surfaces are opt-in, friends-only, and wait for the Phase 2 gate.

---

## Surface map

Phases are the ones in `BACKLOG.md`: 0 Rails, 1 Basics, 2 Clients + widgets + imports,
3 Tracking, 4 Social, 5 Gamification, 6 Realtime / DMs / rooms, 7 Agent.

| Surface | Emits | Server routes | Phase · milestone |
| --- | --- | --- | --- |
| The Field (home) | `ContinueRow`, `StartRow`, `CalendarRow`, `NowPlayingCard`, `Shelf`, `JobLedger`, `UndoRibbon` (+ `TonightStrip` in 7, `StreakBar` in 5, `FriendStories` in 4) | `GET /v1/up-next`, `GET /v1/calendar`, `GET /v1/library/items`, `GET /v1/imports` | 2 · M7 |
| Week grid | `WeekGrid` | `GET /v1/calendar?from&to`, `PUT .../episodes/{s}/{e}` | 2 · M7 |
| Composer | none — produces intent | agent tool layer | 7 · M13 |
| Intent preview | `PlanCard` | `POST .../plan` (dry run) | 7 · M13 |
| Work ledger | `JobLedger` | `GET /v1/imports/{id}` | 2 · M8 |
| Title room | `TitleCard`, `SeasonMap` (+ friends watching in 4) | `GET /v1/titles/{id}`, `PATCH /v1/library/items/{id}` | 2 · M7 |
| Tonight | `TonightStrip` | `GET /v1/library/items?status=in_progress` | 7 · M13 |
| Shelf | `Shelf` | `GET /v1/library/items` + saved query | 1–2 · M6 / M7 |
| Catch-up calendar | `CalendarMonth` | `GET /v1/calendar` | 2 · M9 |
| Import studio | `MatchTable`, `PlanCard`, `JobLedger` | `POST /v1/imports/*`, unmatched triage | 2 · M9 |
| Capture | `JobLedger`, `MatchTable`, `PlanCard` | `POST /v1/imports/capture` | 7 · M13 |
| Undo ribbon | `UndoRibbon` | action journal + undo endpoint | 1 · M4 |
| Mac companion | sidebar + inspector over the same components | same `/v1` | 2 · M7 |
| Web (`aaru-client`) | same components as Svelte views | same `/v1` | 2 · WEB-001 |
| Widgets + Live Activity | widget renderings of `ContinueRow`, `CalendarRow`, `WeekGrid`, `NowPlayingCard` (+ `StreakBar` in 5) | App Group snapshot; writes via App Intent → same `/v1` route as a tap | 2 · WID-* |
| Now playing | `NowPlayingCard` | check-in (2), `POST /v1/scrobble/*` (3) | 2–3 |
| Friend stories | `FriendStories` | friend activity route | 4 · SOC-003 |
| Profile and stats | `StatsPanel`, `BadgeShelf` | stats + badges routes | 5 · GAM-004/006 |
| Leaderboard | `Shelf`-like ranked list, friends only | leaderboard route | 5 · GAM-005 |
| Room | `RoomPanel` | rooms routes + `/v1/ws` | 6 · ROOM-001 |
| Conversations | `ConversationView` | ciphertext message routes + `/v1/ws` | 6 · DM-* |
| Approvals | `PlanCard` | `POST /v1/plans/{id}/approve`, `/deny` | 7 · M14 |
| Shortcuts / App Intents | `TitleCard`, `TonightStrip` as intent snippets | agent tool layer | 7 · M14 |
| MCP | none — headless, no rendering | `POST /v1/mcp` | 7 · M14 |

No surface gets a private endpoint. If a view needs data no route returns, add the route,
not a view-shaped one.

---

## Component catalog

The agent returns **component names and props only**. It never returns layout, HTML, or
markdown tables of library rows. If the model wants something outside this table, the host
refuses and substitutes the nearest catalog piece.

| Component | Job | Props (shape, not final signature) |
| --- | --- | --- |
| `TitleCard` | Add / status / owned / rating | `titleId` or `MediaRef`, `status`, `isOwned`, `rating` |
| `SeasonMap` | Episode heat + bulk tick | `libraryItemId`, `season`, watched set, `nextEpisode` |
| `PlanCard` | Preview of a mutation | `planId`, summary counts, per-op diff, autonomy setting |
| `JobLedger` | Import or bulk progress | `importJobId`, step rows, `state`, `stats`, unmatched count |
| `TonightStrip` | 1–3 next actions | ordered `libraryItemId` + reason + est. minutes |
| `Shelf` | Filtered library page | `shelfId` or inline query, result page, `isPinned` |
| `CalendarMonth` | Your airings | month, day → episode refs, agent highlight string |
| `MatchTable` | Import reconciliation | `importJobId`, three buckets: matched / needs eyes / unknown |
| `UndoRibbon` | Last agent write | `actionId`, human summary, expiry, `isUndoable` |
| `WeekGrid` | Seven-day airing grid, check in place | week start, day → episode cells (`libraryItemId`, `EpisodeKey`, name, network, local time, banner URL, state: watched / premiere / finale / today) |
| `ContinueRow` | In-progress titles | ordered `libraryItemId`, next `EpisodeKey`, time left, remaining count + duration, `isFinale` |
| `StartRow` | Wishlist titles you can start | ordered `libraryItemId`, runtime |
| `CalendarRow` | Next airings | episode refs + relative badge (`today` / `new` / `in N hours` / `in N days`) |
| `NowPlayingCard` | Current watch | `libraryItemId`, `EpisodeKey`, progress, started at, ends at, source (check-in / scrobble) |
| `StreakBar` | Streak and week ticks | current streak, longest, last 7 days |
| `FriendStories` | Friends' watches today | friend ids, per-friend ordered watch events |
| `BadgeShelf` | Earned badges | badge ids, tier, earned at |
| `StatsPanel` | Profile numbers | days watched, episodes, mean score, breakdowns |
| `RoomPanel` | Watch-together room | `roomId`, title / episode, members + drift, countdown, state |
| `ConversationView` | E2E conversation | `conversationId`, participants; message bodies decrypt on device only |

`PlanCard`, `JobLedger`, `MatchTable`, and `UndoRibbon` are the four that make agent writes
safe. None of them is optional decoration.

**The catalog grows from nine to twenty, said out loud here (2026-10-09).** Phase 1.5 did not
grow it, and Capture, remote approval, Shortcuts, and MCP still render on the original nine.
The eleven new components add product, not agent reach, and each has a reason:

- `WeekGrid` (Phase 2) — the CAT week schedule is the one view users of that site ask for by
  name; `CalendarMonth` cannot show seven dense days.
- `ContinueRow`, `StartRow`, `CalendarRow` (Phase 2) — the Field needs concrete rows that work
  without the agent; these are Trakt's proven shapes.
- `NowPlayingCard` (Phase 2) — the same data drives the Live Activity; one renderer for both.
- `FriendStories` (Phase 4) — the only social read surface on Home.
- `StreakBar`, `BadgeShelf`, `StatsPanel` (Phase 5) — gamification has no home in the nine.
- `RoomPanel`, `ConversationView` (Phase 6) — realtime and E2E messaging are new objects.

The agent may emit the read-only social components but never initiates a friend request, a
message, or a room invite: those are user acts with no agent write path. A twenty-first
component still needs a paragraph here.

---

## Shelf is not a List

These are different objects. Code must not collapse them.

| | **List** (`AaruList`) | **Shelf** (saved query) |
| --- | --- | --- |
| Domain term | Yes — `CLAUDE.md` domain language | View concept, not a domain noun |
| What it stores | Explicit membership rows | A query, no membership |
| Table | `lists`, `list_items` | `saved_queries` |
| Membership changes when | The user adds or removes an item | The library changes underneath it |
| Order | User-curated, stable | Derived from sort, unstable by design |
| Example | "Films to show Dad" | "Movies with no rating" |
| Routes | `/v1/lists`, `/v1/lists/{id}/items` | `GET /v1/library/items` + a stored filter |

`Shelf` (the component) can render either: a shelf's query result, or a list's items. That
shared renderer is exactly why the underlying objects must stay distinct in the model layer.

Rules:

- The agent must never write `list_items` when the user asked for a shelf. "Make a shelf of
  X" creates a saved query. "Make a list of X" creates an `AaruList` and materializes rows.
- Converting one to the other is a mutation. It needs a `PlanCard` first.
- A shelf is deterministic: same library state, same query, same rows. No agent ranking
  inside a shelf. Ranking belongs to `TonightStrip`, which is explicitly a suggestion.
- A shelf is not a filter preset in the UI layer. It is a named, persisted, pinnable artifact
  the agent can create and the user can rename or delete.

Wording that follows from this: the user "pins a shelf", "adds to a list". Do not write
"add to shelf" anywhere in UI copy or route names.

---

## Agent emission rules

1. **Catalog only.** Names from the component table above. Unknown name → host refuses.
2. **No invisible writes.** Any mutation crossing more than one library item goes through a
   `PlanCard`. First-run imports always do, regardless of size.
3. **Every write is journaled and undoable.** See `AUD-001` / `AUD-002` in `BACKLOG.md`.
4. **No bulk text.** More than ~10 titles in an answer is a `Shelf`, never prose or a table.
5. **Autonomy is a setting, not a vibe.** `ask me` / `fill empty only` / `overwrite if newer`
   is read from user config and shown on the `PlanCard`. The model does not choose it.
6. **Catalog data stays catalog data.** A `TitleCard` for a search hit carries a `MediaRef`,
   not a `libraryItemId`, until the user adds it.
7. **An outside caller is not a privileged caller.** An agent reaching Aaru over App Intents
   or MCP emits nothing — it gets tool results. Anything it wants to *change* beyond a single
   item becomes a `PlanCard` the user approves inside Aaru, labelled with the calling token's
   name. There is no route by which a caller approves its own plan. See X-009.

---

## Build order

Client work follows the server, per `CLAUDE.md`: table, then DTO, then screen.

0. **Phase 0 · Rails** — no views. CI, Xcode project, release lanes, infra.
1. **Phase 1 · M4** — action journal + undo endpoint land with library mutations, not after
   them.
2. **Phase 1 · M6** — `saved_queries` alongside lists, so the Shelf/List split exists in the
   schema from the start. `CAL-001` and `UPN-001` give the rows and the grid their data.
3. **Phase 2 · M7** — `TitleCard`, `SeasonMap`, `Shelf`, `UndoRibbon`, `ContinueRow`,
   `StartRow`, `CalendarRow`, `WeekGrid`, `NowPlayingCard` as plain SwiftUI views driven by
   direct user input, the same set in `aaru-client` (Svelte), then widgets from the same
   snapshot. No agent yet. This proves the components before the model touches them.
4. **Phase 2 · M8/M9** — `JobLedger`, `MatchTable`, `CalendarMonth` with real import data.
   **Gate:** basics done. Nothing below starts before it.
5. **Phase 3** — `NowPlayingCard` fed by scrobbles. No new component.
6. **Phase 4** — `FriendStories`, friends watching on the Title room.
7. **Phase 5** — `StreakBar`, `BadgeShelf`, `StatsPanel`, streak widget.
8. **Phase 6** — `RoomPanel`, `ConversationView` on the WebSocket gateway.
9. **Phase 7 · M13** — composer, `PlanCard`, `TonightStrip`, and the tool layer
   (`search_titles`, `read_library`, `plan_import`, `apply_library_patch`, `list_airs`) on top
   of components that already work by hand. Then Capture, which is an import source reusing
   `JobLedger` / `MatchTable` / `PlanCard`, and the model provider behind it.
10. **Phase 7 · M14** — the outbound transports on the finished tool layer: App Intents first
    (no server work), then MCP with agent tokens and remote approval. `Approvals` renders a
    `PlanCard` a caller proposed; nothing new is drawn.

The order matters: every component must be usable without the agent before the agent is
allowed to emit it. That is what keeps a failed model call from producing a dead screen.

---

## Open

- **M7 shell.** `DESIGN.md` makes The Field the primary home. `BACKLOG.md` M7 currently
  describes classic library screens. Recommendation: build M7 as the component set plus a
  simple vertical home, and let M13 add the composer on top — not a tab bar that later gets
  replaced.
- **Where `saved_queries` live.** Server-side (syncs across devices, agent can create them)
  vs client-side. Recommendation: server, because the agent creates them.
