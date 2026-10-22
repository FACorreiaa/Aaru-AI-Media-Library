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
/// (IMP-011), each hit is a choice. A hit already in the library opens its item.
struct SearchView: View {
    let api: Client?
    let library: LibraryModel
    let lists: ListsModel
    var intoList: Binding<ListDetail>?
    var pick: SearchPick?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var model: SearchModel
    @State private var listTarget: CatalogHit?

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
        _model = State(initialValue: SearchModel(api: api, library: library, lists: lists, pick: pick))
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                scopePicker
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                if let pick {
                    Text(pick.note).font(.footnote).foregroundStyle(Color(.muted))
                        .listRowBackground(Color.clear)
                }
                if let problem = model.problem {
                    Text(problem).font(.footnote).foregroundStyle(Color(.danger))
                        .listRowBackground(Color.clear)
                }
                if model.incomplete {
                    Text(model.notice ?? "Some results are missing right now.")
                        .font(.footnote)
                        .foregroundStyle(Color(.muted))
                        .listRowBackground(Color.clear)
                }
                ForEach(model.hits, id: \.self) { hit in
                    row(hit).listRowBackground(Color.clear)
                }
                if model.scope == .all, model.trimmedQuery.count >= 2, !model.isSearching || !model.hits.isEmpty {
                    SearchElsewhereRow(query: model.trimmedQuery, isFirst: model.hits.isEmpty) { model.scope = $0 }
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(.paper))
            .overlay {
                if model.scope != .all, model.hits.isEmpty, !model.isSearching, model.trimmedQuery.count >= 2,
                   model.problem == nil
                {
                    ContentUnavailableView.search(text: model.query)
                } else if model.isSearching, model.hits.isEmpty {
                    ProgressView()
                }
            }
            .navigationTitle(pick?.navigationTitle ?? intoList.map { "Add to \($0.wrappedValue.name)" } ?? "Search")
            #if os(iOS)
                // Always showing: the sheet opens to type into, not to scroll first.
                .searchable(
                    text: $model.query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: model.scope.prompt
                )
            #else
                .searchable(text: $model.query, prompt: model.scope.prompt)
            #endif
                .task(id: model.key) { await model.search() }
                .navigationDestination(for: String.self) { id in
                    LibraryEntryDestination(id: id, api: api, library: library, lists: lists)
                }
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

    /// Six segments do not fit at the accessibility sizes; a menu does.
    @ViewBuilder private var scopePicker: some View {
        @Bindable var model = model
        let picker = Picker("Type", selection: $model.scope) {
            ForEach(SearchScope.allCases) { Text($0.label).tag($0) }
        }
        if dynamicType.isAccessibilitySize {
            picker.pickerStyle(.menu)
        } else {
            picker.pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private func row(_ hit: CatalogHit) -> some View {
        let kind = MediaKind(type: hit._type, isAnime: hit.isAnime)
        if let pick {
            TapHitRow(hit: hit, kind: kind, action: "Choose", isDone: false, isAdding: model.adding.contains(hit.id)) {
                Task {
                    if await model.choose(hit, for: pick) {
                        dismiss()
                    }
                }
            }
            .disabled(!model.adding.isEmpty)
        } else if let intoList {
            TapHitRow(
                hit: hit,
                kind: kind,
                action: "Add",
                isDone: intoList.wrappedValue.contains(hit),
                isAdding: model.adding.contains(hit.id)
            ) {
                Task {
                    if let updated = await model.add(hit, to: intoList.wrappedValue) {
                        intoList.wrappedValue = updated
                    }
                }
            }
        } else if let id = library.entry(matching: hit)?.id {
            // In the library already: the row opens the item (UX-073).
            NavigationLink(value: id) {
                SearchHitRow(hit: hit, kind: kind, isInLibrary: true, isAdding: false) { _ in } onAddToList: {}
            }
        } else {
            SearchHitRow(
                hit: hit,
                kind: kind,
                isInLibrary: false,
                isAdding: model.adding.contains(hit.id)
            ) { status in
                Task { await model.add(hit, status: status) }
            } onAddToList: {
                listTarget = hit
            }
        }
    }
}
