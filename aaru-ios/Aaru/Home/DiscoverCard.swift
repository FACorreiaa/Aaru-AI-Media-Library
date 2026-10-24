import AaruAPI
import SwiftUI

/// `DiscoverCard` (DISC-001): a poster from a public row, on Home and on Discover. Not yet on
/// the shelf, a tap opens its preview (`CatalogPreviewSheet`) and a hold is the add menu (a
/// status or a list); on the shelf, it opens the item and wears a check. A release date shows as
/// a badge.
struct DiscoverCard: View {
    let hit: CatalogHit
    /// The caller's item for this title, when they have it.
    let libraryItemID: String?
    /// "Tomorrow", "Nov 14", "Out now": see `releaseBadge`.
    var badge: String?
    /// Lines under the title in place of the year, e.g. On air's next episode (DISC-003).
    var lines: [String]?
    /// A row's fixed card width; nil fills a grid cell (the Seasons view).
    let width: CGFloat?
    let isAdding: Bool
    let onAdd: (LibraryStatus) -> Void
    let onAddToList: () -> Void

    @State private var previewing = false
    /// "Add to list…" in the preview: the picker opens once the preview is gone.
    @State private var listAfterPreview = false

    private var kind: MediaKind {
        MediaKind(type: hit._type, isAnime: hit.isAnime)
    }

    var body: some View {
        Group {
            if let libraryItemID {
                NavigationLink(value: libraryItemID) { card }
                    .accessibilityLabel("\(hit.title), in your library")
            } else {
                Menu {
                    ForEach([LibraryStatus.wishlist, .inProgress, .finished]) { status in
                        Button(status.label(for: kind)) { onAdd(status) }
                    }
                    Divider()
                    Button("Add to list…", systemImage: "text.badge.plus", action: onAddToList)
                } label: {
                    card
                } primaryAction: {
                    previewing = true
                }
                .menuStyle(.button)
                .disabled(isAdding)
                .accessibilityLabel(hit.title)
                .accessibilityHint("Shows details. Hold to add.")
            }
        }
        .buttonStyle(.plain)
        .modifier(HoverLift())
        .sheet(isPresented: $previewing, onDismiss: previewDismissed) {
            CatalogPreviewSheet(
                hit: hit, libraryItemID: libraryItemID, isAdding: isAdding, onAdd: onAdd,
                onAddToList: { listAfterPreview = true }
            )
        }
    }

    private func previewDismissed() {
        guard listAfterPreview else { return }
        listAfterPreview = false
        onAddToList()
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 6) {
            HomeArt(url: hit.posterUrl.flatMap(URL.init(string:)), aspect: kind.posterAspect)
                .overlay(alignment: .topTrailing) { shelfMark.padding(6) }
                .overlay(alignment: .topLeading) {
                    if let badge {
                        HomeChip(text: badge, tint: Color(.accent).opacity(0.9)).padding(6)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if let kind = kindChip {
                        HomeChip(text: kind).padding(6)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: AaruRadius.field, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(hit.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                ForEach(lines ?? [detail].compactMap(\.self), id: \.self) { line in
                    Text(line)
                        .font(.caption2)
                        .foregroundStyle(Color(.muted))
                        .lineLimit(1)
                }
            }
        }
        .frame(width: width)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var shelfMark: some View {
        if isAdding {
            ProgressView()
                .controlSize(.small)
                .padding(6)
                .background(.thinMaterial, in: Circle())
        } else {
            Image(systemName: libraryItemID == nil ? "plus" : "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(libraryItemID == nil ? Color(.ink) : Color(.onAccent))
                .frame(width: 26, height: 26)
                .background(
                    libraryItemID == nil ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(Color(.accent)),
                    in: Circle()
                )
                .accessibilityHidden(true)
        }
    }

    /// Rows mix kinds only for anime films; say "Film" there so a poster is not mistaken. An
    /// album wears its year here instead, with the artist under the name, unless a release date
    /// already says when (Coming soon, MUS-002).
    private var kindChip: String? {
        if kind == .music {
            return badge == nil ? hit.year.map(String.init) : nil
        }
        return hit.isAnime && hit._type == .movie ? "Film" : nil
    }

    /// "2026", "2026 · James Clear" for a book, or the artist for an album.
    private var detail: String? {
        let parts = kind == .music ? [hit.byline] : [hit.year.map(String.init), hit.byline]
        let present = parts.compactMap(\.self)
        return present.isEmpty ? nil : present.joined(separator: " · ")
    }

    /// The row whose past release dates read "Out now"; elsewhere a past date shows nothing.
    nonisolated static let inTheatersRow = "movies_in_theaters"

    /// "Today", "Tomorrow", "In 3 days", "Nov 14" from a `YYYY-MM-DD` release date, and
    /// "Out now" for a past one in theaters. Nil when there is no date or it cannot be read.
    static func releaseBadge(
        _ releaseDate: String?, row: String, now: Date = .now, calendar: Calendar = .current
    ) -> String? {
        let parts = releaseDate?.split(separator: "-").compactMap { Int($0) } ?? []
        guard parts.count == 3,
              let day = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: day).day ?? 0
        switch days {
        case ..<0: return row == inTheatersRow ? "Out now" : nil
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 2 ... 6: return "In \(days) days"
        default:
            let sameYear = calendar.component(.year, from: now) == parts[0]
            return day.formatted(sameYear ? .dateTime.month(.abbreviated).day() : .dateTime.month(.abbreviated).year())
        }
    }
}

/// The empty-library header above Discover: what Home becomes once something is tracked. The
/// same headline as Home's empty state (UX-075), with the two ways in: search, or an import.
struct HomeWelcome: View {
    let onSearch: () -> Void
    let onImport: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: AaruSpace.medium) {
                symbol
                copy
                Spacer(minLength: 8)
                actions
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: AaruSpace.medium) {
                    symbol
                    copy
                }
                actions
            }
        }
        .padding(AaruSpace.large)
        .background(
            Color(.medallion).opacity(AaruAlpha.ghost),
            in: RoundedRectangle(cornerRadius: AaruRadius.panel, style: .continuous)
        )
        .accessibilityElement(children: .contain)
    }

    private var symbol: some View {
        Image(systemName: "sparkles.tv")
            .font(.title2)
            .foregroundStyle(Color(.accent))
            .accessibilityHidden(true)
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(HomeEmptyCopy.headline)
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text("Pick from the rows below, search, or bring your history from another app.")
                .font(.caption)
                .foregroundStyle(Color(.muted))
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button("Search", action: onSearch)
                .buttonStyle(.borderedProminent)
            Button(HomeEmptyCopy.importAction, action: onImport)
                .buttonStyle(.bordered)
        }
    }
}

/// Home's one empty headline and import action, shared by the empty state and the welcome card.
enum HomeEmptyCopy {
    static let headline = "Add something to see what's next"
    static let importAction = "Bring your history"
}
