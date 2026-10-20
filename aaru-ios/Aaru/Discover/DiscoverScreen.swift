import AaruAPI
import SwiftUI

/// Discover (APP-012): catalog rows to add from without typing. Renders the cache first, then
/// refreshes. Credits TMDB and AniList, whose lists these are.
struct DiscoverScreen: View {
    let api: Client?
    let library: LibraryModel
    let lists: ListsModel

    @State private var model: DiscoverModel
    @State private var showsSearch = false

    init(api: Client?, library: LibraryModel, lists: ListsModel, model: DiscoverModel? = nil) {
        self.api = api
        self.library = library
        self.lists = lists
        _model = State(initialValue: model ?? DiscoverModel(api: api))
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
                .sheet(isPresented: $showsSearch) {
                    SearchView(api: api, library: library, lists: lists)
                }
                .safeAreaInset(edge: .bottom) {
                    ProblemBanner(message: model.problem) { model.problem = nil }
                }
                .background(Color(.paper))
        }
    }

    @ViewBuilder private var content: some View {
        let sections = model.visibleSections
        if sections.isEmpty, model.isLoading || !model.hasLoaded, model.problem == nil {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if sections.isEmpty {
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
                    ForEach(sections, id: \.id) { section in
                        DiscoverRow(
                            title: DiscoverModel.title(for: section),
                            hits: section.items,
                            showsDates: DiscoverModel.showsDates(section),
                            api: api, library: library, lists: lists
                        ) { model.problem = $0 }
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
