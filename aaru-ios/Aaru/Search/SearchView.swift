import AaruAPI
import SwiftUI

/// What a search covers: everything on screen at once, or one kind. Books and music are never in
/// All (Open Library and MusicBrainz are slow and noisy), so All ends with rows that search them
/// instead.
enum SearchScope: String, CaseIterable, Identifiable {
    case all, film, show, anime, book, music

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

    /// The search field's hint: what the provider matches on.
    var prompt: String {
        kind?.searchPrompt ?? "Title"
    }
}

extension MediaKind {
    /// The search field's hint for one kind.
    var searchPrompt: String {
        switch self {
        case .book: "Title, author or ISBN"
        case .music: "Album or artist"
        case .film, .show, .anime: "Title"
        }
    }
}

extension CatalogHit {
    /// The line under a hit's name: "Show · 2022", "Book · 2016 · James Clear", or the artist and
    /// year for an album.
    func detailLine(kind: MediaKind) -> String {
        let year = year.map(String.init)
        let parts = kind == .music ? [byline, year] : [kind.noun, year, byline]
        return parts.compactMap(\.self).joined(separator: " · ")
    }
}

/// Pick mode (IMP-011): the search starts from a name the user did not type, and one tap chooses
/// a hit for something else (an unmatched import row) instead of adding it.
struct SearchPick {
    let query: String
    let scope: SearchScope
    /// Hits from this year come first: the catalog's search does not read a year.
    let year: Int?
    let navigationTitle: String
    /// Above the results: what is being matched.
    let note: String
    /// Answers a problem to show, or nil once the choice is saved and the sheet can close.
    let choose: @MainActor (CatalogHit) async -> String?
}

/// APP-004: catalog search, debounced, with add and an initial status. All by default (APP-011).
/// Given `intoList` (LST-003), each hit adds to that list instead of the library; given `pick`
/// (IMP-011), each hit is a choice.
struct SearchView: View {
    let api: Client?
    let library: LibraryModel
    let lists: ListsModel
    var intoList: Binding<ListDetail>?
    var pick: SearchPick?

    @Environment(\.dismiss) private var dismiss
    @State private var listTarget: CatalogHit?
    @State private var query: String
    @State private var scope: SearchScope
    @State private var hits: [CatalogHit] = []
    @State private var incomplete = false
    @State private var notice: String?
    @State private var isSearching = false
    @State private var problem: String?
    /// Hits being added right now: a second tap waits instead of adding twice.
    @State private var adding: Set<String> = []

    init(
        api: Client?,
        library: LibraryModel,
        lists: ListsModel,
        intoList: Binding<ListDetail>? = nil,
        pick: SearchPick? = nil
    ) {
        self.api = api
        self.library = library
        self.lists = lists
        self.intoList = intoList
        self.pick = pick
        _query = State(initialValue: pick?.query ?? "")
        _scope = State(initialValue: pick?.scope ?? .all)
    }

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

                if let pick {
                    Text(pick.note).font(.footnote).foregroundStyle(Color(.muted))
                        .listRowBackground(Color.clear)
                }
                if let problem {
                    Text(problem).font(.footnote).foregroundStyle(.red)
                        .listRowBackground(Color.clear)
                }
                if incomplete {
                    Text(notice ?? "Some results are missing right now.")
                        .font(.footnote)
                        .foregroundStyle(Color(.muted))
                        .listRowBackground(Color.clear)
                }
                ForEach(hits, id: \.self) { hit in
                    if let pick {
                        TapHitRow(
                            hit: hit,
                            kind: MediaKind(type: hit._type, isAnime: hit.isAnime),
                            action: "Choose",
                            isDone: false,
                            isAdding: adding.contains(hit.id)
                        ) {
                            Task { await choose(hit, for: pick) }
                        }
                        .disabled(!adding.isEmpty)
                        .listRowBackground(Color.clear)
                    } else if let intoList {
                        TapHitRow(
                            hit: hit,
                            kind: MediaKind(type: hit._type, isAnime: hit.isAnime),
                            action: "Add",
                            isDone: intoList.wrappedValue.contains(hit),
                            isAdding: adding.contains(hit.id)
                        ) {
                            Task { await add(hit, to: intoList) }
                        }
                        .listRowBackground(Color.clear)
                    } else {
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
                }
                if scope == .all, trimmedQuery.count >= 2, !isSearching || !hits.isEmpty {
                    SearchElsewhereRow(query: trimmedQuery, isFirst: hits.isEmpty) { scope = $0 }
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
            .navigationTitle(pick?.navigationTitle ?? intoList.map { "Add to \($0.wrappedValue.name)" } ?? "Search")
            .searchable(text: $query, prompt: scope.prompt)
            .task(id: SearchKey(query: query, scope: scope)) { await search() }
            .sheet(item: $listTarget) { hit in
                ListPickerSheet(
                    ref: .init(_type: hit._type, ids: hit.ids, title: hit.title, year: hit.year),
                    titleName: hit.title,
                    lists: lists
                )
            }
            .toolbar {
                if pick == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
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
                if let year = pick?.year {
                    // Stable: the catalog's order holds within each group.
                    hits = hits.filter { $0.year == year } + hits.filter { $0.year != year }
                }
                incomplete = results.incomplete
                notice = results.notice
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

    private func choose(_ hit: CatalogHit, for pick: SearchPick) async {
        guard adding.isEmpty else { return }
        adding.insert(hit.id)
        defer { adding.remove(hit.id) }
        if let failure = await pick.choose(hit) {
            problem = failure
        } else {
            dismiss()
        }
    }

    private func add(_ hit: CatalogHit, to list: Binding<ListDetail>) async {
        guard !adding.contains(hit.id) else { return }
        adding.insert(hit.id)
        defer { adding.remove(hit.id) }
        let ref = MediaRef(_type: hit._type, ids: hit.ids, title: hit.title, year: hit.year)
        if let updated = await lists.add(ref, to: list.wrappedValue.id) {
            list.wrappedValue = updated
        } else {
            problem = lists.problem ?? "\(hit.title) could not be added to \(list.wrappedValue.name)."
            lists.problem = nil
        }
    }
}

/// A hit one tap acts on: adds it to the list (list mode) or chooses it (pick mode).
private struct TapHitRow: View {
    let hit: CatalogHit
    let kind: MediaKind
    /// The button's word: "Add", "Choose".
    let action: String
    /// Already on the list: a check instead of the button.
    let isDone: Bool
    let isAdding: Bool
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            PosterView(url: hit.posterUrl.flatMap(URL.init(string:)), kind: kind)
                .frame(width: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(hit.title).font(.body.weight(.medium)).lineLimit(2)
                Text(hit.detailLine(kind: kind))
                    .font(.footnote)
                    .foregroundStyle(Color(.muted))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if isDone {
                Label("On this list", systemImage: "checkmark")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.tint)
                    .accessibilityLabel("On this list")
            } else if isAdding {
                ProgressView()
            } else {
                Button(action: onTap) {
                    Text(action)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .overlay(Capsule().strokeBorder(Color(.ink).opacity(0.25)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
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
                Text(hit.detailLine(kind: kind))
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

/// The last row of an All search: books and music are searched on their own.
private struct SearchElsewhereRow: View {
    let query: String
    /// Nothing else matched, so the row says so first.
    let isFirst: Bool
    let onSearch: (SearchScope) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isFirst {
                Text("No films, shows or anime match.")
                    .font(.footnote)
                    .foregroundStyle(Color(.muted))
            }
            ForEach([SearchScope.book, .music]) { scope in
                if let kind = scope.kind {
                    Button {
                        onSearch(scope)
                    } label: {
                        Label("Search \(kind.label) for \u{201C}\(query)\u{201D}", systemImage: kind.symbol)
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 6)
    }
}
