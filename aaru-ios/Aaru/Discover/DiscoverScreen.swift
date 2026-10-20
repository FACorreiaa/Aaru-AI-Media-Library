import AaruAPI
import SwiftUI

/// Discover (APP-012, DISC-001): catalog rows to add from without typing, with the same cards as
/// Home's Discover rows. Renders the cache first, then refreshes. Credits TMDB and AniList, whose
/// lists these are.
struct DiscoverScreen: View {
    let api: Client?
    let library: LibraryModel
    let lists: ListsModel

    @State private var model: DiscoverModel
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
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Discover")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Search", systemImage: "magnifyingglass") { showsSearch = true }
                    }
                }
                .task { await model.loadIfNeeded() }
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
                    ProblemBanner(message: model.problem) { model.problem = nil }
                }
                .background(Color(.paper))
        }
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
                        HomeRow(title: row.title) {
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
