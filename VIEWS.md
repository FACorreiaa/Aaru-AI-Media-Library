# Aaru views

Surfaces and the component catalog. `DESIGN.md` says what Aaru should feel like; this file
says what gets built, what each surface is allowed to emit, and which server routes back it.

Rules from `CLAUDE.md` bound everything here: private by default, catalog layer and library
layer stay separate, no vendor JSON across the API boundary, imports are one-way jobs. Social
surfaces are opt-in, friends-only, and wait for the Phase 2 gate, except where `BACKLOG.md`
records an owner's exception (groups, 2026-10-20).

---

## Surface map

Phases are the ones in `BACKLOG.md`: 0 Rails, 1 Basics, 2 Clients + widgets + imports,
3 Tracking, 4 Social, 5 Gamification, 6 Realtime / DMs / rooms, 7 Agent.

| Surface | Emits | Server routes | Phase · milestone |
| --- | --- | --- | --- |
| The Field (home) | `ContinueRow`, `StartRow`, `CalendarRow`, `DiscoverRow`, Listening row (albums in progress, MUS-001), `NowPlayingCard`, `Shelf`, `JobLedger`, `UndoRibbon`; last-7-days strip (GAM-006d), status count chips, `UnfinishedRow`, list chips (2026-10-20), `TonightStrip` client-composed and the last import as a collapsed `JobLedger` (2026-10-21) (+ the agent's `TonightStrip` in 7, `StreakBar` in 5, `FriendStories` in 4) | `GET /v1/up-next` (with `counts`, `unfinished`), `GET /v1/calendar`, `GET /v1/discover`, `GET /v1/library/items`, `GET /v1/imports`, `GET /v1/me/stats?span=last7`, `GET /v1/lists`, `GET /v1/me/now-playing` (SCR-008) | 2 · M7, DISC-001, APP-013 |
| Discover | Today: `DiscoverRow` per DISC-001 row, add with status or to a list. Seasons: `SeasonBrowser` (DISC-002). Concerts: `ConcertList` (MUS-003) | `GET /v1/discover`, `GET /v1/discover/season`, `POST /v1/concerts/near`, `GET /v1/concerts/artists`, `GET /v1/me/concert-place`, `POST /v1/library/items`, `POST /v1/lists/{id}/items` | 2 · DISC-001 / APP-012 (pulled forward 2026-10-20), DISC-002, MUS-003 (2026-10-21) |
| Insights | `StatsPanel` (7 days / 30 days / month / year / all time), then Music when the period has `stats.music`: listens and hours with their change, the top five artists / tracks / albums, "All listens" (MUS-008). A sidebar destination at the bottom on web, iPad and Mac; on iPhone from Home's Last 7 days and Library's More menu (DESIGN.md §18) | `GET /v1/me/stats?year&month` or `?span=all|last7|last30`, `GET /v1/me/listens/top?by&limit=5` | 2 · GAM-006c (pulled forward 2026-10-20), GAM-006d (2026-10-21), MUS-008 |
| Listens | none — Recent (listens under day headings: cover, track, artist · album, time; load more) and Top (7 days / 30 days / Year / all time × artists / tracks / albums, top 20). Side by side when wide, a Recent \| Top switch on a phone. An album row opens its title page when it can: on the web when the album is in the catalog, on Apple when it is in the library. Titled "Listens" (never "Music", the albums kind). From Library's More menu and Insights' "All listens" on both clients, and the last listen in Settings → Connections → Music. Not a destination (DESIGN.md §18) | `GET /v1/me/listens?before&limit`, `GET /v1/me/listens/top?by&span|year&tz&limit` | 2 · MUS-008 (owner exception 2026-10-21) |
| Lists | `Shelf` rendering a list's items: show status, next airing, library status and progress (LST-003) | `GET /v1/lists`, `GET /v1/lists/{id}` (`items`), `POST /v1/lists/{id}/items` | 2 · APP-015: sidebar on web, iPad and Mac; on iPhone inside Library (DESIGN.md §18) |
| Week grid (Calendar's Week mode) | `WeekGrid` | `GET /v1/calendar?from&to`, `PUT .../episodes/{s}/{e}` | 2 · M7 |
| Composer | none — produces intent | agent tool layer | 7 · M13 |
| Intent preview | `PlanCard` | `POST .../plan` (dry run) | 7 · M13 |
| Work ledger | `JobLedger` | `GET /v1/imports/{id}` | 2 · M8 |
| Title room | `TitleCard`, `SeasonMap`, episode sheet (+ friends watching in 4); for an album, a square cover and the tracklist instead of the season map (MUS-001) | `GET /v1/titles/{id}`, `PATCH /v1/library/items/{id}` | 2 · M7 |
| Tonight | `TonightStrip` | `GET /v1/library/items?status=in_progress` | 7 · M13 (client-composed on the Field since 2026-10-21, DESIGN.md §5) |
| Shelf | `Shelf` | `GET /v1/library/items` + saved query | 1–2 · M6 / M7 |
| Library · Now | `NowCard` (Library only; the agent does not emit it — `TonightStrip` is its agent counterpart) | the synced shelf; `PUT .../episodes/{s}/{e}`, `PATCH /v1/library/items/{id}` | 2 · APP-017 |
| Catch-up calendar | `CalendarMonth` + agenda, the episode sheet, and Missed (aired, unwatched, last 4 weeks) | `GET /v1/calendar?from&to` (≤ 42 days), `PUT .../episodes/{s}/{e}` | 2 · M7, CAL-002 |
| Import studio | `MatchTable`, `PlanCard`, `JobLedger` | `POST /v1/imports/*`, unmatched triage (`POST /v1/imports/{id}/rows/{index}/resolve`) | 2 · M9 |
| Capture | `JobLedger`, `MatchTable`, `PlanCard` | `POST /v1/imports/capture` | 7 · M13 |
| Undo ribbon | `UndoRibbon` | action journal + undo endpoint | 1 · M4 |
| History (Settings → Your data) | none — journaled actions newest first, by whom (you, an import, a connection), Undo; an applied import or request links here (UX-060) | `GET /v1/actions`, `POST /v1/actions/{id}/undo` | 2 · DESIGN.md §9, §18 (2026-10-21) |
| Mac companion | sidebar + inspector over the same components | same `/v1` | 2 · M7 |
| Web (`aaru-client`) | same components as SolidJS views | same `/v1` | 2 · WEB-001 |
| Widgets + Live Activity | widget renderings of `ContinueRow`, `CalendarRow`, `WeekGrid`, `NowPlayingCard`, Listening (MUS-001) (+ `StreakBar` in 5) | App Group snapshot; writes via App Intent → same `/v1` route as a tap | 2 · WID-* |
| Now playing | `NowPlayingCard` | check-in (2), `POST /v1/scrobble/*` (3); Stremio `player` events fill `watch_events`; `GET /v1/me/now-playing` reads them back, top of the Field (SCR-008, 2026-10-21) | 2–3 |
| Settings | none — eight pages in this order: Account (name and handle, sign-in, appearance on this device, sign out), Friends & privacy (friends, blocked, Location: concerts near), Notifications, Import (Trakt, the history sources in `CLAUDE.md` order, the jobs), Connections (agents and the browser extension, Stremio addon, music scrobblers), Your data (recaps, History, export), About, Delete account. Web `/app/settings/{account,friends,notifications,import,connections,data,about,delete}` with a sub-nav; iPhone and iPad a list of pages, opened on iPhone from the account button; Mac the Settings scene's seven panes, Delete account inside Account (DESIGN.md §18, supersedes the five groups of 2026-10-21) | `GET /v1/me`, `/v1/me/notifications`, `/v1/me/concert-place` (Concerts near, MUS-003), `/v1/concerts/places`, `/v1/imports`, `/v1/agent/tokens`, `/v1/actions`, `/v1/me/export` | 2 · APP-007 |
| Stremio addon (Settings) | none — a section of Settings → Connections: connect, one-time install links, live links with last use, disconnect | `GET`/`POST /v1/agent/tokens?for=stremio`, `DELETE /v1/agent/tokens/{id}` | 3 · SCR-003 (owner un-deferred 2026-10-19) |
| Agents (Settings) | none — a section of Settings → Connections: pick an agent (Claude Code, Codex, Hermes, Gemini CLI, other) or the browser extension, its setup steps, create a token shown once with the steps filled in (the extension connects itself), live connections with last use, disconnect | `GET`/`POST /v1/agent/tokens?for=mcp`, `?for=scrobble`, `GET /v1/agent/setup/{kind}`, `DELETE /v1/agent/tokens/{id}` | 7 · OUT-001/004 (owner pulled forward 2026-10-20); SCR-007 (2026-10-21) |
| Music scrobblers (Settings) | none — a section of Settings → Connections: the last listen, pick a scrobbler (Web Scrobbler, Pano Scrobbler, Navidrome, Jellyfin, other), connect, its steps from the server with values to copy and the token shown once, a wait for the first listen, live scrobblers with last use, disconnect | `GET`/`POST /v1/agent/tokens?for=music` (`scrobbler`), `GET /v1/me/listens?limit=1`, `DELETE /v1/agent/tokens/{id}` | 2 · MUS-007 (owner exception 2026-10-21) |
| Invite (the Friends section) | none — "Invite a friend" (optionally with a title picked from search), the share sheet, open invites with time left and Revoke | `GET`/`POST /v1/social/invites`, `DELETE /v1/social/invites/{code}`, `GET /v1/search` | 4 · SOC-002 (owner pulled forward 2026-10-21) |
| Invite letter | none — web `/i/{code}`, an `InviteSheet` in the apps: who sent it, the title it carries with an "Add to my Plan to watch" switch, a handle field when the friend has none, Join Aaru (signed out) or Add as a friend | `GET /v1/invites/{code}` (public), `POST /v1/social/invites/{code}/redeem`, `PUT /v1/me/profile` | 4 · SOC-002 (2026-10-21) |
| Friends (tab on Apple, `/app/friends` on the web) | none — Lately (friends' last two weeks), Invite, requests, friends, blocks | `GET /v1/activity`, `/v1/social/*` | 4 · SOC-003 minimal (owner 2026-10-21) |
| Recommend | none — a sheet from a title (pick friends) or a friend's profile (find a title), with a note of up to 140 characters; the friend's "For you from friends" at the top of Friends adds it to Plan to watch or dismisses it | `POST /v1/social/recommendations`, `GET /v1/me/recommendations`, `POST …/{id}/add`, `DELETE …/{id}` | 4 · SOC-006 (2026-10-21) |
| Friend profile | none — shelf first: header with counts, Watching, You both (both want, both finished, they loved), Recently finished; only a name when they hide their library | `GET /v1/social/friends/{userId}/profile` | 4 · SOC-001/003 (2026-10-21) |
| Friend stories | `FriendStories` | friend activity route | 4 · SOC-003 |
| Recap | `RecapStory` | `GET /v1/me/stats` | 2 · GAM-006a (pulled forward 2026-10-16) |
| Profile and stats | `ProfilePanel`; `BadgeShelf` in 5. From the medallion on Home (iOS sheet, web `/app/profile`) | `GET /v1/me/profile/stats`; badges routes in 5 | 2 · GAM-006b (pulled forward 2026-10-22); 5 · GAM-004 |
| Leaderboard | `Shelf`-like ranked list, friends only | leaderboard route | 5 · GAM-005 |
| Groups | `GroupRail`, `ChannelList`, `MessageList`, `MemberList`, `SpoilerVeil`; agent replies inside `MessageList` carry `TitleCard`, `CalendarRow`, `Shelf` | `/v1/groups/*`, `/v1/group-invites/*`, `/v1/realtime/ticket`, `/v1/ws` | 4 · GRP-001…GRP-012 (pulled forward 2026-10-20) |
| Watch channel | `WatchPanel` above the channel's `MessageList` | `/v1/groups/{id}/channels/{cid}/session` + `/v1/ws` | 4 · GRP-009 (absorbs ROOM-001) |
| Conversations | `ConversationView` | ciphertext message routes + `/v1/ws` | 6 · DM-* |
| Approvals | `PlanCard`, pinned at the top of Home ("Waiting for you") until The Field exists; a push opens one | `GET /v1/plans`, `GET /v1/plans/{id}`, `POST /v1/plans/{id}/approve`, `/deny` | 7 · OUT-004 (built 2026-10-20) |
| Shortcuts / App Intents | `TitleCard`, `TonightStrip` as intent snippets | agent tool layer | 7 · M14 |
| MCP | none — headless, no rendering | `POST /v1/mcp` | 7 · OUT-004 (built 2026-10-20) |
| Extension connect (web only) | none — "Connect {browser} to Aaru?", what it may do, Approve (enabled once the extension answers) / Not now; Connected / Not connected / not installed | `POST /v1/agent/tokens` (`kind = browser`), `DELETE …/{id}` when the extension never took it | 3 · SCR-007 (2026-10-21) |
| OAuth consent (web only) | none — the app's name, the host it returns to, a name, Allow changes, Allow / Not now | `GET /v1/oauth/requests/{id}`, `POST …/approve`, `POST …/deny` | 7 · OUT-004 (built 2026-10-20) |

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
| `SeasonMap` | Episode heat + bulk tick | `libraryItemId`, seasons (episode number, name, still, air time), watched set, `nextEpisode` |
| `PlanCard` | Preview of a mutation | `planId`, summary counts, per-op diff, autonomy setting |
| `JobLedger` | Import or bulk progress | `importJobId`, step rows (done / current / to do), `state`, `stats`, `rowsMatched` of `rowsTotal` on the matching step, unmatched count |
| `TonightStrip` | 1–3 next actions | ordered `libraryItemId` + reason + est. minutes |
| `Shelf` | Filtered library page | `shelfId` or inline query, result page, `isPinned` |
| `CalendarMonth` | Your airings, Stremio-style | month, Monday-start weeks, day → poster thumbs (two and "+N" on phones, three wider), selected day (a sheet on phones), agenda by date with poster rows that open the episode sheet (still, synopsis, network · time, badge, watched toggle, open show), filters (hide watched, premieres/finales, shows/anime); agent highlight string later |
| `MatchTable` | Import reconciliation | `importJobId`, three buckets: matched / needs eyes / unknown |
| `UndoRibbon` | Last agent write | `actionId`, human summary, expiry, `isUndoable` |
| `WeekGrid` | Seven-day airing grid, check in place | week start, day → episode cells (`libraryItemId`, `EpisodeKey`, name, synopsis, network, local time or none when `airTimeKnown` is false, banner URL = `backdropUrl` → poster → tint, state: watched / premiere / new season / finale / today); Monday start |
| `ContinueRow` | In-progress titles | ordered `libraryItemId`, next `EpisodeKey`, time left, remaining count + duration, `isFinale` |
| `StartRow` | Wishlist titles you can start | ordered `libraryItemId`, runtime |
| `CalendarRow` | Next airings | episode refs + relative badge (`today` / `new` / `in N hours` / `in N days`) |
| `DiscoverRow` | Public catalog rows on Home and Discover (DISC-001) | row id + title, `CatalogHit`s (a `MediaRef` each) with `libraryItemId` when on the shelf, kind badge, date badge; each a `DiscoverCard` (poster, add or open) |
| `ConcertList` | Concerts on Discover (MUS-003) | "Your artists on tour" and "Near <city>": ticket-stub date block, act, venue · city, distance · time, "Tickets ↗" out; radius 25/50/100 km, "Use my location", "Show more"; List/Map on Apple |
| `SeasonBrowser` | One season of public catalog titles on Discover (DISC-002) | season + year with steps either side, kind (anime, new shows, returning, movies), `CatalogHit` grid with `libraryItemId`, "Show more"; `DiscoverCard` per hit |
| `NowPlayingCard` | Current watch | `libraryItemId`, `EpisodeKey`, progress, started at, ends at, source (check-in / scrobble). Rendered on iOS as the "Now watching" Live Activity (`NowWatchingAttributes`, WID-005) |
| `UnfinishedRow` | Dropped or stalled items | ordered `libraryItemId`, reason (`dropped` / `stalled`), since, next `EpisodeKey` for shows |
| `StreakBar` | Streak and week ticks | current streak, longest, last 7 days |
| `FriendStories` | Friends' watches today | friend ids, per-friend ordered watch events |
| `BadgeShelf` | Earned badges | badge ids, tier, earned at |
| `ProfilePanel` | Profile | all-time time in days and hours, episodes, pages read, tiles per kind, time by kind, top eight genres, three most watched, networks, mean score and ratings histogram; undated ticks included; static (GAM-006b) |
| `CardMenu` | Library, Home cards (web) | ⋯, right-click or long press: "Mark show watched" / "Mark watched", Open. iOS uses the card's context menu (PROG-005) |
| `UndoToast` | Anywhere a bulk tap writes | "Marked N episodes · Undo", about six seconds, through `/v1/actions/{id}/undo` (PROG-005) |
| `StatsPanel` | Insights | span (`last7` / `last30` / `month` / `year` / `all`), totals with an absolute change against `prior` on rolling spans, buckets, by kind, top titles, ratings distribution (10 bins), longest run; static. All-time numbers with undated ticks live on `ProfilePanel`. Music (MUS-008) sits under it on Insights |
| `RecapStory` | A month or year as a story | `year`, optional `month`; the deck is built on the device from `/v1/me/stats`. A year adds biggest day, genres, kinds and persona cards (GAM-006e); "On repeat" (top artist, plays · hours, top three tracks) after the top five when the period has listens (MUS-008) |
| `GroupRail` | The groups you are in | group ids, names, monogram, unread flag, mention count, selected group |
| `ChannelList` | A group's channels | group id, channels by kind (`text` / `title` / `watch` / `shelf`) with name, title poster for `title`, unread flag, mention count; `#general` first |
| `MessageList` | A channel's conversation and its composer | channel id, kind, "not end-to-end" label, messages (author or Aaru, body, `components`, reply, mentions, spoiler stamp, edited / deleted / from a blocked member), last-read marker, typing names; composer with `@` suggestions |
| `MemberList` | Who is in a group | members by role, Aaru as a member with its medallion, `share_progress` per member |
| `SpoilerVeil` | Hides a message the reader is not caught up to | message id, stamped `EpisodeKey`, reader's progress; tap to reveal |
| `WatchPanel` | Watch-together session in a `watch` channel (was `RoomPanel`) | channel id, title / episode, ready members + drift, countdown from server time, reactions, state, "Mark watched for me" |
| `ConversationView` | E2E conversation | `conversationId`, participants; message bodies decrypt on device only |

`PlanCard`, `JobLedger`, `MatchTable`, and `UndoRibbon` are the four that make agent writes
safe. None of them is optional decoration.

**`AgentPresence` is chrome, not a catalog component (2026-10-21).** The reed mark, breathing
slowly, beside a request waiting for the user or an import that is matching. The client shows
it from state it already has; the agent never emits it. Web `src/components/AgentPresence.tsx`,
Apple `Design/AgentPresence.swift`.

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
  `RoomPanel` became `WatchPanel` on 2026-10-20, when rooms moved into groups.
- `RecapStory` (GAM-006a, the twenty-first, added 2026-10-16) — the Recap is a full-screen,
  tap-through story with a share image; no grid or row of the twenty can play a sequence. It is
  read-only, so the agent may open it ("show me my October") but it writes nothing.
- `DiscoverRow` (DISC-001, the twenty-second, added 2026-10-20) — a new account's Home had
  nothing to show; these are public catalog rows (trending, this season), the same for
  everyone. It is the only row of catalog hits rather than library items, so each card carries
  a `MediaRef` and adds through the same `POST /v1/library/items` a search hit uses (rule 6
  below); a hit the caller already has carries `libraryItemId` and opens the item. Home renders
  the rows, and the Discover tab/page (APP-012) shows the same rows as a destination; the agent
  does not emit them, since it would be recommending.
- `SeasonBrowser` (DISC-002, added 2026-10-21) — browsing a season by name needs steps through
  time and a kind switch, which a row of cards has no place for. The same public `CatalogHit`s
  and the same add path as `DiscoverRow`; the agent does not emit it either.
- `ConcertList` (MUS-003, added 2026-10-21) — concerts are dated events with a venue and a ticket
  link, not titles, so no title renderer fits. Read-only, linked out; the agent does not emit it.
- `UnfinishedRow` (2026-10-20, the twenty-third) — Unfinished business (`DESIGN.md` §1) had no
  renderer. It is `ContinueRow`'s shape over `dropped` and 30-day-stalled items. `StatsPanel`
  is pulled forward from Phase 5 as Insights (GAM-006c), with no new component.

- `GroupRail`, `ChannelList`, `MessageList`, `MemberList`, `SpoilerVeil` (GRP-004/005/007, the
  twenty-fourth to twenty-eighth, added 2026-10-20) — groups are a new object: a place where
  friends talk, with channels. No existing piece can hold a conversation (`ConversationView` is
  E2E and one-to-one), and a spoiler guard needs its own renderer so every surface veils the
  same way. The composer lives inside `MessageList`; it is not the agent's Composer surface.
  These are app chrome: the agent never emits them.

The agent may emit the read-only social components. It posts in a group channel only as a
reply to an explicit `@aaru` mention, and only with catalog components whose buttons are the
viewer's own taps. It never starts a thread, never sends a DM, and never sends a friend request,
an invite link, a group invite, a room invite, a reaction or a recommendation: those are user
acts with no agent write path. A
twenty-ninth component still needs a paragraph here.

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
   direct user input, the same set in `aaru-client` (SolidJS), then widgets from the same
   snapshot. No agent yet. This proves the components before the model touches them.
4. **Phase 2 · M8/M9** — `JobLedger`, `MatchTable`, `CalendarMonth` with real import data.
   **Gate:** basics done. Nothing below starts before it.
5. **Phase 3** — `NowPlayingCard` fed by scrobbles. No new component.
6. **Phase 4** — `FriendStories`, friends watching on the Title room. Groups (pulled forward
   2026-10-20): `GroupRail`, `ChannelList`, `MessageList`, `MemberList` by hand first, then
   `SpoilerVeil` and `WatchPanel` with the channel kinds, then `@aaru` replies rendering
   `TitleCard`, `CalendarRow` and `Shelf` in `MessageList`.
7. **Phase 5** — `StreakBar`, `BadgeShelf`, streak widget (`StatsPanel` came early as
   Insights, 2026-10-20; Phase 5 adds genres and the profile).
8. **Phase 6** — `ConversationView` on the WebSocket gateway (`WatchPanel` shipped with groups).
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

- ~~**Navigation and Settings.**~~ Closed 2026-10-21 by the owner: DESIGN.md §18. Sidebar
  Home · Discover · Library · Calendar · Lists · Groups, then Insights and Settings; the iPhone
  tab bar keeps five (Lists moves into Library there); Settings in eight pages.
- ~~**M7 shell.**~~ Closed 2026-10-20, superseded 2026-10-21 by the entry above. The Field stays a vertical Home the composer lands on
  in M13, and the iPhone tab bar is capped at five destinations: Home · Discover · Library ·
  Calendar · Lists (sidebar on iPad and Mac, header links on web). Insights opens from Home's
  stats strip and next to Recap; it is not a tab. These are destinations, not the media-type
  tabs `DESIGN.md` "Do not" rules out.
- **Where `saved_queries` live.** Server-side (syncs across devices, agent can create them)
  vs client-side. Recommendation: server, because the agent creates them.
