import AaruCore
import FluentKit
import FluentSQL
import Foundation

/// GAM-006a activity reads: one query per period.
struct PostgresStatsStore: StatsStore {
    let sql: any SQLDatabase

    func activity(
        userID: UserID,
        from: LocalDay,
        until: LocalDay,
        timeZone: TimeZone
    ) async throws -> [StatsActivity] {
        let zone = timeZone.identifier
        // A finish at exactly 00:00 UTC is a date-only import (Letterboxd, Goodreads, MAL):
        // that day is the day, in every time zone.
        // The day filter below needs the zone, so it cannot use an index; these instants bound the
        // same days a day wider on each side (no zone is more than 14 hours off UTC), so the
        // episode ticks are read through `episode_progress_item_watched` for the period only.
        let lower: SQLQueryString = "(\(bind: from.description)::date - 1)::timestamp AT TIME ZONE 'UTC'"
        let upper: SQLQueryString = "(\(bind: until.description)::date + 1)::timestamp AT TIME ZONE 'UTC'"
        let query: SQLQueryString = """
        WITH activity AS (
            SELECT li.title_id, t.type, t.is_anime, t.genres, li.rating, ep.watched_at AS at,
                (ep.watched_at AT TIME ZONE \(bind: zone))::date AS day,
                1 AS episodes, coalesce(se.runtime_minutes, t.runtime_minutes, 0) AS minutes, false AS finished
            FROM episode_progress ep
            JOIN library_items li ON li.id = ep.library_item_id
            JOIN titles t ON t.id = li.title_id
            LEFT JOIN show_episodes se ON se.title_id = li.title_id
                AND se.season = ep.season AND se.episode = ep.episode
            WHERE li.user_id = \(bind: userID.rawValue) AND ep.watched_at_known AND ep.watched_at >= \(lower)
              AND ep.watched_at < \(upper)
            UNION ALL
            SELECT li.title_id, t.type, t.is_anime, t.genres, li.rating, li.finished_at AS at,
                CASE WHEN li.finished_at AT TIME ZONE 'UTC' = date_trunc('day', li.finished_at AT TIME ZONE 'UTC')
                    THEN (li.finished_at AT TIME ZONE 'UTC')::date
                    ELSE (li.finished_at AT TIME ZONE \(bind: zone))::date END AS day,
                0 AS episodes, CASE WHEN t.type = 'movie' THEN coalesce(t.runtime_minutes, 0) ELSE 0 END AS minutes,
                true AS finished
            FROM library_items li JOIN titles t ON t.id = li.title_id
            WHERE li.user_id = \(bind: userID.rawValue) AND li.status = 'finished' AND li.finished_at IS NOT NULL
              AND li.finished_at >= \(lower) AND li.finished_at < \(upper)
        )
        SELECT day::text AS day, title_id, type, is_anime, genres, rating,
            sum(episodes)::int AS episodes, sum(minutes)::int AS minutes, bool_or(finished) AS finished,
            min(at) AS first_at, max(at) AS last_at
        FROM activity
        WHERE day >= \(bind: from.description)::date AND day < \(bind: until.description)::date
        GROUP BY day, title_id, type, is_anime, genres, rating
        ORDER BY day, first_at
        """
        return try await sql.raw(query).all(decoding: ActivityRow.self, keyDecodingStrategy: .convertFromSnakeCase)
            .compactMap { row in
                guard let day = LocalDay(row.day), let type = MediaType(rawValue: row.type) else { return nil }
                return StatsActivity(
                    day: day, titleID: TitleID(row.titleId), type: type, isAnime: row.isAnime, rating: row.rating,
                    episodes: row.episodes, minutes: row.minutes, finished: row.finished,
                    firstAt: row.firstAt, lastAt: row.lastAt, genres: row.genres
                )
            }
    }
}

private struct ActivityRow: Decodable {
    let day: String
    let titleId: UUID
    let type: String
    let isAnime: Bool
    let genres: [String]
    let rating: Double?
    let episodes: Int
    let minutes: Int
    let finished: Bool
    let firstAt: Date
    let lastAt: Date
}
