import AaruAPI
import SwiftUI

/// Discover (APP-012, DISC-001): catalog rows to add from without typing, with the same cards as
/// Home's Discover rows. Renders the cache first, then refreshes. Credits the providers whose rows
/// are on screen (UX-048). A segmented control switches Today's rows for On air (this week's shows
/// by channel, DISC-003), the Seasons view (DISC-002) and, when the server has concerts on, the
/// Concerts view (MUS-003). LIB-005: Today's filter turns the rows into one grid of the titles
/// that match, 20 at a time with more on scroll.
struct DiscoverScreen: View {
    enum Section: String, CaseIterable, Identifiable {
        case today, onAir, seasons, concerts

        var id: String {
            rawValue
        }

        var label: String {
            switch self {
            case .today: "Today"
            case .onAir: "On air"
            case .seasons: "Seasons"
            case .concerts: "Concerts"
            }
        }
    }

    let api: Client?
    let library: LibraryModel
    let lists: ListsModel

    @State private var model: DiscoverModel
    @State private var onAir: OnAirModel
    @State private var seasons: SeasonModel
    @State private var concerts: ConcertsModel
    @State private var section: Section = .today
    @State private var listTarget: CatalogHit?
    @State private var query = ""
    @State private var shown = Paging.pageSize
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicType

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
        private var compact: Bool {
            sizeClass == .compact
        }
    #else
        private let compact = false
    #endif

    init(api: Client?, library: LibraryModel, lists: ListsModel, model: DiscoverModel? = nil) {
        self.api = api
        self.library = library
        self.lists = lists
        _model = State(initialValue: model ?? DiscoverModel(api: api, library: library))
        _onAir = State(initialValue: OnAirModel(api: api, library: library))
        _seasons = State(initialValue: SeasonModel(api: api, library: library))
        _concerts = State(initialValue: ConcertsModel(api: api))
    }

    var body: some View {
        @Bindable var router = router
        NavigationStack {
            Group {
                switch section {
                case .today:
                    content
                        .searchable(text: $query, prompt: "Filter Discover")
                        .onChange(of: query) { shown = Paging.pageSize }
                case .onAir:
                    OnAirView(model: onAir, compact: compact) { listTarget = $0 }
                        .task { await onAir.loadIfNeeded() }
                case .seasons:
                    SeasonBrowser(model: seasons, compact: compact) { listTarget = $0 }
                case .concerts:
                    ConcertsView(model: concerts)
                        .searchable(text: $concerts.searchText, prompt: "Search an artist")
                        .searchScopes($concerts.scope) {
                            Text(concerts.nearScopeLabel).tag(ConcertSearchScope.near)
                            Text("Anywhere").tag(ConcertSearchScope.anywhere)
                        }
                        .onSubmit(of: .search) { concerts.submitSearch() }
                        // Cancel, or the field's ×, goes back to everything near.
                        .onChange(of: concerts.searchText) { _, text in
                            if text.trimmingCharacters(in: .whitespaces).isEmpty {
                                concerts.clearSearch()
                            }
                        }
                }
            }
            .navigationTitle("Discover")
            #if os(iOS)
                .safeAreaInset(edge: .top, spacing: 0) {
                    sectionPicker
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .background(.bar)
                }
            #endif
                .toolbar {
                    #if os(macOS)
                        ToolbarItem(placement: .principal) { sectionPicker.fixedSize() }
                    #endif
                    ToolbarItem(placement: .primaryAction) {
                        Button("Search", systemImage: "magnifyingglass") { router.showsSearch = true }
                    }
                    // iPhone has no Sports tab: it opens from here (SPT-004).
                    if compact, router.sportsAvailable {
                        ToolbarItem(placement: .primaryAction) {
                            Button(AppTab.sports.title, systemImage: AppTab.sports.symbol) {
                                router.showsSportsInDiscover = true
                            }
                        }
                    }
                }
                .navigationDestination(isPresented: $router.showsSportsInDiscover) {
                    SportsView(api: api)
                }
                .task { await model.loadIfNeeded() }
                .task { await concerts.loadSetting() }
                .onChange(of: concerts.available) { _, available in
                    if !available, section == .concerts {
                        section = .today
                    }
                }
                // View → Refresh (⌘R) reloads the section on screen.
                .refreshesOnCommand(.discover) { await reload() }
                .refreshable { await reload() }
                .navigationDestination(for: String.self) { id in
                    LibraryEntryDestination(id: id, api: api, library: library, lists: lists)
                }
                .catalogDestination(api: api, library: library, lists: lists)
                .sheet(item: $listTarget) { hit in
                    ListPickerSheet(
                        ref: .init(_type: hit._type, ids: hit.ids, title: hit.title, year: hit.year),
                        titleName: hit.title,
                        lists: lists
                    )
                }
                .safeAreaInset(edge: .bottom) {
                    switch section {
                    case .today: ProblemBanner(message: model.problem) { model.problem = nil }
                    case .onAir: ProblemBanner(message: onAir.problem) { onAir.problem = nil }
                    case .seasons: ProblemBanner(message: seasons.problem) { seasons.problem = nil }
                    case .concerts: ProblemBanner(message: concerts.problem) { concerts.problem = nil }
                    }
                }
                .background(Color(.paper))
        }
    }

    private func reload() async {
        switch section {
        case .today: await model.load()
        case .onAir: await onAir.load()
        case .seasons: await seasons.reload()
        case .concerts: await concerts.reload()
        }
    }

    /// Rows with a fuller view of their own: this season's anime and what is on the air.
    private func trailing(for row: String) -> (label: String, action: () -> Void)? {
        switch row {
        case "anime_season": ("All seasons", { showSeasons(.anime) })
        case "tv_on_air": ("By channel", { section = .onAir })
        default: nil
        }
    }

    private func showSeasons(_ kind: SeasonKind) {
        seasons.kind = kind
        section = .seasons
    }

    /// Concerts only when the server has them on.
    private var sections: [Section] {
        Section.allCases.filter { $0 != .concerts || concerts.available }
    }

    private var sectionPicker: some View {
        Picker("Discover", selection: $section) {
            ForEach(sections) { section in
                Text(section.label).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    @ViewBuilder private var content: some View {
        let rows = model.visibleRows
        if rows.isEmpty, model.isLoading || !model.hasLoaded, model.problem == nil {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if rows.isEmpty, model.problem != nil {
            // A failed first load is an error, not an empty catalog (UX-063).
            LoadFailedView(
                title: "Couldn't load Discover",
                message: "The catalog rows didn't load. Search still works."
            ) { await model.load() }
        } else if rows.isEmpty {
            ContentUnavailableView {
                Label("Nothing to discover right now", systemImage: "binoculars")
            } description: {
                Text("The catalog rows are empty for now. Search still works.")
            } actions: {
                Button("Search") { router.showsSearch = true }
                    .buttonStyle(.borderedProminent)
            }
        } else if !query.isEmpty {
            found(model.matches(query))
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AaruSpace.section) {
                    ForEach(rows, id: \.id) { row in
                        HomeRow(
                            title: row.title,
                            note: row.note,
                            trailing: trailing(for: row.id)
                        ) {
                            ForEach(row.items) { hit in
                                DiscoverCard(
                                    hit: hit,
                                    libraryItemID: model.libraryItemID(hit),
                                    badge: DiscoverCard.releaseBadge(hit.releaseDate, row: row.id),
                                    width: HomeCardSize.poster.width(compact: compact, dynamicType: dynamicType),
                                    isAdding: model.adding.contains(hit.id)
                                ) { status in
                                    Task { await model.add(hit, status: status) }
                                } onAddToList: {
                                    listTarget = hit
                                }
                            }
                        }
                    }
                    DiscoverCredits(providers: DiscoverCredits.providers(for: rows))
                }
                .padding(.vertical, 16)
            }
        }
    }
}

extension DiscoverScreen {
    /// The filter's grid: the titles that match, 20 more each time the end comes into view.
    @ViewBuilder func found(_ matches: [DiscoverMatch]) -> some View {
        if matches.isEmpty {
            ContentUnavailableView {
                Label("Nothing on Discover matches “\(query)”", systemImage: "magnifyingglass")
            } description: {
                Text("Search finds every title.")
            } actions: {
                Button("Search") { router.showsSearch = true }
                    .buttonStyle(.bordered)
            }
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: compact ? 104 : 140), spacing: 12, alignment: .top)],
                    spacing: 20
                ) {
                    ForEach(matches.prefix(shown)) { match in
                        DiscoverCard(
                            hit: match.hit,
                            libraryItemID: model.libraryItemID(match.hit),
                            badge: DiscoverCard.releaseBadge(match.hit.releaseDate, row: match.row),
                            width: nil,
                            isAdding: model.adding.contains(match.hit.id)
                        ) { status in
                            Task { await model.add(match.hit, status: status) }
                        } onAddToList: {
                            listTarget = match.hit
                        }
                    }
                }
                .padding(16)
                LoadMore(shown: $shown, total: matches.count)
            }
        }
    }
}

/// The providers' credit, linking to About for the full notices: "Rows from TMDB, AniList and
/// Open Library", naming only the providers whose rows are on screen (UX-048).
struct DiscoverCredits: View {
    let providers: [String]

    /// Each kind's source, in a fixed order: films and shows from TMDB, anime from AniList, books
    /// from Open Library, albums from ListenBrainz.
    static func providers(for rows: [DiscoverRow]) -> [String] {
        let kinds = Set(rows.flatMap(\.items).map { MediaKind(type: $0._type, isAnime: $0.isAnime) })
        return [
            ("TMDB", kinds.contains(.film) || kinds.contains(.show)),
            ("AniList", kinds.contains(.anime)),
            ("Open Library", kinds.contains(.book)),
            ("ListenBrainz", kinds.contains(.music)),
        ].filter(\.1).map(\.0)
    }

    var body: some View {
        if !providers.isEmpty {
            NavigationLink {
                AboutView()
            } label: {
                Label("Rows from \(providers.formatted(.list(type: .and)))", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Color(.muted))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .accessibilityHint("Shows the providers' notices in About")
        }
    }
}

// MARK: Previews

#Preview("Discover") {
    DiscoverScreen(
        api: nil, library: LibraryModel(), lists: ListsModel(api: nil),
        model: DiscoverModel(preview: HomeModel.newAccount.discover)
    )
    .environment(AppRouter())
}
