import AaruCore
import FluentKit
import FluentSQL
import Foundation

/// Groups, members and invites. Channels and messages are in `PostgresGroupStore+Messages.swift`.
struct PostgresGroupStore: GroupStore {
    let database: any Database

    var sql: any SQLDatabase {
        get throws { try sqlDatabase(database) }
    }

    struct Found: Decodable { let found: Bool }
    struct Count: Decodable { let count: Int }

    private struct SummaryRow: Decodable {
        let id: UUID
        let name: String
        let role: String
        let defaultChannelId: UUID
        let unread: Int
        let mentions: Int
        let shareProgress: Bool

        var summary: GroupSummary {
            GroupSummary(
                id: id, name: name, role: GroupRole(rawValue: role) ?? .member,
                defaultChannelID: defaultChannelId, unread: unread, mentions: mentions, shareProgress: shareProgress
            )
        }
    }

    private struct MemberRow: Decodable {
        let userId: UUID
        let handle: String
        let displayName: String?
        let role: String
        let joinedAt: Date
        let shareProgress: Bool
    }

    private struct InviteRow: Decodable {
        let id: UUID
        let groupId: UUID
        let groupName: String
        let createdAt: Date
        let inviterId: UUID
        let inviterHandle: String
        let inviterDisplayName: String?
        let inviteeId: UUID
        let inviteeHandle: String
        let inviteeDisplayName: String?

        var invite: GroupInvite {
            GroupInvite(
                id: id, groupID: groupId, groupName: groupName,
                inviter: SocialUser(id: UserID(inviterId), handle: inviterHandle, displayName: inviterDisplayName),
                invitee: SocialUser(id: UserID(inviteeId), handle: inviteeHandle, displayName: inviteeDisplayName),
                createdAt: createdAt
            )
        }
    }

    /// A message `m` from someone else since the viewer's read point `r` (unread), and not deleted.
    static func unseen(_ viewer: UserID) -> SQLQueryString {
        """
        m.deleted_at IS NULL AND m.author_id IS DISTINCT FROM \(bind: viewer.rawValue)
        AND m.created_at > coalesce(r.last_read_at, '-infinity')
        """
    }

    private func summaries(_ viewer: UserID, group: UUID?) async throws -> [GroupSummary] {
        let only: SQLQueryString = group.map { "AND g.id = \(bind: $0)" } ?? ""
        let messages: SQLQueryString = """
        FROM group_channels c JOIN group_messages m ON m.channel_id = c.id
        LEFT JOIN group_read_state r ON r.channel_id = c.id AND r.user_id = \(bind: viewer.rawValue)
        WHERE c.group_id = g.id AND \(Self.unseen(viewer))
        """
        return try await sql.raw("""
        SELECT g.id, g.name, gm.role, gm.share_progress,
            (SELECT id FROM group_channels WHERE group_id = g.id AND is_default) AS default_channel_id,
            (SELECT count(*) \(messages)) AS unread,
            (SELECT count(*) \(messages) AND \(bind: viewer.rawValue) = ANY(m.mentions)) AS mentions
        FROM group_members gm JOIN groups g ON g.id = gm.group_id
        WHERE gm.user_id = \(bind: viewer.rawValue) \(only)
        ORDER BY gm.joined_at, g.id
        """).all(decoding: SummaryRow.self, keyDecodingStrategy: .convertFromSnakeCase).map(\.summary)
    }

    func groups(for user: UserID) async throws -> [GroupSummary] {
        try await summaries(user, group: nil)
    }

    func summary(_ group: UUID, viewer: UserID) async throws -> GroupSummary? {
        try await summaries(viewer, group: group).first
    }

    func ownedCount(_ user: UserID) async throws -> Int {
        try await sql.raw("""
        SELECT count(*) FROM group_members WHERE user_id = \(bind: user.rawValue) AND role = 'owner'
        """).first(decoding: Count.self)?.count ?? 0
    }

    func createGroup(id: UUID, name: String, owner: UserID, general: GroupChannel, now: Date) async throws {
        try await database.transaction { database in
            let sql = try sqlDatabase(database)
            try await sql.raw("""
            INSERT INTO groups (id, name, created_at, updated_at)
            VALUES (\(bind: id), \(bind: name), \(bind: now), \(bind: now))
            """).run()
            try await sql.raw("""
            INSERT INTO group_members (group_id, user_id, role, joined_at)
            VALUES (\(bind: id), \(bind: owner.rawValue), 'owner', \(bind: now))
            """).run()
            try await Self.insert(general, sql: sql)
        }
    }

    func renameGroup(_ group: UUID, name: String, now: Date) async throws {
        try await sql.raw("""
        UPDATE groups SET name = \(bind: name), updated_at = \(bind: now) WHERE id = \(bind: group)
        """).run()
    }

    func deleteGroup(_ group: UUID) async throws {
        try await sql.raw("DELETE FROM groups WHERE id = \(bind: group)").run()
    }

    // MARK: Members

    func members(_ group: UUID) async throws -> [GroupMember] {
        try await sql.raw("""
        SELECT gm.user_id, p.handle, u.display_name, gm.role, gm.joined_at, gm.share_progress
        FROM group_members gm JOIN profiles p ON p.user_id = gm.user_id JOIN users u ON u.id = gm.user_id
        WHERE gm.group_id = \(bind: group)
        ORDER BY gm.joined_at, p.handle
        """).all(decoding: MemberRow.self, keyDecodingStrategy: .convertFromSnakeCase).map {
            GroupMember(
                user: SocialUser(id: UserID($0.userId), handle: $0.handle, displayName: $0.displayName),
                role: GroupRole(rawValue: $0.role) ?? .member,
                joinedAt: $0.joinedAt,
                shareProgress: $0.shareProgress
            )
        }
    }

    func role(_ group: UUID, user: UserID) async throws -> GroupRole? {
        struct Row: Decodable { let role: String }
        return try await sql.raw("""
        SELECT role FROM group_members WHERE group_id = \(bind: group) AND user_id = \(bind: user.rawValue)
        """).first(decoding: Row.self).flatMap { GroupRole(rawValue: $0.role) }
    }

    func setRole(_ group: UUID, user: UserID, role: GroupRole) async throws {
        try await sql.raw("""
        UPDATE group_members SET role = \(bind: role.rawValue)
        WHERE group_id = \(bind: group) AND user_id = \(bind: user.rawValue)
        """).run()
    }

    func removeMember(_ group: UUID, user: UserID) async throws {
        try await database.transaction { database in
            let sql = try sqlDatabase(database)
            try await sql.raw("""
            DELETE FROM group_read_state WHERE user_id = \(bind: user.rawValue)
              AND channel_id IN (SELECT id FROM group_channels WHERE group_id = \(bind: group))
            """).run()
            try await sql.raw("""
            DELETE FROM group_members WHERE group_id = \(bind: group) AND user_id = \(bind: user.rawValue)
            """).run()
        }
    }

    func transferOwnership(_ group: UUID, from previous: UserID, to next: UserID) async throws {
        try await database.transaction { database in
            let sql = try sqlDatabase(database)
            // Demote first: one owner per group is a unique index.
            try await sql.raw("""
            UPDATE group_members SET role = 'admin'
            WHERE group_id = \(bind: group) AND user_id = \(bind: previous.rawValue)
            """).run()
            try await sql.raw("""
            UPDATE group_members SET role = 'owner'
            WHERE group_id = \(bind: group) AND user_id = \(bind: next.rawValue)
            """).run()
        }
    }

    // MARK: Invites

    func createInvite(id: UUID, group: UUID, inviter: UserID, invitee: UserID, now: Date) async throws {
        try await sql.raw("""
        INSERT INTO group_invites (id, group_id, inviter_id, invitee_id, created_at)
        VALUES (\(bind: id), \(bind: group), \(bind: inviter.rawValue), \(bind: invitee.rawValue), \(bind: now))
        ON CONFLICT (group_id, invitee_id) DO NOTHING
        """).run()
    }

    private func invites(where condition: SQLQueryString) async throws -> [GroupInvite] {
        try await sql.raw("""
        SELECT i.id, i.group_id, g.name AS group_name, i.created_at,
               i.inviter_id, ip.handle AS inviter_handle, iu.display_name AS inviter_display_name,
               i.invitee_id, tp.handle AS invitee_handle, tu.display_name AS invitee_display_name
        FROM group_invites i JOIN groups g ON g.id = i.group_id
        JOIN profiles ip ON ip.user_id = i.inviter_id JOIN users iu ON iu.id = i.inviter_id
        JOIN profiles tp ON tp.user_id = i.invitee_id JOIN users tu ON tu.id = i.invitee_id
        WHERE \(condition)
        ORDER BY i.created_at DESC
        """).all(decoding: InviteRow.self, keyDecodingStrategy: .convertFromSnakeCase).map(\.invite)
    }

    func invites(to user: UserID) async throws -> [GroupInvite] {
        try await invites(where: "i.invitee_id = \(bind: user.rawValue)")
    }

    func invitesPending(_ group: UUID) async throws -> [GroupInvite] {
        try await invites(where: "i.group_id = \(bind: group)")
    }

    func acceptInvite(id: UUID, invitee: UserID, now: Date) async throws -> UUID? {
        struct Row: Decodable { let groupId: UUID }
        return try await database.transaction { database in
            let sql = try sqlDatabase(database)
            guard let row = try await sql.raw("""
            DELETE FROM group_invites WHERE id = \(bind: id) AND invitee_id = \(bind: invitee.rawValue)
            RETURNING group_id
            """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)
            else { return nil }
            try await sql.raw("""
            INSERT INTO group_members (group_id, user_id, role, joined_at)
            VALUES (\(bind: row.groupId), \(bind: invitee.rawValue), 'member', \(bind: now))
            ON CONFLICT DO NOTHING
            """).run()
            // History before joining is not unread.
            try await sql.raw("""
            INSERT INTO group_read_state (user_id, channel_id, last_read_at)
            SELECT \(bind: invitee.rawValue), id, \(bind: now) FROM group_channels WHERE group_id = \(bind: row.groupId)
            ON CONFLICT DO NOTHING
            """).run()
            return row.groupId
        }
    }

    func deleteInvite(id: UUID, party: UserID) async throws -> (group: UUID, invitee: UserID)? {
        struct Row: Decodable {
            let groupId: UUID
            let inviteeId: UUID
        }
        return try await sql.raw("""
        DELETE FROM group_invites
        WHERE id = \(bind: id) AND (inviter_id = \(bind: party.rawValue) OR invitee_id = \(bind: party.rawValue))
        RETURNING group_id, invitee_id
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase).map {
            ($0.groupId, UserID($0.inviteeId))
        }
    }
}
