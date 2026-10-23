import AaruAPI
import Charts
import SwiftUI

// The profile's sections below the header (GAM-006b): time watched, the count tiles, where the
// time went, genres, most watched and where you watch, then favorites (FAV-001). Drawn at their
// final values, never grown.

// MARK: Time

/// "41 days, 6 hours" in the display serif, "990 hours · 4,812 episodes" under it.
struct ProfileTimeHero: View {
    let minutes: Int
    let episodes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Time watched").eyebrow()
            Text(ProfileModel.timeLabel(minutes: minutes))
                .font(.aaruDisplay(.largeTitle, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color(.ink))
            let totals = ProfileModel.totalsLine(minutes: minutes, episodes: episodes)
            if !totals.isEmpty {
                Text(totals)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Color(.muted))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// TV, anime and films as one stacked bar, with a legend that carries the hours.
struct ProfileTimeSplit: View {
    struct Part: Identifiable {
        let kind: MediaKind
        let minutes: Int
        var id: MediaKind {
            kind
        }

        var label: String {
            kind == .show ? "TV" : kind.label
        }

        var color: Color {
            switch kind {
            case .show: Color(.accent)
            case .anime: Color(.gold)
            default: Color(.medallion)
            }
        }
    }

    let parts: [Part]

    /// TV, anime, films, in that order, leaving out what has no time.
    static func parts(_ byKind: [Components.Schemas.StatsKind]) -> [Part] {
        [MediaKind.show, .anime, .film].compactMap { kind in
            let minutes = byKind.filter { MediaKind($0.kind) == kind }.map(\.minutes).reduce(0, +)
            return minutes > 0 ? Part(kind: kind, minutes: minutes) : nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Chart(parts) { part in
                BarMark(x: .value("Hours", Double(part.minutes) / 60), y: .value("Time", "All"))
                    .foregroundStyle(by: .value("Kind", part.label))
                    .accessibilityLabel(part.label)
                    .accessibilityValue(profileHours(minutes: part.minutes, long: true))
            }
            .chartForegroundStyleScale(domain: parts.map(\.label), range: parts.map(\.color))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .frame(height: 24)
            .clipShape(.rect(cornerRadius: AaruRadius.thumb, style: .continuous))
            HStack(spacing: 16) {
                ForEach(parts) { part in
                    HStack(spacing: 6) {
                        Circle().fill(part.color).frame(width: 8, height: 8)
                        Text(part.label).font(.subheadline.weight(.medium))
                        Text(profileHours(minutes: part.minutes))
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(Color(.muted))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// "120 h", or "45m" under an hour; spelled out for VoiceOver.
func profileHours(minutes: Int, long: Bool = false) -> String {
    if minutes < 60 {
        return long ? "\(minutes) minutes" : durationLabel(minutes: minutes)
    }
    return long ? "\(hoursValue(minutes: minutes)) hours" : "\(hoursValue(minutes: minutes)) h"
}

// MARK: Counts

/// Shows, anime, films, books: two by two, each opening Library filtered to its kind.
struct ProfileCountTiles: View {
    let stats: ProfileStats
    let onShowKind: (MediaKind) -> Void

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                tile(.show, stats.shows.finished, "show watched", "shows watched", watching(stats.shows))
                tile(.anime, stats.anime.finished, "anime watched", "anime watched", watching(stats.anime))
            }
            GridRow {
                tile(.film, stats.movies.finished, "film watched", "films watched", nil)
                tile(.book, stats.books.finished, "book read", "books read", booksDetail)
            }
        }
    }

    private func watching(_ counts: LibraryCounts) -> String? {
        counts.inProgress > 0 ? "\(counts.inProgress.formatted()) watching" : nil
    }

    private var booksDetail: String? {
        if stats.pagesRead > 0 {
            return "\(stats.pagesRead.formatted()) pages"
        }
        return stats.books.inProgress > 0 ? "\(stats.books.inProgress.formatted()) reading" : nil
    }

    private func tile(_ kind: MediaKind, _ count: Int, _ one: String, _ many: String, _ detail: String?)
        -> some View
    {
        Button { onShowKind(kind) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Image(systemName: kind.symbol)
                    .font(.subheadline)
                    .foregroundStyle(Color(.accent))
                    .padding(.bottom, 4)
                Text(count.formatted())
                    .font(.aaruDisplay(.title, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color(.ink))
                Text(count == 1 ? one : many)
                    .font(.footnote)
                    .foregroundStyle(Color(.ink))
                Text(detail ?? " ")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Color(.muted))
                    .accessibilityHidden(detail == nil)
            }
            .panel()
            .contentShape(.rect(cornerRadius: AaruRadius.panel, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(kind.label) in Library")
    }
}

// MARK: Genres, titles, networks

/// The top genres by time: name and title count, the hours trailing, a bar against the first.
struct ProfileGenreBars: View {
    let genres: [Components.Schemas.StatsGenre]

    var body: some View {
        let most = max(1, genres.map(\.minutes).max() ?? 1)
        VStack(spacing: AaruSpace.large) {
            ForEach(genres, id: \.name) { genre in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(genre.name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text(titles(genre.titles))
                            .font(.caption)
                            .foregroundStyle(Color(.muted))
                        Spacer(minLength: 8)
                        Text(profileHours(minutes: genre.minutes))
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(Color(.muted))
                    }
                    ShareBar(fraction: Double(genre.minutes) / Double(most))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(genre.name)
                .accessibilityValue("\(profileHours(minutes: genre.minutes, long: true)), \(titles(genre.titles))")
            }
        }
    }

    private func titles(_ count: Int) -> String {
        count == 1 ? "1 title" : "\(count.formatted()) titles"
    }
}

/// A thin track and its filled share, drawn at its final width.
private struct ShareBar: View {
    let fraction: Double

    var body: some View {
        Capsule()
            .fill(Color(.line))
            .frame(height: 6)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color(.accent))
                        .frame(width: max(6, proxy.size.width * min(1, fraction)))
                }
            }
    }
}

/// Up to three posters with their hours, each opening its title when it is on the shelf.
struct ProfileMostWatched: View {
    let titles: [StatsTitle]
    let library: LibraryModel

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(titles, id: \.title.id) { entry in
                if let id = library.entry(forTitle: entry.title.id)?.id {
                    NavigationLink(value: id) { cover(entry) }
                        .buttonStyle(.plain)
                } else {
                    cover(entry)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func cover(_ entry: StatsTitle) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PosterView(url: entry.title.posterURL, kind: entry.title.mediaKind)
            Text(entry.title.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(.ink))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(profileHours(minutes: entry.minutes))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(Color(.muted))
        }
        .frame(maxWidth: 132, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.title.title)
        .accessibilityValue(profileHours(minutes: entry.minutes, long: true))
    }
}

/// The networks and services the time went to, as chips: "Netflix 120 h".
struct ProfileNetworkChips: View {
    let networks: [Components.Schemas.StatsGenre]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(networks, id: \.name) { network in
                    HStack(spacing: 6) {
                        Text(network.name).font(.subheadline.weight(.medium))
                        Text(profileHours(minutes: network.minutes))
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(Color(.muted))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.surface), in: .capsule)
                    .overlay { Capsule().strokeBorder(Color(.line), lineWidth: 1) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(network.name)
                    .accessibilityValue(profileHours(minutes: network.minutes, long: true))
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: Favorites

/// FAV-001: a cover row per kind that has favorites, in order, and Edit to the editor. With none
/// yet, one line and the way to choose some.
struct ProfileFavorites: View {
    let model: FavoritesModel
    let library: LibraryModel

    var body: some View {
        let favorites = model.favorites ?? .empty
        VStack(alignment: .leading, spacing: AaruSpace.medium) {
            HStack(alignment: .firstTextBaseline) {
                Text("Favorites")
                    .font(.aaruDisplay(.title3, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: AaruSpace.small)
                NavigationLink("Edit") { FavoritesEditor(model: model) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(.accent))
                    .accessibilityHint("Opens your favorites")
            }
            if model.favorites != nil, favorites.filledKinds.isEmpty {
                Text("Pick up to 10 films, shows, anime, manga, books and albums.")
                    .font(.subheadline)
                    .foregroundStyle(Color(.muted))
            }
            ForEach(favorites.filledKinds) { kind in
                FavoriteCoverRow(title: kind.label, titles: favorites[kind], library: library)
            }
        }
    }
}

/// One kind's favorites as a sideways row of covers, each opening its title when it is on the
/// shelf. Most watched's look: cover, title, and a muted line.
private struct FavoriteCoverRow: View {
    let title: String
    let titles: [TitleSummary]
    let library: LibraryModel

    var body: some View {
        VStack(alignment: .leading, spacing: AaruSpace.small) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(.ink))
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: AaruSpace.large) {
                    ForEach(titles, id: \.id) { title in
                        if let id = library.entry(forTitle: title.id)?.id {
                            NavigationLink(value: id) { cover(title) }
                                .buttonStyle(.plain)
                        } else {
                            cover(title)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func cover(_ title: TitleSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PosterView(url: title.posterURL, kind: title.mediaKind)
            Text(title.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(.ink))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let line = favoriteLine(title) {
                Text(line)
                    .font(.caption2)
                    .foregroundStyle(Color(.muted))
                    .lineLimit(1)
            }
        }
        .frame(width: 104, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
