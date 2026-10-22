import AaruCore
import FluentKit
import FluentSQL
import Foundation

/// SOC-002 friend invite links.
extension PostgresSocialStore {
    private struct InviteRow: Decodable {
        let id: UUID
        let code: String
        let inviterId: UUID
        let titleId: UUID?
        let createdAt: Date
        let expiresAt: Date
        let redeemedBy: UUID?
        let redeemedAt: Date?
        let revokedAt: Date?

        var invite: FriendInvite {
            FriendInvite(
                id: id, code: code, inviter: UserID(inviterId), titleID: titleId.map { TitleID($0) },
                createdAt: createdAt, expiresAt: expiresAt, redeemedBy: redeemedBy.map { UserID($0) },
                redeemedAt: redeemedAt, revokedAt: revokedAt
            )
        }
    }

    private static let inviteColumns = """
    id, code, inviter_id, title_id, created_at, expires_at, redeemed_by, redeemed_at, revoked_at
    """

    func createInvite(_ invite: FriendInvite) async throws {
        try await mappingConflicts("That invite code is taken.") {
            try await sqlDatabase(database).raw("""
            INSERT INTO social_invites (id, code, inviter_id, title_id, created_at, expires_at)
            VALUES (\(bind: invite.id), \(bind: invite.code), \(bind: invite.inviter.rawValue),
                    \(bind: invite.titleID?.rawValue), \(bind: invite.createdAt), \(bind: invite.expiresAt))
            """).run()
        }
    }

    func invite(code: String) async throws -> FriendInvite? {
        try await sqlDatabase(database).raw("""
        SELECT \(unsafeRaw: Self.inviteColumns) FROM social_invites WHERE code = \(bind: code)
        """).first(decoding: InviteRow.self, keyDecodingStrategy: .convertFromSnakeCase)?.invite
    }

    func openInvites(_ inviter: UserID, now: Date) async throws -> [FriendInvite] {
        try await sqlDatabase(database).raw("""
        SELECT \(unsafeRaw: Self.inviteColumns) FROM social_invites
        WHERE inviter_id = \(bind: inviter.rawValue)
          AND redeemed_at IS NULL AND revoked_at IS NULL AND expires_at > \(bind: now)
        ORDER BY created_at DESC
        """).all(decoding: InviteRow.self, keyDecodingStrategy: .convertFromSnakeCase).map(\.invite)
    }

    func revokeInvite(code: String, inviter: UserID, now: Date) async throws -> Bool {
        struct Row: Decodable { let id: UUID }
        return try await sqlDatabase(database).raw("""
        UPDATE social_invites SET revoked_at = \(bind: now)
        WHERE code = \(bind: code) AND inviter_id = \(bind: inviter.rawValue)
          AND redeemed_at IS NULL AND revoked_at IS NULL AND expires_at > \(bind: now)
        RETURNING id
        """).first(decoding: Row.self) != nil
    }

    func redeemInvite(code: String, redeemer: UserID, now: Date) async throws -> UserID? {
        struct Row: Decodable { let inviterId: UUID }
        return try await database.transaction { database in
            let sql = try sqlDatabase(database)
            // The conditional update is the lock: of two people opening one link at once, one wins.
            guard let row = try await sql.raw("""
            UPDATE social_invites SET redeemed_by = \(bind: redeemer.rawValue), redeemed_at = \(bind: now)
            WHERE code = \(bind: code) AND inviter_id <> \(bind: redeemer.rawValue)
              AND redeemed_at IS NULL AND revoked_at IS NULL AND expires_at > \(bind: now)
            RETURNING inviter_id
            """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)
            else { return nil }
            try await sql.raw("""
            DELETE FROM social_friend_requests
            WHERE (from_user_id = \(bind: row.inviterId) AND to_user_id = \(bind: redeemer.rawValue))
               OR (from_user_id = \(bind: redeemer.rawValue) AND to_user_id = \(bind: row.inviterId))
            """).run()
            try await sql.raw("""
            INSERT INTO social_friendships (user_low, user_high, created_at)
            VALUES (LEAST(\(bind: row.inviterId), \(bind: redeemer.rawValue)),
                    GREATEST(\(bind: row.inviterId), \(bind: redeemer.rawValue)), \(bind: now))
            ON CONFLICT DO NOTHING
            """).run()
            return UserID(row.inviterId)
        }
    }
}
