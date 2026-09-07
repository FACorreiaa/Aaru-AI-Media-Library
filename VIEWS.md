# Aaru views

Surfaces and the component catalog. `DESIGN.md` says what Aaru should feel like; this file
says what gets built, what each surface is allowed to emit, and which server routes back it.

Rules from `CLAUDE.md` bound everything here: private by default, catalog layer and library
layer stay separate, no vendor JSON across the API boundary, imports are one-way jobs.

---

## Surface map

| Surface | Emits | Server routes | Milestone |
| --- | --- | --- | --- |
| The Field (home) | `TonightStrip`, `Shelf`, `CalendarMonth`, `JobLedger`, `UndoRibbon` | `GET /v1/library/items`, `GET /v1/imports` | M7 |
| Composer | none — produces intent | agent tool layer | M13 |
| Intent preview | `PlanCard` | `POST .../plan` (dry run) | M13 |
| Work ledger | `JobLedger` | `GET /v1/imports/{id}` | M8 |
| Title room | `TitleCard`, `SeasonMap` | `GET /v1/titles/{id}`, `PATCH /v1/library/items/{id}` | M7 |
| Tonight | `TonightStrip` | `GET /v1/library/items?status=in_progress` | M13 |
| Shelf | `Shelf` | `GET /v1/library/items` + saved query | M6 / M7 |
| Catch-up calendar | `CalendarMonth` | airings derived from library + `show_episodes` | M9 |
| Import studio | `MatchTable`, `PlanCard`, `JobLedger` | `POST /v1/imports/*`, unmatched triage | M9 |
| Capture | `JobLedger`, `MatchTable`, `PlanCard` | `POST /v1/imports/capture` | M13 |
| Undo ribbon | `UndoRibbon` | action journal + undo endpoint | M4 |
| Mac companion | sidebar + inspector over the same components | same `/v1` | M7 |
| Approvals | `PlanCard` | `POST /v1/plans/{id}/approve`, `/deny` | M14 |
| Shortcuts / App Intents | `TitleCard`, `TonightStrip` as intent snippets | agent tool layer | M14 |
| MCP | none — headless, no rendering | `POST /v1/mcp` | M14 |

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

`PlanCard`, `JobLedger`, `MatchTable`, and `UndoRibbon` are the four that make agent writes
safe. None of them is optional decoration.

**The catalog is nine components and phase 1.5 did not grow it.** Capture, remote approval,
Shortcuts, and MCP all render on the nine above. That is the check on the design: a new agent
surface that needs a tenth component is adding product, not adding reach. If a future change
needs one, say so out loud here rather than quietly appending a row.

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

1. **M4** — action journal + undo endpoint land with library mutations, not after them.
2. **M6** — `saved_queries` alongside lists, so the Shelf/List split exists in the schema
   from the start.
3. **M7** — `TitleCard`, `SeasonMap`, `Shelf`, `UndoRibbon` as plain SwiftUI views driven by
   direct user input. No agent yet. This proves the components before the model touches them.
4. **M8/M9** — `JobLedger`, `MatchTable`, `CalendarMonth` with real import data.
5. **M13** — composer, `PlanCard`, `TonightStrip`, and the tool layer
   (`search_titles`, `read_library`, `plan_import`, `apply_library_patch`, `list_airs`) on top
   of components that already work by hand. Then Capture, which is an import source reusing
   `JobLedger` / `MatchTable` / `PlanCard`, and the model provider behind it.
6. **M14** — the outbound transports on the finished tool layer: App Intents first (no server
   work), then MCP with agent tokens and remote approval. `Approvals` renders a `PlanCard` a
   caller proposed; nothing new is drawn.

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
