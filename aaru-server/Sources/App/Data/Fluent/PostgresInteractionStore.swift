import AaruCore
import FluentKit
import FluentSQL
import Foundation

/// SOC-007 reactions and SOC-006 recommendations.
struct PostgresInteractionStore: InteractionStore {
    let sql: any SQLDatabase

    func reactions(on rows: [ActivityKey], viewer: UserID) async throws -> [ActivityKey: ReactionSummary] {
        guard !rows.isEmpty else { return [:] }
        struct Row: Decodable {
            let ownerId: UUID
            let titleId: UUID
            let day: String
            let emoji: String
            let count: Int
            let mine: Bool
        }
        let owners = rows.map(\.owner.rawValue)
        let titles = rows.map(\.titleID.rawValue)
        let days = rows.map(\.day)
        let found = try await sql.raw("""
        SELECT r.owner_id, r.title_id, r.day::text AS day, r.emoji, count(*)::int AS count,
            bool_or(r.user_id = \(bind: viewer.rawValue)) AS mine
        FROM social_reactions r
        JOIN unnest(\(bind: owners)::uuid[], \(bind: titles)::uuid[], \(bind: days)::date[])
            AS k(owner_id, title_id, day)
            ON k.owner_id = r.owner_id AND k.title_id = r.title_id AND k.day = r.day
        GROUP BY r.owner_id, r.title_id, r.day, r.emoji
        """).all(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)
        var summaries: [ActivityKey: ReactionSummary] = [:]
        for row in found {
            let key = ActivityKey(owner: UserID(row.ownerId), titleID: TitleID(row.titleId), day: row.day)
            summaries[key, default: ReactionSummary()].counts[row.emoji] = row.count
            if row.mine {
                summaries[key]?.mine = row.emoji
            }
        }
        return summaries
    }

    func react(_ emoji: String?, on row: ActivityKey, by user: UserID, now: Date) async throws {
        guard let emoji else {
            try await sql.raw("""
            DELETE FROM social_reactions
            WHERE user_id = \(bind: user.rawValue) AND owner_id = \(bind: row.owner.rawValue)
              AND title_id = \(bind: row.titleID.rawValue) AND day = \(bind: row.day)::date
            """).run()
            return
        }
        try await sql.raw("""
        INSERT INTO social_reactions (user_id, owner_id, title_id, day, emoji, created_at)
        VALUES (\(bind: user.rawValue), \(bind: row.owner.rawValue), \(bind: row.titleID.rawValue),
                \(bind: row.day)::date, \(bind: emoji), \(bind: now))
        ON CONFLICT (user_id, owner_id, title_id, day)
        DO UPDATE SET emoji = EXCLUDED.emoji, created_at = EXCLUDED.created_at
        """).run()
    }

    func hasTitle(_ owner: UserID, _ titleID: TitleID) async throws -> Bool {
        struct Row: Decodable { let found: Bool }
        return try await sql.raw("""
        SELECT EXISTS (
            SELECT 1 FROM library_items WHERE user_id = \(bind: owner.rawValue) AND title_id = \(bind: titleID.rawValue)
        ) AS found
        """).first(decoding: Row.self)?.found ?? false
    }

    func recommend(_ recommendations: [Recommendation]) async throws {
        for item in recommendations {
            try await sql.raw("""
            INSERT INTO social_recommendations (id, from_user_id, to_user_id, title_id, note, created_at)
            VALUES (\(bind: item.id), \(bind: item.sender.rawValue), \(bind: item.recipient.rawValue),
                    \(bind: item.titleID.rawValue), \(bind: item.note), \(bind: item.createdAt))
            ON CONFLICT (from_user_id, to_user_id, title_id) WHERE added_at IS NULL AND dismissed_at IS NULL
            DO NOTHING
            """).run()
        }
    }

    func inbox(_ user: UserID, limit: Int) async throws -> [Recommendation] {
        try await sql.raw("""
        SELECT r.id, r.from_user_id, r.to_user_id, r.title_id, r.note, r.created_at
        FROM social_recommendations r
        JOIN social_friendships f
            ON f.user_low = LEAST(r.from_user_id, r.to_user_id) AND f.user_high = GREATEST(r.from_user_id, r.to_user_id)
        WHERE r.to_user_id = \(bind: user.rawValue) AND r.added_at IS NULL AND r.dismissed_at IS NULL
        ORDER BY r.created_at DESC
        LIMIT \(bind: limit)
        """).all(decoding: RecommendationRow.self, keyDecodingStrategy: .convertFromSnakeCase).map(\.recommendation)
    }

    func resolve(_ id: UUID, to user: UserID, added: Bool, now: Date) async throws -> Recommendation? {
        let column = added ? "added_at" : "dismissed_at"
        return try await sql.raw("""
        UPDATE social_recommendations SET \(unsafeRaw: column) = \(bind: now)
        WHERE id = \(bind: id) AND to_user_id = \(bind: user.rawValue) AND added_at IS NULL AND dismissed_at IS NULL
        RETURNING id, from_user_id, to_user_id, title_id, note, created_at
        """).first(decoding: RecommendationRow.self, keyDecodingStrategy: .convertFromSnakeCase)?.recommendation
    }

    private struct RecommendationRow: Decodable {
        let id: UUID
        let fromUserId: UUID
        let toUserId: UUID
        let titleId: UUID
        let note: String?
        let createdAt: Date

        var recommendation: Recommendation {
            Recommendation(
                id: id, sender: UserID(fromUserId), recipient: UserID(toUserId), titleID: TitleID(titleId), note: note,
                createdAt: createdAt
            )
        }
    }
}
