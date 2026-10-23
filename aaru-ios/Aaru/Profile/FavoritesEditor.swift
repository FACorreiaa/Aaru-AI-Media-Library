import AaruAPI
import SwiftUI

/// FAV-001: one kind's top 10 at a time. Drag to reorder (Edit on iPhone), swipe to remove, Add
/// from the title picker scoped to the kind. Each change saves the whole kind; a reorder or
/// removal shows at once and goes back if the server says no.
struct FavoritesEditor: View {
    let model: FavoritesModel

    @State private var kind: FavoriteKind
    @State private var adding = false
    @Environment(\.dynamicTypeSize) private var typeSize

    init(model: FavoritesModel, kind: FavoriteKind = .film) {
        self.model = model
        _kind = State(initialValue: kind)
    }

    private var titles: [TitleSummary] {
        model.favorites?[kind] ?? []
    }

    var body: some View {
        @Bindable var model = model
        List {
            Section {
                FavoriteKindPicker(kind: $kind, compact: typeSize.isAccessibilitySize)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            Section {
                if model.favorites == nil {
                    ProgressView().frame(maxWidth: .infinity)
                } else if titles.isEmpty {
                    Text("No favorite \(kind.label.lowercased()) yet.")
                        .foregroundStyle(Color(.muted))
                }
                ForEach(Array(titles.enumerated()), id: \.element.id) { index, title in
                    FavoriteRow(rank: index + 1, title: title)
                        .contextMenu {
                            Button("Remove", systemImage: "minus.circle", role: .destructive) {
                                remove(IndexSet(integer: index))
                            }
                        }
                }
                .onDelete(perform: remove)
                .onMove(perform: move)
                Button("Add", systemImage: "plus") { adding = true }
                    .disabled(model.favorites == nil || titles.count >= FavoritesModel.limit)
            } footer: {
                Text("Up to \(FavoritesModel.limit). First is your favorite.")
            }
        }
        .settingsPage("Favorites", problem: $model.problem)
        .toolbar {
            #if os(iOS)
                ToolbarItem(placement: .primaryAction) { EditButton() }
            #endif
        }
        .sheet(isPresented: $adding) {
            TitlePickerSheet(api: model.api, navigationTitle: "Add to \(kind.label)", kind: kind.mediaKind) { hit in
                // The sheet closes either way, so a refusal shows here in the server's words.
                _ = await model.add(hit, to: kind)
                return true
            }
        }
        .task { await model.load() }
        .refreshable { await model.load() }
    }

    private func remove(_ offsets: IndexSet) {
        var next = titles
        next.remove(atOffsets: offsets)
        save(next)
    }

    private func move(_ source: IndexSet, _ destination: Int) {
        var next = titles
        next.move(fromOffsets: source, toOffset: destination)
        save(next)
    }

    private func save(_ next: [TitleSummary]) {
        let kind = kind
        Task { await model.reorder(kind, to: next) }
    }
}

/// Six kinds as a segmented control until the text is an accessibility size; then a menu.
private struct FavoriteKindPicker: View {
    @Binding var kind: FavoriteKind
    let compact: Bool

    var body: some View {
        if compact {
            Picker("Kind", selection: $kind) {
                ForEach(FavoriteKind.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)
        } else {
            Picker("Kind", selection: $kind) {
                ForEach(FavoriteKind.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}

/// "1", the cover, the title and its year or byline.
private struct FavoriteRow: View {
    let rank: Int
    let title: TitleSummary
    @ScaledMetric(relativeTo: .body) private var coverWidth: CGFloat = 40

    var body: some View {
        HStack(spacing: AaruSpace.medium) {
            Text("\(rank)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(rank == 1 ? Color(.accent) : Color(.muted))
                .frame(minWidth: 20, alignment: .trailing)
            PosterView(url: title.posterURL, kind: title.mediaKind)
                .frame(width: coverWidth)
            VStack(alignment: .leading, spacing: AaruSpace.xsmall) {
                Text(title.title).font(.body.weight(.medium)).lineLimit(2)
                if let line = favoriteLine(title) {
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(Color(.muted))
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// "2016 · James Clear"; an album leads with its artist.
func favoriteLine(_ title: TitleSummary) -> String? {
    let year = title.year.map(String.init)
    let parts = title._type == .album ? [title.byline, year] : [year, title.byline]
    let line = parts.compactMap(\.self).joined(separator: " · ")
    return line.isEmpty ? nil : line
}
