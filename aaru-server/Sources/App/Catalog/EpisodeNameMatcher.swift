import AaruCore
import Foundation

/// An episode as a source names it: a season number when the source has one, and the episode's
/// title. Netflix's viewing activity and its player both give these, never TMDB's numbering.
struct NamedEpisode: Codable, Sendable, Equatable, Hashable {
    var season: Int?
    var name: String
}

/// IMP-018 and SCR-007: an episode named by a source → its key in the catalog's episode list.
/// Same season first; if the source's seasons differ from TMDB's (Netflix splits and merges
/// them), the one episode in the whole show with that name. Two with the name is no answer.
enum EpisodeNameMatcher {
    static func match(_ named: NamedEpisode, in episodes: [CatalogEpisode]) -> EpisodeKey? {
        let wanted = MatchKey.normalize(named.name)
        guard !wanted.isEmpty else { return nil }
        let matches = episodes.filter { episode in
            episode.name.map { MatchKey.normalize($0) == wanted } ?? false
        }
        if let season = named.season {
            let inSeason = matches.filter { $0.season == season }
            if inSeason.count == 1 {
                return try? EpisodeKey(season: inSeason[0].season, episode: inSeason[0].episode)
            }
        }
        // Specials (season 0) only match when the source said season 0.
        let regular = matches.filter { $0.season != 0 || named.season == 0 }
        guard regular.count == 1 else { return nil }
        return try? EpisodeKey(season: regular[0].season, episode: regular[0].episode)
    }
}
