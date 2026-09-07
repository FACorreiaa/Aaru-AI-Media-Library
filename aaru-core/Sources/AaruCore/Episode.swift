import Foundation

/// A season/episode coordinate.
///
/// This is the identity used for progress. Provider episode ids are stored on
/// `Episode`, never used as the progress key — a user can tick an episode Aaru
/// has not hydrated yet.
public struct EpisodeKey: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let season: Int
    public let episode: Int

    public init(season: Int, episode: Int) throws {
        guard season >= 0, episode >= 1 else {
            throw ValidationError.invalidEpisodeNumber(season: season, episode: episode)
        }
        self.season = season
        self.episode = episode
    }

    public static func < (lhs: EpisodeKey, rhs: EpisodeKey) -> Bool {
        (lhs.season, lhs.episode) < (rhs.season, rhs.episode)
    }

    /// `S01E02`. Stable enough to log and to show in a UI.
    public var description: String {
        String(format: "S%02dE%02d", season, episode)
    }
}

extension EpisodeKey: Codable {
    private enum CodingKeys: String, CodingKey {
        case season, episode
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let season = try container.decode(Int.self, forKey: .season)
        let episode = try container.decode(Int.self, forKey: .episode)
        do {
            try self.init(season: season, episode: episode)
        } catch let error as ValidationError {
            throw DecodingError.dataCorruptedError(
                forKey: .episode,
                in: container,
                debugDescription: error.description
            )
        }
    }
}

/// One episode of a show, as the catalog describes it.
public struct Episode: Codable, Hashable, Sendable, Identifiable {
    public var key: EpisodeKey
    public var name: String?
    public var airDate: Date?
    /// TMDB episode id, when hydration supplied one.
    public var tmdbID: String?

    public var id: EpisodeKey { key }
    public var season: Int { key.season }
    public var number: Int { key.episode }

    public init(key: EpisodeKey, name: String? = nil, airDate: Date? = nil, tmdbID: String? = nil) {
        self.key = key
        self.name = name
        self.airDate = airDate
        self.tmdbID = tmdbID
    }
}

/// One season of a show.
public struct Season: Codable, Hashable, Sendable, Identifiable {
    public var number: Int
    public var name: String?
    public var episodes: [Episode]

    public var id: Int { number }

    public init(number: Int, name: String? = nil, episodes: [Episode] = []) {
        self.number = number
        self.name = name
        self.episodes = episodes
    }
}
