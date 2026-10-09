import AaruCore
import Foundation

/// One search result: a catalog projection, never a library row.
struct CatalogHit: Sendable, Equatable {
    var type: MediaType
    var title: String
    var originalTitle: String?
    var year: Int?
    var posterURL: URL?
    var overview: String?
    /// Authors for books; empty otherwise.
    var byline: String?
    var ids: ExternalIDs
    var isAnime: Bool

    var mediaRef: MediaRef {
        MediaRef(type: type, ids: ids, title: title, year: year)
    }
}

/// Lifecycle of a show as its catalog reports it. Drives PROG-003's auto-finish and
/// the hydration staleness window.
enum TitleStatus: String, Sendable {
    case upcoming
    case returning
    case ended
    case canceled
}

/// A full catalog record, ready to become a `titles` row.
struct CatalogTitle: Sendable, Equatable {
    var hit: CatalogHit
    var status: TitleStatus?
    var runtimeMinutes: Int?
}

struct CatalogEpisode: Sendable, Equatable {
    var season: Int
    var episode: Int
    var name: String?
    var airsAt: Date?
    var runtimeMinutes: Int?
    var tmdbEpisodeID: String?
}

/// What a show's episode source returns: the show's status plus every known episode.
struct CatalogEpisodes: Sendable, Equatable {
    var status: TitleStatus?
    var episodes: [CatalogEpisode]
}

protocol CatalogSearching: Sendable {
    func search(query: String, type: MediaType) async throws -> [CatalogHit]
    /// The provider's record for these ids, or nil when it has none.
    func hydrate(ids: ExternalIDs, type: MediaType) async throws -> CatalogTitle?
}

protocol EpisodeListing: Sendable {
    /// Every episode the provider knows for a show it can identify from `ids`.
    func episodes(ids: ExternalIDs) async throws -> CatalogEpisodes?
}

/// The adapters, by role. Search scope `anime` goes to AniList; movie/show to TMDB;
/// book to Open Library.
struct CatalogProviders: Sendable {
    var tmdb: any CatalogSearching & EpisodeListing
    var anilist: any CatalogSearching & EpisodeListing
    var openLibrary: any CatalogSearching
}

extension Date {
    /// "2025-03-14" → that day at 00:00 UTC. Providers give dates, not instants.
    static func catalogDay(_ string: String?) -> Date? {
        guard let string, string.count >= 10 else { return nil }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(identifier: "UTC")
        let parts = string.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return components.date
    }
}

/// The leading four-digit year of a provider date string, if any.
func catalogYear(_ string: String?) -> Int? {
    guard let string, let match = string.firstMatch(of: /\d{4}/) else { return nil }
    return Int(match.output)
}
