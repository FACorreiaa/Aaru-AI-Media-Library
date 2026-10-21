import AaruAPI
import SwiftUI

typealias ListItem = Components.Schemas.ListItem

/// One list member (LST-003): kind, year and network; for shows their status and next airing;
/// the library status and progress when the title is on the shelf.
struct ListItemRow: View {
    let item: ListItem

    private var kind: MediaKind {
        MediaKind(type: item.title._type, isAnime: item.title.isAnime)
    }

    var body: some View {
        HStack(spacing: 14) {
            PosterView(url: item.title.posterUrl.flatMap(URL.init(string:)), kind: kind)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title.title).font(.body.weight(.medium)).lineLimit(2)
                Text(metaLine)
                    .font(.footnote)
                    .foregroundStyle(Color(.muted))
                    .lineLimit(1)
                if item.showStatus != nil || item.nextAiring != nil {
                    HStack(spacing: 8) {
                        if let status = item.showStatus {
                            Text(status.label)
                                .font(.caption)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 1)
                                .overlay(Capsule().strokeBorder(Color(.ink).opacity(0.18)))
                        }
                        if let next = item.nextAiring {
                            TimelineView(.everyMinute) { context in
                                Text(EpisodeCode.short(season: next.season, number: next.number) + " · " + HomeModel.airingLabel(
                                    airsAt: next.airsAt, airTimeKnown: next.airTimeKnown, now: context.date,
                                    calendar: .aaru
                                ))
                            }
                            .font(.footnote)
                            .foregroundStyle(.tint)
                        }
                    }
                }
                if let entry = item.entry {
                    let row = LibraryRow(entry)
                    Text([row.status.label(for: row.kind), row.detail].compactMap(\.self).joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(Color(.muted))
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "2022 · Show · Apple TV+", or the artist and year for an album.
    private var metaLine: String {
        let year = item.title.year.map(String.init)
        let parts = kind == .music ? [item.title.byline, year] : [year, kind.noun, item.title.network]
        return parts.compactMap(\.self).joined(separator: " · ")
    }
}

extension ListDetail {
    /// "On this list" for a search hit: any provider id in common.
    func contains(_ hit: CatalogHit) -> Bool {
        let keys = hit.ids.keys
        return items.contains { !$0.title.ids.keys.isDisjoint(with: keys) }
    }
}
