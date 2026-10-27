import AaruCore
import FluentKit
import FluentSQL
import Foundation

struct PostgresSocialStore: SocialStore {
    let database: any Database

    private var sql: any SQLDatabase {
        get throws { try sqlDatabase(database) }
    }

    private struct UserRow: Decodable {
        let userId: UUID
        let handle: String
        let displayName: String?
        let avatarVersion: Int64?

        var user: SocialUser {
            SocialUser(id: UserID(userId), handle: handle, displayName: displayName, avatarVersion: avatarVersion)
        }
    }

    private struct RequestRow: Decodable {
        let id: UUID
        let createdAt: Date
        let fromUserId: UUID
        let fromHandle: String
        let fromDisplayName: String?
        let fromAvatarVersion: Int64?
        let toUserId: UUID
        let toHandle: String
        let toDisplayName: String?
        let toAvatarVersion: Int64?

        var request: FriendRequest {
            FriendRequest(
                id: id,
                sender: SocialUser(
                    id: UserID(fromUserId), handle: fromHandle, displayName: fromDisplayName,
                    avatarVersion: fromAvatarVersion
                ),
                recipient: SocialUser(
                    id: UserID(toUserId), handle: toHandle, displayName: toDisplayName, avatarVersion: toAvatarVersion
                ),
                createdAt: createdAt
            )
        }
    }

    private struct Found: Decodable { let found: Bool }

    func socialUser(_ id: UserID) async throws -> SocialUser? {
        try await sql.raw("""
        SELECT p.user_id, p.handle, u.display_name, u.avatar_version FROM profiles p JOIN users u ON u.id = p.user_id
        WHERE p.user_id = \(bind: id.rawValue)
        """).first(decoding: UserRow.self, keyDecodingStrategy: .convertFromSnakeCase)?.user
    }

    func socialUser(handle: String) async throws -> SocialUser? {
        try await sql.raw("""
        SELECT p.user_id, p.handle, u.display_name, u.avatar_version FROM profiles p JOIN users u ON u.id = p.user_id
        WHERE p.handle = \(bind: handle)
        """).first(decoding: UserRow.self, keyDecodingStrategy: .convertFromSnakeCase)?.user
    }

    func saveProfile(_ id: UserID, handle: String?, name: PersonName?) async throws {
        try await mappingConflicts("That handle is taken.") {
            try await database.transaction { database in
                let sql = try sqlDatabase(database)
                if let handle {
                    try await sql.raw("""
                    INSERT INTO profiles (user_id, handle) VALUES (\(bind: id.rawValue), \(bind: handle))
                    ON CONFLICT (user_id) DO UPDATE SET handle = EXCLUDED.handle, updated_at = now()
                    """).run()
                }
                if let name {
                    try await sql.raw("""
                    UPDATE users SET first_name = \(bind: name.first), last_name = \(bind: name.last),
                        display_name = \(bind: name.displayName), updated_at = now()
                    WHERE id = \(bind: id.rawValue)
                    """).run()
                }
            }
        }
    }

    func isBlocked(_ first: UserID, _ second: UserID) async throws -> Bool {
        try await sql.raw("""
        SELECT EXISTS (
            SELECT 1 FROM social_blocks
            WHERE (blocker_id = \(bind: first.rawValue) AND blocked_id = \(bind: second.rawValue))
               OR (blocker_id = \(bind: second.rawValue) AND blocked_id = \(bind: first.rawValue))
        ) AS found
        """).first(decoding: Found.self)?.found ?? false
    }

    func areFriends(_ first: UserID, _ second: UserID) async throws -> Bool {
        try await sql.raw("""
        SELECT EXISTS (
            SELECT 1 FROM social_friendships
            WHERE user_low = LEAST(\(bind: first.rawValue), \(bind: second.rawValue))
              AND user_high = GREATEST(\(bind: first.rawValue), \(bind: second.rawValue))
        ) AS found
        """).first(decoding: Found.self)?.found ?? false
    }

    func pendingRequest(sender: UserID, recipient: UserID) async throws -> UUID? {
        struct Row: Decodable { let id: UUID }
        return try await sql.raw("""
        SELECT id FROM social_friend_requests
        WHERE from_user_id = \(bind: sender.rawValue) AND to_user_id = \(bind: recipient.rawValue)
        """).first(decoding: Row.self)?.id
    }

    func createRequest(id: UUID, sender: UserID, recipient: UserID, now: Date) async throws {
        try await sql.raw("""
        INSERT INTO social_friend_requests (id, from_user_id, to_user_id, created_at)
        VALUES (\(bind: id), \(bind: sender.rawValue), \(bind: recipient.rawValue), \(bind: now))
        ON CONFLICT (from_user_id, to_user_id) DO NOTHING
        """).run()
    }

    func incomingRequests(_ id: UserID) async throws -> [FriendRequest] {
        try await requests(where: "r.to_user_id", is: id)
    }

    func outgoingRequests(_ id: UserID) async throws -> [FriendRequest] {
        try await requests(where: "r.from_user_id", is: id)
    }

    private func requests(where column: String, is id: UserID) async throws -> [FriendRequest] {
        try await sql.raw("""
        SELECT r.id, r.created_at,
               r.from_user_id, fp.handle AS from_handle, fu.display_name AS from_display_name,
               fu.avatar_version AS from_avatar_version,
               r.to_user_id, tp.handle AS to_handle, tu.display_name AS to_display_name,
               tu.avatar_version AS to_avatar_version
        FROM social_friend_requests r
        JOIN profiles fp ON fp.user_id = r.from_user_id JOIN users fu ON fu.id = r.from_user_id
        JOIN profiles tp ON tp.user_id = r.to_user_id JOIN users tu ON tu.id = r.to_user_id
        WHERE \(unsafeRaw: column) = \(bind: id.rawValue)
        ORDER BY r.created_at DESC
        """).all(decoding: RequestRow.self, keyDecodingStrategy: .convertFromSnakeCase).map(\.request)
    }

    func acceptRequest(id: UUID, recipient: UserID, now: Date) async throws -> UserID? {
        struct Row: Decodable { let fromUserId: UUID }
        return try await database.transaction { database in
            let sql = try sqlDatabase(database)
            guard let row = try await sql.raw("""
            DELETE FROM social_friend_requests
            WHERE id = \(bind: id) AND to_user_id = \(bind: recipient.rawValue)
            RETURNING from_user_id
            """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)
            else { return nil }
            // The reverse request, if both asked, is answered by the same acceptance.
            try await sql.raw("""
            DELETE FROM social_friend_requests
            WHERE from_user_id = \(bind: recipient.rawValue) AND to_user_id = \(bind: row.fromUserId)
            """).run()
            try await sql.raw("""
            INSERT INTO social_friendships (user_low, user_high, created_at)
            VALUES (LEAST(\(bind: row.fromUserId), \(bind: recipient.rawValue)),
                    GREATEST(\(bind: row.fromUserId), \(bind: recipient.rawValue)), \(bind: now))
            ON CONFLICT DO NOTHING
            """).run()
            return UserID(row.fromUserId)
        }
    }

    func deleteRequest(id: UUID, party: UserID) async throws -> Bool {
        struct Row: Decodable { let id: UUID }
        return try await sql.raw("""
        DELETE FROM social_friend_requests
        WHERE id = \(bind: id) AND (from_user_id = \(bind: party.rawValue) OR to_user_id = \(bind: party.rawValue))
        RETURNING id
        """).first(decoding: Row.self) != nil
    }

    func friends(_ id: UserID) async throws -> [SocialUser] {
        try await sql.raw("""
        SELECT p.user_id, p.handle, u.display_name, u.avatar_version
        FROM social_friendships f
        JOIN profiles p ON p.user_id = CASE WHEN f.user_low = \(bind: id.rawValue) THEN f.user_high ELSE f.user_low END
        JOIN users u ON u.id = p.user_id
        WHERE f.user_low = \(bind: id.rawValue) OR f.user_high = \(bind: id.rawValue)
        ORDER BY p.handle
        """).all(decoding: UserRow.self, keyDecodingStrategy: .convertFromSnakeCase).map(\.user)
    }

    func unfriend(_ first: UserID, _ second: UserID) async throws -> Bool {
        struct Row: Decodable { let userLow: UUID }
        return try await sql.raw("""
        DELETE FROM social_friendships
        WHERE user_low = LEAST(\(bind: first.rawValue), \(bind: second.rawValue))
          AND user_high = GREATEST(\(bind: first.rawValue), \(bind: second.rawValue))
        RETURNING user_low
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase) != nil
    }

    func block(_ blocker: UserID, _ blocked: UserID, now: Date) async throws {
        try await database.transaction { database in
            let sql = try sqlDatabase(database)
            try await sql.raw("""
            INSERT INTO social_blocks (blocker_id, blocked_id, created_at)
            VALUES (\(bind: blocker.rawValue), \(bind: blocked.rawValue), \(bind: now))
            ON CONFLICT DO NOTHING
            """).run()
            try await sql.raw("""
            DELETE FROM social_friendships
            WHERE user_low = LEAST(\(bind: blocker.rawValue), \(bind: blocked.rawValue))
              AND user_high = GREATEST(\(bind: blocker.rawValue), \(bind: blocked.rawValue))
            """).run()
            try await sql.raw("""
            DELETE FROM social_friend_requests
            WHERE (from_user_id = \(bind: blocker.rawValue) AND to_user_id = \(bind: blocked.rawValue))
               OR (from_user_id = \(bind: blocked.rawValue) AND to_user_id = \(bind: blocker.rawValue))
            """).run()
        }
    }

    func unblock(_ blocker: UserID, _ blocked: UserID) async throws -> Bool {
        struct Row: Decodable { let blockedId: UUID }
        return try await sql.raw("""
        DELETE FROM social_blocks
        WHERE blocker_id = \(bind: blocker.rawValue) AND blocked_id = \(bind: blocked.rawValue)
        RETURNING blocked_id
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase) != nil
    }

    func blocked(by id: UserID) async throws -> [SocialUser] {
        try await sql.raw("""
        SELECT p.user_id, p.handle, u.display_name, u.avatar_version
        FROM social_blocks b JOIN profiles p ON p.user_id = b.blocked_id JOIN users u ON u.id = p.user_id
        WHERE b.blocker_id = \(bind: id.rawValue)
        ORDER BY p.handle
        """).all(decoding: UserRow.self, keyDecodingStrategy: .convertFromSnakeCase).map(\.user)
    }

    func blockers(of id: UserID) async throws -> Set<UserID> {
        struct Row: Decodable { let blockerId: UUID }
        return try await Set(sql.raw("""
        SELECT blocker_id FROM social_blocks WHERE blocked_id = \(bind: id.rawValue)
        """).all(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase).map { UserID($0.blockerId) })
    }

    func report(_ report: UserReport) async throws {
        try await sql.raw("""
        INSERT INTO social_reports (id, reporter_id, target_user_id, reason, note, created_at)
        VALUES (\(bind: report.id), \(bind: report.reporter.rawValue), \(bind: report.target.rawValue),
                \(bind: report.reason.rawValue), \(bind: report.note), \(bind: report.createdAt))
        """).run()
    }
}

// MARK: Avatars (SOC-001b)

extension PostgresSocialStore {
    func saveAvatar(_ id: UserID, image: Data) async throws {
        try await database.transaction { database in
            let sql = try sqlDatabase(database)
            try await sql.raw("""
            INSERT INTO avatars (user_id, image) VALUES (\(bind: id.rawValue), \(bind: image))
            ON CONFLICT (user_id) DO UPDATE SET image = EXCLUDED.image, updated_at = now()
            """).run()
            // Milliseconds, not a counter: a removed avatar's version is never handed out again.
            try await sql.raw("""
            UPDATE users SET avatar_version = GREATEST(
                (extract(epoch FROM clock_timestamp()) * 1000)::bigint, coalesce(avatar_version, 0) + 1
            ), updated_at = now()
            WHERE id = \(bind: id.rawValue)
            """).run()
        }
    }

    func deleteAvatar(_ id: UserID) async throws {
        try await database.transaction { database in
            let sql = try sqlDatabase(database)
            try await sql.raw("DELETE FROM avatars WHERE user_id = \(bind: id.rawValue)").run()
            try await sql.raw("""
            UPDATE users SET avatar_version = NULL, updated_at = now() WHERE id = \(bind: id.rawValue)
            """).run()
        }
    }

    func avatar(_ id: UserID) async throws -> Data? {
        struct Row: Decodable { let image: Data }
        return try await sql.raw("SELECT image FROM avatars WHERE user_id = \(bind: id.rawValue)")
            .first(decoding: Row.self)?.image
    }
}
