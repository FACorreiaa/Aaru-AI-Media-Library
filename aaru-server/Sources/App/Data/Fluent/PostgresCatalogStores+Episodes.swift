import AaruCore
import FluentSQL
import Foundation

/// A show's episodes as the provider reports them, upserted by number.
extension PostgresTitleStore {
    /// Rows per upsert: eleven binds a row, well under Postgres's 65,535.
    private static let episodeChunk = 500

    func saveEpisodes(_ id: TitleID, _ fresh: CatalogEpisodes, hydratedAt: Date) async throws {
        // One transaction, a few hundred episodes per statement: a long-running show is a handful
        // of round trips, and a reader never sees the title stamped hydrated over half its episodes.
        // One statement cannot upsert a row twice, so a provider's repeated episode keeps its last
        // copy, as the row-by-row upsert did.
        var seen = Set<[Int]>()
        let episodes = fresh.episodes.reversed().filter { seen.insert([$0.season, $0.episode]).inserted }.reversed()
            .map(\.self)
        try await sql.transaction { sql in
            for start in stride(from: 0, to: episodes.count, by: Self.episodeChunk) {
                let chunk = episodes[start ..< min(start + Self.episodeChunk, episodes.count)]
                let values = SQLList(chunk.map { episode in
                    SQLQueryString("""
                    (\(bind: UUID()), \(bind: id.rawValue), \(bind: episode.season), \(bind: episode.episode),
                     \(bind: episode.name), \(bind: episode.overview), \(bind: episode.airsAt),
                     \(bind: episode.airTimeKnown), \(bind: episode.runtimeMinutes), \(bind: episode.tmdbEpisodeID),
                     \(bind: episode.stillURL?.absoluteString))
                    """)
                })
                try await sql.raw("""
                INSERT INTO show_episodes
                    (id, title_id, season, episode, name, overview, airs_at, airs_at_exact, runtime_minutes,
                     tmdb_episode_id, still_url)
                VALUES \(values)
                ON CONFLICT (title_id, season, episode) DO UPDATE SET
                    name = EXCLUDED.name, overview = EXCLUDED.overview,
                    airs_at = EXCLUDED.airs_at, airs_at_exact = EXCLUDED.airs_at_exact,
                    runtime_minutes = EXCLUDED.runtime_minutes, tmdb_episode_id = EXCLUDED.tmdb_episode_id,
                    still_url = EXCLUDED.still_url
                """).run()
            }
            // A provider that drops its art does not erase ours.
            try await sql.raw("""
            UPDATE titles SET backdrop_url = coalesce(\(bind: fresh.backdropURL?.absoluteString), backdrop_url),
                network = coalesce(\(bind: fresh.network), network), episodes_hydrated_at = \(bind: hydratedAt),
                status = \(bind: fresh.status?.rawValue), updated_at = \(bind: hydratedAt)
            WHERE id = \(bind: id.rawValue)
            """).run()
        }
    }
}
