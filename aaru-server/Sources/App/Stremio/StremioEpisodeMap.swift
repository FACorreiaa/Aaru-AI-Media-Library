import AaruCore
import Foundation

/// Stremio names an episode by Cinemeta's numbers (`tt…:season:episode`, IMDb's seasons), and
/// TMDB can number the same episodes differently: Bleach: Thousand-Year Blood War is its own IMDb
/// series with seasons 1 to 4, while TMDB keeps it as season 2 of Bleach. Such an episode is found
/// on the TMDB show by the day Cinemeta says it came out (live test, 2026-10-22: Stremio's S3·E11
/// ticked nothing, because TMDB's Bleach has no season 3).
struct StremioEpisodeMap: Sendable {
    /// How far TMDB's air date may sit from Cinemeta's release day: time zones, a day-late upload.
    static let tolerance: TimeInterval = 36 * 60 * 60

    /// Cinemeta's episode list for an IMDb series.
    let videos: @Sendable (String) async throws -> [StremioWatched.Video]
    var cache = VideoCache()

    /// The episode of `title` that Stremio's `key` of IMDb series `imdb` is. `key` itself when the
    /// numbers can be trusted: the show is that IMDb series, or its IMDb id is unknown, and it has
    /// the episode. Nil when no episode matches, so nothing is ticked rather than a wrong one.
    func episode(
        _ key: EpisodeKey, imdb: String, title: Title, episodes: [CatalogEpisode]
    ) async -> EpisodeKey? {
        let sameSeries = title.ids.imdb == nil || title.ids.imdb == imdb
        if sameSeries, episodes.contains(where: { $0.season == key.season && $0.episode == key.episode }) {
            return key
        }
        guard let listed = await cache.videos(imdb, fetch: videos) else { return sameSeries ? key : nil }
        return Self.match(key, listed: listed, episodes: episodes) ?? (sameSeries ? key : nil)
    }

    /// The TMDB episode that aired when Cinemeta's `key` did. Two episodes out the same day pair up
    /// in order, and only when both lists have the same number of them that day.
    static func match(_ key: EpisodeKey, listed: [StremioWatched.Video], episodes: [CatalogEpisode]) -> EpisodeKey? {
        guard let released = listed.first(where: { $0.season == key.season && $0.episode == key.episode })?.released
        else { return nil }
        let sameDay = StremioWatched.ordered(listed.filter { video in
            video.season > 0 && video.released.map { abs($0.timeIntervalSince(released)) < 60 * 60 } == true
        })
        let aired = episodes
            .filter { episode in
                episode.season > 0
                    && episode.airsAt.map { abs($0.timeIntervalSince(released)) <= tolerance } == true
            }
            .sorted { ($0.season, $0.episode) < ($1.season, $1.episode) }
        guard let order = sameDay.firstIndex(where: { $0.season == key.season && $0.episode == key.episode }),
              aired.count == sameDay.count
        else { return nil }
        return try? EpisodeKey(season: aired[order].season, episode: aired[order].episode)
    }

    /// Cinemeta's lists for a few hours: a player reports each episode several times.
    actor VideoCache {
        static let lifetime: TimeInterval = 6 * 60 * 60
        static let capacity = 200

        private var entries: [String: (fetched: Date, videos: [StremioWatched.Video])] = [:]

        /// Nil when Cinemeta failed; an empty list when it does not know the series.
        func videos(
            _ imdb: String, fetch: @Sendable (String) async throws -> [StremioWatched.Video]
        ) async -> [StremioWatched.Video]? {
            if let entry = entries[imdb], Date().timeIntervalSince(entry.fetched) < Self.lifetime {
                return entry.videos
            }
            guard let fetched = try? await fetch(imdb) else { return nil }
            if entries.count >= Self.capacity {
                entries.removeAll()
            }
            entries[imdb] = (Date(), fetched)
            return fetched
        }
    }
}
