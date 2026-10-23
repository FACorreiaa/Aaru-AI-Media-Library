import AaruAPI
import SwiftUI

/// A catalog search that picks one title, for title channels, shelves and watch parties. The
/// same search as Add; picking never touches the library.
struct TitlePickerSheet: View {
    let navigationTitle: String
    /// True when the pick was used; the sheet then closes.
    let onPick: (CatalogHit) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var model: TitlePickerModel
    @State private var query = ""
    @State private var kind = MediaKind.show
    @State private var picking: String?

    init(api: Client?, navigationTitle: String, onPick: @escaping (CatalogHit) async -> Bool) {
        self.navigationTitle = navigationTitle
        self.onPick = onPick
        _model = State(initialValue: TitlePickerModel(api: api))
    }

    private struct SearchKey: Equatable {
        let query: String
        let kind: MediaKind
    }

    var body: some View {
        NavigationStack {
            List {
                KindPicker(kind: $kind, compact: typeSize.isAccessibilitySize)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                if let problem = model.problem {
                    Text(problem).font(.footnote).foregroundStyle(Color(.danger)).listRowBackground(Color.clear)
                }
                ForEach(model.hits, id: \.self) { hit in
                    Button {
                        pick(hit)
                    } label: {
                        HStack(spacing: AaruSpace.medium) {
                            PosterView(
                                url: hit.posterUrl.flatMap(URL.init(string:)),
                                kind: MediaKind(type: hit._type, isAnime: hit.isAnime)
                            )
                            .frame(width: 44)
                            VStack(alignment: .leading, spacing: AaruSpace.xsmall) {
                                Text(hit.title).font(.body.weight(.medium)).lineLimit(2)
                                Text(pickerLine(hit))
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
                if model.hits.isEmpty, !model.isSearching, query.count >= 2, model.problem == nil {
                    ContentUnavailableView.search(text: query)
                } else if model.isSearching, model.hits.isEmpty {
                    ProgressView()
                }
            }
            .navigationTitle(navigationTitle)
            .searchable(text: $query, prompt: kind.searchPrompt)
            .task(id: SearchKey(query: query, kind: kind)) { await model.search(query, kind: kind) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    /// "2016 · James Clear"; an album leads with its artist, as everywhere else.
    private func pickerLine(_ hit: CatalogHit) -> String {
        let year = hit.year.map(String.init)
        let parts = hit._type == .album ? [hit.byline, year] : [year, hit.byline]
        return parts.compactMap(\.self).joined(separator: " · ")
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
}

/// Five kinds fit a segmented control until the text is an accessibility size; then a menu.
private struct KindPicker: View {
    @Binding var kind: MediaKind
    let compact: Bool

    var body: some View {
        if compact {
            Picker("Type", selection: $kind) {
                ForEach(MediaKind.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)
        } else {
            Picker("Type", selection: $kind) {
                ForEach(MediaKind.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
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
