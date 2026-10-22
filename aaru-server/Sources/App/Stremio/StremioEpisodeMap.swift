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

    /// Cinemeta's entry for an IMDb series.
    let series: @Sendable (String) async throws -> StremioSeries
    var cache = SeriesCache()

    /// TVDB's id for IMDb series `imdb`, which names the show Aaru tracks when TMDB lists the
    /// series as an entry of its own (TMDB `336301` for `tt14986406`, a near-empty duplicate).
    func tvdb(imdb: String) async -> String? {
        await cache.series(imdb, fetch: series)?.tvdb
    }

    /// The episode of `title` that Stremio's `key` of IMDb series `imdb` is. `key` itself when the
    /// numbers can be trusted: the show is that IMDb series, or its IMDb id is unknown, and it has
    /// the episode. Nil when no episode matches, so nothing is ticked rather than a wrong one.
    func episode(
        _ key: EpisodeKey, imdb: String, title: Title, episodes: [CatalogEpisode]
    ) async -> EpisodeKey? {
        if Self.trusted(key, imdb: imdb, title: title, episodes: episodes) {
            return key
        }
        let listed = await cache.series(imdb, fetch: series)?.videos
        return Self.place(key, imdb: imdb, title: title, episodes: episodes, listed: listed)
    }

    /// True when Stremio's number is the show's own: the show is that IMDb series (or its IMDb id
    /// is unknown) and has the episode.
    static func trusted(_ key: EpisodeKey, imdb: String, title: Title, episodes: [CatalogEpisode]) -> Bool {
        sameSeries(imdb, title) && episodes.contains { $0.season == key.season && $0.episode == key.episode }
    }

    /// `episode` without the fetch, for a caller that has Cinemeta's list (`listed`, nil when
    /// Cinemeta failed): the history import (IMP-016) and the addon share one rule.
    static func place(
        _ key: EpisodeKey, imdb: String, title: Title, episodes: [CatalogEpisode], listed: [StremioWatched.Video]?
    ) -> EpisodeKey? {
        if trusted(key, imdb: imdb, title: title, episodes: episodes) {
            return key
        }
        let fallback = sameSeries(imdb, title) ? key : nil
        guard let listed else { return fallback }
        return match(key, listed: listed, episodes: episodes) ?? fallback
    }

    private static func sameSeries(_ imdb: String, _ title: Title) -> Bool {
        title.ids.imdb == nil || title.ids.imdb == imdb
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

    /// Cinemeta's entries for a few hours: a player reports each episode several times.
    actor SeriesCache {
        static let lifetime: TimeInterval = 6 * 60 * 60
        static let capacity = 200

        private var entries: [String: (fetched: Date, series: StremioSeries)] = [:]

        /// Nil when Cinemeta failed; an empty entry when it does not know the series.
        func series(
            _ imdb: String, fetch: @Sendable (String) async throws -> StremioSeries
        ) async -> StremioSeries? {
            if let entry = entries[imdb], Date().timeIntervalSince(entry.fetched) < Self.lifetime {
                return entry.series
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
