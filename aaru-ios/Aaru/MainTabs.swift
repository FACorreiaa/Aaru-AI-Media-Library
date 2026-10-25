import AaruAPI
import SwiftUI

/// The signed-in app: a sidebar on Mac and iPad, four tabs and More on iPhone (DESIGN.md §18).
struct MainTabs: View {
    let api: Client?
    let library: LibraryModel
    let lists: ListsModel
    let imports: ImportsModel
    let groups: GroupsModel
    let realtime: RealtimeClient
    let settings: SettingsContext

    /// Discover's rows, shared by Discover and the kind pages so `/v1/discover` loads once.
    @State private var discover: DiscoverModel

    @Environment(AppRouter.self) private var router
    @Environment(ProgressModel.self) private var progress: ProgressModel?
    @Environment(PlusModel.self) private var plus: PlusModel?
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #else
        @Environment(\.openSettings) private var openSettings
    #endif
    /// A title a widget or an alert asked to open (`aaru://title/{id}`).
    @State private var linkedTitle: LinkedTitle?
    /// An agent request a notification asked to open (OUT-004).
    @State private var linkedPlan: LinkedTitle?
    /// A capture whose plan is ready, from its notification (AG-006).
    @State private var linkedImport: LinkedTitle?

    init(
        api: Client?, library: LibraryModel, lists: ListsModel, imports: ImportsModel, groups: GroupsModel,
        realtime: RealtimeClient, settings: SettingsContext
    ) {
        self.api = api
        self.library = library
        self.lists = lists
        self.imports = imports
        self.groups = groups
        self.realtime = realtime
        self.settings = settings
        _discover = State(initialValue: DiscoverModel(api: api, library: library))
    }

    /// iPhone and a compact iPad window: no sidebar, and only the compact tabs (NAV-002). iOS
    /// shows the first four in the bar and turns the fifth into More, which lists Groups, Books,
    /// Manga, Music and Sports; the sidebar-only destinations are left out, since a hidden
    /// `.sidebarOnly` tab would still be counted there.
    private var compactTabBar: Bool {
        #if os(iOS)
            sizeClass == .compact
        #else
            false
        #endif
    }

    /// Sports only while this server has it on (SPT-004).
    private func isAvailable(_ destination: AppTab) -> Bool {
        destination != .sports || router.sportsAvailable
    }

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            if compactTabBar {
                ForEach(AppTab.compact.filter(isAvailable)) { destination in
                    tab(for: destination, placement: .automatic)
                }
            } else {
                // Lists and Friends stay out of iPad's floating tab bar, as before (§18).
                ForEach(AppTab.primary) { destination in
                    tab(for: destination, placement: destination.isInCompactTabBar ? .automatic : .sidebarOnly)
                }
                TabSection("More") {
                    ForEach(AppTab.more.filter(isAvailable)) { destination in
                        tab(for: destination, placement: .sidebarOnly)
                    }
                }
                TabSection {
                    ForEach(AppTab.secondary) { destination in
                        tab(for: destination, placement: .sidebarOnly)
                    }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        #if os(macOS)
            .frame(minWidth: 760, minHeight: 520)
        #endif
            .sheet(item: $linkedPlan) { link in
                if let api {
                    PlanSheet(api: api, id: link.id) { linkedPlan = nil }
                }
            }
            .sheet(item: $linkedImport) { link in
                NavigationStack {
                    ImportDetailView(id: link.id, imports: imports, library: library, lists: lists, api: api)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { linkedImport = nil }
                            }
                        }
                }
            }
            .sheet(item: $linkedTitle) { link in
                NavigationStack {
                    LibraryEntryDestination(id: link.id, api: api, library: library, lists: lists)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { linkedTitle = nil }
                            }
                        }
                }
            }
            .sheet(isPresented: $router.showsSearch) {
                SearchView(api: api, library: library, lists: lists)
            }
        #if os(iOS)
            .sheet(isPresented: $router.showsSettingsSheet) {
                settingsScreen(showsDone: true)
            }
            .onChange(of: sizeClass, initial: true) { _, size in
                router.isCompact = size == .compact
                // A sidebar-only destination has no tab once the window turns compact.
                if size == .compact, !router.tab.isInCompactTabBar {
                    router.select(router.tab)
                }
            }
        #else
            .onChange(of: router.settingsWindowRequest) { openSettings() }
        #endif
            // Screens outside the tab (a title's "Discuss in a group…") reach groups through this.
            .environment(groups)
            // A title page's "From friends" reads the friend count from here (BOARD-003).
            .environment(settings.models.social)
            .onChange(of: groups.openRequest) { _, request in
                if request != nil {
                    router.tab = .groups
                }
            }
            // The tab's mention badge needs the counts before the tab is opened.
            .task { await groups.load() }
            // Sports shows only when this server has it on. Asked again on each return to the
            // app, so a server that turned it on (or off) shows without a relaunch.
            .task(id: scenePhase) {
                guard scenePhase == .active, let available = await SportSettingsModel.isAvailable(api: api) else {
                    return
                }
                router.sportsAvailable = available
            }
            // Renewals and Ask to Buy approvals arrive while the app runs (BIL-004).
            .task { await plus?.listen() }
            // Badges earned elsewhere (an import, another device) toast on return (GAM-004).
            .task(id: scenePhase) {
                if scenePhase == .active {
                    await progress?.refresh()
                    // MyAnimeList changes come back on each open; the server spaces the reads (SCR-010).
                    _ = try? await api?.requestMALPull()
                }
            }
            .modifier(OptionalUnlockToast(model: progress))
            // The socket is open while the app is active, and its events keep groups current.
            .task { await groups.follow() }
            .task(id: scenePhase) {
                if scenePhase == .background {
                    realtime.stop()
                } else {
                    realtime.start()
                }
            }
        #if os(iOS)
            // Launch already follows Live Activity tokens; signing in starts it again so the
            // current tokens go up with the new session.
            .task { LiveActivityRegistrar.current?.start() }
        #endif
            // A notification tapped before sign-in, or before the app was running, waits in
            // PushInbox; this view only exists signed in, so it reads it on appear too (UX-012).
            .onChange(of: PushInbox.shared.planID, initial: true) { _, id in
                guard let id else { return }
                linkedPlan = LinkedTitle(id: id)
                PushInbox.shared.planID = nil
            }
            .onChange(of: PushInbox.shared.importID, initial: true) { _, id in
                guard let id else { return }
                linkedImport = LinkedTitle(id: id)
                PushInbox.shared.importID = nil
            }
            .onChange(of: PushInbox.shared.libraryItemID, initial: true) { _, id in
                guard let id else { return }
                linkedTitle = LinkedTitle(id: id)
                PushInbox.shared.libraryItemID = nil
            }
            .onChange(of: PushInbox.shared.groupLink, initial: true) { _, url in
                guard let url else { return }
                openGroup(url)
                PushInbox.shared.groupLink = nil
            }
            .onOpenURL(perform: open)
    }

    private func open(_ url: URL) {
        // RootView opens friend invites, signed in or out.
        if InviteLink(url) != nil {
            return
        }
        if let id = WidgetLink.libraryItemId(in: url) {
            linkedTitle = LinkedTitle(id: id)
        } else if !router.open(url) {
            openGroup(url)
        }
    }

    /// A group alert or link: the channel it names, or the Groups tab (GRP-012).
    private func openGroup(_ url: URL) {
        switch GroupLink(url) {
        case .groups?: router.tab = .groups
        // The Groups tab opens itself for a channel request.
        case let .channel(request)?: groups.openRequest = request
        case nil: break
        }
    }

    /// One destination's tab. The Groups mention badge rides on its tab: in the sidebar, and on
    /// its row under More on iPhone.
    private func tab(for destination: AppTab, placement: TabPlacement) -> some TabContent<AppTab> {
        Tab(destination.title, systemImage: destination.symbol, value: destination) {
            screen(for: destination)
        }
        .badge(destination == .groups ? groups.mentionTotal : 0)
        .tabPlacement(placement)
    }

    @ViewBuilder
    private func screen(for destination: AppTab) -> some View {
        switch destination {
        case .home:
            HomeScreen(
                api: api, library: library, lists: lists, imports: imports,
                onSelectTab: { router.select($0) },
                onShowLibrary: { router.showLibrary($0) }
            )
        case .discover:
            DiscoverScreen(api: api, library: library, lists: lists, model: discover)
        case .library:
            @Bindable var router = router
            LibraryView(api: api, library: library, lists: lists, filter: $router.libraryFilter)
        case .calendar:
            CalendarScreen(api: api, library: library, lists: lists)
        case .lists:
            ListsScreen(lists: lists, library: library, api: api)
        case .friends:
            FriendsScreen(social: settings.models.social, board: settings.models.board)
        default:
            moreScreen(for: destination)
        }
    }

    /// The More group's destinations (NAV-002), and the ones set apart below it.
    @ViewBuilder
    private func moreScreen(for destination: AppTab) -> some View {
        switch destination {
        case .groups:
            GroupsScreen(groups: groups, social: settings.models.social, board: settings.models.board)
        case .books, .manga, .music:
            if let kind = destination.kind {
                KindScreen(kind: kind, api: api, library: library, lists: lists, discover: discover)
            }
        case .sports:
            SportsScreen(api: api)
        case .insights:
            NavigationStack {
                InsightsView(api: api, library: library)
            }
        default:
            settingsScreen(showsDone: false)
        }
    }

    private func settingsScreen(showsDone: Bool) -> some View {
        SettingsView(context: settings, showsDone: showsDone)
    }

    struct LinkedTitle: Identifiable {
        let id: String
    }
}

/// The unlock toast over the signed-in app, when the environment has a progress model (previews
/// have none).
private struct OptionalUnlockToast: ViewModifier {
    let model: ProgressModel?

    func body(content: Content) -> some View {
        if let model {
            content.unlockToast(model)
        } else {
            content
        }
    }
}
