import SwiftUI

/// The top of a kind page (NAV-002): the user's titles of that kind in progress, then planned,
/// each a short row with "See all" into Library filtered to the kind and status. Read from the
/// synced shelf, so it shows offline. An empty shelf says so quietly; the rows below lead.
struct KindShelf: View {
    let kind: MediaKind
    let library: LibraryModel
    let compact: Bool
    /// "See all": Library, filtered to this kind and the row's status.
    let onSeeAll: (LibraryStatus) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicType

    /// In progress first: what the user is in the middle of leads. Books also keep what is paused
    /// and what was read (BOOK-002).
    private var statuses: [LibraryStatus] {
        kind == .book ? [.inProgress, .wishlist, .onHold, .finished] : [.inProgress, .wishlist]
    }

    /// A short row; "See all" holds the rest.
    private static let rowLimit = 12

    private struct Shelf {
        let status: LibraryStatus
        let rows: [LibraryRow]
    }

    private var shelves: [Shelf] {
        statuses
            .map { Shelf(status: $0, rows: library.rows(kind: kind, status: $0)) }
            .filter { !$0.rows.isEmpty }
    }

    var body: some View {
        let shelves = shelves
        if shelves.isEmpty {
            // Before the first sync an empty shelf is not known to be empty.
            if library.hasSynced || !library.rows.isEmpty {
                Text(emptyText)
                    .font(.subheadline)
                    .foregroundStyle(Color(.muted))
                    .padding(.horizontal, 20)
            }
        } else {
            ForEach(shelves, id: \.status) { shelf in
                HomeRow(
                    title: shelf.status.label(for: kind),
                    trailing: (label: String(localized: "See all"), action: { onSeeAll(shelf.status) })
                ) {
                    ForEach(shelf.rows.prefix(Self.rowLimit)) { row in
                        NavigationLink(value: row.id) { LibraryPosterCard(row: row) }
                            .buttonStyle(.plain)
                            .posterHover()
                            .frame(width: HomeCardSize.poster.width(compact: compact, dynamicType: dynamicType))
                    }
                }
            }
        }
    }

    private var emptyText: String {
        switch kind {
        case .music: String(localized: "No albums on your shelf yet. Add one from the rows below, or search.")
        case .manga: String(localized: "No manga on your shelf yet. Add one from the rows below, or search.")
        default: String(localized: "No books on your shelf yet. Import a list above, or add one from the rows below.")
        }
    }
}

/// Music's views (NAV-002): its albums (shelf and rows), Concerts (MUS-003, while the server has
/// them on) and Listens (MUS-008).
enum MusicPane: String, CaseIterable, Identifiable {
    case albums, concerts, listens

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .albums: String(localized: "Albums")
        case .concerts: String(localized: "Concerts")
        case .listens: String(localized: "Listens")
        }
    }
}

extension MediaKind {
    /// The Discover row kind that holds this kind's titles (DISC-004).
    var discoverKind: DiscoverRowKind {
        switch self {
        case .film: .film
        case .show: .show
        case .anime: .anime
        case .manga: .manga
        case .book: .book
        case .music: .album
        }
    }
}
