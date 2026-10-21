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
    var backdropURL: URL?
    var network: String?
    /// First release (films) or first air date (shows), `YYYY-MM-DD`; nil when the provider
    /// gives no full date.
    var releaseDate: String?

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
    /// CAT-018: the provider's genre names, in its order. Empty for books.
    var genres: [String] = []
}

struct CatalogEpisode: Sendable, Equatable {
    var season: Int
    var episode: Int
    var name: String?
    var airsAt: Date?
    var runtimeMinutes: Int?
    var tmdbEpisodeID: String?
    /// True when `airsAt` is the exact broadcast time (AniList); false when the provider gives
    /// only a date (TMDB), stored as midnight UTC of that date.
    var airTimeKnown = false
    var overview: String?
    var stillURL: URL?
}

/// What a show's episode source returns: the show's status plus every known episode.
struct CatalogEpisodes: Sendable, Equatable {
    var status: TitleStatus?
    var episodes: [CatalogEpisode]
    /// The show's wide art and network as the episode source reports them now. Saved with the
    /// episodes, so titles added before these existed fill in on their next refresh.
    var backdropURL: URL?
    var network: String?
}

protocol CatalogSearching: Sendable {
    func search(query: String, type: MediaType) async throws -> [CatalogHit]
    /// The provider's record for these ids, or nil when it has none.
    func hydrate(ids: ExternalIDs, type: MediaType) async throws -> CatalogTitle?
}

/// Many anime by MyAnimeList id in few requests (IMP-017). AniList's `idMal_in`.
protocol MALBatchHydrating: Sendable {
    /// Keyed by MAL id; an id the provider does not know is missing.
    func hydrate(malIDs: [String]) async throws -> [String: CatalogTitle]
}

/// One query across films and shows at once (CAT-019's All scope). TMDB's `search/multi`.
protocol MultiSearching: Sendable {
    /// Films and shows, best first; people and adult titles are never returned.
    func searchMulti(query: String) async throws -> [CatalogHit]
}

protocol EpisodeListing: Sendable {
    /// Every episode the provider knows for a show it can identify from `ids`.
    func episodes(ids: ExternalIDs) async throws -> CatalogEpisodes?
}

/// The adapters, by role. Search scope `anime` goes to AniList; movie/show to TMDB;
/// book to Open Library; `all` to TMDB's multi search and AniList together.
struct CatalogProviders: Sendable {
    var tmdb: any CatalogSearching & EpisodeListing & MultiSearching
    var anilist: any CatalogSearching & EpisodeListing
    var openLibrary: any CatalogSearching
    /// Exact air times for TMDB's date-only episodes (TVmaze, CAT-011). Optional: without it the
    /// calendar shows dates.
    var airTimes: (any AirTimeRefining)?
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

/// A provider date string as `YYYY-MM-DD`, or nil when it is not a full date.
func catalogDate(_ string: String?) -> String? {
    guard let string, let match = string.prefixMatch(of: /\d{4}-\d{2}-\d{2}/) else { return nil }
    return String(match.output)
}

/// The leading four-digit year of a provider date string, if any.
func catalogYear(_ string: String?) -> Int? {
    guard let string, let match = string.firstMatch(of: /\d{4}/) else { return nil }
    return Int(match.output)
}
