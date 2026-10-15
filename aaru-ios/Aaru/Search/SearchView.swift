import AaruAPI
import SwiftUI

/// APP-004: type-scoped catalog search, debounced, with add and an initial status.
struct SearchView: View {
    let api: Client?
    let library: LibraryModel
    let lists: ListsModel

    @Environment(\.dismiss) private var dismiss
    @State private var listTarget: CatalogHit?
    @State private var query = ""
    @State private var kind = MediaKind.film
    @State private var hits: [CatalogHit] = []
    @State private var isSearching = false
    @State private var problem: String?
    /// Hits being added right now: a second tap waits instead of adding twice.
    @State private var adding: Set<String> = []

    private struct SearchKey: Equatable {
        let query: String
        let kind: MediaKind
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("Type", selection: $kind) {
                    ForEach(MediaKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if let problem {
                    Text(problem).font(.footnote).foregroundStyle(.red)
                        .listRowBackground(Color.clear)
                }
                ForEach(hits, id: \.self) { hit in
                    SearchHitRow(
                        hit: hit,
                        kind: MediaKind(type: hit._type, isAnime: hit.isAnime),
                        isOnShelf: library.contains(hit),
                        isAdding: adding.contains(key(hit))
                    ) { status in
                        Task { await add(hit, status: status) }
                    } onAddToList: {
                        listTarget = hit
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(.paper))
            .overlay {
                if hits.isEmpty, !isSearching, query.count >= 2, problem == nil {
                    ContentUnavailableView.search(text: query)
                } else if isSearching, hits.isEmpty {
                    ProgressView()
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: kind == .book ? "Title, author or ISBN" : "Title")
            .task(id: SearchKey(query: query, kind: kind)) { await search() }
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
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2, let api else {
            hits = []
            problem = nil
            return
        }
        // Debounce: a new keystroke cancels this task before the request goes out.
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            switch try await api.searchCatalog(query: .init(q: text, _type: kind.searchType)) {
            case let .ok(response):
                hits = try response.body.json.items
                problem = nil
            case let .default(_, error):
                hits = []
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
        let id = key(hit)
        guard let api, !adding.contains(id) else { return }
        adding.insert(id)
        defer { adding.remove(id) }
        let ref = Components.Schemas.MediaRef(_type: hit._type, ids: hit.ids, title: hit.title, year: hit.year)
        do {
            switch try await api.addLibraryItem(body: .json(.init(mediaRef: ref, status: status))) {
            case let .ok(response): try library.upsert(response.body.json)
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "\(hit.title) could not be added."
            }
        } catch {
            problem = "Aaru could not reach the server."
        }
    }

    private func key(_ hit: CatalogHit) -> String {
        hit.id
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
                Text([hit.year.map(String.init), hit.byline].compactMap(\.self).joined(separator: " · "))
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
                Menu {
                    ForEach([LibraryStatus.wishlist, .inProgress, .finished]) { status in
                        Button(status.label) { onAdd(status) }
                    }
                    Divider()
                    Button("Add to list…", systemImage: "text.badge.plus", action: onAddToList)
                } label: {
                    Text("Add")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .overlay(Capsule().strokeBorder(Color(.ink).opacity(0.25)))
                } primaryAction: {
                    onAdd(.wishlist)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .accessibilityHint("Adds to your wishlist. Hold for other statuses.")
            }
        }
        .padding(.vertical, 4)
    }
}
