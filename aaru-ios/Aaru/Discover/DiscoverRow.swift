import AaruAPI
import SwiftUI

/// `DiscoverRow`: one Discover section as a row of poster cards, each with its kind, a release
/// badge, and either "On your shelf" or Add. Used on Discover and as Home's "New shows" teaser.
struct DiscoverRow: View {
    let title: String
    var trailing: (label: String, action: () -> Void)?
    let hits: [CatalogHit]
    let showsDates: Bool
    let api: Client?
    let library: LibraryModel
    let lists: ListsModel
    /// A failed add, for the screen's problem banner.
    var onProblem: (String) -> Void = { _ in }

    @State private var adding: Set<String> = []
    @State private var listTarget: CatalogHit?

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
        private var compact: Bool {
            sizeClass == .compact
        }
    #else
        private let compact = false
    #endif

    var body: some View {
        HomeRow(title: title, trailing: trailing) {
            ForEach(hits, id: \.self) { hit in
                DiscoverCard(
                    hit: hit,
                    badge: showsDates ? DiscoverModel.dateBadge(hit.releaseDate) : nil,
                    isOnShelf: library.contains(hit),
                    isAdding: adding.contains(hit.id),
                    width: HomeCardSize.poster.width(compact: compact)
                ) { status in
                    Task { await add(hit, status: status) }
                } onAddToList: {
                    listTarget = hit
                }
            }
        }
        .sheet(item: $listTarget) { hit in
            ListPickerSheet(
                ref: .init(_type: hit._type, ids: hit.ids, title: hit.title, year: hit.year),
                titleName: hit.title,
                lists: lists
            )
        }
    }

    private func add(_ hit: CatalogHit, status: LibraryStatus) async {
        guard !adding.contains(hit.id) else { return }
        adding.insert(hit.id)
        defer { adding.remove(hit.id) }
        if let failure = await library.add(hit, status: status, api: api) {
            onProblem(failure)
        }
    }
}

/// One catalog title on a Discover row.
private struct DiscoverCard: View {
    let hit: CatalogHit
    let badge: String?
    let isOnShelf: Bool
    let isAdding: Bool
    let width: CGFloat
    let onAdd: (LibraryStatus) -> Void
    let onAddToList: () -> Void

    private var kind: MediaKind {
        MediaKind(type: hit._type, isAnime: hit.isAnime)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PosterView(url: hit.posterUrl.flatMap(URL.init(string:)), kind: kind)
                .overlay(alignment: .topLeading) {
                    HomeChip(text: kind.noun).padding(6)
                }
                .overlay(alignment: .bottomLeading) {
                    if let badge {
                        HomeChip(text: badge, tint: Color.accentColor.opacity(0.9)).padding(6)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let byline = hit.byline ?? hit.year.map(String.init) {
                    Text(byline)
                        .font(.caption2)
                        .foregroundStyle(Color(.muted))
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            Group {
                if isOnShelf {
                    Label("On your shelf", systemImage: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                } else if isAdding {
                    ProgressView().controlSize(.small)
                } else {
                    AddMenu(kind: kind, onAdd: onAdd, onAddToList: onAddToList)
                }
            }
            .frame(minHeight: 30, alignment: .leading)
        }
        .frame(width: width, alignment: .topLeading)
    }
}
