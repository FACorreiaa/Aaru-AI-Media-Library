import AaruAPI
import SwiftUI

/// NAV-002: Books, Manga and Music, one page per kind. At the top the user's shelf for the kind
/// (`KindShelf`), below it the kind's Discover rows with the same cards as Discover, credited to
/// the providers shown. The rows come from the Discover model the app shares, so `/v1/discover`
/// loads once. Music adds a segmented control for Concerts (MUS-003, while the server has them
/// on) and Listens (MUS-008).
struct KindScreen: View {
    let kind: MediaKind
    let api: Client?
    let library: LibraryModel
    let lists: ListsModel
    let discover: DiscoverModel

    /// Music only: Concerts, moved here from Discover.
    @State private var concerts: ConcertsModel
    @State private var listTarget: CatalogHit?
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

    init(kind: MediaKind, api: Client?, library: LibraryModel, lists: ListsModel, discover: DiscoverModel) {
        self.kind = kind
        self.api = api
        self.library = library
        self.lists = lists
        self.discover = discover
        _concerts = State(initialValue: ConcertsModel(api: api))
    }

    private var tab: AppTab {
        switch kind {
        case .manga: .manga
        case .music: .music
        default: .books
        }
    }

    /// The view on screen: always the albums for Books and Manga, the chosen one for Music.
    private var pane: MusicPane {
        kind == .music ? router.musicPane : .albums
    }

    var body: some View {
        NavigationStack {
            Group {
                switch pane {
                case .albums: page
                case .concerts: concertsPane
                case .listens: ListensContent(api: api, library: library)
                }
            }
            .navigationTitle(tab.title)
            #if os(iOS)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if kind == .music {
                        musicPicker
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                            .background(.bar)
                    }
                }
            #endif
                .toolbar {
                    #if os(macOS)
                        if kind == .music {
                            ToolbarItem(placement: .principal) { musicPicker.fixedSize() }
                        }
                    #endif
                    ToolbarItem(placement: .primaryAction) {
                        Button("Search", systemImage: "magnifyingglass") { router.showsSearch = true }
                    }
                }
                .task { await discover.loadIfNeeded() }
                .task {
                    if kind == .music {
                        await concerts.loadSetting()
                    }
                }
                .onChange(of: concerts.available) { _, available in
                    if !available, router.musicPane == .concerts {
                        router.musicPane = .albums
                    }
                }
                // View → Refresh (⌘R) reloads the view on screen.
                .refreshesOnCommand(tab) { await reload() }
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
                    switch pane {
                    case .albums: ProblemBanner(message: discover.problem) { discover.problem = nil }
                    case .concerts: ProblemBanner(message: concerts.problem) { concerts.problem = nil }
                    case .listens: EmptyView()
                    }
                }
                .background(Color(.paper))
        }
    }

    private func reload() async {
        switch pane {
        case .albums:
            async let rows: Void = discover.load()
            async let shelf: Void = library.sync(api: api)
            _ = await (rows, shelf)
        case .concerts: await concerts.reload()
        // Listens loads its own panes as they appear.
        case .listens: break
        }
    }

    /// Concerts only when the server has them on.
    private var musicPanes: [MusicPane] {
        MusicPane.allCases.filter { $0 != .concerts || concerts.available }
    }

    private var musicPicker: some View {
        @Bindable var router = router
        return Picker("Music", selection: $router.musicPane) {
            ForEach(musicPanes) { pane in
                Text(pane.label).tag(pane)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    /// The shelf, then the kind's rows.
    private var page: some View {
        let rows = discover.visibleRows(of: [kind.discoverKind])
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: AaruSpace.section) {
                KindShelf(kind: kind, library: library, compact: compact) { status in
                    router.showLibrary(LibraryFilter(kind: kind, status: status))
                }
                if rows.isEmpty {
                    rowsPlaceholder
                }
                ForEach(rows, id: \.id) { row in
                    HomeRow(title: row.title, note: row.note) {
                        ForEach(row.items) { hit in
                            DiscoverCard(
                                hit: hit,
                                libraryItemID: discover.libraryItemID(hit),
                                badge: DiscoverCard.releaseBadge(hit.releaseDate, row: row.id),
                                width: HomeCardSize.poster.width(compact: compact, dynamicType: dynamicType),
                                isAdding: discover.adding.contains(hit.id)
                            ) { status in
                                Task { await discover.add(hit, status: status) }
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
        .refreshable { await reload() }
    }

    /// No rows yet: loading, or a quiet line when they did not load (the banner says why).
    @ViewBuilder private var rowsPlaceholder: some View {
        if discover.isLoading || !discover.hasLoaded, discover.problem == nil {
            ProgressView().frame(maxWidth: .infinity)
        } else if discover.problem != nil {
            Text("The catalog rows didn't load. Search still works.")
                .font(.subheadline)
                .foregroundStyle(Color(.muted))
                .padding(.horizontal, 20)
        }
    }

    private var concertsPane: some View {
        ConcertsView(model: concerts)
            .searchable(text: $concerts.searchText, prompt: "Search an artist")
            .searchScopes($concerts.scope) {
                Text(concerts.nearScopeLabel).tag(ConcertSearchScope.near)
                Text("Anywhere").tag(ConcertSearchScope.anywhere)
            }
            .onSubmit(of: .search) { Task { await concerts.submitSearch() } }
            // Cancel, or the field's ×, goes back to everything near.
            .onChange(of: concerts.searchText) { _, text in
                if text.trimmingCharacters(in: .whitespaces).isEmpty {
                    concerts.clearSearch()
                }
            }
    }
}

// MARK: Previews

#Preview("Books") {
    KindScreen(
        kind: .book, api: nil, library: LibraryModel(), lists: ListsModel(api: nil),
        discover: DiscoverModel(preview: HomeModel.newAccount.discover)
    )
    .environment(AppRouter())
}
