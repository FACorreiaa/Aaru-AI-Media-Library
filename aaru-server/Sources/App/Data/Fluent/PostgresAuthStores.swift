import AaruCore
import FluentKit
import FluentSQL
import Foundation

// Postgres implementations for M2: user profile/delete, sessions, magic links.

extension PostgresUserStore {
    func profile(_ id: UserID) async throws -> UserProfile? {
        struct UserRow: Decodable {
            let displayName: String?
            let handle: String?
        }
        struct IdentityRow: Decodable { let provider: String }
        let sql = try sqlDatabase(database)
        guard let user = try await sql.raw("""
        SELECT u.display_name, p.handle FROM users u LEFT JOIN profiles p ON p.user_id = u.id
        WHERE u.id = \(bind: id.rawValue)
        """).first(decoding: UserRow.self, keyDecodingStrategy: .convertFromSnakeCase)
        else { return nil }
        let identities = try await sql.select().column("provider").from("auth_identities")
            .where("user_id", .equal, id.rawValue)
            .orderBy("provider")
            .all(decoding: IdentityRow.self)
        return UserProfile(
            id: id,
            displayName: user.displayName,
            handle: user.handle,
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
            try await Self.leaveGroups(id, sql: sql)
            try await sql.delete(from: "users").where("id", .equal, id.rawValue).run()
        }
    }

    func count() async throws -> Int {
        struct Row: Decodable { let count: Int }
        let row = try await sqlDatabase(database).raw("SELECT count(*)::int AS count FROM users")
            .first(decoding: Row.self)
        return row?.count ?? 0
    }
}

extension PostgresUserStore {
    /// Group messages are server-visible, so an account's messages are emptied, not orphaned with
    /// their text. Each group it owned passes to its oldest admin, else its oldest member, and a
    /// group with nobody else in it goes. The membership rows then cascade with the user.
    static func leaveGroups(_ id: UserID, sql: any SQLDatabase) async throws {
        try await sql.raw("""
        UPDATE group_messages SET body = '', mentions = '{}', mentions_agent = false,
            deleted_at = coalesce(deleted_at, now())
        WHERE author_id = \(bind: id.rawValue)
        """).run()
        try await sql.raw("""
        DELETE FROM groups g WHERE g.id IN (SELECT group_id FROM group_members WHERE user_id = \(bind: id.rawValue))
          AND NOT EXISTS (SELECT 1 FROM group_members o WHERE o.group_id = g.id AND o.user_id <> \(bind: id.rawValue))
        """).run()
        struct Owned: Decodable { let groupId: UUID }
        let owned = try await sql.raw("""
        UPDATE group_members SET role = 'admin' WHERE user_id = \(bind: id.rawValue) AND role = 'owner'
        RETURNING group_id
        """).all(decoding: Owned.self, keyDecodingStrategy: .convertFromSnakeCase)
        for group in owned {
            try await sql.raw("""
            UPDATE group_members SET role = 'owner'
            WHERE group_id = \(bind: group.groupId) AND user_id = (
                SELECT user_id FROM group_members
                WHERE group_id = \(bind: group.groupId) AND user_id <> \(bind: id.rawValue)
                ORDER BY role = 'admin' DESC, joined_at, user_id LIMIT 1
            )
            """).run()
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

    func create(email: String, tokenHash: String, codeHash: String, expiresAt: Date) async throws {
        try await sql.insert(into: "magic_links")
            .columns("id", "email", "token_hash", "code_hash", "expires_at")
            .values(SQLBind(UUID()), SQLBind(email), SQLBind(tokenHash), SQLBind(codeHash), SQLBind(expiresAt))
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

    func consume(email: String, codeHash: String, maxAttempts: Int, now: Date) async throws -> Bool {
        struct Row: Decodable { let email: String }
        let live: SQLQueryString = """
        email = \(bind: email) AND used_at IS NULL AND expires_at > \(bind: now)
        """
        let used = try await sql.raw("""
        UPDATE magic_links SET used_at = \(bind: now)
        WHERE id = (
            SELECT id FROM magic_links
            WHERE \(live) AND code_hash = \(bind: codeHash) AND failed_attempts < \(bind: maxAttempts)
            ORDER BY created_at DESC LIMIT 1
            FOR UPDATE
        ) AND used_at IS NULL
        RETURNING email
        """).first(decoding: Row.self)
        if used != nil {
            return true
        }
        try await sql.raw("UPDATE magic_links SET failed_attempts = failed_attempts + 1 WHERE \(live)").run()
        return false
    }
}
