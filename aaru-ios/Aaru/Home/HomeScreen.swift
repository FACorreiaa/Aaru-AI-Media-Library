import AaruAPI
import SwiftUI

/// Home (APP-009, DESIGN.md §13): Continue watching, Start watching, and what airs next, as
/// Trakt-style rows of cards. Renders from the cache first, then refreshes.
struct HomeScreen: View {
    let api: Client?
    let library: LibraryModel
    let lists: ListsModel
    /// Switches the app to the Calendar destination.
    var onSeeCalendar: () -> Void

    @State private var model: HomeModel
    @State private var showsSearch = false

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
        onSeeCalendar: @escaping () -> Void
    ) {
        self.api = api
        self.library = library
        self.lists = lists
        self.onSeeCalendar = onSeeCalendar
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
                .task { await model.loadIfNeeded() }
                .refreshable { await model.load() }
                .navigationDestination(for: String.self) { id in
                    LibraryEntryDestination(id: id, api: api, library: library, lists: lists)
                }
                .sheet(isPresented: $showsSearch) {
                    SearchView(api: api, library: library, lists: lists)
                }
                .safeAreaInset(edge: .bottom) {
                    ProblemBanner(message: model.problem) { model.problem = nil }
                }
                .background(Color(.paper))
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isEmpty, model.hasLoaded {
            ContentUnavailableView {
                Label("Add a show to see what's next", systemImage: "sparkles.tv")
            } description: {
                Text("Shows you are watching, things to start, and new episodes land here.")
            } actions: {
                Button("Search") { showsSearch = true }
                    .buttonStyle(.borderedProminent)
            }
        } else if model.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if !model.continueWatching.isEmpty {
                        HomeRow(title: "Continue watching") {
                            ForEach(model.continueWatching, id: \.libraryItemId) { entry in
                                ContinueCard(
                                    entry: entry,
                                    width: HomeCardSize.wide.width(compact: compact),
                                    isPending: model.pending.contains(entry.libraryItemId)
                                ) { Task { await model.markNextWatched(entry) } }
                            }
                        }
                    }
                    if !model.upcoming.isEmpty {
                        HomeRow(title: "Airing soon", trailing: ("See calendar", onSeeCalendar)) {
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
                }
                .padding(.vertical, 16)
            }
        }
    }
}

// MARK: Previews

#Preview("Home") {
    HomeScreen(api: nil, library: LibraryModel(), lists: ListsModel(api: nil), model: .sample) {}
}

#Preview("Home · dark") {
    HomeScreen(api: nil, library: LibraryModel(), lists: ListsModel(api: nil), model: .sample) {}
        .preferredColorScheme(.dark)
}

#Preview("Mac", traits: .fixedLayout(width: 1280, height: 800)) {
    HomeScreen(api: nil, library: LibraryModel(), lists: ListsModel(api: nil), model: .sample) {}
}

#Preview("Empty") {
    HomeScreen(
        api: nil, library: LibraryModel(), lists: ListsModel(api: nil),
        model: HomeModel(preview: .init(upNext: .init(continueWatching: [], startWatching: []), airing: []))
    ) {}
}
