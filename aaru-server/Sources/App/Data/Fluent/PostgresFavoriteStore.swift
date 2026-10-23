import AaruCore
import FluentKit
import FluentSQL
import Foundation

/// FAV-001: `favorites`, one row per title in a user's top 10 for a kind.
struct PostgresFavoriteStore: FavoriteStore {
    let database: any Database

    private struct Row: Decodable {
        let kind: String
        let titleId: UUID
    }

    func favorites(of user: UserID) async throws -> [FavoriteKind: [TitleID]] {
        let rows = try await sqlDatabase(database).raw("""
        SELECT kind, title_id FROM favorites WHERE user_id = \(bind: user.rawValue) ORDER BY kind, position
        """).all(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)
        var favorites: [FavoriteKind: [TitleID]] = [:]
        for row in rows {
            guard let kind = FavoriteKind(rawValue: row.kind) else { continue }
            favorites[kind, default: []].append(TitleID(row.titleId))
        }
        return favorites
    }

    func replaceFavorites(_ titles: [TitleID], kind: FavoriteKind, for user: UserID) async throws {
        try await database.transaction { database in
            let sql = try sqlDatabase(database)
            try await sql.raw("""
            DELETE FROM favorites WHERE user_id = \(bind: user.rawValue) AND kind = \(bind: kind.rawValue)
            """).run()
            guard !titles.isEmpty else { return }
            // `ordinality` is the position, from 0.
            try await sql.raw("""
            INSERT INTO favorites (user_id, kind, position, title_id)
            SELECT \(bind: user.rawValue), \(bind: kind.rawValue), (f.position - 1)::int, f.title_id
            FROM unnest(\(bind: titles.map(\.rawValue))::uuid[]) WITH ORDINALITY AS f(title_id, position)
            """).run()
        }
    }
}
