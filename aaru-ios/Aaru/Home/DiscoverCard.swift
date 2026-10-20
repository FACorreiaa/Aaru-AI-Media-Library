import AaruAPI
import SwiftUI

/// `DiscoverCard` (DISC-001): a poster from a public row. Not yet on the shelf, the poster is
/// an add menu (tap for the wishlist, hold for a status or a list); on the shelf, it opens the
/// item and wears a check.
struct DiscoverCard: View {
    let hit: CatalogHit
    /// The caller's item for this title, when they have it.
    let libraryItemID: String?
    let width: CGFloat
    let isAdding: Bool
    let onAdd: (LibraryStatus) -> Void
    let onAddToList: () -> Void

    var body: some View {
        Group {
            if let libraryItemID {
                NavigationLink(value: libraryItemID) { card }
                    .accessibilityLabel("\(hit.title), in your library")
            } else {
                Menu {
                    ForEach([LibraryStatus.wishlist, .inProgress, .finished]) { status in
                        Button(status.label) { onAdd(status) }
                    }
                    Divider()
                    Button("Add to list…", systemImage: "text.badge.plus", action: onAddToList)
                } label: {
                    card
                } primaryAction: {
                    onAdd(.wishlist)
                }
                .menuStyle(.button)
                .disabled(isAdding)
                .accessibilityLabel(hit.title)
                .accessibilityHint("Adds to your wishlist. Hold for other statuses.")
            }
        }
        .buttonStyle(.plain)
        .modifier(HoverLift())
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 6) {
            HomeArt(url: hit.posterUrl.flatMap(URL.init(string:)), aspect: 2 / 3)
                .overlay(alignment: .topTrailing) { badge.padding(6) }
                .overlay(alignment: .bottomLeading) {
                    if let kind = kindChip {
                        HomeChip(text: kind).padding(6)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 1) {
                Text(hit.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(Color(.muted))
                        .lineLimit(1)
                }
            }
        }
        .frame(width: width)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var badge: some View {
        if isAdding {
            ProgressView()
                .controlSize(.small)
                .padding(6)
                .background(.thinMaterial, in: Circle())
        } else {
            Image(systemName: libraryItemID == nil ? "plus" : "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(libraryItemID == nil ? Color(.ink) : .white)
                .frame(width: 26, height: 26)
                .background(
                    libraryItemID == nil ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(Color.accentColor),
                    in: Circle()
                )
                .accessibilityHidden(true)
        }
    }

    /// Rows mix kinds only for anime films; say "Film" there so a poster is not mistaken.
    private var kindChip: String? {
        hit.isAnime && hit._type == .movie ? "Film" : nil
    }

    /// "2026", or "2026 · James Clear" for a book.
    private var detail: String? {
        let parts = [hit.year.map(String.init), hit.byline].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// The empty-library header above Discover: what Home becomes once something is tracked.
struct HomeWelcome: View {
    let onSearch: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "sparkles.tv")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Add a show to see what's next")
                    .font(.subheadline.weight(.semibold))
                Text("Pick from the rows below or search. What you watch and what airs next land here.")
                    .font(.caption)
                    .foregroundStyle(Color(.muted))
            }
            Spacer(minLength: 8)
            Button("Search", action: onSearch)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(14)
        .background(Color(.medallion).opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }
}
