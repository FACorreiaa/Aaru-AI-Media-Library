import AaruCore
import FluentKit
import FluentSQL
import Foundation

// Postgres implementations for M2: user profile/delete, sessions, magic links.

extension PostgresUserStore {
    func profile(_ id: UserID) async throws -> UserProfile? {
        struct UserRow: Decodable { let displayName: String? }
        struct IdentityRow: Decodable { let provider: String }
        let sql = try sqlDatabase(database)
        guard let user = try await sql.select().column("display_name").from("users")
            .where("id", .equal, id.rawValue)
            .first(decoding: UserRow.self, keyDecodingStrategy: .convertFromSnakeCase)
        else { return nil }
        let identities = try await sql.select().column("provider").from("auth_identities")
            .where("user_id", .equal, id.rawValue)
            .orderBy("provider")
            .all(decoding: IdentityRow.self)
        return UserProfile(
            id: id,
            displayName: user.displayName,
            providers: identities.compactMap { AuthIdentity.Provider(rawValue: $0.provider) }
        )
    }

    func deleteUser(_ id: UserID) async throws {
        try await database.transaction { database in
            let sql = try sqlDatabase(database)
            // Magic links are keyed by email, not user, so they do not cascade.
            try await sql.raw("""
            DELETE FROM magic_links WHERE email IN (
                SELECT email FROM auth_identities WHERE user_id = \(bind: id.rawValue) AND email IS NOT NULL
            )
            """).run()
            try await sql.delete(from: "users").where("id", .equal, id.rawValue).run()
        }
    }
}

struct PostgresSessionStore: SessionStore {
    let sql: any SQLDatabase

    func create(userID: UserID, tokenHash: String, expiresAt: Date) async throws {
        try await sql.insert(into: "sessions")
            .columns("id", "user_id", "token_hash", "expires_at")
            .values(SQLBind(UUID()), SQLBind(userID.rawValue), SQLBind(tokenHash), SQLBind(expiresAt))
            .run()
    }

    func userID(forTokenHash tokenHash: String, now: Date) async throws -> UserID? {
        struct Row: Decodable { let userId: UUID }
        let row = try await sql.select().column("user_id").from("sessions")
            .where("token_hash", .equal, tokenHash)
            .where("expires_at", .greaterThan, now)
            .first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)
        return row.map { UserID($0.userId) }
    }

    func delete(tokenHash: String) async throws {
        try await sql.delete(from: "sessions").where("token_hash", .equal, tokenHash).run()
    }
}

struct PostgresMagicLinkStore: MagicLinkStore {
    let sql: any SQLDatabase

    func create(email: String, tokenHash: String, expiresAt: Date) async throws {
        try await sql.insert(into: "magic_links")
            .columns("id", "email", "token_hash", "expires_at")
            .values(SQLBind(UUID()), SQLBind(email), SQLBind(tokenHash), SQLBind(expiresAt))
            .run()
    }

    func consume(tokenHash: String, now: Date) async throws -> String? {
        struct Row: Decodable { let email: String }
        // One statement: two concurrent verifies cannot both win.
        return try await sql.raw("""
        UPDATE magic_links SET used_at = \(bind: now)
        WHERE token_hash = \(bind: tokenHash) AND used_at IS NULL AND expires_at > \(bind: now)
        RETURNING email
        """).first(decoding: Row.self)?.email
    }
}
