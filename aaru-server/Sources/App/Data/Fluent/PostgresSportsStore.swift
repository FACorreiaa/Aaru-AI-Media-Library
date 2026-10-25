import AaruCore
import FluentKit
import FluentSQL
import Foundation

struct PostgresSportsStore: SportsStore {
    let database: any Database

    private var sql: any SQLDatabase {
        get throws { try sqlDatabase(database) }
    }

    func follows(userID: UserID) async throws -> [SportFollow] {
        struct Row: Decodable {
            let kind: String
            let providerId: String
            let name: String
            let sport: String
            let badgeUrl: String?
            let country: String?
            let leagueId: String?
            let teamId: String?
            let teamName: String?
            let createdAt: Date
        }
        return try await sql.raw("""
        SELECT kind, provider_id, name, sport, badge_url, country, league_id, team_id, team_name, created_at
        FROM sport_follows WHERE user_id = \(bind: userID.rawValue)
        ORDER BY created_at, kind, provider_id
        """).all(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase).compactMap { row in
            guard let kind = SportEntityKind(rawValue: row.kind) else { return nil }
            return SportFollow(
                entity: SportEntity(
                    kind: kind, id: row.providerId, name: row.name, sport: row.sport,
                    badgeURL: row.badgeUrl.flatMap(URL.init(string:)), country: row.country, leagueID: row.leagueId,
                    teamID: row.teamId, teamName: row.teamName
                ),
                createdAt: row.createdAt
            )
        }
    }

    func follow(_ entity: SportEntity, userID: UserID, limit: Int, now: Date) async throws -> Bool {
        try await database.transaction { transaction in
            let sql = try sqlDatabase(transaction)
            // One writer per user at a time, so two follows racing at the limit cannot both pass.
            try await sql.raw("SELECT 1 FROM users WHERE id = \(bind: userID.rawValue) FOR UPDATE").run()
            struct Count: Decodable {
                let count: Int
                let existing: Int
            }
            let counts = try await sql.raw("""
            SELECT count(*)::int AS count,
                count(*) FILTER (WHERE kind = \(bind: entity.kind.rawValue)
                    AND provider_id = \(bind: entity.id))::int AS existing
            FROM sport_follows WHERE user_id = \(bind: userID.rawValue)
            """).first(decoding: Count.self)
            if let counts, counts.existing == 0, counts.count >= limit {
                return false
            }
            try await sql.raw("""
            INSERT INTO sport_follows (user_id, kind, provider_id, name, sport, badge_url, country, league_id,
                team_id, team_name, created_at)
            VALUES (\(bind: userID.rawValue), \(bind: entity.kind.rawValue), \(bind: entity.id),
                \(bind: String(entity.name.prefix(300))), \(bind: String(entity.sport.prefix(100))),
                \(bind: entity.badgeURL?.absoluteString), \(bind: entity.country.map { String($0.prefix(200)) }),
                \(bind: entity.leagueID), \(bind: entity.teamID),
                \(bind: entity.teamName.map { String($0.prefix(300)) }), \(bind: now))
            ON CONFLICT (user_id, kind, provider_id) DO UPDATE SET name = EXCLUDED.name, sport = EXCLUDED.sport,
                badge_url = EXCLUDED.badge_url, country = EXCLUDED.country, league_id = EXCLUDED.league_id,
                team_id = EXCLUDED.team_id, team_name = EXCLUDED.team_name
            """).run()
            return true
        }
    }

    func unfollow(kind: SportEntityKind, id: String, userID: UserID) async throws {
        try await sql.raw("""
        DELETE FROM sport_follows
        WHERE user_id = \(bind: userID.rawValue) AND kind = \(bind: kind.rawValue) AND provider_id = \(bind: id)
        """).run()
    }

    func watchCountry(userID: UserID) async throws -> String? {
        struct Row: Decodable {
            let watchCountryCode: String?
        }
        return try await sql.raw("""
        SELECT watch_country_code FROM sport_settings WHERE user_id = \(bind: userID.rawValue)
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)?.watchCountryCode
    }

    func saveWatchCountry(_ code: String?, userID: UserID, now: Date) async throws {
        try await sql.raw("""
        INSERT INTO sport_settings (user_id, watch_country_code, updated_at)
        VALUES (\(bind: userID.rawValue), \(bind: code), \(bind: now))
        ON CONFLICT (user_id) DO UPDATE SET watch_country_code = EXCLUDED.watch_country_code,
            updated_at = EXCLUDED.updated_at
        """).run()
    }
}
