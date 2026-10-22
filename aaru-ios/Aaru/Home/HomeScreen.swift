import AaruAPI
import SwiftUI

/// Home, drawn as the Field (APP-009, APP-013, DESIGN.md §1 and §13): what a player is playing
/// now (SCR-008, §15) sits under the heading when there is something; Tonight leads, then
/// Continue watching, the albums being listened to (MUS-001), what airs next, Start watching and
/// Unfinished as Trakt-style rows of cards, then Discover's public rows (DISC-001). Requests
/// waiting for the user, the last import, the week, the shelf's counts, the recap and the user's
/// lists sit in a side column on wide screens and after the rows on a phone. Renders from the
/// cache first, then refreshes.
struct HomeScreen: View {
    let api: Client?
    let library: LibraryModel
    let lists: ListsModel
    /// The user's imports, for the newest one's note. Nil in previews.
    var imports: ImportsModel?
    /// Switches the app to another destination (Calendar, Discover, Lists).
    var onSelectTab: (RootView.AppTab) -> Void
    /// Switches to Library, filtered: to one status (the count chips) or one kind (the profile).
    var onShowLibrary: (LibraryFilter) -> Void

    @State private var model: HomeModel
    @State private var showsSearch = false
    @State private var recap: RecapPeriod?
    @State private var listTarget: CatalogHit?
    /// Agent requests waiting for the user (OUT-004), pinned above the rows.
    @State private var plans: [AgentPlan] = []
    @Environment(\.scenePhase) private var scenePhase

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
        private var compact: Bool {
            sizeClass == .compact
        }
    #else
        private let compact = false
    #endif

    init(
        api: Client?,
        library: LibraryModel,
        lists: ListsModel,
        imports: ImportsModel? = nil,
        model: HomeModel? = nil,
        onSelectTab: @escaping (RootView.AppTab) -> Void = { _ in },
        onShowLibrary: @escaping (LibraryFilter) -> Void = { _ in }
    ) {
        self.api = api
        self.library = library
        self.lists = lists
        self.imports = imports
        self.onSelectTab = onSelectTab
        self.onShowLibrary = onShowLibrary
        _model = State(initialValue: model ?? HomeModel(api: api, library: library))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Home")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                // The profile (GAM-006b) leads; the top trailing spot is the account button's (§18).
                .profileEntry(api: api, library: library, lists: lists) { onShowLibrary(LibraryFilter(kind: $0)) }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Search", systemImage: "magnifyingglass") { showsSearch = true }
                    }
                    #if os(macOS)
                        ToolbarItem {
                            Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.load() } }
                                .keyboardShortcut("r", modifiers: .command)
                                .disabled(model.isLoading)
                        }
                    #endif
                }
                // Each appearance: the first load, or a refetch if the shelf changed while away.
                .task {
                    await model.loadIfNeeded()
                    await model.shelfChanged()
                }
                .task { await loadPlans() }
                // Players report only on a change, so what is playing is asked again every 30 s
                // while Home is open and the app is in front; the card's clock runs in between.
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    while !Task.isCancelled {
                        await model.loadNowPlaying()
                        try? await Task.sleep(for: .seconds(30))
                    }
                }
                .task { await imports?.load() }
                .task {
                    if !lists.hasLoaded {
                        await lists.load()
                    }
                }
                .refreshable {
                    await model.load()
                    await model.loadNowPlaying()
                    await loadPlans()
                    await imports?.load()
                }
                .navigationDestination(for: String.self) { id in
                    LibraryEntryDestination(id: id, api: api, library: library, lists: lists)
                }
                // Adds from Search and Discover land on the shelf; Home's rows come from other endpoints.
                .onChange(of: library.revision) { Task { await model.shelfChanged() } }
                .sheet(
                    isPresented: $showsSearch,
                    onDismiss: { Task { await model.shelfChanged() } },
                    content: { SearchView(api: api, library: library, lists: lists) }
                )
                .sheet(item: $listTarget) { hit in
                    ListPickerSheet(
                        ref: .init(_type: hit._type, ids: hit.ids, title: hit.title, year: hit.year),
                        titleName: hit.title,
                        lists: lists
                    )
                }
                .recapStory($recap, api: api)
                .safeAreaInset(edge: .bottom) {
                    ProblemBanner(message: model.problem) { model.problem = nil }
                }
                .undoToast()
                .background { FieldBackground() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isEmpty, model.discover.isEmpty, model.nowPlaying == nil, model.hasLoaded {
            ContentUnavailableView {
                Label("Add a show to see what's next", systemImage: "sparkles.tv")
            } description: {
                Text("Shows you are watching, things to start, and new episodes land here.")
            } actions: {
                Button("Browse Discover") { onSelectTab(.discover) }
                    .buttonStyle(.borderedProminent)
                Button("Search") { showsSearch = true }
                    .buttonStyle(.bordered)
            }
        } else if model.isEmpty, model.discover.isEmpty, model.nowPlaying == nil {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    nowPlayingSection
                    if compact {
                        tonightSection
                        waitingSection
                        welcome
                        ownRows
                        sideBlocks
                        discoverRows
                    } else {
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 28) {
                                tonightSection
                                welcome
                                ownRows
                                discoverRows
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .leading, spacing: 24) {
                                waitingSection
                                sideBlocks
                            }
                            .frame(width: 340)
                        }
                    }
                }
                .padding(.vertical, 16)
            }
        }
    }

    /// The last 7 days (to Insights, shown at zero too) and the shelf's counts (to Library,
    /// hidden at zero).
    /// A failure leaves the requests on the server; the next appearance shows them.
    private func loadPlans() async {
        guard let api, case let .ok(response)? = try? await api.listPlans(query: .init(status: .pending)) else {
            return
        }
        plans = (try? response.body.json.items) ?? plans
    }

    @ViewBuilder private var summary: some View {
        if let stats = model.weekStats {
            NavigationLink {
                InsightsView(api: api, library: library, model: InsightsModel(api: api, span: .last7))
            } label: {
                WeekStrip(stats: stats)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
        }
        if let counts = model.counts, counts.total > 0 {
            CountChips(counts: counts) { onShowLibrary(LibraryFilter(status: $0)) }
        }
    }
}

// MARK: The Field's sections

extension HomeScreen {
    /// "The Field", and when it is: "Tuesday evening · 3 in progress · 2 airing today".
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("The Field")
                .font(.aaruDisplay(.largeTitle, weight: .semibold))
                .foregroundStyle(Color(.ink))
                .accessibilityAddTraits(.isHeader)
            Text(model.fieldLine)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Color(.muted))
        }
        .padding(.horizontal, 20)
    }

    /// Full width under the heading, above the split, so it leads on every screen size.
    @ViewBuilder private var nowPlayingSection: some View {
        if let playing = model.nowPlaying {
            NowPlayingCard(playing: playing, wide: !compact)
                .padding(.horizontal, 20)
        }
    }

    @ViewBuilder private var tonightSection: some View {
        if let tonight = model.tonight {
            TonightCard(
                tonight: tonight,
                isPending: model.pending.contains(tonight.primary.libraryItemId),
                wide: !compact
            ) { entry in Task { await model.markNextWatched(entry) } }
                .padding(.horizontal, 20)
        }
    }

    /// Agent requests waiting for the user (OUT-004), with the heron while any wait.
    @ViewBuilder private var waitingSection: some View {
        if let api, !plans.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("Waiting for you").eyebrow()
                        .accessibilityAddTraits(.isHeader)
                    AgentPresence(label: "Aaru is waiting for your answer")
                }
                ForEach(plans, id: \.id) { plan in
                    PlanCardView(api: api, plan: plan) { decided in
                        if decided.status == .applied {
                            Task { await model.load() }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder private var welcome: some View {
        if model.isEmpty {
            HomeWelcome { showsSearch = true }
                .padding(.horizontal, 20)
        }
    }

    /// The user's own rows. Continue watching leaves out the show Tonight already leads with.
    @ViewBuilder private var ownRows: some View {
        let continuing = model.continueWatching.filter { entry in
            guard case let .continuing(lead)? = model.tonight?.primary else { return true }
            return entry.libraryItemId != lead.libraryItemId
        }
        if !continuing.isEmpty {
            HomeRow(title: "Continue watching") {
                ForEach(continuing, id: \.libraryItemId) { entry in
                    ContinueCard(
                        entry: entry,
                        width: HomeCardSize.wide.width(compact: compact),
                        isPending: model.pending.contains(entry.libraryItemId)
                    ) { Task { await model.markNextWatched(entry) } }
                        .markWatchedMenu(library.entry(entry.libraryItemId), api: api, library: library) {
                            #if os(iOS)
                                Button("Start watching", systemImage: "play.circle") {
                                    Task { await model.startWatching(entry) }
                                }
                            #endif
                        }
                }
            }
        }
        if !model.listening.isEmpty {
            HomeRow(title: "Listening") {
                ForEach(model.listening) { row in
                    ListeningCard(row: row, width: HomeCardSize.poster.width(compact: compact))
                }
            }
        }
        if !model.upcoming.isEmpty {
            HomeRow(title: "Airing soon", trailing: ("See calendar", { onSelectTab(.calendar) })) {
                ForEach(model.upcoming, id: \.cellID) { entry in
                    AiringCard(
                        entry: entry,
                        when: model.airingLabel(entry),
                        width: HomeCardSize.banner.width(compact: compact)
                    )
                    .markWatchedMenu(library.entry(entry.libraryItemId), api: api, library: library) {}
                }
            }
        }
        if !model.startWatching.isEmpty {
            HomeRow(title: "Start watching") {
                ForEach(model.startWatching, id: \.libraryItemId) { entry in
                    StartCard(entry: entry, width: HomeCardSize.poster.width(compact: compact))
                        .markWatchedMenu(library.entry(entry.libraryItemId), api: api, library: library) {}
                }
            }
        }
        if !model.unfinished.isEmpty {
            HomeRow(title: "Unfinished") {
                ForEach(model.unfinished, id: \.libraryItemId) { entry in
                    UnfinishedCard(
                        entry: entry,
                        reason: model.unfinishedLabel(entry),
                        width: HomeCardSize.poster.width(compact: compact)
                    )
                }
            }
        }
    }

    /// The side column on wide screens, after the rows on a phone: the last import, the week,
    /// the shelf's counts, the recap and the user's lists.
    @ViewBuilder private var sideBlocks: some View {
        if let imports, let job = lastImport {
            NavigationLink {
                ImportDetailView(id: job.id, imports: imports, library: library, lists: lists, api: api)
            } label: {
                LastImportCard(job: job)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
        }
        summary
        if let offered = RecapPeriod.offered(now: .now, calendar: model.calendar) {
            RecapBanner(period: offered) { recap = offered }
                .padding(.horizontal, 20)
        }
        if !lists.lists.isEmpty {
            HomeRow(title: "Your lists", trailing: ("All lists", { onSelectTab(.lists) })) {
                ForEach(lists.lists, id: \.id) { list in
                    NavigationLink {
                        ListDetailView(listID: list.id, lists: lists, library: library, api: api)
                    } label: {
                        ListChip(list: list)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var lastImport: ImportJob? {
        imports?.jobs.max { $0.createdAt < $1.createdAt }
    }
}

extension HomeScreen {
    /// DISC-001: the public rows, after the user's own. The first one leads to the Discover tab.
    private var discoverRows: some View {
        let rows = model.discover.filter { !$0.items.isEmpty }
        return ForEach(rows, id: \.id) { row in
            HomeRow(
                title: row.title,
                note: row.note,
                trailing: row.id == rows.first?.id ? ("See Discover", { onSelectTab(.discover) }) : nil
            ) {
                ForEach(row.items) { hit in
                    DiscoverCard(
                        hit: hit,
                        libraryItemID: model.libraryItemID(hit),
                        badge: DiscoverCard.releaseBadge(hit.releaseDate, row: row.id),
                        width: HomeCardSize.poster.width(compact: compact),
                        isAdding: model.adding.contains(hit.id)
                    ) { status in
                        Task { await model.add(hit, status: status) }
                    } onAddToList: {
                        listTarget = hit
                    }
                }
            }
        }
    }
}
