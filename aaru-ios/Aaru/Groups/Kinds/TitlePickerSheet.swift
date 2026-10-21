import AaruAPI
import SwiftUI

/// A catalog search that picks one title, for title channels, shelves and watch parties. The
/// same search as Add; picking never touches the library.
struct TitlePickerSheet: View {
    let api: Client?
    let navigationTitle: String
    /// True when the pick was used; the sheet then closes.
    let onPick: (CatalogHit) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var kind = MediaKind.show
    @State private var hits: [CatalogHit] = []
    @State private var isSearching = false
    @State private var picking: String?
    @State private var problem: String?

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
                    Text(problem).font(.footnote).foregroundStyle(.red).listRowBackground(Color.clear)
                }
                ForEach(hits, id: \.self) { hit in
                    Button {
                        pick(hit)
                    } label: {
                        HStack(spacing: 14) {
                            PosterView(
                                url: hit.posterUrl.flatMap(URL.init(string:)),
                                kind: MediaKind(type: hit._type, isAnime: hit.isAnime)
                            )
                            .frame(width: 44)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(hit.title).font(.body.weight(.medium)).lineLimit(2)
                                Text([hit.year.map(String.init), hit.byline].compactMap(\.self)
                                    .joined(separator: " · "))
                                    .font(.footnote)
                                    .foregroundStyle(Color(.muted))
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            if picking == hit.id {
                                ProgressView()
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(picking != nil)
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
            .navigationTitle(navigationTitle)
            .searchable(text: $query, prompt: kind == .book ? "Title, author or ISBN" : "Title")
            .task(id: SearchKey(query: query, kind: kind)) { await search() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func pick(_ hit: CatalogHit) {
        Task {
            picking = hit.id
            defer { picking = nil }
            if await onPick(hit) {
                dismiss()
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
}

extension CatalogHit {
    /// The reference the server resolves to an Aaru title.
    var mediaRef: Components.Schemas.MediaRef {
        .init(_type: _type, ids: ids, title: title, year: year)
    }
}

extension Components.Schemas.TitleSummary {
    /// The reference that names this exact Aaru title.
    var mediaRef: Components.Schemas.MediaRef {
        .init(titleId: id, _type: _type)
    }
}
