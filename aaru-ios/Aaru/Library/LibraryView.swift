import AaruAPI
import SwiftUI

/// What the library is narrowed to. Owned by the router so Home's count chips can set it.
struct LibraryFilter: Equatable {
    var kind: MediaKind?
    var status: LibraryStatus?

    var isActive: Bool {
        kind != nil || status != nil
    }
}

/// APP-003: the library. Filter by kind and status, poster grid or rows, readable offline. On
/// iPhone it is also the way into Lists, which has no tab there (DESIGN.md §18). LIB-005: a
/// filter over every title by name, and 20 at a time with more on scroll.
struct LibraryView: View {
    let api: Client?
    let library: LibraryModel
    let lists: ListsModel
    @Binding var filter: LibraryFilter

    @Environment(AppRouter.self) private var router
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @AppStorage("library.layout") private var layout = LibraryLayout.grid
    @State private var showsInsights = false
    @State private var recap: RecapPeriod?
    /// The row whose "Add to list…" was chosen.
    @State private var listTarget: LibraryRow?
    /// The row whose "Remove from library…" waits for a yes.
    @State private var removing: LibraryRow?
    /// A failed "Now" write (APP-017) or removal.
    @State private var problem: String?
    @State private var query = ""
    @State private var shown = Paging.pageSize

    private var rows: [LibraryRow] {
        library.rows(kind: filter.kind, status: filter.status)
            .filter { Paging.matches(query, $0.title, $0.originalTitle, $0.byline) }
    }

    /// iPhone (and a compact iPad window): Lists opens from here.
    private var showsListsEntry: Bool {
        #if os(iOS)
            sizeClass == .compact
        #else
            false
        #endif
    }

    var body: some View {
        @Bindable var router = router
        NavigationStack {
            content
                .navigationTitle("Library")
                .safeAreaInset(edge: .top, spacing: 0) {
                    LibraryFilterBar(
                        filter: $filter,
                        syncProblem: library.firstSyncProblem == nil ? library.syncProblem : nil
                    )
                }
                .searchable(text: $query, prompt: "Filter your library")
                .onChange(of: query) { shown = Paging.pageSize }
                .onChange(of: filter) { shown = Paging.pageSize }
                .toolbar { toolbar }
                .accountButton()
                .refreshable { await library.sync(api: api) }
                .refreshesOnCommand(.library) { await library.sync(api: api) }
                .task { await library.sync(api: api) }
                .navigationDestination(for: String.self) { id in
                    // A missing item (removed elsewhere) says so instead of an empty screen (UX-071).
                    LibraryEntryDestination(id: id, api: api, library: library, lists: lists)
                }
                .navigationDestination(for: NowGroupRoute.self) { route in
                    NowGroupView(route: route, library: library, api: api)
                }
                .navigationDestination(isPresented: $router.showsListsInLibrary) {
                    ListsView(lists: lists, library: library, api: api)
                }
                .navigationDestination(isPresented: $showsInsights) { InsightsView(api: api, library: library) }
                .sheet(item: $listTarget) { row in
                    if let entry = library.entry(row.id) {
                        ListPickerSheet(
                            ref: .init(titleId: entry.title.id, _type: entry.title._type),
                            titleName: entry.title.title,
                            lists: lists
                        )
                    }
                }
                .confirmationDialog(
                    "Remove “\(removing?.title ?? "")” from your library?",
                    isPresented: $removing.isPresent,
                    titleVisibility: .visible,
                    presenting: removing
                ) { row in
                    Button("Remove from library", role: .destructive) { remove(row) }
                } message: { _ in
                    Text(TitleRemoval.message)
                }
                .recapStory($recap, api: api)
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 0) {
                        RemovalRibbon(title: library.lastRemoval) {
                            library.lastRemoval = nil
                            router.openHistory()
                        } onDismiss: {
                            library.lastRemoval = nil
                        }
                        ProblemBanner(message: problem) { problem = nil }
                    }
                }
                .undoToast()
                .background(Color(.paper))
        }
    }

    @ViewBuilder private var content: some View {
        if rows.isEmpty {
            emptyState
        } else if layout == .grid {
            ScrollView {
                if showsListsEntry {
                    ListsEntryRow(count: lists.hasLoaded ? lists.lists.count : nil) { router.showLists() }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
                now
                LibraryGrid(rows: Array(rows.prefix(shown))) { row in rowMenu(row) }
                LoadMore(shown: $shown, total: rows.count)
            }
        } else {
            List {
                if showsListsEntry {
                    ListsEntryRow(count: lists.hasLoaded ? lists.lists.count : nil) { router.showLists() }
                        .listRowBackground(Color.clear)
                }
                now
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                ForEach(rows.prefix(shown)) { row in
                    NavigationLink(value: row.id) { LibraryListRow(row: row) }
                        .listRowBackground(Color.clear)
                        .contextMenu { rowMenu(row) }
                }
                LoadMore(shown: $shown, total: rows.count)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    /// Loading, a failed first sync, a new account's empty library, or filters that match
    /// nothing. Only a successful sync can say the library is empty (UX-062).
    @ViewBuilder private var emptyState: some View {
        if let failure = library.firstSyncProblem {
            LoadFailedView(title: "Your library didn't load", message: failure) {
                await library.sync(api: api)
            }
        } else if library.rows.isEmpty, !library.hasSynced {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if library.rows.isEmpty {
            OwlUnavailableView(
                title: "Your library is empty",
                message: "Search for a film, show, anime, book or album, or bring your history from another app."
            ) {
                Button("Search") { router.showsSearch = true }
                    .buttonStyle(.borderedProminent)
                Button("Bring your history") { router.openSettings(.imports) }
                    .buttonStyle(.bordered)
            }
        } else if !query.isEmpty, !filter.isActive {
            ContentUnavailableView.search(text: query)
        } else {
            ContentUnavailableView {
                Label("No titles match these filters", systemImage: "line.3.horizontal.decrease.circle")
            } actions: {
                Button("Clear filters") {
                    filter = LibraryFilter()
                    query = ""
                }
                .buttonStyle(.bordered)
            }
        }
    }

    /// Hidden while a status other than in progress is chosen: Now is the in-progress part.
    /// Hidden while filtering too: the results lead.
    @ViewBuilder private var now: some View {
        if query.isEmpty, filter.status == nil || filter.status == .inProgress {
            NowSection(library: library, api: api, kind: filter.kind) { problem = $0 }
        }
    }

    @ViewBuilder private func rowMenu(_ row: LibraryRow) -> some View {
        if let entry = library.entry(row.id) {
            MarkWatchedButton(entry: entry, api: api, library: library)
        }
        Button("Add to list…", systemImage: "text.badge.plus") { listTarget = row }
        Divider()
        Button("Remove from library…", systemImage: "trash", role: .destructive) { removing = row }
    }

    private func remove(_ row: LibraryRow) {
        Task { problem = await library.remove(row.id, api: api) }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            // ⌘F is the menu bar's Search, so this button carries no shortcut of its own.
            Button("Search", systemImage: "magnifyingglass") { router.showsSearch = true }
        }
        if showsListsEntry {
            ToolbarItem(placement: .primaryAction) {
                Button("Lists", systemImage: "list.bullet.rectangle") { router.showLists() }
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Menu("More", systemImage: "ellipsis.circle") {
                Picker("Layout", selection: $layout) {
                    Label("Grid", systemImage: "square.grid.2x2").tag(LibraryLayout.grid)
                    Label("Rows", systemImage: "list.bullet").tag(LibraryLayout.list)
                }
                Divider()
                Button("Insights", systemImage: "chart.bar") { showsInsights = true }
                // Listens is a view of the Music page (NAV-002).
                Button("Listens", systemImage: "music.note.list") { router.showListens() }
                Menu("Recaps", systemImage: "sparkles") {
                    ForEach(RecapPeriod.shortcuts(now: .now, calendar: .aaru)) { period in
                        Button(period.label) { recap = period }
                    }
                }
            }
        }
    }
}

/// Grid of posters, or rows. The stored raw values predate the "Rows" label.
enum LibraryLayout: String {
    case grid, list
}

/// What the confirmation for removing a title says, in Library and the title room alike.
enum TitleRemoval {
    static let message = "Its status, rating, notes and progress go with it. You can undo this in "
        + "Settings → Your data → History."
}
