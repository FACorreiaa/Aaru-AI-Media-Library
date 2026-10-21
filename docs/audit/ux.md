# UX / information architecture audit (2026-10-21)

Wave 1 · A of the whole-app audit. Read in full: every route in `aaru-client/src/routes` (33
files) with the settings, nav, empty and error components they render, and every `.swift` file
in `aaru-ios/Aaru` (139 files). Docs only: this file is the spec the Apple (B) and web (C)
agents implement. The target IA is `DESIGN.md` §18 "Navigation and Settings"; `VIEWS.md`
"Surface map" matches it.

Paths: `web:` is `aaru-client/src/`, `ios:` is `aaru-ios/Aaru/`. Severity: **high** hides a
destination, states something false, or loses the user's place; **med** a dead end, a missing
state or copy that breaks `CLAUDE.md` domain language; **low** drift and polish. Status starts
`open`; B and C mark each `fixed` or `deferred (reason)` in their PRs.

Checked and fine, so not listed: neutral status words where no kind is chosen (Home count chips,
Library "All", Insights tiles: `CLAUDE.md` allows "Planned / In progress / Finished / Dropped"
for no kind); "watchlist" only as Trakt / IMDb / Letterboxd's own word; group invites are
friends-only with no link or code anywhere; "Not end-to-end" on every web channel and on Apple
text, title and watch channels; `@aaru` posts only when tagged; member roles owner / admin /
member; Home's heading "The Field" with the nav label "Home" (§1, owner); "Your artists on tour"
on Discover (§13a records why it is not a recommendation).

## Findings

### Navigation

| ID | Sev | Platform | Where | Problem | Fix | Owner |
| --- | --- | --- | --- | --- | --- | --- |
| UX-001 | high | iPhone | `ios:RootView.swift:174-203`, `:43` | Seven tabs under `.sidebarAdaptable`. A compact tab bar shows four plus More, so Lists, Groups (and its mention badge, `:40`) and Settings sit behind More, each with a nested `NavigationStack`. | Compact tab bar: Home · Discover · Library · Calendar · Groups. Lists from Library and Home; Insights from Home and Library; Settings from an account button as a sheet (§18). | apple |
| UX-002 | high | web | `web:components/AppHeader.tsx:7-15`, every `app_.*` page | A scrolling pill row per page; no shell. Settings sits among the destinations; Insights is not in nav at all. | One layout route with the sidebar of §18: six destinations, then Insights and Settings at the bottom, account row last. | web |
| UX-003 | med | Mac | `ios:RootView.swift:175`, `ios:Settings/SettingsWindow.swift:32-61` | Settings is both a sidebar row and the ⌘, window, with different contents (window has "General", no Insights, no Notifications). | Drop the Settings row on macOS; the Settings scene is the only Settings, with the panes of §18. | apple |
| UX-004 | med | both | `web:routes/app_.settings.recaps.tsx:19-24`, `ios:Settings/SettingsView.swift:57-58`, `ios:Library/LibraryView.swift:186` | Insights is reached from Home's strip, a Settings page and (Apple) Library's More menu. It is a destination filed as a setting. | Insights in the sidebar's bottom group (web, iPad, Mac). iPhone: Home's Last 7 days and Library's More menu. Remove the Settings page. | both |
| UX-005 | med | web | `web:routes/app_.week.tsx:76`, `web:components/AppHeader.tsx:11`, `web:routes/app.tsx:585` | The URL is `/app/week`; the nav, `<title>` and h1 say Calendar. Week is one of its three modes. | Route `/app/calendar` (`?view=week|month|missed`), `/app/week` redirects keeping search. | web |
| UX-006 | med | web | `web:routes/app_.title.$id.tsx:238-246`, `app_.lists.$id.tsx:127-135`, `app_.imports.$id.tsx:107-116`, `web:components/RouteError.tsx:16-49` | Detail and error pages drop the nav for a hand-rolled header. The title page's back link always reads "Library", whatever page opened it. | Every `/app` page inside the shell. Back link names where you came from (history state), else the owning destination. | web |
| UX-007 | med | web | `web:components/AppHeader.tsx:40-55`, `web:routes/app_.discover.tsx:129` | Search opens in place only where the page passes `onSearch`; elsewhere it navigates to Library. | One Search in the sidebar (and ⌘K) that opens the search dialog in place on every page. | web |
| UX-008 | med | web | `web:components/AppHeader.tsx` | No mention or invite count on Groups; Apple badges the tab (`ios:RootView.swift:40`). | Mention total as a badge on the Groups sidebar row. | web |
| UX-009 | low | web | `web:components/AppHeader.tsx:57-59` | Sign out in the global header and again in Account. | Account page only; the sidebar's account row opens Account. | web |
| UX-010 | med | web | `web:components/RouteError.tsx:43-48` | Not found's "Go home" is `href="/"`, so a signed-in user lands on the marketing page. | `/app` when the path is under `/app` (as `RouteError` already does at `:14`). | web |
| UX-011 | high | web | `web:routes/app.tsx:91`, `app_.plans.$id.tsx:12`, `app_.title.$id.tsx:62` (every `/app` `beforeLoad`), `web:routes/auth.verify.tsx:40` | Sign-in redirects drop the destination, so a push to a request or a title loses its target after sign-in. Only `/connect/extension` and `/oauth/consent` pass `next`. | Every app redirect passes `next: location.href`; sign-in and the magic link keep it. | web |
| UX-012 | med | Apple | `ios:RootView.swift:125-140` | A notification tapped while signed out is held in `PushInbox` but never re-read after sign-in (`onChange` will not fire again). | Re-check `PushInbox` when `isSignedIn` turns true. | apple |
| UX-013 | low | web | `web:routes/app_.title.$id.tsx:59`, `app_.lists.$id.tsx:34`, `app_.groups.tsx:31` (children set no head) | Tab titles read "Title · Aaru", "List · Aaru", "Groups · Aaru" on every channel. | The item's name: "Andor · Aaru", "Films to show Dad · Lists · Aaru", "#general · Book club · Aaru". | web |
| UX-014 | med | web | `web:components/LegalPage.tsx:24`, `web:components/Brand.tsx:9`, `web:routes/app_.settings.about.tsx:56-61` | Settings → About links to the public About and Privacy pages, whose wordmark goes to the landing page: no way back into the app. | Signed in: a "‹ Settings" back link and the wordmark to `/app`. | web |
| UX-015 | low | web | `web:routes/index.tsx:20`, `:110-115`, `:40` | The landing page ignores the session ("Sign in" for a signed-in visitor). Its FAQ says sharing is still to come ("when it arrives"). | "Open Aaru" when signed in; FAQ names friends and groups as they are. | web |
| UX-016 | med | both | `web:components/MusicSection.tsx:139-144`, `web:components/music/MusicInsights.tsx:107`, `ios:Library/LibraryView.swift:187`, `ios:Settings/MusicSection.swift:23-25` | The listen log is reached from different places per platform. On the web, with no listens yet, only by typing `/app/music`. | Same two doors on both: Insights' music block ("All listens", always shown) and Library's More menu. Connections → Music links to it once a listen exists. | both |
| UX-017 | low | Apple | `ios:RootView.swift:141-148` | No deep link to a Settings page, so empty states cannot send you to the page that fixes them. | `aaru://settings/<slug>` with the web's slugs (§18). | apple |

### Settings

| ID | Sev | Platform | Where | Problem | Fix | Owner |
| --- | --- | --- | --- | --- | --- | --- |
| UX-020 | high | both | `web:components/settings/SettingsNav.tsx:5-31`, `ios:Settings/SettingsView.swift:5-11`, `:38-63`, `ios:Settings/SettingsWindow.swift:32-61` | Five groups (Account, Imports & export, Connected apps, Insights & recaps, About) with friends, notifications, appearance and concerts all under Account. Not the owner's 2026-10-21 IA. | Rebuild to the eight pages of §18, with the exact section moves listed there. | both |
| UX-021 | med | both | `web:routes/app_.settings.about.tsx:65-90`, `ios:Settings/AboutView.swift:76-104` | Delete account sits under About. | Its own last page, danger-styled, confirm dialog, link to Export (Mac: bottom of the Account pane). | both |
| UX-022 | med | both | `web:components/settings/AccountPage.tsx:105-107`, `ios:Settings/AccountSettings.swift:23` | "Concerts near" lives under Account. | Friends & privacy → "Location": the one place Aaru stores where you are. | both |
| UX-023 | med | both | page "Connected apps" (`web:routes/app_.settings.connected.tsx:30`, `ios:Settings/ConnectedAppsSettings.swift:17`); section "Connections" (`web:components/ConnectionsSection.tsx:94`, `ios:Settings/ConnectionsSection.swift:46`); "Settings → Connections" in `web:routes/connect.extension.tsx:153-154`, `web:routes/oauth.consent.tsx:120`, `ios:Settings/BrowserExtensionView.swift:26` | Three names for one place, and the consent and extension pages name a page that does not exist. | The page is **Connections** (`/app/settings/connections`), with sections Agents, Stremio, Music. | both |
| UX-024 | low | both | `ios:Settings/MusicSection.swift:40`, `:68`, `web:components/MusicSection.tsx` vs Stremio and Connections "Revoke" | Two verbs for ending a connection. | "Disconnect" everywhere; the confirm says what stops ("Claude Code can no longer reach your library"). | both |
| UX-025 | med | both | `web:components/StremioSection.tsx:233`, `ios:Settings/StremioSection.swift:217` | The Stremio addon and Stremio history live on different pages; the cross-reference is plain text. | Connections → Stremio gets a link "Import your Stremio history" to Import; Import keeps the history source. | both |
| UX-026 | med | both | `web:components/settings/ImportsPage.tsx:103-181`, `web:lib/imports/model.ts:5-40`, `ios:Settings/ImportsSettings.swift:74-111`, `ios:Settings/ImportsModel.swift:16` | Sources are not in `CLAUDE.md`'s import order; "Any site" is first. | Trakt, then Stremio history, IMDb, Letterboxd, Goodreads, Pogdesign CAT, Netflix, MyAnimeList, AniList, and "Any other CSV" last. | both |
| UX-027 | low | both | `web:lib/imports/model.ts:9`, `ios:Settings/ImportsModel.swift:33` | The "Any site" hint names Simkl and Serializd, which `CLAUDE.md` lists as out-of-scope integrations. | "A CSV from any other site, or a spreadsheet. Aaru reads the columns." | both |
| UX-028 | med | web | `web:routes/index.tsx:48`, `web:components/ImportSources.tsx:4-13` | The landing page promises TV Time; no client offers it and the server has no such source (`openapi.yaml` import `source` enum: auto, imdb, letterboxd, netflix, goodreads, mal, csv). | Drop TV Time from the landing until the server has it. Owner: `CLAUDE.md` still lists TV Time in the import order. | web |
| UX-029 | med | Apple | `ios:Settings/SettingsView.swift:149-156` | Every Settings page shows one shared `imports.problem`, so an error from one page follows you to the next. | A problem per page (owned by that page's model). | apple |
| UX-030 | low | both | `web:components/settings/AccountPage.tsx:52-53` + `web:components/SocialSection.tsx:101-147`; `ios:Settings/AccountSettings.swift:15` + `ios:Social/FriendsView.swift:61` | The name shows read-only in one place and is edited under the handle in another. | Account → "Name and handle", one editor. | both |
| UX-031 | med | both | `ios:Push/PushRegistrar.swift:117-130`, `ios:Settings/AccountSettings.swift:59-61`, `web:components/NotificationsSection.tsx:16-33` | Agent-request alerts are sent but no setting mentions them. | Footer: "Requests from your connected agents always alert you." No new setting. | both |
| UX-032 | med | Mac | `ios:Settings/AccountSettings.swift:24-28` | Notifications are iOS-only; the Mac has no way to see or change them. | Mac Notifications pane with the same three account-level switches; footer "Alerts go to your iPhone and your browsers." | apple |
| UX-033 | low | web | `web:routes/app_.settings.index.tsx:25-34`, `web:components/settings/SettingsNav.tsx:47-48` | On a desktop, Account renders at two URLs. | Desktop `/app/settings` redirects to `/app/settings/account`; a phone keeps the list. | web |
| UX-034 | low | both | `web:components/settings/ImportsPage.tsx:184`, `ios:Settings/ImportsSettings.swift:120-133`, `web:routes/app_.imports.$id.tsx:127` | The jobs list vanishes when empty; the import page calls its home "Settings → Imports". | "No imports yet." under the heading; copy says "Settings → Import". | both |
| UX-035 | low | Apple | `ios:Settings/SettingsView.swift:29`, `:69` | `showsDone` is never set. | Use it: the iPhone account button presents Settings as a sheet with Done (UX-001). | apple |

### Domain language

| ID | Sev | Platform | Where | Problem | Fix | Owner |
| --- | --- | --- | --- | --- | --- | --- |
| UX-040 | high | both | web: `routes/app_.library.tsx:238`, `routes/app.tsx:476`, `components/HomeRows.tsx:418`, `components/SearchPanel.tsx:281`, `routes/app_.imports.$id.tsx:128`, `:154`, `lib/imports/model.ts:138`, `components/recap/RecapCards.tsx:96`, `routes/index.tsx:134`, `:166`, `routes/sign-in.tsx:120`, `routes/about.tsx:30`. ios: `Library/LibraryView.swift:76`, `Search/SearchView.swift:281`, `:284`, `WelcomeView.swift:76`, `:84`, `Settings/ImportDetailView.swift:43`, `:51`, `Settings/ImportLedger.swift:56`, `Recap/RecapCards.swift:19`, `Discover/ConcertsView.swift:98` | "Shelf" used for the library. A Shelf is a saved query (`VIEWS.md` "Shelf is not a List"). | "library": "Your library is empty", "In your library", "New in your library", "Check against your library", "Everything you watch, read and listen to, in one library". | both |
| UX-041 | med | both | `web:lib/groups/kinds.ts:34`, `web:components/groups/ShelfView.tsx:119`; `ios:Groups/Kinds/NewChannelSheet.swift:10`, `:20`, `:29`, `ios:Groups/Kinds/ShelfChannelView.swift:113`, `:127` | The `shelf` channel kind is labelled "Shelf", but it is membership the group edits: a list. | UI label "List" ("A list the whole group adds to", "Nothing on this list yet", "Remove from list"), its own symbol (not `books.vertical`). The stored kind stays `shelf`. Owner: `CLAUDE.md` names the kind `shelf`; say if the doc should change too. | both |
| UX-042 | med | both | web: `components/groups/Composer.tsx:175`, `:182`, `ChannelList.tsx:251`, `MemberList.tsx:75`, `:88`, `:222`, `lib/groups/agent.ts:91-93`. ios: `Groups/Composer.swift:41`, `:87`, `MessageRow.swift:79`, `:82`, `:212`, `ChannelView.swift:158`, `:222`, `GroupSheets.swift:68`, `:255`, `Kinds/SpoilerChoice.swift:82`, `:90`, `Kinds/DiscussInGroupSheet.swift:58`, `AgentViews.swift:64` | Group posts called "Message" / "messages". In `CLAUDE.md`, Message is the end-to-end DM. | Composer "Write in #general"; explanatory copy says "group messages" (as `ChannelHeader` already does); row states drop the noun: "Deleted", "Hidden: from someone you blocked", "New" divider, "Load earlier". | both |
| UX-043 | med | both | `web:components/library/NowSection.tsx:244-248`, `ios:Library/NowSection.swift:206`; `web:lib/library/now.ts:87`, `ios:Library/LibraryModel+Now.swift:39`; `web:lib/groups/kinds.ts:127-128`, `ios:Groups/Kinds/TitleChannelHeader.swift:182-191` | Kind is known but the words are not the kind's: a book's close button says "Finished"; a film or show without progress reads "In progress"; a member's progress reads "Finished" / "Not started" for any kind. | "Mark read"; "Watching"; the kind's status words (Watched / Read / Listened, Plan to watch…). | both |
| UX-044 | low | both | `ios:Library/NowSection.swift:189`, `ios:Title/TitleDetailView.swift:236`, `ios:Home/TonightCard.swift:83`, web twins | Three phrasings of one tick: "Watched S1 · E5", "Mark S1 · E5 watched", "Mark watched". | "Mark S1 · E5 watched" where the episode is named, "Mark watched" where it is not (DESIGN §6 updated). | both |
| UX-045 | low | both | `ios:Lists/ListItemRow.swift:36`, `ios:Home/HomeCards.swift:189`, `web:lib/groups/kinds.ts` (`episodeCode`) | Episode codes in "S1 · E8", "S1E8" and "S01E05". | "S1 · E8" everywhere; "S01E05" only in the week cell (§14). One formatter per client. | both |
| UX-046 | low | Apple | `ios:Library/LibraryView.swift:267`, `ios:Lists/ListItemRow.swift:60`, `ios:Title/TitleDetailView.swift:222` | Plural kind for one item ("2022 · Shows"). | `kind.noun` ("Show"), as Search does. | apple |
| UX-047 | low | both | `web:routes/app_.title.$id.tsx:221-223`, `ios:Title/TitleDetailView.swift:221` | The catalog's show status shown raw ("Returning series", "ended"). | One label map (Apple has `ShowStatusPayload.label`, `ListItemRow.swift:65-74`). | both |
| UX-048 | low | both | `web:routes/app_.library.tsx:215`, Apple Library Layout menu, `web:routes/app_.discover.tsx:213-246`, `ios:Discover/DiscoverScreen.swift:186` | "List" as a layout name and "Lists from TMDB…" in the credit, next to List the domain object. The credit also leaves out Open Library (Apple) and the music sources (both). | Layout "Grid / Rows"; credit "Rows from …" built from the providers on screen. | both |
| UX-049 | low | both | `web:routes/app_.music.tsx:25`, `:56`, `ios:Music/MusicView.swift:46`, `ios:Settings/MusicSection.swift:55`, `web:routes/app.tsx:570` | "Music" is both the albums kind and the log page; "Listening" is albums in progress and the log link; "listening log" a third name. | The log page is **Listens** (the `CLAUDE.md` word), linked as "All listens ›". "Listening" stays for albums in progress. | both |
| UX-050 | low | both | `ios:Discover/SeasonBrowser.swift:130`, `:162`, `ios:Discover/ConcertsView.swift:59`, `:209`, web `SeasonBrowser` / `ConcertList` twins | Vendor names as the subject of errors ("AniList isn't answering", "Ticketmaster isn't answering"). | "This season's list isn't answering", "Concert listings aren't answering"; vendors stay in the credit line. | both |
| UX-051 | low | both | `web:lib/groups/kinds.ts:29`; `ios:Groups/Kinds/NewChannelSheet.swift:9`, `WatchPanel.swift:41`, `:161`, `:261` | The `watch` kind reads "Watch party"; `CLAUDE.md` calls the session a Room. | Owner's call: record "Watch party" as Room's UI word in `CLAUDE.md`, or rename. No client change until then. | owner |
| UX-052 | low | both | `web:components/HomeRows.tsx:220-227`, `ios:Home/HomeScreen.swift:291`; `ios:Home/HomeScreen.swift:264`, `ios:Title/TitleRoomParts.swift:103` | "Start watching" holds albums, and on Apple also names the Live Activity menu item. | Albums out of Start watching (they have Listening); the menu item "Watching now…". | both |
| UX-053 | low | both | `web:routes/app_.music.tsx:35-40`, `ios:Music/MusicView.swift:175` vs Insights spans | "This year" on Listens, "Year" on Insights. | "Year" on both. | both |
| UX-054 | low | both | `ios:Insights/InsightsView.swift:49-55`, `web:routes/app_.settings.recaps.tsx:15-17`, `ios:Recap/RecapCards.swift:19`, `ios:Groups/GroupsScreen.swift:207-211` | Copy says "watched and read", leaving out listening, which these surfaces count. | "watched, read and listened to". | both |

### Dead ends and states

| ID | Sev | Platform | Where | Problem | Fix | Owner |
| --- | --- | --- | --- | --- | --- | --- |
| UX-060 | high | both | web: `components/settings/ImportsPage.tsx:100-101`, `routes/app_.imports.$id.tsx:181`, `components/ConnectionsSection.tsx:97-98`, `components/StremioSection.tsx:73-74`, `:202`, `routes/oauth.consent.tsx:99`. ios: `Approvals/PlanCardView.swift:98`, `Settings/ImportDetailView.swift:71`, `Settings/ConnectionsSection.swift:49-51` | Copy promises "undo it from your history"; neither client has a history. `GET /v1/actions` and `POST /v1/actions/{id}/undo` exist and are uncalled. | **History** on Settings → Your data: journaled actions newest first, who made them (you, an import, a connection), Undo. An applied import or request links to it. Until it ships, the copy must not promise it. | both |
| UX-061 | high | both | `web:routes/app_.title.$id.tsx`, `ios:Title/TitleDetailView.swift`; `ios:Title/LibraryEntryDestination.swift:27` | No way to remove a title from the library on either client; `DELETE /v1/library/items/{id}` is unused. | "Remove from library" in the title room's menu, confirmed, journaled (undo in History). | both |
| UX-062 | high | Apple | `ios:Calendar/CatchUpView.swift:15-17`; `ios:Library/LibraryView.swift:74` | A failed fetch reads as a fact: Missed says "You are all caught up"; a failed first sync says the library is empty. | Gate empty states on a successful load; a failure gets the error state of UX-063. | apple |
| UX-063 | med | Apple | `ios:Home/HomeScreen.swift:129` + `HomeModel.swift:181-183`; `ios:Insights/InsightsView.swift:68-70`; `ios:Lists/ListsModel.swift:97-105`; `ios:Groups/GroupLists.swift:10-33`; `ios:Groups/ChannelModel.swift:71-76`; `ios:Groups/Kinds/ShelfChannelView.swift:27-33`; `ios:Groups/Kinds/TitleChannelHeader.swift:44-49`, `:84-86`; `ios:Groups/Kinds/WatchPanel.swift:31-32`, `:48-50`; `ios:Week/WeekDayPager.swift:78`; Month has no loading state (`ios:Calendar/MonthView.swift`) | First-load failure leaves an endless spinner or a blank screen, with the reason only in a banner and no retry (Home's spinner is outside the ScrollView, so pull-to-refresh is gone too). | One shared error state (`ContentUnavailableView`, the reason, "Try again") once a first load fails; a spinner only while loading. | apple |
| UX-064 | med | web | `web:routes/app_.groups.$groupId.$channelId.tsx:23`, `:56-73`; `web:routes/app_.groups.$groupId.tsx:25-32` | A network failure reads "This channel is gone."; a failed group load silently redirects to Groups. | "Gone" only on 404; otherwise an error with Try again. | web |
| UX-065 | med | Apple | `ios:Groups/GroupsModel.swift:118-121` | Any failed group-detail load (a 500 included) removes the group from the list. | Forget it only on 403 / 404; anything else is a problem. | apple |
| UX-066 | med | web | `web:components/DiscoverRows.tsx:113`, `web:routes/app_.discover.tsx:190`, `:202` | Empty Discover rows show nothing; Seasons and Concerts suspend with no fallback. | Apple's empty copy (`ios:Discover/DiscoverScreen.swift:139-147`); still placeholders at real size (§13a). | web |
| UX-067 | med | Apple | `ios:Week/WeekModel.swift:57-59`, `ios:Calendar/AgendaList.swift:32-41`, `ios:Calendar/CatchUpView.swift:17-22` | Calendar empty states ignore filters ("add shows" when Anime or Finales hides them). The web already says "with these filters". | "No episodes match these filters" + "Clear filters". | apple |
| UX-068 | med | Apple | `ios:Calendar/CalendarScreen.swift:71`, `ios:Calendar/DaySheet.swift` | Probable dead tap: on iPhone a Month day opens as a sheet, and its rows ask CalendarScreen to present the episode sheet over it. Not verified on a device. | Present the episode sheet from inside DaySheet (or push in its stack); verify on TestFlight. | apple |
| UX-069 | med | Apple | `ios:Calendar/CalendarEpisodeSheet.swift:37-38` | No Done; on the Mac the only way out is "Open show". | A `.cancellationAction` Done. | apple |
| UX-070 | med | iPhone | `ios:Title/TitleDetailView.swift:266-272` | The book Page field uses the number pad and saves on submit only; the number pad has no Return, so the page never saves. | Save on focus loss or a Save button, as the Now card does. | apple |
| UX-071 | med | Apple | `ios:Library/LibraryView.swift:43-47` | A pushed library item that is missing renders an empty screen. | `LibraryEntryDestination`, as Home and Calendar use. | apple |
| UX-072 | med | both | `web:routes/app_.lists.$id.tsx:307-329`, `ios:Lists/ListsView.swift:180-182` | A list member not in the library is inert text: you cannot open it or add it. | An Add control on the row (tap: Plan to …; hold: status or list), as Discover cards have. | both |
| UX-073 | med | both | `web:components/HomeRows.tsx:384-391`, `web:components/SearchPanel.tsx`, `ios:Search/SearchView.swift`, `ios:Home/DiscoverCard.swift` | A search hit or Discover card not in the library cannot be opened before adding; the title room needs a library item. | Owner's call: a catalog-only title room needs a route by `MediaRef`. Until then, make the check after adding a link to the new item. | owner |
| UX-074 | med | both | `ios:Groups/GroupLists.swift:63-72`, `ios:Groups/GroupSheets.swift:289-292`; `web:routes/app_.groups.index.tsx:120-138` | "Choose a handle first, in Settings → …" and "No friends yet" are plain text on Apple; Friends is only reachable deep in Settings though Groups depends on it. The web links, to an anchor that moves. | Buttons: "Choose a handle" → Settings → Account; "Add friends" → Settings → Friends & privacy (Apple via `aaru://settings/…`; web `/app/settings/account#handle`, `/app/settings/friends`). | both |
| UX-075 | med | both | `web:routes/app.tsx:615-678`, `ios:Home/HomeScreen.swift:119-128`, `ios:Home/DiscoverCard.swift:156-163`, `ios:Home/HomeModel.swift:90-93`; `web:routes/app_.library.tsx:237-250`, `ios:Library/LibraryView.swift:75-88` | A new account's Home and Library offer Search and Discover but never Import, the one thing `DESIGN.md` §8 calls the main onboarding. Apple says "Add a show" to an account with only books; the headline is duplicated. Filtered-empty Library has no Clear filters. | Secondary action "Bring your history" → Settings → Import; one headline, "Add something to see what's next"; "Clear filters" on filtered empty. | both |
| UX-076 | med | Apple | `ios:Groups/Kinds/ShelfChannelView.swift:191-208`, `ios:Groups/ChannelHeader.swift:44-47` | The shared-list channel never shows "Not end-to-end" (the web's does, `web:components/groups/ShelfView.tsx:106`). The chip's popover leaves out that `@aaru` reads recent group messages. | `ChannelHeader` on that channel; popover adds "When someone tags @aaru, it reads this channel's recent group messages to answer." (web too). | both |
| UX-077 | med | Apple | `ios:Music/MusicView.swift:77-83` | "No listens yet" points to "Settings → Connected apps" in words only. The web links. | A "Connect a scrobbler" button to Connections → Music. | apple |
| UX-078 | med | both | `web:routes/app_.imports.$id.tsx:140-142`, `:202`; `ios:Settings/ImportDetailView.swift:25-32`, `:59`, `:94` | A failed import cannot be discarded; rows are cut at 200 with no count of the rest. | "Remove this import" on a failed job, back to Import; "Showing 200 of 1,204". | both |
| UX-079 | low | Apple | `ios:Lists/ListsView.swift:35-46`, `:193`, `:220`, `:288-294` | Deleting a list has no confirm (the web asks); the picker titled "Add “X”" does not mark lists that already hold it; the name sheet closes on a failed save. | Confirm "The list goes; the titles stay in your library."; pre-mark membership; title "Add “X” to a list"; stay open on failure. | apple |
| UX-080 | low | web | `web:routes/app.tsx:541-546` | Home's "New list" chip goes to Lists without starting one. | `/app/lists?new=1` focuses the name field. | web |
| UX-081 | low | web | `web:routes/app_.recap.tsx:47-66`, `:108` | Closing a recap always goes to Home; changing `?year&month` in place does not reload. | Close goes back; load on search change. | web |
| UX-082 | low | Apple | `ios:Approvals/PlanCardView.swift:119` | A request decided in the sheet leaves Home's "Waiting for you" stale. | Wire `onDecided` to reload Home's plans. | apple |
| UX-083 | low | both | `ios:Groups/Kinds/DiscussInGroupSheet.swift:6-8`, `:38`, `ios:Title/TitleDetailView.swift:84-88`, `web:components/groups/DiscussButton.tsx:9` | "Discuss in a group" exists only for groups you manage; a plain member cannot jump to an existing title channel. | List every group; "Open" where the channel exists, otherwise only managers see "Start". | both |
| UX-084 | low | both | `ios:Groups/GroupSheets.swift:135-141`, `web:components/groups/ChannelList.tsx:93-146` | An owner sees Delete group but no Leave, and no hint why. | "Leave group…" for the owner explains "Make someone else owner first" and opens Members. | both |
| UX-085 | low | Apple | `ios:Groups/GroupsScreen.swift:205`, `ios:Groups/GroupSheets.swift:88-96`, `ios:Groups/GroupsScreen.swift:198-204` | On iPad and Mac, sidebar errors show only with a channel selected, and Members opens as a sheet from the menu but an inspector from the toolbar. | Banner on the split root; Members always the inspector in split layout. | apple |
| UX-086 | low | web | `web:components/groups/GroupRail.tsx:31`, `web:components/groups/ChannelList.tsx` | The rail's top item is titled "Home", like the app's Home; a phone's channel list has no "‹ Groups". | "Invites" (or "All groups"); a back link on phones. | web |
| UX-087 | low | web | `web:routes/app_.week.tsx:460-482` | The empty calendar's "Find shows to add" opens search over every kind. | Open Search scoped to Shows. | web |
| UX-088 | low | web | `web:routes/app_.library.tsx:85` | The kind filter is not in the URL (status is), so back and refresh lose it. | `?kind=`. | web |
| UX-089 | low | web | `web:routes/connect.extension.tsx` | "Connected. You can close this tab." has no way into the app. | Add "Open Aaru" → Connections. | web |
| UX-090 | low | Apple | `ios:Session/SessionStore.swift:37-39` | A 401 signs out silently. | Welcome shows "You were signed out. Sign in again." | apple |
| UX-091 | low | iPhone | `ios:Week/WeekView.swift:54-63` | Five arrow buttons plus the mode picker and Filters in one compact toolbar. | Compact: Today and the week arrows; days by swipe. | apple |
| UX-092 | low | Apple | `ios:Home/HomeCards.swift:164` | "Airing soon" opens the title while every calendar row opens the episode sheet. | The episode sheet, with "Open show" in it. | apple |

## Parity

Both have, in matching shape: Home rows, Tonight, Waiting for you; Discover Today / Seasons /
Concerts; Library with Now; Calendar Week / Month / Missed with filters; Lists; Groups with the
four channel kinds; Insights, Recap, Listens; every import; Connections (agents, browser
extension, Stremio, scrobblers); export; delete account; Link Google; appearance.

Neither has, though the server does: History and undo (UX-060), removing a library item
(UX-061), Shelves (saved queries, `/v1/shelves*`, `VIEWS.md` "Shelf"), reporting a user
(`/v1/social/reports`), a device list (`/v1/devices`). History and remove are findings because
copy and the domain depend on them; Shelves, report and devices are product work for the
owner to schedule, not audit fixes.

Platform-only, by design: Live Activity and widgets (Apple), Mac Settings window (Mac), consent
and extension-connect pages (web).

## Apple agent must do

- [ ] Root navigation per §18: iPhone tab bar Home · Discover · Library · Calendar · Groups; iPad
      and Mac sidebar Home · Discover · Library · Calendar · Lists · Groups, then Insights (and
      Settings on iPad) in a bottom `TabSection`; no Settings row on Mac (UX-001, UX-003, UX-004).
- [ ] iPhone: account button (`person.crop.circle`, top-trailing on Home and Library) presents
      Settings as a sheet with Done; Library gets a "Lists" entry; Library's More menu keeps
      Insights, Listens and Recaps (UX-001, UX-016, UX-035).
- [ ] Mac: Go menu ⌘1…⌘7 for the sidebar rows; ⌘, opens the Settings scene (UX-003).
- [ ] Settings rebuilt to the eight pages with the section moves of §18; iPhone/iPad list of
      `NavigationLink`s; Mac Settings scene as a `TabView` of seven panes with Delete account at
      the bottom of Account (UX-020, UX-021, UX-022, UX-023, UX-025, UX-030, UX-032).
- [ ] Import page in `CLAUDE.md` order, "Any other CSV" last, new hint, empty jobs line
      (UX-026, UX-027, UX-034).
- [ ] One verb, Disconnect; footer on agent-request alerts; per-page problem banner
      (UX-024, UX-029, UX-031).
- [ ] `aaru://settings/<slug>` deep links; push re-read after sign-in (UX-012, UX-017).
- [ ] Copy: "library" not "shelf"; shared-list channel label; group-message wording; per-kind
      status words; one tick phrasing; one episode code; `kind.noun`; show-status labels;
      Grid / Rows; Listens; vendor-free errors; Year; "watched, read and listened to"; Start
      watching without albums; "Watching now…" (UX-040…UX-050, UX-052…UX-054).
- [ ] History page (Your data) and Remove from library, both journaled with undo; if History
      cannot land in this PR, change the copy that promises it (UX-060, UX-061).
- [ ] States: no false empty states; one shared first-load error state with Try again;
      filter-aware Calendar empties; group detail failures keep the group (UX-062, UX-063,
      UX-065, UX-067).
- [ ] Dead ends: DaySheet episode tap (verify on TestFlight), episode sheet Done, book Page save,
      Library missing item, list members addable, handle/friends buttons, Music empty button,
      failed import removable + row count, list delete confirm and picker, plan sheet reload,
      Discuss for every member, owner Leave hint, split banner and inspector, 401 message, compact
      Week toolbar, Airing soon → episode sheet (UX-068…UX-072, UX-074…UX-079, UX-082…UX-085,
      UX-090…UX-092).

## Web agent must do

- [ ] Shell per §18: one pathless layout route with the sidebar (≥1024px persistent and
      collapsible, a Sheet below), six destinations, Insights and Settings at the bottom, account
      row; Groups mention badge; one in-place Search with ⌘K; Sign out only on Account; every
      `/app` page inside it, back links that name where you came from (UX-002, UX-006, UX-007,
      UX-008, UX-009).
- [ ] `/app/calendar` with `/app/week` redirecting; page titles from the item's name; Not found
      and legal pages lead back into the app; landing reads the session and has a current FAQ
      (UX-005, UX-010, UX-013, UX-014, UX-015).
- [ ] `next` through every sign-in redirect and the magic link (UX-011).
- [ ] Settings at `/app/settings/{account,friends,notifications,import,connections,data,about,delete}`
      with the sub-nav and section moves of §18; old slugs redirect; desktop `/app/settings` →
      account; Trakt returns to `import` (UX-020…UX-027, UX-030, UX-031, UX-033, UX-034).
- [ ] Drop TV Time from the landing and `ImportSources` (UX-028).
- [ ] Copy: "library" not "shelf"; shared-list channel label; group-message wording; per-kind
      status words; tick phrasing; episode code; show-status labels; Grid / Rows and the credit
      line; Listens; vendor-free errors; Year; "watched, read and listened to"; Start watching
      without albums (UX-040…UX-045, UX-047…UX-050, UX-052…UX-054).
- [ ] History page (Your data) and Remove from library, both journaled with undo; if History
      cannot land in this PR, change the copy that promises it (UX-060, UX-061).
- [ ] States and dead ends: channel and group load failures, Discover empty and fallbacks,
      list members addable, handle/friends links to the new slugs, Import on new-account empty
      states and Clear filters, popover `@aaru` line, failed import removable + row count,
      Home "New list", recap close and reload, Discuss for every member, owner Leave hint, rail
      naming and phone back, calendar search scope, `?kind=`, extension success link
      (UX-064, UX-066, UX-072, UX-074, UX-075, UX-076, UX-078, UX-080, UX-081, UX-083, UX-084,
      UX-086…UX-089).

## For the owner

- UX-001: the iPhone tab bar can hold five of the six destinations. This spec keeps Groups (its
  badge must show) and moves Lists into Library on iPhone only. Say if Lists should keep the
  tab instead.
- UX-041: the group `shelf` channel reads "List" in the UI; should `CLAUDE.md` rename the kind?
- UX-051: "Watch party" in the UI vs Room in `CLAUDE.md`.
- UX-028: TV Time is in `CLAUDE.md`'s import order but no source exists.
- UX-073: a title room for catalog titles not yet in the library needs a server route.
