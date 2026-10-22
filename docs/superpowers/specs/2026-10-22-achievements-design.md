# Achievements: points, levels, streaks, badges and a friends board (design)

Owner-approved 2026-10-22. Items GAM-001…005 and WID-007, pulled forward before the P2 gate.

## Context

Owner wants friends to feel like followers and achievements that cover the whole range of what people do in Aaru, on web and iOS/Mac.

Starting point, checked on `origin/main` at `57d1056`.

**Friends already shipped** (SOC-001/002/003/006/007, 2026-10-21):
- mutual friendships, invite links, the Friends tab and `/app/friends`;
- friend profiles (shelf first), the 14-day "Lately" activity feed;
- reactions, recommendations, and the `share_library_with_friends` switch.

**Gamification has nothing built.** GAM-001…005 and WID-007 are open. Recap, Insights and Home stats exist, all on `/v1/me/stats`.

### Owner decisions (2026-10-22)

1. **Friends stay mutual-accept, with no one-way follow.** The "follower feel" comes from profiles, activity, and achievements shown on profiles.
2. **Build the full P5 stack now:**
   - points ledger and levels;
   - daily streaks and the streak widget;
   - tiered badges with a wide catalog;
   - a weekly friends leaderboard.
3. **This is an owner exception before the P2 gate**, with 0 strangers so far. It is recorded in BACKLOG decisions and the CLAUDE.md exception list.
4. **Imported history counts for milestone badges.** It does not count for streaks, weekly points, or activity badges. On import day, earned badges arrive silently as one summary.
5. **Friends see your badges and level** behind a new switch, `show_achievements_to_friends`, default ON and separate from the library switch.
   - The leaderboard is its own opt-in, `leaderboard_opt_in`, default OFF.
   - Blocks apply both ways. There is never a global board.
6. **Unlocking a badge** shows a quiet medallion toast, plus a haptic on iOS. A badge's top tier also gets a one-time full-card reveal.
7. **About 15% of badges are hidden** ("???") until earned. The rest are visible with a progress bar ("62 / 100").
8. **Names are plain with a little wit:** Century, Night Owl, Completionist. Code stores tiers as 1–4; the UI shows them as bronze, silver, gold and platinum.

### Calls I made (owner can veto)

- A day with only listens does **not** keep a streak alive.
- `friend_added` and `import_first` points are left out of the weekly board.
- Point values and caps follow BACKLOG GAM-001 (table below).
- No push notification for unlocks or for a streak about to break.
- Tier visuals follow the Mindspace gold rule:
  - Stone ring, then Ink ring, then a gold hairline, then a double gold hairline.
  - Gold never fills a surface.

## Architecture

### Badge sources

Badges are evaluated from two sources. This amends ARCHITECTURE.md and GAM-004, which currently say "ledger events only".

- **Milestone badges read library facts:** `library_items`, `episode_progress`, lists, `import_jobs`, `listens` and the social tables. Imports therefore count automatically, and the library stays the source of truth.
- **Activity badges read the points ledger and streak days**, which only live actions write.
- Each `user_badges` row stores the `action_id` that earned it. If that action is undone and the rule no longer holds, the tier is taken back. Nothing else ever removes a badge.

### Ledger (GAM-001)

**Table `points_events`:**
- Columns: `user_id`, `kind`, `points`, `dedupe_root`, `seq`, `dedupe_key` (`root#seq`), `reverses`, `title_id`, `season`, `episode`, `action_id` (`ON DELETE SET NULL`), `local_date`, `time_zone`, `created_at`.
- Unique on `(user_id, dedupe_key)`.

**One idempotent `award` / `revoke` path (X-010):**
- `award` inserts only when the last event on that root is not an award.
- `revoke` inserts the negative of the active award.
- Undo writes a compensating event; nothing is ever edited.

**Dedupe roots are keyed by title,** so removing a title and re-adding it never earns twice:
- `ep:{title}:{s}:{e}`
- `finish:{title}`
- `season:{title}:{s}`
- `friend:{low}:{high}`
- `room:{sessionId}`
- `streak:{runStart}:{n}`

**`user_progress`** holds total, level, streak, time zone, the dirty flag and a lease. It is a cache that can be rebuilt from the ledger.

**Levels** are a pure function of total points: `floor((1+√(1+4·total/50))/2)`, the inverse of `50·L·(L−1)`.

**Point values** (in code, `Gamification/PointsRules.swift`):

| Kind | Points | Daily cap |
|---|---|---|
| episode | 10 | 300 |
| movie_finished | 25 | 100 |
| book_finished | 50 | 150 |
| album_finished | 10 | 50 |
| season_bonus | 30 | 90 |
| scrobble_bonus | +5 | 50 |
| book_progress | 5 | 15 |
| listen | 1 | 25 |
| room_attended | 15 | 45 |
| friend_added | 20 | 60 |
| import_first | 50 | once |
| streak milestone | 50 / 200 / 500 / 1000 | at 7 / 30 / 100 / 365 days |

Notes:
- `scrobble_bonus` only applies when the action came through a Stremio or browser-extension scrobble token.
- `book_progress` is one award per book per day.
- `listen` only counts listens with `listened_at` within 24 h of arriving.

### Hooks (verified on main)

**Library writes.** Points are recorded in the same transaction as the write:
- `PostgresLibraryStore.apply` (`Data/Fluent/PostgresLibraryStore.swift:12`) and `.undo` (`:40`) call `PostgresGamificationStore.recordLibraryWrite(...)`.
- This only runs for these journal kinds: `add`, `update`, `remove`, `episode`, `season`, `undo`. It never runs for `import`, `plan` or `list`.
- A pure `LibraryWriteFacts.derive(op:inverse:)` diffs the op and its stored inverse. That inverse already holds the exact ticks added or removed and the previous status, rating and page, so the journal needs no new kinds.

**`LibraryService.commit`** (`Library/LibraryService+Prepare.swift:144`):
- returns the `ActionRecord`;
- passes `caller.timeZone`;
- runs the inline badge evaluation after commit.

**`Caller`** (`Library/LibraryOp.swift`) gains `timeZone` and `scrobbled`.

**Friendships:**
- `SocialService.accept`, the matching-request branch of `sendRequest`, and `InviteService` redeem all call `friendAdded`.
- `PostgresSocialStore.unfriend` and `block` return `created_at`. A friendship that ends in under 7 days reverses the friend points for both people.

**Watch parties:** `GroupService+Kinds` `startCountdown` and `markWatched` call `roomAttended`.

**Listens:** `ListenStore.insert` returns the rows it kept, and `ListenService.submit` passes them to `listensKept`.

**Imports:**
- The import apply and resolve paths, and plan approval, mark the user dirty with origin `batch`.
- No points or streak days are written per item.
- The only award is `import_first`.

**Background worker.** There is no Hummingbird Jobs. A new `Gamification/GamificationWorker.swift`, built on `workerLoops` (`Imports/ImportWorker.swift:27`), claims dirty users with `FOR UPDATE SKIP LOCKED` and a lease. It handles batch evaluation, retries and the backfill. Register it in `backgroundServices(...)` (`App+build.swift`).

### Streaks (GAM-003)

**Table `check_ins(user_id, local_date, time_zone, first_at)`**, primary key `(user_id, local_date)`:
- Append-only.
- Written only for live episodes, finishes and book progress.
- The UI calls these "streak days"; "check-in" stays the Live Activity's word.

**Time zone comes from a new `X-Timezone` header** (no client sends one today):
- **Server:** `API/ClientTimeZoneMiddleware.swift` puts it into `AppRequestContext`.
- **Apple:** `aaru-api/Sources/AaruAPI/TimeZoneMiddleware.swift`, added in `Client+Aaru.swift`.
- **Web:**
  - The shell sets an `aaru_tz` cookie.
  - `src/lib/api/client.ts` forwards the cookie as the header.
- **Fallback:** when there is no header, use the stored `user_progress.time_zone`, then UTC.

**The streak rule lives in AaruCore** (`aaru-core/Sources/AaruCore/Streak.swift`), shared by the server and the widget:
- A streak is alive if its last day is today or yesterday.
- Past days are never recomputed.
- Travel grace: a one-date gap is bridged when the time zone differs on either side and the days' first actions (`first_at`) are at most 48 h apart.

### Badge catalog: 61 badges, 9 hidden (H)

**Badge-row codes:**
- T = tiered.
- P = private, never shown to friends.
- L = library facts, imports count.
- E = live ledger.
- C = streak days.
- S = social tables.
- I = import jobs.
- M = listens.

- **Films:**
  - Opening Night (first film)
  - Cinephile T 10/100/250/1000
  - Silver Screen H (a film from before 1960)
  - Double Feature E (two films in one day)
- **Shows:**
  - Pilot
  - Box Set T episodes 100/1k/5k/10k
  - Credits Roll T shows 5/25/100
  - Season Pass T full seasons 10/50/200
  - Completionist T ended shows fully watched 1/10/25
  - Long Haul H (a show with 100+ episodes)
  - One More Episode H E (a whole season of 6+ episodes in one day)
  - Marathon E (10 episodes in one day)
  - Day One T E (watched within 24 h of airing) 1/10/50
  - Finale Night H E
- **Anime:**
  - Opening Theme
  - Simulcast T 5/25/100
  - Filler Arc T episodes 100/500/2000
- **Books:**
  - Bookmark
  - Bookworm T 10/50/100/250
  - Page Turner T pages 1k/10k/50k/100k
  - Doorstopper H (an 800+ page book)
  - Chapter a Day E (book progress on 7 days in a row)
- **Music (M):**
  - Needle Drop
  - Heavy Rotation T 100/1k/10k/50k
  - Crate Digger T artists 25/100/500
  - Liner Notes T albums 5/25/100 (L)
- **Ratings and notes:**
  - First Verdict
  - Critic T 25/100/500/1000
  - Ten Out of Ten H
  - Tough Crowd H
  - Margin Notes T P 10/50/200
- **Lists, shelves and owned:**
  - Curator
  - Archivist T 3/10/25
  - Shelf Life
  - Collector T P 25/100/500
- **Imports (I):**
  - Moving In
  - Well Travelled T sources 2/4/6
  - 10 source stamps: Trakt, Stremio, IMDb, Letterboxd, Goodreads, CAT, Netflix, MAL, AniList, CSV
- **Discovery (L):**
  - Genre Hopper T 5/10/15
  - Time Traveller T decades 4/6/8
  - Channel Surfer T networks 5/15/30
  - All-Rounder (one of every kind)
- **Streaks (C):**
  - Unbroken T 7/30/100/365
  - Comeback H
  - Night Owl T E (progress between 00:00 and 04:59) 10/50/200
- **Social (S):**
  - Plus One
  - Inner Circle T 5/10/25
  - Ambassador T invites 1/5/10
  - Tastemaker T recommendations 1/10/50
  - Good Call H (5 of your recommendations added by friends)
  - Applause T reactions 10/100
  - Watch Party T E 1/5/25

**Dropped because the data doesn't exist on main:** country and language badges, rewatches, concerts. Group message counts are dropped too, because they would reward spam.

## API (`aaru-server/Sources/AppAPI/openapi.yaml`)

**`GET /v1/me/progress`** returns:
- `{total, level, levelStart, nextLevelAt, weekPoints}`;
- `streak {current, longest, today, days[7]}`;
- `unseen {count, origin: live|batch|backfill, items ≤5}`. Each item is a `BadgeAward`, which carries `reveal` for a top-tier award.

**Badges and points:**
- **`GET /v1/me/badges`** returns the whole catalog with progress. A hidden badge that isn't earned yet sends only `{id, hidden}`: the server never ships the rule or the copy for it.
- **`POST /v1/me/badges/seen`** with `{ids}` answers 204.
- **`GET /v1/me/points?before=`** returns ledger pages, for a "how you earned it" list.

**`GET /v1/social/leaderboard?week=YYYY-Www`:**
- Covers the viewer plus friends who opted in.
- Blocks are filtered both ways.
- Weeks are counted on each person's local dates.
- A viewer who has not opted in gets `optedIn: false` and an empty list.

**`SocialSettings`** gains `showAchievementsToFriends` and `leaderboardOptIn`:
- Optional on PUT, so old TestFlight builds don't reset them.
- Always present in the response.

**`FriendProfile.achievements?`** is `{level, badges[]}`:
- Sent only when the friend's switch is on.
- Independent of library sharing.
- Never includes private badges.
- The existing 404s are unchanged.

**How clients find out about unlocks:** they re-read `/v1/me/progress` after a write. Web relies on the existing POST cache invalidation in `src/start.ts`. iOS uses a debounced `refreshSoon` from `LibraryModel.upsert`.

## Client surfaces

Agents draft the screens; the owner judges mockups before these PRs merge.

**Achievements has no tab of its own.** It opens from:
- the Home streak/level strip;
- the "You" card on Friends;
- Insights.

**Web (`aaru-client/src`):**
- New:
  - `lib/timezone.ts`
  - `lib/achievements/{model,model.test,server}.ts`
  - components `StreakBar`, `BadgeShelf`, `BadgeMedallion`, `Leaderboard`, `UnlockWatcher` (the toast through `~/components/ui`; batch and backfill give one summary), `BadgeReveal` (a ui `Dialog` animated with `motion/mini`; respects reduced motion)
  - route `_shell.app_.achievements.tsx`, plus its entry in `size-budget.json`
- Modified:
  - `lib/api/client.ts` (header)
  - `components/shell/AppShell.tsx` (cookie and watcher)
  - `lib/queries.ts`
  - `_shell.app.tsx` (Home strip)
  - `_shell.app_.friends.$handle.tsx` (shelf and level)
  - `_shell.app_.friends.index.tsx` ("You" card and "This week" board, or an opt-in card)
  - `_shell.app_.settings.friends.tsx` and `FriendsCard.tsx` (the two switches)
  - `lib/social/server.ts`

**iOS and Mac (`aaru-ios/Aaru`):**
- New, under `Achievements/`:
  - `ProgressModel` (`@Observable`)
  - `AchievementsView`
  - `BadgeShelf`
  - `BadgeMedallion`
  - `StreakBar`
  - `UnlockToast` (`.sensoryFeedback(.success)`)
  - `BadgeReveal`
  - `LeaderboardSection`
- Modified:
  - `Session/AppServices.swift`
  - `RootView.swift` (hosts the toast)
  - `Home/HomeSections.swift` and `HomeModel.swift`
  - `Library/LibraryModel.swift`
  - `Social/FriendProfileView.swift`
  - `Social/FriendsView.swift` (toggles, "You" card, board)
  - `Social/SocialModel.swift`

**Widget (WID-007):**
- `Shared/WidgetSnapshot.swift` gains the streak days.
- New `AaruWidgets/StreakWidget.swift`, small and accessory sizes: a flame, the day count and 7 bars.
- Timeline entries at the next two local midnights, using AaruCore's `Streak`.
- Registered in `AaruWidgetsBundle.swift`.

## Backfill

The worker treats a user with no `user_progress` row as dirty, with origin `backfill`:
1. Create `user_progress` with 0 points. No points are backfilled.
2. Fill streak days only from ticks with `watched_at_known = true`.
3. Evaluate the milestone badges.
4. Clients show one toast: "Aaru gives badges now. You've already earned N."

The worker is throttled to one user per tick and is idempotent.

## PR order

All work is in a worktree off `origin/main`. Each PR:
- updates the BACKLOG status rows;
- regenerates clients after any `openapi.yaml` change (`./scripts/generate-api-client.sh`, `npm run api:generate`).

0. **Docs and decisions.**
   - Spec `docs/superpowers/specs/2026-10-22-achievements-design.md`, with the catalog as an appendix for owner review.
   - BACKLOG "Decisions recorded 2026-10-22".
   - CLAUDE.md: the exceptions sentence, and domain terms Badge, Streak, Level.
   - ARCHITECTURE.md §Gamification rewrite, and the social settings line.
   - DESIGN.md: §17 Achievements subsection, the §16 streak widget, the §18 switches.
   - VIEWS.md: `StreakBar` and `BadgeShelf` props.
   - `docs/privacy.md`: the stored time zone, what friends see, the opt-in board.
1. **Ledger, levels and time zone (server, GAM-001/002).**
   - Migration `AddGamification`.
   - `Data/Stores+Gamification.swift` and `Data/Fluent/PostgresGamificationStore.swift`.
   - `Gamification/{PointsRules,Levels,GamificationService}.swift`.
   - `API/ClientTimeZoneMiddleware.swift` and `API/GamificationHandlers.swift`.
   - The hooks above.
   - `/v1/me/progress` and `/v1/me/points`.
   - The Apple `TimeZoneMiddleware`.
   - `TestSupport+UntouchedGamification.swift`.
2. **Streaks (server and AaruCore, GAM-003).** Migration `AddStreaks`, `Streak.swift`, milestone bonuses, and the `progress.streak` field.
3. **Badges and backfill (server, GAM-004).**
   - Migration `AddBadges`.
   - `BadgeCatalog`, `BadgeRules`, `GamificationWorker`.
   - The facts query, inline evaluation, and taking tiers back on undo.
   - The badges endpoints.
   - An achievements section in `Export/AccountExport.swift`.
4. **Visibility and leaderboard (server, GAM-005).** Migration `AddAchievementSettings`, partial PUT, `FriendProfile.achievements`, and the leaderboard endpoint.
5. **Web.**
6. **iOS and Mac.**
7. **Streak widget (WID-007).**

## Verification

**Server tests** (Postgres via `docker compose up -d`; `LibraryHarness`), drawn from BACKLOG's "Done when" criteria:
- **GamificationTests:**
  - the same scrobble twice awards once;
  - undo then redo nets one award;
  - unfriend under 7 days reverses the friend award, over 7 days does not;
  - re-friending earns nothing;
  - caps hold;
  - imports and plans award nothing per item;
  - a `user_progress` rebuilt from the ledger equals the cached row.
- **LevelTests:** table-driven.
- **StreakTests:**
  - 23:50 and 00:10 local count as two days;
  - a time-zone change never breaks a past streak;
  - travel grace;
  - imported ticks write no streak day.
- **BadgeRuleTests:** one row per badge and every tier boundary.
- **BadgeEvaluatorTests:**
  - re-running awards nothing;
  - an import gives a batch origin;
  - undo takes back the tier;
  - a hidden badge is redacted;
  - private badges never reach a friend's view.
- **LeaderboardTests:**
  - someone who has not opted in never appears on anyone's board;
  - blocks apply both ways;
  - local-date weeks;
  - excluded kinds;
  - an old client's PUT leaves the new fields unchanged.

**Commands:**
```bash
cd aaru-server && docker compose up -d && swift test
swift test --package-path aaru-core
./scripts/generate-api-client.sh && swift test --package-path aaru-api
cd aaru-client && npm run api:generate && npm run check && npm run lint && npm run typecheck && npm test && npm run build && npm run size
xcodebuild build -project aaru-ios/Aaru.xcodeproj -scheme Aaru -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

**End to end:**
1. Run the server and web locally. Tick episodes and check that the toast shows, the Home strip updates, and the badge moves onto the shelf.
2. Undo, and check that the points drop.
3. Run a CSV import, and check that there is one summary toast and that the streak does not change.
4. With a second account as a friend: check the profile shows the badges, that turning the switch off hides them, and that the board appears only after opting in.
5. Use iOS through TestFlight for the toast, haptic and reveal (owner rule: verify on TestFlight, not locally).
6. Check that the streak widget flips at local midnight with the app closed.

## Risks

- **Write latency.** Points are recorded inside the library transaction, so marking a whole season must stay one `unnest` statement per table. Measure it.
- **Genre and page backfill is unfinished.** Genre Hopper and Page Turner undercount until `titles.genres` and `page_count` are complete. Those badges then arrive as ordinary live unlocks.
- **Hidden-badge copy sits in the source,** so it stays secret only while the repo is private.
- **Old TestFlight builds don't send `X-Timezone`.** Their streak days fall back to the stored zone or UTC.
