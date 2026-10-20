import AaruCore
import FluentKit
import FluentSQL
import Foundation

/// Channels, messages and read state.
extension PostgresGroupStore {
    private struct ChannelRow: Decodable {
        let id: UUID
        let groupId: UUID
        let name: String
        let topic: String?
        let position: Int
        let isDefault: Bool
        let createdAt: Date
        let unread: Int?
        let mentions: Int?

        var channel: GroupChannel {
            GroupChannel(
                id: id, groupID: groupId, name: name, topic: topic, position: position, isDefault: isDefault,
                createdAt: createdAt, unread: unread ?? 0, mentions: mentions ?? 0
            )
        }
    }

    private struct MessageRow: Decodable {
        let id: UUID
        let channelId: UUID
        let authorId: UUID?
        let authorHandle: String?
        let authorDisplayName: String?
        let body: String
        let mentions: [UUID]
        let mentionsAgent: Bool
        let createdAt: Date
        let editedAt: Date?
        let deletedAt: Date?

        var message: GroupMessage {
            let author = authorId.flatMap { id in
                authorHandle.map { SocialUser(id: UserID(id), handle: $0, displayName: authorDisplayName) }
            }
            return GroupMessage(
                id: id, channelID: channelId, author: author, body: body, mentions: mentions.map(UserID.init),
                mentionsAgent: mentionsAgent, createdAt: createdAt, editedAt: editedAt, deletedAt: deletedAt
            )
        }
    }

    private static let messageColumns: SQLQueryString = """
    SELECT m.id, m.channel_id, m.author_id, p.handle AS author_handle, u.display_name AS author_display_name,
        m.body, m.mentions, m.mentions_agent, m.created_at, m.edited_at, m.deleted_at
    FROM group_messages m
    LEFT JOIN profiles p ON p.user_id = m.author_id LEFT JOIN users u ON u.id = m.author_id
    """

    static func insert(_ channel: GroupChannel, sql: any SQLDatabase) async throws {
        try await sql.raw("""
        INSERT INTO group_channels (id, group_id, kind, name, topic, position, is_default, created_at)
        VALUES (\(bind: channel.id), \(bind: channel.groupID), 'text', \(bind: channel.name), \(bind: channel.topic),
                \(bind: channel.position), \(bind: channel.isDefault), \(bind: channel.createdAt))
        """).run()
    }

    // MARK: Channels

    func channels(_ group: UUID, viewer: UserID) async throws -> [GroupChannel] {
        let messages: SQLQueryString = """
        FROM group_messages m WHERE m.channel_id = c.id AND \(Self.unseen(viewer))
        """
        return try await sql.raw("""
        SELECT c.id, c.group_id, c.name, c.topic, c.position, c.is_default, c.created_at,
            (SELECT count(*) \(messages)) AS unread,
            (SELECT count(*) \(messages) AND \(bind: viewer.rawValue) = ANY(m.mentions)) AS mentions
        FROM group_channels c
        LEFT JOIN group_read_state r ON r.channel_id = c.id AND r.user_id = \(bind: viewer.rawValue)
        WHERE c.group_id = \(bind: group)
        ORDER BY c.position, c.created_at
        """).all(decoding: ChannelRow.self, keyDecodingStrategy: .convertFromSnakeCase).map(\.channel)
    }

    func channel(_ id: UUID, group: UUID) async throws -> GroupChannel? {
        try await sql.raw("""
        SELECT id, group_id, name, topic, position, is_default, created_at, NULL::bigint AS unread,
            NULL::bigint AS mentions
        FROM group_channels WHERE id = \(bind: id) AND group_id = \(bind: group)
        """).first(decoding: ChannelRow.self, keyDecodingStrategy: .convertFromSnakeCase)?.channel
    }

    func createChannel(_ channel: GroupChannel) async throws {
        try await mappingConflicts("A channel already has that name.") {
            try await Self.insert(channel, sql: sql)
        }
    }

    func updateChannel(_ id: UUID, name: String?, topic: String??) async throws {
        let topicSet: SQLQueryString = topic.map { "\(bind: $0)" } ?? "topic"
        try await mappingConflicts("A channel already has that name.") {
            try await sql.raw("""
            UPDATE group_channels SET name = coalesce(\(bind: name), name), topic = \(topicSet)
            WHERE id = \(bind: id)
            """).run()
        }
    }

    func deleteChannel(_ id: UUID) async throws -> Bool {
        struct Row: Decodable { let id: UUID }
        return try await sql.raw("""
        DELETE FROM group_channels WHERE id = \(bind: id) AND NOT is_default RETURNING id
        """).first(decoding: Row.self) != nil
    }

    // MARK: Messages

    func messages(_ channel: UUID, cursor: MessageCursor, limit: Int) async throws -> [GroupMessage] {
        let anchor: SQLQueryString = "SELECT created_at, id FROM group_messages WHERE channel_id = \(bind: channel)"
        let query: SQLQueryString = switch cursor {
        case .latest:
            "\(Self.messageColumns) WHERE m.channel_id = \(bind: channel) ORDER BY m.created_at DESC, m.id DESC"
        case let .before(id):
            """
            \(Self.messageColumns) WHERE m.channel_id = \(bind: channel)
              AND (m.created_at, m.id) < (\(anchor) AND id = \(bind: id))
            ORDER BY m.created_at DESC, m.id DESC
            """
        case let .after(id):
            """
            \(Self.messageColumns) WHERE m.channel_id = \(bind: channel)
              AND (m.created_at, m.id) > (\(anchor) AND id = \(bind: id))
            ORDER BY m.created_at, m.id
            """
        }
        let rows = try await sql.raw("\(query) LIMIT \(bind: limit)")
            .all(decoding: MessageRow.self, keyDecodingStrategy: .convertFromSnakeCase).map(\.message)
        if case .after = cursor {
            return rows
        }
        return rows.reversed()
    }

    func message(_ id: UUID, channel: UUID) async throws -> GroupMessage? {
        try await sql.raw("""
        \(Self.messageColumns) WHERE m.id = \(bind: id) AND m.channel_id = \(bind: channel)
        """).first(decoding: MessageRow.self, keyDecodingStrategy: .convertFromSnakeCase)?.message
    }

    func postMessage(_ message: GroupMessage, nonce: String?) async throws -> GroupMessage {
        struct Row: Decodable { let id: UUID }
        let author = message.author?.id.rawValue
        let inserted = try await sql.raw("""
        INSERT INTO group_messages (id, channel_id, author_id, body, mentions, mentions_agent, client_nonce, created_at)
        VALUES (\(bind: message.id), \(bind: message.channelID), \(bind: author), \(bind: message.body),
                \(bind: message.mentions.map(\.rawValue)), \(bind: message.mentionsAgent), \(bind: nonce),
                \(bind: message.createdAt))
        ON CONFLICT (author_id, client_nonce) DO NOTHING
        RETURNING id
        """).first(decoding: Row.self)
        let id: UUID
        if let inserted {
            id = inserted.id
        } else {
            // A retry: answer with the message the first attempt stored.
            guard let first = try await sql.raw("""
            SELECT id FROM group_messages WHERE author_id = \(bind: author) AND client_nonce = \(bind: nonce)
            """).first(decoding: Row.self) else { throw StoreConflict(message: "That message was not saved.") }
            id = first.id
        }
        return try await sql.raw("\(Self.messageColumns) WHERE m.id = \(bind: id)")
            .first(decoding: MessageRow.self, keyDecodingStrategy: .convertFromSnakeCase)?.message ?? message
    }

    func editMessage(_ id: UUID, body: String, mentions: [UserID], mentionsAgent: Bool, now: Date) async throws {
        try await sql.raw("""
        UPDATE group_messages SET body = \(bind: body), mentions = \(bind: mentions.map(\.rawValue)),
            mentions_agent = \(bind: mentionsAgent), edited_at = \(bind: now)
        WHERE id = \(bind: id) AND deleted_at IS NULL
        """).run()
    }

    func deleteMessage(_ id: UUID, now: Date) async throws {
        try await sql.raw("""
        UPDATE group_messages SET body = '', mentions = '{}', mentions_agent = false, deleted_at = \(bind: now)
        WHERE id = \(bind: id) AND deleted_at IS NULL
        """).run()
    }

    func markRead(_ user: UserID, channel: UUID, upTo message: UUID) async throws {
        try await sql.raw("""
        INSERT INTO group_read_state (user_id, channel_id, last_read_at)
        SELECT \(bind: user.rawValue), channel_id, created_at FROM group_messages
        WHERE id = \(bind: message) AND channel_id = \(bind: channel)
        ON CONFLICT (user_id, channel_id) DO UPDATE
            SET last_read_at = GREATEST(group_read_state.last_read_at, EXCLUDED.last_read_at)
        """).run()
    }

    func exportMessages(_ user: UserID) async throws -> [ExportedGroupMessage] {
        struct Row: Decodable {
            let groupName: String
            let channelName: String
            let body: String
            let createdAt: Date
        }
        return try await sql.raw("""
        SELECT g.name AS group_name, c.name AS channel_name, m.body, m.created_at
        FROM group_messages m JOIN group_channels c ON c.id = m.channel_id JOIN groups g ON g.id = c.group_id
        WHERE m.author_id = \(bind: user.rawValue) AND m.deleted_at IS NULL
        ORDER BY m.created_at
        """).all(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase).map {
            ExportedGroupMessage(group: $0.groupName, channel: $0.channelName, body: $0.body, createdAt: $0.createdAt)
        }
    }
}
