import AaruCore
import Foundation

/// IMP-003: reads a user's Trakt library into import rows. Watched history (with every watched
/// episode), watchlist, ratings and lists; the plan-then-approve pipeline does the rest.
struct TraktImporter: Sendable {
    let api: TraktAPI

    func rows(token: String) async throws -> [ImportRow] {
        async let movies = api.get([TraktWatchedMovie].self, "sync/watched/movies", token: token)
        async let shows = api.get([TraktWatchedShow].self, "sync/watched/shows", token: token)
        async let watchlist = api.get([TraktItem].self, "sync/watchlist", token: token)
        async let ratings = api.get([TraktItem].self, "sync/ratings", token: token)
        async let lists = api.get([TraktList].self, "users/me/lists", token: token)

        var builder = Builder()
        for entry in try await movies {
            builder.add(entry.movie, type: .movie, status: .finished, finishedAt: Self.date(entry.lastWatchedAt))
        }
        for entry in try await shows {
            let watched = (entry.seasons ?? []).flatMap { season in
                season.episodes.compactMap { try? EpisodeKey(season: season.number, episode: $0.number) }
            }
            builder.add(entry.show, type: .show, status: .inProgress, watched: watched)
        }
        for item in try await watchlist {
            if let (media, type) = Self.media(item) {
                builder.add(media, type: type, status: .wishlist)
            }
        }
        for item in try await ratings {
            guard let (media, type) = Self.media(item), let rating = item.rating else { continue }
            builder.rate(media, type: type, rating: Double(rating))
        }
        for list in try await lists {
            let items = try await api.get([TraktItem].self, "users/me/lists/\(list.ids.trakt)/items", token: token)
            for item in items {
                if let (media, type) = Self.media(item) {
                    builder.list(media, type: type, name: list.name)
                }
            }
        }
        return builder.rows
    }

    /// Rows keyed by Trakt id, so a title that is watched, rated and on a list is one row.
    private struct Builder {
        var rows: [ImportRow] = []
        var index: [String: Int] = [:]

        private func key(_ media: TraktMedia, _ type: MediaType) -> String {
            "\(type.rawValue):\(media.ids.trakt.map(String.init) ?? media.ids.imdb ?? media.title ?? "")"
        }

        private mutating func row(_ media: TraktMedia, _ type: MediaType) -> Int {
            let key = key(media, type)
            if let existing = index[key] {
                return existing
            }
            rows.append(ImportRow(
                sourceKey: media.ids.trakt.map { "trakt:\($0)" }, type: type, title: media.title ?? "Untitled",
                year: media.year, ids: media.ids.externalIDs, status: nil, lists: [], listOnly: true
            ))
            index[key] = rows.count - 1
            return rows.count - 1
        }

        /// The first status wins: watched history comes first, then the watchlist.
        mutating func add(
            _ media: TraktMedia,
            type: MediaType,
            status: LibraryStatus,
            finishedAt: Date? = nil,
            watched: [EpisodeKey] = []
        ) {
            let slot = row(media, type)
            rows[slot].listOnly = nil
            if rows[slot].status == nil {
                rows[slot].status = status
            }
            if rows[slot].finishedAt == nil {
                rows[slot].finishedAt = finishedAt
            }
            if !watched.isEmpty {
                rows[slot].watched = watched
            }
        }

        /// A rating alone means the title was watched.
        mutating func rate(_ media: TraktMedia, type: MediaType, rating: Double) {
            let slot = row(media, type)
            rows[slot].rating = rating
            if rows[slot].listOnly == true {
                rows[slot].listOnly = nil
                rows[slot].status = .finished
            }
        }

        /// A title only on a list joins the list without joining the library.
        mutating func list(_ media: TraktMedia, type: MediaType, name: String) {
            let slot = row(media, type)
            if !rows[slot].lists.contains(name) {
                rows[slot].lists.append(name)
            }
        }
    }

    private static func media(_ item: TraktItem) -> (TraktMedia, MediaType)? {
        switch item.type {
        case "movie": item.movie.map { ($0, .movie) }
        case "show": item.show.map { ($0, .show) }
        default: nil
        }
    }

    private static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }
}
