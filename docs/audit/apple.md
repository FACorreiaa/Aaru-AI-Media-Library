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

- **Builds**: see the PR body for the final `xcodebuild` and `swift test` results.

## Findings

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
