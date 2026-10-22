# Apple audit: HIG, iPad and Mac (2026-10-21)

Wave 2 · B of the whole-app audit. Read in full: every `.swift` file in `aaru-ios/Aaru`,
`aaru-ios/Shared` and `aaru-ios/AaruWidgets`. One multiplatform SwiftUI target (iPhone, iPad,
native Mac, iOS 18 / macOS 15) plus the widget extension. The target IA is `DESIGN.md` §18; the
UX findings it implements are in `docs/audit/ux.md` ("Apple agent must do").

Paths are relative to `aaru-ios/`. Line numbers are from before the fix. Severity: **high** hides
a destination, states something false or breaks a platform convention users rely on; **med** a
missing state, a dead end, an accessibility failure; **low** drift and polish.

## Measured

- **Contrast** (WCAG 2.x relative luminance, from the color assets):

  | Text color | on Paper (light / dark) | on Surface (light / dark) | Verdict |
  | --- | --- | --- | --- |
  | Muted | 5.74 / 7.84 | 5.20 / 7.06 | passes 4.5:1 body text; asset unchanged |
  | Muted on Stone | 4.74 / 8.27 | | passes |
  | Accent | 5.50 / 8.21 | 4.98 / 7.39 | passes |
  | Danger | 6.11 / 8.22 | 5.54 / 7.40 | passes |
  | system `.red` | **3.16** / 5.15 | **2.86** / 4.63 | fails in light: replaced by `Color(.danger)` |
  | Gold | **3.62** / 7.67 | **3.28** / 6.90 | fails as body text in light: only large or bold, or Ink |
  | Paper on Danger (ProblemBanner) | 6.11 / 8.22 | | passes |

- **Builds** (Xcode 26.2, after the rebase onto `main` with #118): `xcodebuild build … -destination
  'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO` and `-destination 'platform=macOS'`
  both **BUILD SUCCEEDED** with no warnings in app code; `swift test --package-path aaru-api`
  passes (5 tests). No `openapi.yaml` or generated-client change: every call the audit needed
  (`/v1/actions`, undo, `DELETE /v1/library/items/{id}`) was already generated.

## Checklist

`docs/audit/ux.md` → "Apple agent must do", then the rest of the brief.

| Item | State | Where |
| --- | --- | --- |
| Root navigation per §18: five iPhone tabs, sidebar with everything on iPad and Mac, no Settings row on Mac (UX-001, 003, 004) | done | APL-001…003 |
| iPhone account button → Settings sheet with Done; Lists in Library; More = Insights, Listens, Recaps (UX-001, 016, 035) | done | APL-021, APL-300, APL-301, APL-303 |
| Mac Go menu ⌘1…⌘7, ⌘, for the Settings scene (UX-003) | done | APL-004 |
| Settings as eight pages; iPhone and iPad list of links; Mac `TabView` of seven panes, Delete account at the bottom of Account; one view per page (UX-020…023, 025, 030, 032) | done | APL-008…011, APL-013, APL-018, APL-020, APL-035 |
| Import in `CLAUDE.md` order, "Any other CSV" last, new hint, empty jobs line (UX-026, 027, 034) | done | APL-014…016 |
| Disconnect everywhere, agent-request alert footer, per-page problem banner (UX-024, 029, 031) | done | APL-012, APL-017, APL-019 |
| `aaru://settings/<slug>`, push re-read after sign-in (UX-012, 017) | done | APL-006, APL-007 |
| Copy pass (UX-040…050, 052…054) | done | APL-032, 106…109, 115, 203…207, 218, 221…223, 228, 237…240, 245, 303, 308…311, 332 |
| History with Undo; Remove from library (UX-060, 061) | done | APL-022, APL-244, APL-305, APL-329 |
| No false empty states; shared first-load error; filter-aware Calendar empties; group failures keep the group (UX-062, 063, 065, 067) | done | APL-028, 100…105, 200, 219, 233, 306, 319…322 |
| Dead ends (UX-068…072, 074…079, 082…085, 090…092) | done; DaySheet's episode tap (APL-323) still needs a TestFlight check; UX-073 partial: a search hit not in the library has no page yet (owner call) | APL-023, 024, 110…114, 201, 202, 210, 228, 239, 304, 307, 316…318, 323…325, 330, 331 |
| Mac `.commands` (⌘N, ⌘F, ⌘R, sidebar and toolbar), `defaultSize`, `windowResizability` | done | APL-004, APL-005, APL-036 |
| Toolbar placement, hover, context menus, keyboard navigation | done | APL-114, 121, 127, 215, 313, 325 |
| `NavigationSplitView` where it fits | Lists and Groups done; Library and Calendar deferred: the grid is the content and Month already shows its agenda beside it | APL-314, APL-131, APL-338 |
| Adaptive grids, `.searchable` placement, iPad multitasking widths | done; a 1/3-width watch party lobby needs a device check | APL-211, 229, 313, 131; APL-129 deferred |
| Drag-and-drop | deferred beyond list reorder: no title drop payload yet (product call) | APL-130, APL-339 |
| Dynamic Type to accessibility sizes | done in the app; the dense widget grids keep fixed small fonts (design call) | APL-030, 122, 125, 126, 128, 212, 213, 230, 235, 312, 334; APL-249 deferred |
| VoiceOver labels | done | APL-027, 121, 231, 327 |
| Muted ≥ 4.5:1 on Paper and Surface | passes, asset unchanged; system red replaced by Danger | Measured; APL-029, 119, 232 |
| 44pt targets, SF Symbols, standard sheets and toolbars, Reduce Motion | done | APL-031, 120, 123, 214, 231, 234, 246, 326, 333, 038 |
| Direct API calls out of views into `@Observable` models | done | APL-025, 116, 209, 227, 241, 243 |
| One `PosterThumb`, shared `ProblemBanner`, views over ~300 lines split | done | APL-026, 027, 118, 217, 225, 235, 247, 336 |
| Swift 6 strict concurrency clean | done: both builds with no warnings in app code | Measured |
| `Color(.x)` assets and the serif display face kept | done; three system-serif spots moved to `aaruDisplay` | APL-242 |
| Screenshots | see below | `docs/audit/apple-shots/` |

## Findings

In the per-area tables below, paths are relative to `aaru-ios/Aaru/` (or `aaru-ios/` when they
start with `AaruWidgets` or `Shared`), and a bare file name is in the folder named before it.

Ranges: APL-001… navigation, Settings, Mac and shared components; APL-100… Groups; APL-200…
Home, Discover, Search, Insights, Recap, Music, Approvals, widgets; APL-300… Library, Lists,
Calendar, Week, Title.

### Navigation, Settings, Mac, shared

| ID | Sev | File:line | Problem | Fix | Status |
| --- | --- | --- | --- | --- | --- |
| APL-001 | high | `Aaru/RootView.swift:174-203` | Seven tabs under `.sidebarAdaptable`: a compact tab bar showed four plus More, hiding Lists, Groups (and its badge) and Settings (UX-001). | `AppTab` + `AppRouter` (`Navigation/AppRouter.swift`). Tab bar Home · Discover · Library · Calendar · Groups; Lists, Insights and Settings are `.tabPlacement(.sidebarOnly)`, Insights and Settings in a bottom `TabSection`. A window that turns compact on a sidebar-only row is moved to its iPhone home. | fixed |
| APL-002 | med | `Aaru/RootView.swift:175`, `Settings/SettingsWindow.swift:32-61` | On the Mac, Settings was a sidebar row and the ⌘, window with different contents (UX-003). | No Settings row on macOS (`AppTab.secondary`); the Settings scene is the only Settings. | fixed |
| APL-003 | med | `Settings/SettingsView.swift:57-58` | Insights was filed under Settings (UX-004). | Insights is a sidebar destination (iPad, Mac); iPhone keeps Home's strip and Library's More menu. | fixed |
| APL-004 | high | `Aaru/AaruApp.swift:18-62` | No `.commands`, `defaultSize` or `windowResizability`; the main window opened at an arbitrary size and could shrink until the sidebar collapsed into the content. | `Navigation/AaruCommands.swift`: New List ⌘N, Search Titles ⌘F, Refresh ⌘R, Go ⌘1…⌘7, `SidebarCommands`, `ToolbarCommands` (⌘, comes from the Settings scene; iPad's Go menu adds Settings ⌘,). `defaultSize(1180, 780)`, `.contentMinSize` over a 760 × 520 minimum; the Settings scene `.contentSize`. | fixed |
| APL-005 | med | `Home/HomeScreen.swift:69`, `Library/LibraryView.swift:177` | ⌘R and ⌘F were bound to toolbar buttons, so they worked only on that one screen and two tabs kept live copies in the view tree. | Menu commands drive `AppRouter` (`refreshTick`, `showsSearch`); screens opt in with `.refreshesOnCommand(tab)`. Search is one sheet at the root. | fixed |
| APL-006 | med | `Aaru/RootView.swift:125-140` | A notification tapped while signed out waited in `PushInbox` and was never read after sign-in (UX-012). | The signed-in `MainTabs` reads the inbox with `onChange(initial: true)` when it appears. | fixed |
| APL-007 | low | `Aaru/RootView.swift:141-148` | No deep link to a Settings page (UX-017). | `aaru://settings` and `aaru://settings/<slug>` with the web's slugs; `aaru://settings/trakt` (Trakt's return) opens Import. | fixed |
| APL-008 | high | `Settings/SettingsView.swift`, `SettingsWindow.swift`, `AccountSettings.swift`, `ConnectedAppsSettings.swift`, `AboutView.swift` | Five groups with friends, notifications, appearance and concerts under Account; not §18 (UX-020). | Eight pages (`SettingsPage`) in §18's order. iPhone and iPad: a grouped list of `NavigationLink`s with tinted symbol squares, the account row on top, Delete account alone and in danger. Mac: a `TabView` of seven panes. One view per page (`SettingsPageView`) on every platform; files under `Settings/Pages` and `Settings/Sections`. | fixed |
| APL-009 | med | `Settings/AboutView.swift:76-104` | Delete account sat under About (UX-021). | `Pages/DeleteAccountPage.swift`: what goes, "Export your data first" → Your data, the danger button, "Delete account?" with **Delete account and library** / Keep it. Mac: the same section at the bottom of Account. | fixed |
| APL-010 | med | `Settings/AccountSettings.swift:23` | "Concerts near" lived under Account (UX-022). | Friends & privacy → **Location**, with the footer saying it is the only place Aaru stores where you are. | fixed |
| APL-011 | med | `Settings/ConnectedAppsSettings.swift:17`, `ConnectionsSection.swift:46`, `BrowserExtensionView.swift:26` | "Connected apps", "Connections" and "Settings → Connections" for one place (UX-023). | The page is **Connections**, sections Agents, Stremio, Music; every reference says "Settings → Connections". | fixed |
| APL-012 | low | `Settings/ConnectionsSection.swift:31`, `StremioSection.swift:34` vs `MusicSection.swift:40` | Revoke and Disconnect for the same act (UX-024). | **Disconnect** everywhere through one `ConnectionRow` and one `confirmsDisconnect` dialog whose message says what stops. | fixed |
| APL-013 | med | `Settings/StremioSection.swift:217` | The addon and Stremio history were on different pages with only a plain-text pointer (UX-025). | "Import your Stremio history" button → Import. Guide copy names "Settings → Import". | fixed |
| APL-014 | med | `Settings/ImportsModel.swift:16`, `ImportsSettings.swift:74-111` | Sources not in `CLAUDE.md`'s import order, "Any site" first (UX-026). | `HistorySource.ordered`: Stremio history, IMDb, Letterboxd, Goodreads, Pogdesign CAT, Netflix, MyAnimeList, AniList, Any other CSV; Trakt above. | fixed |
| APL-015 | low | `Settings/ImportsModel.swift:33` | The catch-all hint named Simkl and Serializd (UX-027). | "A CSV from any other site, or a spreadsheet. Aaru reads the columns." | fixed |
| APL-016 | low | `Settings/ImportsSettings.swift:120-133` | The jobs list vanished when empty (UX-034). | "No imports yet." once loaded ("Loading your imports…" before). | fixed |
| APL-017 | med | `Settings/SettingsView.swift:149-156` | One shared `imports.problem` banner on every page, so an error followed you (UX-029). | One model per page (`SettingsServices`: Account, Notifications, Connections, Data, History; Social; Imports) and `.settingsPage(_:problem:)` shows that page's own. | fixed |
| APL-018 | low | `Settings/AccountSettings.swift:15`, `Social/FriendsView.swift:61` | Name read-only in one place, edited under the handle in another (UX-030). | Account → "Name and handle", one editor (`ProfileEditor`). | fixed |
| APL-019 | med | `Settings/AccountSettings.swift:59-61` | Agent-request alerts were sent but no setting mentioned them (UX-031). | Footer "Requests from your connected agents always alert you." | fixed |
| APL-020 | med | `Settings/AccountSettings.swift:24-28`, `Push/PushRegistrar.swift` | Notifications existed only on iOS; the Mac could not see the account's switches (UX-032). | `NotificationsModel` (cross-platform, `/v1/me/notifications`) owns the switches; `PushRegistrar` keeps only permission and the APNs token. Mac pane footer: "Alerts go to your iPhone and your browsers." | fixed |
| APL-021 | low | `Settings/SettingsView.swift:29`, `:69` | `showsDone` was never set (UX-035). | The iPhone sheet passes it; Done is the confirmation action. | fixed |
| APL-022 | high | `Approvals/PlanCardView.swift:98`, `Settings/ImportDetailView.swift:71`, `ConnectionsSection.swift:49-51` | Copy promised "undo it from your history"; there was no history (UX-060). | `Pages/HistoryView.swift` + `HistoryModel`: the journal newest first, by whom (you, an import, a connection, Aaru), relative time, Undo with a confirm, undone rows struck through; reload of library and lists after an undo. Your data links it; an applied import links "See it in History" (`router.openHistory()`). | fixed |
| APL-023 | med | `Settings/ImportDetailView.swift:25-32`, `:59`, `:94` | A failed import could not be removed; rows were cut at 200 with no count (UX-078). | "Remove this import" on a failed job; header counts and "Showing 200 of 1,204." footer; Discard of a plan is confirmed. | fixed |
| APL-024 | low | `Session/SessionStore.swift:37-39` | A 401 signed out silently (UX-090). | `wasSignedOutByServer`; Welcome shows "You were signed out. Sign in again." | fixed |
| APL-025 | med | `Settings/AccountSettings.swift:34`, `LinkGoogleButton.swift:41`, `ExportDataSection.swift:63`, `ConnectionsSection.swift:105-135`, `StremioSection.swift:124-176`, `MusicSection.swift:92-127`, `:316-334`, `ConnectionSetupView.swift:139-171`, `TraktSection.swift:57-125`, `ImportsSettings.swift:136-163` | Settings views called `api` directly, so each had its own loading, error and retry logic. | `Settings/Models/*`: `AccountModel`, `NotificationsModel`, `ConnectionsModel`, `DataModel`, `HistoryModel`; Trakt, file upload, gunzip and CAT files moved into `ImportsModel`. Views hold presentation state only. | fixed |
| APL-026 | low | `Calendar/MonthGridView.swift:175`, `Groups/Kinds/NewChannelSheet.swift:152` | Two private `PosterThumb`s. | One `Design/PosterThumb.swift` (catalog image, initials tile or kind symbol, decorative). | fixed |
| APL-027 | med | `Lists/ListsView.swift:298-316` | `ProblemBanner` lived in a Lists file and dismissed with `onTapGesture`, so VoiceOver read no button and a two-line message could clip. | `Design/ProblemBanner.swift`: a plain-style `Button` with a hint, ≥ 44pt, multiline, opacity transition. | fixed |
| APL-028 | med | (many, see UX-063) | No shared first-load error state. | `Design/LoadFailedView.swift`: `ContentUnavailableView` with the reason and "Try again" (shows progress while retrying). Used by History, Groups, Home, Insights, Library, Lists, Calendar. | fixed |
| APL-029 | med | `Settings/*`, `Session/EmailSignInSheet.swift:47` | Error text in system `.red`: 3.16:1 on Paper. | `Color(.danger)` (6.11:1). | fixed |
| APL-030 | low | `Session/EmailSignInSheet.swift:18-81` | A fixed `VStack` with a `Spacer`: at accessibility sizes the field and its button fall off the sheet. | Wrapped in a `ScrollView` that bounces only when needed. | fixed |
| APL-031 | low | `WelcomeView.swift:166` | The outline button scaled on press under Reduce Motion. | No scale when Reduce Motion is on. | fixed |
| APL-032 | med | `WelcomeView.swift:76`, `:84` | "on one shelf", "One shelf, four plain statuses"; leaves out listening (UX-040, UX-054). | "Everything you watch, read and listen to, in one library." / "One library, four plain statuses". | fixed |
| APL-033 | low | `Settings/StremioSection.swift:179`, `MusicSection.swift:322`, `ConnectionSetupView.swift:118` | Three copies of the platform pasteboard code. | `Design/Pasteboard.swift`. | fixed |
| APL-034 | low | `Settings/ConnectionsSection.swift:79-87` | `Text + Text` concatenation (deprecated in the iOS 26 SDK). | Text interpolation. | fixed |
| APL-035 | low | `Design/Appearance.swift` | Appearance was a top-level Settings row with a tinted square, unlike every other row. | A plain picker under Account → On this device; the Mac "General" pane is gone. | fixed |
| APL-036 | low | `Settings/SettingsWindow.swift:30` | The Mac Settings window had only a minimum size. | 560–820 × 480+, ideal 640 × 640, `.contentSize` resizability. | fixed |
| APL-037 | low | `Social/FriendsView.swift:5-41` | Friends was a push two levels down from Account; Friends & privacy is a page of its own. | `FriendsPage` with the sections inline, a "Choose a handle" link when there is none, a loading row, context menus with symbols, scaled monograms. | fixed |
| APL-038 | low | `Home/NowPlaying.swift:49`, `Home/NowPlayingCard.swift:66`, `:83` | Now playing (#118, merged during the audit) spelled its episode code by hand, cut the episode line at one line and had a 32pt time toggle. | `EpisodeCode.short`, two lines, 44pt. Its 30 s poll, Tonight's filter and the Live Activity registrar were carried through the rebase unchanged. | fixed |
| APL-039 | high | `Aaru/RootView.swift:131-146` | Found in the simulator shots: on iPhone the tab bar showed Home · Discover · Library · Calendar · More, with Groups and its badge under More. `.tabPlacement(.sidebarOnly)` hides a tab from the bar but iOS still counts it. | At compact width the `TabView` holds only the five tab-bar destinations and no bottom section; the sidebar keeps everything at regular width. | fixed |

### Groups and the gateway

Realtime needed no change.

| ID | Sev | File:line | Problem | Fix | Status |
| --- | --- | --- | --- | --- | --- |
| APL-100 | high | Groups/GroupsModel.swift:118-121 | Any failed group-detail load, a 500 included, removed the group from the list (UX-065) | Forget the group only on 403/404; other failures keep it and show an error | fixed |
| APL-101 | high | GroupsModel.swift:94-96, GroupLists.swift:29-33, GroupsScreen.swift:176-180 | A failed first load of groups showed an endless spinner or "No groups yet" (UX-063) | `loadProblem` on the model; new `GroupsListOverlay`: spinner while loading, `LoadFailedView` with Try again on failure, empty state only after a real load | fixed |
| APL-102 | med | GroupLists.swift:207-209, GroupsScreen.swift:246-248 | A failed group detail left the channel list and the channel destination spinning forever (UX-063) | `detailProblems` per group; `LoadFailedView` with retry | fixed |
| APL-103 | med | ChannelModel.swift:71-76, ChannelView.swift:229-230 | A failed first page of a channel spun forever; the reason only showed in a banner (UX-063) | `loadProblem`; new `ChannelStart` shows `LoadFailedView` in the timeline | fixed |
| APL-104 | med | Kinds/ShelfChannelView.swift:27-33 | Shared-list load failures were silent: an empty grid with no spinner (UX-063) | `ShelfModel` reports the error; spinner while loading, error with retry on failure | fixed |
| APL-105 | med | Kinds/TitleChannelHeader.swift:44-49, 84-86; Kinds/WatchPanel.swift:31-32, 48-50 | Title card and watch party spun forever on failure (UX-063) | `loadProblem` on both models; new compact `PanelLoadFailed` (reason + Try again); a failed refresh keeps what is shown | fixed |
| APL-106 | med | Kinds/NewChannelSheet.swift:10, 20, 29; ShelfChannelView.swift:113, 127 | The `shelf` kind read "Shelf" with `books.vertical` (UX-041) | Label "List", "A list the whole group adds to.", "Nothing on this list yet", "Remove from list", symbol `list.bullet.rectangle.portrait`; stored kind stays `shelf` | fixed |
| APL-107 | med | Composer.swift:41, 87; MessageRow.swift:79, 82, 212; ChannelView.swift:158, 222; GroupSheets.swift:68, 255; SpoilerChoice.swift:82, 90; DiscussInGroupSheet.swift:58; AgentViews.swift:64 | Group posts were called "Message" (UX-042) | "Write in #x", "Editing", "Deleted", "Hidden: from someone you blocked", "New", "Load earlier", "Delete this group message?", "Every channel and group message goes", spoiler copy without the noun | fixed |
| APL-108 | med | Kinds/TitleChannelHeader.swift:182-191 | Member progress read "Finished" or "S1E3" whatever the kind (UX-043, UX-045) | `MemberProgress.summary(for: kind)`: the kind's status words, "S1 · E3" | fixed |
| APL-109 | low | WatchPanel.swift:74; SpoilerChoice.swift:26, 47 | Episode codes read "S1E3" (UX-045) | `EpisodeCode.text`, "S1 · E3" | fixed |
| APL-110 | med | GroupLists.swift:63-72; GroupSheets.swift:289-292 | "Choose a handle first, in Settings → …" and "No friends yet" were plain text (UX-074) | Buttons: "Choose a handle" opens `router.openSettings(.account)`, "Add friends" opens `.friends`. From the invite sheet, Settings opens after the sheet closes, so two sheets never present at once | fixed |
| APL-111 | med | Kinds/ShelfChannelView.swift:191-208; ChannelHeader.swift:44-47 | The shared list never showed "Not end-to-end", and the popover left out @aaru (UX-076) | `ShelfScreen` gets `ChannelHeader`; the popover adds the @aaru line when the group has the agent | fixed |
| APL-112 | low | Kinds/DiscussInGroupSheet.swift:6-8, 38 | Discuss listed only groups you manage (UX-083) | Lists every group: "Open" where the title channel exists, "Start" for managers, otherwise "No channel about it yet. An admin can start one."; `discuss()` creates a channel only for managers | fixed (the title room's entry is APL-331) |
| APL-113 | low | GroupSheets.swift:135-141 | The owner saw Delete but no Leave, and no reason why (UX-084) | "Leave group…" for the owner: the dialog says "Make someone else owner first, in Members" and offers "Open Members" | fixed |
| APL-114 | low | GroupsScreen.swift:205, 88-96, 198-204 | Split view: the error banner showed only with a channel selected; Members was a sheet from the menu but the inspector from the toolbar (UX-085) | Banner on the `NavigationSplitView`; in the split, Members always opens the inspector and selects that group first | fixed |
| APL-115 | low | GroupsScreen.swift:210 | Copy said "watching and reading" (UX-054) | "watching, reading and listening to" | fixed |
| APL-116 | med | AgentViews.swift:160-171; Kinds/TitlePickerSheet.swift:102-130 | Views called `api` directly (catalog search, the agent card's add to library) | New `TitlePickerModel` (@Observable) runs the search; new `GroupsModel.addToMyLibrary(_:)`; `AgentTitleCard` and its rows take an `onAdd` closure and no longer import AaruAPI | fixed |
| APL-117 | low | Kinds/ShelfChannelView.swift:9-92; Kinds/TitleChannelHeader.swift:28-50 | Models lived inside view files | Moved to Kinds/ShelfModel.swift and Kinds/TitleChannelModel.swift | fixed |
| APL-118 | low | GroupSheets.swift (322 lines), ChannelView.swift (305 lines) | Views over 300 lines | GroupSheets is now 167 lines plus GroupNameSheet, ChannelEditorSheet and InviteFriendsSheet; ChannelView is 272 plus ChannelStart; the pasteboard is `Design/Pasteboard.swift` (APL-033) | fixed |
| APL-119 | med | MessageRow.swift:134, AgentViews.swift:146, Composer.swift:78, TitlePickerSheet.swift:35, NewChannelSheet.swift:102, ChannelEditorSheet, WatchPanel.swift:49 | System red text on Paper is 3.16:1, below 4.5:1 | `Color(.danger)`: 6.11:1 light, 8.22:1 dark | fixed |
| APL-120 | med | ChannelHeader.swift:32-41; Composer.swift:67; TitleChannelHeader.swift:139; WatchPanel.swift:150; MemberList.swift:95 | Icon and chip buttons under 44pt (Not end-to-end chip, send, about sharing, reactions, member actions) | `frame(minWidth/minHeight: 44)` plus `contentShape`; the header drops its vertical padding so it stays 44pt tall | fixed |
| APL-121 | low | MemberList.swift:95-99; GroupsScreen.swift:160 | Icon-only menus whose VoiceOver names were "Actions" or "Group" | `Menu("Actions for <name>", systemImage:)` with `.labelStyle(.iconOnly)`; `.help` on Mac | fixed |
| APL-122 | low | MessageRow.swift:217-228, 152 | Monogram had a fixed 36pt frame, so its letters spilled out at large text sizes | Scales with `@ScaledMetric` (capped at 1.6×) and caps its text at xxxLarge; the message gutter uses a hidden Monogram so rows stay aligned | fixed |
| APL-123 | low | AgentViews.swift:24-28 | Turning Reduce Motion on mid-breath left the repeating scale running | Scale gated on `!reduceMotion`; `onChange` resets it | fixed |
| APL-124 | low | WatchPanel.swift:125 | Countdown used a fixed `.system(size: 34)` | `.system(.largeTitle, design: .rounded, weight: .semibold)` | fixed |
| APL-125 | low | TitlePickerSheet.swift:28-31 | The five-segment kind picker clips at accessibility text sizes | Becomes a menu picker when `dynamicTypeSize.isAccessibilitySize` | fixed |
| APL-126 | low | AgentViews.swift:196, TitleChannelHeader.swift:168/173, ShelfChannelView.swift:168/170, ChannelHeader.swift:19 | `lineLimit(1)` cut key text short at large text sizes | Raised to 2-3 lines; no limit on the AaruMemberRow title | fixed |
| APL-127 | low | ShelfChannelView.swift ShelfCard | No pointer hover effect and no add action in the context menu on iPad/Mac | `.hoverEffect(.highlight)` on iOS; context menu adds "Add to my library" | fixed |
| APL-128 | low | MessageRow.swift:80-86 | The blocked-sender row overflowed at large text sizes | `ViewThatFits`: one line, else stacked | fixed |
| APL-129 | low | WatchPanel lobby and ended rows | Ready, the countdown menu and End share one row, which can crowd a 1/3-width iPad window | none | deferred (needs a check in a 1/3 window on a device; the buttons stay tappable) |
| APL-130 | low | Shelf grid | No drag-and-drop of titles into a shared list | none | deferred (the app has no drop target or payload type for titles yet; product call) |
| APL-131 | info | GroupsScreen.swift NavigationSplitView | iPad 1/3, 1/2 and 2/3 widths | Compact width uses the stack, regular uses the split; sidebar 220-260pt, inspector 220-320pt | checked in code, no change |

### Home, Discover, Search, Insights, Recap, Listens, agent requests, widgets

| ID | Sev | File:line | Problem | Fix | Status |
| --- | --- | --- | --- | --- | --- |
| APL-200 | med | Home/HomeScreen.swift:125 | UX-063: a failed first load showed a spinner forever, outside the ScrollView so pull-to-refresh did nothing | `loadFailed` shows `LoadFailedView`; the spinner moved inside the ScrollView with `.refreshable` | fixed |
| APL-201 | med | HomeScreen.swift:131, DiscoverCard.swift:146 | UX-075: headline repeated twice, worded for shows only, no Import | One headline, "Add something to see what's next", plus "Bring your history" → `router.openSettings(.imports)` | fixed |
| APL-202 | low | HomeSections.swift:96, HomeCards.swift:158 | UX-092: Airing soon opened the title | Opens `CalendarEpisodeSheet` from a CalendarFeed Home owns; "Open show" pushes on Home's `NavigationStack(path:)`. If the airing isn't in the feed, the show opens instead | fixed |
| APL-203 | low | HomeSections.swift:80 | UX-052: the Live Activity menu item was named "Start watching" | Renamed "Watching now…" | fixed |
| APL-204 | low | HomeModel.swift:98 | UX-052: albums showed in Start watching | New `startable` leaves out music | fixed |
| APL-205 | low | TonightCard.swift:79 | UX-044: Tonight's button said "Mark watched" | "Mark S4 · E3 watched" | fixed |
| APL-206 | low | HomeCards, HomeSummary, Tonight, HomeModel | UX-045: episode codes were spelled by hand | All use the shared `EpisodeCode.short` | fixed |
| APL-207 | low | Shared/WidgetSnapshot.swift:44, CountdownWidget, UpNextWidget | UX-045: Countdown showed S01E05; UpNext's VoiceOver read "S1 E5" | New `Airing.shortCode` "S1 · E5"; only the Week widget keeps S01E05 | fixed |
| APL-208 | med | HomeScreen.swift:65,74,88 | Router: Home had its own search sheet, no account button, and a ⌘R shortcut of its own | `router.showsSearch`, `.accountButton()`, `.refreshesOnCommand(.home)`; "All lists" → `router.select(.lists)` | fixed |
| APL-209 | med | HomeScreen / HomeModel | The view called `api.listPlans` | Moved into `HomeModel.loadPlans()` / `planDecided(_:)` | fixed |
| APL-210 | low | HomeScreen.swift:94, HomeSections.swift:44 | UX-082: a request answered in the notification sheet left Home stale | `PlanModel` posts `.aaruPlanDecided`; Home swaps in the result and reloads if it was applied | fixed |
| APL-211 | med | HomeScreen.swift:29 | iPad at 2/3 width and narrow Mac windows squeezed the main column next to the 340pt side column | Single column below 760pt | fixed |
| APL-212 | low | HomeRow.swift:49 | Fixed card widths cut titles off at accessibility text sizes | Cards are 1.4× wider at those sizes (Home and Discover) | fixed |
| APL-213 | low | HomeSummary.swift:43 | The week strip's four figures clipped at large text | Shows 2×2 at accessibility sizes | fixed |
| APL-214 | low | HomeSummary.swift:105 | Count chips were about 34pt tall | 44pt tap area | fixed |
| APL-215 | low | HomeRow.swift:103 | No system pointer effect on iPad | iOS uses `.hoverEffect(.lift)`; macOS keeps its scale, which respects Reduce Motion | fixed |
| APL-216 | low | HomeScreenPreviews.swift | Previews broke once Home read the router | Added `.environment(AppRouter())` | fixed |
| APL-217 | low | HomeScreen, HomeModel | Over the file and type-length limits | Split into HomeSections.swift and HomeLabels.swift | fixed |
| APL-218 | low | DiscoverScreen.swift:196 | UX-048: credit read "Lists from TMDB and AniList" | "Rows from …" naming only providers on screen (TMDB, AniList, Open Library, ListenBrainz) | fixed |
| APL-219 | med | DiscoverScreen.swift:146 | An empty but successful load said "could not be loaded" | `LoadFailedView` only after a real failure | fixed |
| APL-220 | low | DiscoverScreen.swift:80,89 | Own search sheet, no ⌘R, and pull-to-refresh always reloaded Today | Router search; ⌘R and pull-to-refresh reload the section on screen | fixed |
| APL-221 | low | SeasonBrowser.swift:131 | UX-050: error named the vendor | "This season's list isn't answering" | fixed |
| APL-222 | low | ConcertsView.swift:59,209 | UX-050: "Ticketmaster isn't answering" | "Concert listings aren't answering"; Ticketmaster stays in the credit | fixed |
| APL-223 | low | ConcertsView.swift:98 | UX-040: "an album on your shelf" | "in your library" | fixed |
| APL-224 | low | ConcertsParts, ConcertRow, ConcertPlacePicker | `Color.accentColor` used against the app rule | `Color(.accent)` | fixed |
| APL-225 | low | ConcertsView.swift | 381 lines | Split into ConcertsView (267) and ConcertsParts (120) | fixed |
| APL-226 | low | SeasonModel.swift:64 | Retroactive conformance warning | `@retroactive Identifiable` | fixed |
| APL-227 | med | SearchView.swift | Search state and the API call lived in the view | New `SearchModel`; `SearchView(api:library:lists:intoList:)` unchanged | fixed |
| APL-228 | low | SearchRows.swift:66 | UX-040: "On your shelf"; UX-073: a hit already in your library opened nothing | "In your library", and the row opens the item | fixed (UX-073 partial) |
| APL-229 | low | SearchView.swift:91 | The search field could hide on iOS | `.navigationBarDrawer(displayMode: .always)` | fixed |
| APL-230 | low | SearchView.swift:115, InsightsView.swift:79 | Segmented pickers cut off at large text | Become menus at accessibility sizes | fixed |
| APL-231 | low | AddMenu.swift:21, SearchRows.swift:31 | "Add" was about 30pt tall; VoiceOver didn't say what it adds | 44pt tap area; label "Add &lt;title&gt;" | fixed |
| APL-232 | low | SearchView, MusicView (2 places), PlanCardView | System red text is 3.16:1 on Paper | `Color(.danger)` | fixed |
| APL-233 | med | InsightsView.swift:72 | UX-063: blank page on a failed first load | `LoadFailedView`, pull-to-refresh, `.refreshesOnCommand(.insights)` | fixed |
| APL-234 | low | InsightsView.swift:120 | Period stepper arrows under 44pt | 44pt | fixed |
| APL-235 | low | StatsCharts / StatsPanel | Fixed chart heights at large text; StatsPanel 370 lines | Heights scale with text (`@ScaledMetric`); charts moved to StatsCharts.swift | fixed |
| APL-236 | info | StatsCharts RatingsHistogram | The gold flagged as text is a bar colour, which needs only 3:1 | No change needed | n/a |
| APL-237 | low | MusicView.swift:47 | UX-049: page titled "Music" | "Listens" | fixed |
| APL-238 | low | MusicInsights.swift:47 | UX-049: link read "All listening" | "All listens ›" | fixed |
| APL-239 | low | MusicView.swift:78 | UX-077: told the user where to go in words only | "Connect a scrobbler" button → `router.openSettings(.connections)` | fixed |
| APL-240 | low | MusicView TopListens | UX-053: "This year" | "Year" | fixed |
| APL-241 | med | MusicView, MusicInsights | API calls in views | `RecentListensModel` and `TopListensModel`; signatures unchanged | fixed |
| APL-242 | low | MusicView:57, Listening:156, RecapOnRepeat:13,25,30 | System serif instead of the app face | `aaruDisplay` | fixed |
| APL-243 | med | PlanCardView.swift | approve/deny/get calls in views | New `PlanModel`; `PlanSheet(api:id:onDone:)` unchanged | fixed |
| APL-244 | high | PlanCardView.swift:55 | UX-060: "undo it from your history" with nowhere to go | "…undo it from History." plus an "Open History" button; from the sheet it closes the sheet first, then opens History after 450ms | fixed |
| APL-245 | low | RecapCards.swift:19 | UX-040/054: "watched and read, from your own shelf" | "watched, read and listened to, from your own library" | fixed |
| APL-246 | low | RecapView.swift:98 | Close button about 33pt | 44pt | fixed |
| APL-247 | low | RecapCards / RecapDeck | 386 and 311 lines | Pieces to RecapCardParts.swift (renamed Recap\*); RecapPeriod to its own file; its API unchanged | fixed |
| APL-248 | info | AaruWidgets | WidgetKit check: background rule met; artwork already hidden from VoiceOver | No change | n/a |
| APL-249 | low | WeekWidget:104–147, CountdownWidget:131,133 | Fixed 9–12pt fonts in the dense grids | Left as is | deferred (design call: density vs Dynamic Type) |
| APL-250 | low | HomeModel `openAiring` | The first airing tap fetches the calendar again, though Home already has the data | — | deferred: needs `CalendarFeed` to accept entries already fetched; one extra request on the first tap only |

### Library, Lists, Calendar, Week, Title

| ID | Sev | File:line | Problem | Fix | Status |
| --- | --- | --- | --- | --- | --- |
| APL-300 | high | Library/LibraryView.swift:62 | No account button and no refresh command | `.accountButton()`, `.refreshesOnCommand(.library)` | fixed |
| APL-301 | high | Library/LibraryView.swift:70 | iPhone couldn't reach Lists from Library | Lists row at the top of grid and rows, a toolbar Lists button, and `navigationDestination(isPresented: $router.showsListsInLibrary)` | fixed |
| APL-302 | med | Library/LibraryView.swift:159, Calendar/CalendarScreen.swift:130 | Library and Calendar each had their own search sheet; Library also had its own ⌘F | Both set `router.showsSearch`; ⌘F removed | fixed |
| APL-303 | low | Library/LibraryView.swift:28,204 | Layout called "List"; More menu said "Music" (UX-048, UX-049) | Layout "Grid / Rows"; More menu is Insights, Listens, Recaps | fixed |
| APL-304 | med | Library/LibraryView.swift:68 | A missing library item opened an empty screen (UX-071) | Goes to `LibraryEntryDestination` | fixed |
| APL-305 | high | Library/LibraryView.swift:32, LibraryModel.swift:130 | No way to remove a title (UX-061) | "Remove from library…", confirmed; a ribbon offers "Undo in History" | fixed |
| APL-306 | high | Library/LibraryView.swift:58 | A failed first sync said the library was empty (UX-062) | Try-again screen; spinner before the first sync | fixed |
| APL-307 | med | Library/LibraryView.swift:161,168 | New accounts never offered Import; no Clear filters (UX-075) | "Bring your history" opens Import; filtered-empty has Clear filters | fixed |
| APL-308 | med | Library/LibraryModel+Now.swift:39, NowSection.swift:235 | Generic words: "In progress", "Mark watched" on a book (UX-043) | The kind's words: "Watching", "Mark read", "Mark listened" | fixed |
| APL-309 | low | Library/NowSection.swift, Title/TitleDetailView.swift | Three phrasings of one tick (UX-044) | "Mark S1 · E5 watched" when the episode is named, "Mark watched" when not | fixed (Home's half in APL-205–207) |
| APL-310 | low | Title/EpisodeCode.swift:5 | Codes written "S1 · E8", "S1E8" and "S01E05" (UX-045) | One `EpisodeCode` formatter; "S01E05" only in the week cell | fixed (Home's half in APL-205–207) |
| APL-311 | low | Lists/ListItemRow.swift:60, Title/TitleDetailView.swift:164 | Plural kind for one item; raw show status (UX-046, UX-047) | Singular kind ("Show"); one show-status label map | fixed |
| APL-312 | med | Library/NowSection.swift:70 | Now cards fixed-width at accessibility sizes; actions clipped | Cards widen; actions stack vertically | fixed |
| APL-313 | med | Library/LibraryCards.swift:85,96,34 | Fixed grid, no hover, filter chips under 44pt | Adaptive grid that scales with text size; hover on iPad and Mac; 44pt chips | fixed |
| APL-314 | med | Lists/ListsScreen.swift:26 | Lists was a plain stack on iPad and Mac | Split view at regular width, stack at compact | fixed |
| APL-315 | med | Lists/ListsView.swift:61,68 | `router.pendingNewList` ignored; no refresh command | Consumed on appear; `.refreshesOnCommand(.lists)` | fixed |
| APL-316 | med | Lists/ListsView.swift:50,179 | List delete unconfirmed; name sheet closed on a failed save (UX-079) | Delete confirmed; sheet closes only on success and shows the error inline | fixed |
| APL-317 | low | Lists/ListPickerSheet.swift:56 | Picker didn't mark lists already holding the title (UX-079) | Pre-marks them; title "Add “X” to a list" | fixed |
| APL-318 | med | Lists/ListDetailView.swift:148 | A member not in the library was inert (UX-072) | Add control: tap adds as Plan to …, hold picks a status | fixed |
| APL-319 | med | Lists/ListsModel.swift:41, ListDetailView.swift:86 | A failed first load showed empty or spun forever (UX-063) | Try-again screen; banner for later failures | fixed |
| APL-320 | high | Calendar/CatchUpView.swift:19 | Missed said "all caught up" when the fetch failed (UX-062) | Try again on failure; "all caught up" only once the 4 weeks have loaded; Clear filters | fixed |
| APL-321 | med | Week/WeekModel.swift:66, Calendar/MonthModel.swift:84 | "Nothing airs" from another window's data, or after a failure | Empty only once the window has loaded; Try again on failure | fixed |
| APL-322 | med | Week/WeekView.swift, AgendaList.swift, DaySheet.swift | Empty states ignored filters (UX-067) | Shared `CalendarEmptyState` with Clear filters | fixed |
| APL-323 | med | Calendar/DaySheet.swift:39 | Tapping a row in iPhone Month's day sheet did nothing (UX-068) | The day sheet presents the episode sheet itself | fixed, not tested on a device |
| APL-324 | med | Calendar/CalendarEpisodeSheet.swift:25 | No Done; on the Mac the only way out was "Open show" (UX-069) | Done button; actions stack when they don't fit | fixed |
| APL-325 | low | Week/WeekView.swift | Five arrows in iPhone's toolbar (UX-091) | Compact: Today and week arrows. Wide adds day arrows. ⌥⌘←/→ week, ⌘←/→ day or month, ⌘T Today | fixed |
| APL-326 | low | Week/WeekDayPager.swift, MonthGridView.swift:85 | Paging animated under Reduce Motion | No animation under Reduce Motion | fixed |
| APL-327 | low | Week/WeekDayPager.swift:42 | Day page had a poor VoiceOver label | "Thursday, …, today, 2 episodes" | fixed |
| APL-328 | med | Calendar/CalendarScreen.swift:89 | No refresh command | `.refreshesOnCommand(.calendar)` | fixed |
| APL-329 | high | Title/TitleDetailView.swift:151,90 | No Remove in the title room (UX-061) | More menu "Remove from library…", confirmed, then closes the room | fixed |
| APL-330 | med | Title/TitleRoomSections.swift:100 | Book page (number pad, no Return) never saved (UX-070) | Saves when the field loses focus; keyboard Done | fixed |
| APL-331 | med | Title/TitleDetailView.swift:151 | "Discuss in a group…" only for group admins (UX-083) | Shown to any group member | fixed |
| APL-332 | low | Title/TitleRoomParts.swift:104 | Live Activity menu item said "Start watching" (UX-052) | "Watching now…" | fixed |
| APL-333 | med | Title/TitleRoomParts.swift:71,30 | Episode tick 26pt; season header 28pt | Both 44pt | fixed |
| APL-334 | low | Title/TitleDetailView.swift:172, TitleRoomSections.swift:33 | Actions and hero title clipped at accessibility sizes | Actions stack; title wraps | fixed |
| APL-335 | low | Title/TitleRoomSections.swift:208 | One-off view when episodes fail to load | Shared Try-again view | fixed |
| APL-336 | med | Title/TitleDetailView.swift, Lists/ListsView.swift | Views over 300 lines | Split into subviews: TitleDetailView 217 lines, ListsView 230, LibraryView 229 | fixed |
| APL-337 | low | Title/TitleRoomParts.swift:135 | Gold flagged at 3.62:1 on light Paper | No change: these are star icons, not text, so the 3:1 non-text rule applies and they pass. No system red in these folders | no change |
| APL-338 | low | Library, Calendar | Split view for Library and Calendar | Library's grid is the content and the title room already has two columns; Month already shows its agenda beside the grid | deferred, doesn't fit |
| APL-339 | low | Library, Lists | Drag-and-drop beyond list reorder | Only list reorder; dropping onto sidebar lists needs RootView work | deferred: dropping a title onto a sidebar list needs a title drop payload, the same product call as APL-130 |
