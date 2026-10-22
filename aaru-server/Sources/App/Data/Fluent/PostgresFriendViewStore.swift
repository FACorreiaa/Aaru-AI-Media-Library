import AaruCore
import FluentKit
import FluentSQL
import Foundation

/// SOC-001 settings and SOC-003 reads. Activity is read from the library at query time; there is
/// no fan-out table (ARCHITECTURE.md §Social).
struct PostgresFriendViewStore: FriendViewStore {
    let sql: any SQLDatabase

    private struct ItemRow: Decodable {
        let titleId: UUID
        let status: String
        let rating: Double?
        let lastSeason: Int?
        let lastEpisode: Int?
        let bookPage: Int?
        let finishedAt: Date?
        let updatedAt: Date

        var item: FriendItem? {
            guard let status = LibraryStatus(rawValue: status) else { return nil }
            return FriendItem(
                titleID: TitleID(titleId), status: status, rating: rating, lastSeason: lastSeason,
                lastEpisode: lastEpisode, bookPage: bookPage, finishedAt: finishedAt, updatedAt: updatedAt
            )
        }
    }

    private struct TitleRow: Decodable { let titleId: UUID }

    private struct ActivityRow: Decodable {
        let userId: UUID
        let titleId: UUID
        let day: String
        let episodes: Int
        let lastSeason: Int?
        let lastEpisode: Int?
        let finished: Bool
        let rating: Double?
        let lastAt: Date
    }

    func socialSettings(_ id: UserID) async throws -> SocialSettings {
        struct Row: Decodable {
            let shareLibraryWithFriends: Bool
            let showAchievementsToFriends: Bool
            let leaderboardOptIn: Bool
        }
        guard let row = try await sql.raw("""
        SELECT share_library_with_friends, show_achievements_to_friends, leaderboard_opt_in
        FROM social_settings WHERE user_id = \(bind: id.rawValue)
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)
        else { return SocialSettings() }
        return SocialSettings(
            shareLibraryWithFriends: row.shareLibraryWithFriends,
            showAchievementsToFriends: row.showAchievementsToFriends, leaderboardOptIn: row.leaderboardOptIn
        )
    }

    func saveSocialSettings(_ settings: SocialSettings, for id: UserID) async throws {
        try await sql.raw("""
        INSERT INTO social_settings (user_id, share_library_with_friends, show_achievements_to_friends,
            leaderboard_opt_in)
        VALUES (\(bind: id.rawValue), \(bind: settings.shareLibraryWithFriends),
            \(bind: settings.showAchievementsToFriends), \(bind: settings.leaderboardOptIn))
        ON CONFLICT (user_id) DO UPDATE
        SET share_library_with_friends = EXCLUDED.share_library_with_friends,
            show_achievements_to_friends = EXCLUDED.show_achievements_to_friends,
            leaderboard_opt_in = EXCLUDED.leaderboard_opt_in, updated_at = now()
        """).run()
    }

    func friendsSince(_ first: UserID, _ second: UserID) async throws -> Date? {
        struct Row: Decodable { let createdAt: Date }
        return try await sql.raw("""
        SELECT created_at FROM social_friendships
        WHERE user_low = LEAST(\(bind: first.rawValue), \(bind: second.rawValue))
          AND user_high = GREATEST(\(bind: first.rawValue), \(bind: second.rawValue))
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)?.createdAt
    }

    func shelf(of owner: UserID, viewer: UserID, limit: Int) async throws -> FriendShelf {
        async let watching = items(owner, status: "in_progress", order: "li.updated_at DESC", limit: limit)
        async let finished = items(
            owner, status: "finished", order: "li.finished_at DESC NULLS LAST, li.updated_at DESC", limit: limit
        )
        async let counts = counts(owner)
        async let bothWant = titles("""
        SELECT a.title_id FROM library_items a
        JOIN library_items b ON b.title_id = a.title_id AND b.user_id = \(bind: viewer.rawValue)
            AND b.status = 'wishlist'
        WHERE a.user_id = \(bind: owner.rawValue) AND a.status = 'wishlist'
        ORDER BY a.updated_at DESC LIMIT \(bind: limit)
        """)
        async let theyLoved = titles("""
        SELECT a.title_id FROM library_items a
        WHERE a.user_id = \(bind: owner.rawValue) AND a.rating >= 8
          AND NOT EXISTS (
              SELECT 1 FROM library_items b WHERE b.user_id = \(bind: viewer.rawValue) AND b.title_id = a.title_id
          )
        ORDER BY a.rating DESC, a.finished_at DESC NULLS LAST LIMIT \(bind: limit)
        """)
        async let bothFinished = bothFinished(owner, viewer)
        return try await FriendShelf(
            watching: watching, finished: finished, counts: counts, bothWant: bothWant,
            bothFinished: bothFinished, theyLoved: theyLoved
        )
    }

    func activity(viewer: UserID, since: Date, before: Date, limit: Int) async throws -> [FriendActivity] {
        let rows = try await sql.raw("""
        WITH visible AS (
            SELECT f.id FROM (
                SELECT CASE WHEN user_low = \(bind: viewer.rawValue) THEN user_high ELSE user_low END AS id
                FROM social_friendships
                WHERE user_low = \(bind: viewer.rawValue) OR user_high = \(bind: viewer.rawValue)
            ) f
            LEFT JOIN social_settings s ON s.user_id = f.id
            WHERE coalesce(s.share_library_with_friends, true)
            -- Your own rows too, so you see what friends reacted to (SOC-007).
            UNION ALL SELECT \(bind: viewer.rawValue)
        ), events AS (
            SELECT li.user_id, li.title_id, ep.watched_at AS at, ep.season, ep.episode, false AS finished,
                li.rating
            FROM episode_progress ep JOIN library_items li ON li.id = ep.library_item_id
            WHERE li.user_id IN (SELECT id FROM visible) AND ep.watched_at_known
              AND ep.watched_at >= \(bind: since) AND ep.watched_at < \(bind: before)
            UNION ALL
            SELECT li.user_id, li.title_id, li.finished_at, NULL, NULL, true, li.rating
            FROM library_items li
            WHERE li.user_id IN (SELECT id FROM visible) AND li.status = 'finished'
              AND li.finished_at >= \(bind: since) AND li.finished_at < \(bind: before)
        )
        SELECT user_id, title_id, (at AT TIME ZONE 'UTC')::date::text AS day,
            (count(*) FILTER (WHERE NOT finished))::int AS episodes,
            (array_agg(season ORDER BY at DESC) FILTER (WHERE NOT finished))[1] AS last_season,
            (array_agg(episode ORDER BY at DESC) FILTER (WHERE NOT finished))[1] AS last_episode,
            bool_or(finished) AS finished, max(rating) AS rating, max(at) AS last_at
        FROM events
        GROUP BY user_id, title_id, (at AT TIME ZONE 'UTC')::date
        ORDER BY max(at) DESC
        LIMIT \(bind: limit)
        """).all(decoding: ActivityRow.self, keyDecodingStrategy: .convertFromSnakeCase)
        return rows.map {
            FriendActivity(
                friend: UserID($0.userId), titleID: TitleID($0.titleId), day: $0.day, episodes: $0.episodes,
                lastSeason: $0.lastSeason, lastEpisode: $0.lastEpisode, finished: $0.finished, rating: $0.rating,
                lastAt: $0.lastAt
            )
        }
    }

    // MARK: Parts of a shelf

    private func items(_ owner: UserID, status: String, order: String, limit: Int) async throws -> [FriendItem] {
        try await sql.raw("""
        SELECT li.title_id, li.status, li.rating, last.season AS last_season, last.episode AS last_episode,
            li.book_page, li.finished_at, li.updated_at
        FROM library_items li
        LEFT JOIN LATERAL (
            SELECT season, episode FROM episode_progress
            WHERE library_item_id = li.id ORDER BY season DESC, episode DESC LIMIT 1
        ) last ON true
        WHERE li.user_id = \(bind: owner.rawValue) AND li.status = \(bind: status)
        ORDER BY \(unsafeRaw: order)
        LIMIT \(bind: limit)
        """).all(decoding: ItemRow.self, keyDecodingStrategy: .convertFromSnakeCase).compactMap(\.item)
    }

    private func counts(_ owner: UserID) async throws -> [String: Int] {
        struct Row: Decodable {
            let kind: String
            let count: Int
        }
        let rows = try await sql.raw("""
        SELECT CASE WHEN t.is_anime THEN 'anime' ELSE t.type END AS kind, count(*)::int AS count
        FROM library_items li JOIN titles t ON t.id = li.title_id
        WHERE li.user_id = \(bind: owner.rawValue) AND li.status <> 'dropped'
        GROUP BY 1
        """).all(decoding: Row.self)
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.kind, $0.count) })
    }

    private func bothFinished(_ owner: UserID, _ viewer: UserID) async throws -> Int {
        struct Row: Decodable { let count: Int }
        return try await sql.raw("""
        SELECT count(*)::int AS count FROM library_items a
        JOIN library_items b ON b.title_id = a.title_id AND b.user_id = \(bind: viewer.rawValue)
            AND b.status = 'finished'
        WHERE a.user_id = \(bind: owner.rawValue) AND a.status = 'finished'
        """).first(decoding: Row.self)?.count ?? 0
    }

    private func titles(_ query: SQLQueryString) async throws -> [TitleID] {
        try await sql.raw(query).all(decoding: TitleRow.self, keyDecodingStrategy: .convertFromSnakeCase)
            .map { TitleID($0.titleId) }
    }
}
