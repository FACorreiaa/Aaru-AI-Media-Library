import AaruAPI
import SwiftUI

/// Discover (APP-012, DISC-001): catalog rows to add from without typing, with the same cards as
/// Home's Discover rows. Renders the cache first, then refreshes. Credits TMDB and AniList, whose
/// lists these are. A segmented control switches Today's rows for the Seasons view (DISC-002)
/// and, when the server has concerts on, the Concerts view (MUS-003).
struct DiscoverScreen: View {
    enum Section: String, CaseIterable, Identifiable {
        case today, seasons, concerts

        var id: String {
            rawValue
        }

        var label: String {
            switch self {
            case .today: "Today"
            case .seasons: "Seasons"
            case .concerts: "Concerts"
            }
        }
    }

    let api: Client?
    let library: LibraryModel
    let lists: ListsModel

    @State private var model: DiscoverModel
    @State private var seasons: SeasonModel
    @State private var concerts: ConcertsModel
    @State private var section: Section = .today
    @State private var showsSearch = false
    @State private var listTarget: CatalogHit?

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
        _seasons = State(initialValue: SeasonModel(api: api, library: library))
        _concerts = State(initialValue: ConcertsModel(api: api))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch section {
                case .today: content
                case .seasons:
                    SeasonBrowser(model: seasons, compact: compact) { listTarget = $0 }
                case .concerts:
                    ConcertsView(model: concerts)
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
                        Button("Search", systemImage: "magnifyingglass") { showsSearch = true }
                    }
                }
                .task { await model.loadIfNeeded() }
                .task { await concerts.loadSetting() }
                .onChange(of: concerts.available) { _, available in
                    if !available, section == .concerts {
                        section = .today
                    }
                }
                .refreshable { await model.load() }
                .navigationDestination(for: String.self) { id in
                    LibraryEntryDestination(id: id, api: api, library: library, lists: lists)
                }
                .sheet(isPresented: $showsSearch) {
                    SearchView(api: api, library: library, lists: lists)
                }
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
                    case .seasons: ProblemBanner(message: seasons.problem) { seasons.problem = nil }
                    case .concerts: ProblemBanner(message: concerts.problem) { concerts.problem = nil }
                    }
                }
                .background(Color(.paper))
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
        } else if rows.isEmpty {
            ContentUnavailableView {
                Label("Nothing to discover right now", systemImage: "binoculars")
            } description: {
                Text("The catalog lists could not be loaded. Search still works.")
            } actions: {
                Button("Try again") { Task { await model.load() } }
                    .buttonStyle(.borderedProminent)
                Button("Search") { showsSearch = true }
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(rows, id: \.id) { row in
                        HomeRow(
                            title: row.title,
                            trailing: row.id == "anime_season" ? ("All seasons", { showSeasons(.anime) }) : nil
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
                    DiscoverCredits()
                }
                .padding(.vertical, 16)
            }
        }
    }
}

/// The providers' credit, linking to About for the full notices.
private struct DiscoverCredits: View {
    var body: some View {
        NavigationLink {
            AboutView()
        } label: {
            Label("Lists from TMDB and AniList", systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(Color(.muted))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }
}

// MARK: Previews

#Preview("Discover") {
    DiscoverScreen(
        api: nil, library: LibraryModel(), lists: ListsModel(api: nil),
        model: DiscoverModel(preview: HomeModel.newAccount.discover)
    )
}
