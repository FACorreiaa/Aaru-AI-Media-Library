import AaruAPI
import SwiftUI

/// What a search covers: everything on screen at once, or one kind. Books are never in All (Open
/// Library is slow and noisy), so All ends with a row that searches Books instead.
enum SearchScope: String, CaseIterable, Identifiable {
    case all, film, show, anime, book

    var id: String {
        rawValue
    }

    var kind: MediaKind? {
        MediaKind(rawValue: rawValue)
    }

    var label: String {
        kind?.label ?? "All"
    }

    var searchType: Operations.SearchCatalog.Input.Query._TypePayload {
        kind?.searchType ?? .all
    }
}

/// APP-004: catalog search, debounced, with add and an initial status. All by default (APP-011).
struct SearchView: View {
    let api: Client?
    let library: LibraryModel
    let lists: ListsModel

    @Environment(\.dismiss) private var dismiss
    @State private var listTarget: CatalogHit?
    @State private var query = ""
    @State private var scope = SearchScope.all
    @State private var hits: [CatalogHit] = []
    @State private var incomplete = false
    @State private var isSearching = false
    @State private var problem: String?
    /// Hits being added right now: a second tap waits instead of adding twice.
    @State private var adding: Set<String> = []

    private struct SearchKey: Equatable {
        let query: String
        let scope: SearchScope
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("Type", selection: $scope) {
                    ForEach(SearchScope.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if let problem {
                    Text(problem).font(.footnote).foregroundStyle(.red)
                        .listRowBackground(Color.clear)
                }
                if incomplete {
                    Text("Some results are missing right now.")
                        .font(.footnote)
                        .foregroundStyle(Color(.muted))
                        .listRowBackground(Color.clear)
                }
                ForEach(hits, id: \.self) { hit in
                    SearchHitRow(
                        hit: hit,
                        kind: MediaKind(type: hit._type, isAnime: hit.isAnime),
                        isOnShelf: library.contains(hit),
                        isAdding: adding.contains(hit.id)
                    ) { status in
                        Task { await add(hit, status: status) }
                    } onAddToList: {
                        listTarget = hit
                    }
                    .listRowBackground(Color.clear)
                }
                if scope == .all, trimmedQuery.count >= 2, !isSearching || !hits.isEmpty {
                    SearchBooksRow(query: trimmedQuery, isFirst: hits.isEmpty) { scope = .book }
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(.paper))
            .overlay {
                if scope != .all, hits.isEmpty, !isSearching, trimmedQuery.count >= 2, problem == nil {
                    ContentUnavailableView.search(text: query)
                } else if isSearching, hits.isEmpty {
                    ProgressView()
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: scope == .book ? "Title, author or ISBN" : "Title")
            .task(id: SearchKey(query: query, scope: scope)) { await search() }
            .sheet(item: $listTarget) { hit in
                ListPickerSheet(
                    ref: .init(_type: hit._type, ids: hit.ids, title: hit.title, year: hit.year),
                    titleName: hit.title,
                    lists: lists
                )
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func search() async {
        let text = trimmedQuery
        guard text.count >= 2, let api else {
            hits = []
            incomplete = false
            problem = nil
            return
        }
        // Debounce: a new keystroke cancels this task before the request goes out.
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            switch try await api.searchCatalog(query: .init(q: text, _type: scope.searchType)) {
            case let .ok(response):
                let results = try response.body.json
                hits = results.items
                incomplete = results.incomplete
                problem = nil
            case let .default(_, error):
                hits = []
                incomplete = false
                problem = (try? error.body.json.message) ?? "Search is not available right now."
            }
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled {
                problem = "Aaru could not reach the server."
            }
        }
    }

    private func add(_ hit: CatalogHit, status: LibraryStatus) async {
        guard !adding.contains(hit.id) else { return }
        adding.insert(hit.id)
        defer { adding.remove(hit.id) }
        if let failure = await library.add(hit, status: status, api: api) {
            problem = failure
        }
    }
}

private struct SearchHitRow: View {
    let hit: CatalogHit
    let kind: MediaKind
    let isOnShelf: Bool
    let isAdding: Bool
    let onAdd: (LibraryStatus) -> Void
    let onAddToList: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            PosterView(url: hit.posterUrl.flatMap(URL.init(string:)), kind: kind)
                .frame(width: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(hit.title).font(.body.weight(.medium)).lineLimit(2)
                Text([kind.noun, hit.year.map(String.init), hit.byline].compactMap(\.self).joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(Color(.muted))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if isOnShelf {
                Label("On your shelf", systemImage: "checkmark")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.tint)
                    .accessibilityLabel("On your shelf")
            } else if isAdding {
                ProgressView()
            } else {
                AddMenu(kind: kind, onAdd: onAdd, onAddToList: onAddToList)
            }
        }
        .padding(.vertical, 4)
    }
}

/// The last row of an All search: books are searched on their own.
private struct SearchBooksRow: View {
    let query: String
    /// Nothing else matched, so the row says so first.
    let isFirst: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isFirst {
                Text("No films, shows or anime match.")
                    .font(.footnote)
                    .foregroundStyle(Color(.muted))
            }
            Button(action: action) {
                Label("Search Books for \u{201C}\(query)\u{201D}", systemImage: MediaKind.book.symbol)
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 6)
    }
}
