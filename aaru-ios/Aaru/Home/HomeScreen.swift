import AaruAPI
import SwiftUI

/// Home (APP-009, APP-013, DESIGN.md §13): this month's numbers and the shelf's counts, then
/// Continue watching, what airs next, Start watching, Unfinished and the user's lists, as
/// Trakt-style rows of cards, then Discover's public rows (DISC-001). Renders from the cache
/// first, then refreshes.
struct HomeScreen: View {
    let api: Client?
    let library: LibraryModel
    let lists: ListsModel
    /// Switches the app to another destination (Calendar, Discover, Lists).
    var onSelectTab: (RootView.AppTab) -> Void
    /// Switches to Library, filtered to one status.
    var onShowLibrary: (LibraryStatus) -> Void

    @State private var model: HomeModel
    @State private var showsSearch = false
    @State private var recap: RecapPeriod?
    @State private var listTarget: CatalogHit?
    /// Agent requests waiting for the user (OUT-004), pinned above the rows.
    @State private var plans: [AgentPlan] = []

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
        model: HomeModel? = nil,
        onSelectTab: @escaping (RootView.AppTab) -> Void = { _ in },
        onShowLibrary: @escaping (LibraryStatus) -> Void = { _ in }
    ) {
        self.api = api
        self.library = library
        self.lists = lists
        self.onSelectTab = onSelectTab
        self.onShowLibrary = onShowLibrary
        _model = State(initialValue: model ?? HomeModel(api: api, library: library))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Home")
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
                .task {
                    if !lists.hasLoaded {
                        await lists.load()
                    }
                }
                .refreshable {
                    await model.load()
                    await loadPlans()
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
                .background(Color(.paper))
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isEmpty, model.discover.isEmpty, model.hasLoaded {
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
        } else if model.isEmpty, model.discover.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if let api, !plans.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Waiting for you").font(.title2.weight(.medium))
                            ForEach(plans, id: \.id) { plan in
                                PlanCardView(api: api, plan: plan) { decided in
                                    if decided.status == .applied {
                                        Task { await model.load() }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    if model.isEmpty {
                        HomeWelcome { showsSearch = true }
                            .padding(.horizontal, 16)
                    }
                    if let offered = RecapPeriod.offered(now: .now, calendar: model.calendar) {
                        RecapBanner(period: offered) { recap = offered }
                            .padding(.horizontal, 16)
                    }
                    summary
                    if !model.continueWatching.isEmpty {
                        HomeRow(title: "Continue watching") {
                            ForEach(model.continueWatching, id: \.libraryItemId) { entry in
                                ContinueCard(
                                    entry: entry,
                                    width: HomeCardSize.wide.width(compact: compact),
                                    isPending: model.pending.contains(entry.libraryItemId)
                                ) { Task { await model.markNextWatched(entry) } }
                                #if os(iOS)
                                    .contextMenu {
                                        Button("Start watching", systemImage: "play.circle") {
                                            Task { await model.startWatching(entry) }
                                        }
                                    }
                                #endif
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
                            }
                        }
                    }
                    if !model.startWatching.isEmpty {
                        HomeRow(title: "Start watching") {
                            ForEach(model.startWatching, id: \.libraryItemId) { entry in
                                StartCard(entry: entry, width: HomeCardSize.poster.width(compact: compact))
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
                    discoverRows
                }
                .padding(.vertical, 16)
            }
        }
    }

    /// This month's strip (to Insights) and the shelf's counts (to Library). Each hides at zero.
    /// A failure leaves the requests on the server; the next appearance shows them.
    private func loadPlans() async {
        guard let api, case let .ok(response)? = try? await api.listPlans(query: .init(status: .pending)) else {
            return
        }
        plans = (try? response.body.json.items) ?? plans
    }

    @ViewBuilder private var summary: some View {
        if let totals = model.monthStats?.totals, !totals.isZero {
            NavigationLink {
                InsightsView(api: api)
            } label: {
                StatsStrip(totals: totals)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
        }
        if let counts = model.counts, counts.total > 0 {
            CountChips(counts: counts, onSelect: onShowLibrary)
        }
    }
}

extension HomeScreen {
    /// DISC-001: the public rows, after the user's own. The first one leads to the Discover tab.
    private var discoverRows: some View {
        let rows = model.discover.filter { !$0.items.isEmpty }
        return ForEach(rows, id: \.id) { row in
            HomeRow(
                title: row.title,
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

// MARK: Previews

#Preview("Home") {
    HomeScreen(api: nil, library: LibraryModel(), lists: ListsModel(api: nil), model: .sample)
}

#Preview("Home, new account") {
    HomeScreen(api: nil, library: LibraryModel(), lists: ListsModel(api: nil), model: .newAccount)
}

#Preview("Home · dark") {
    HomeScreen(api: nil, library: LibraryModel(), lists: ListsModel(api: nil), model: .sample)
        .preferredColorScheme(.dark)
}

#Preview("Mac", traits: .fixedLayout(width: 1280, height: 800)) {
    HomeScreen(api: nil, library: LibraryModel(), lists: ListsModel(api: nil), model: .sample)
}

#Preview("Empty") {
    HomeScreen(
        api: nil, library: LibraryModel(), lists: ListsModel(api: nil),
        model: HomeModel(preview: .init(upNext: .init(continueWatching: [], startWatching: []), airing: []))
    )
}
