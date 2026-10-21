import AaruCore
import FluentKit
import FluentSQL
import Foundation

/// Title, shelf and watch channels (GRP-007…GRP-009).
extension PostgresGroupStore: GroupKindStore {
    func setShareProgress(_ group: UUID, user: UserID, share: Bool) async throws {
        try await sql.raw("""
        UPDATE group_members SET share_progress = \(bind: share)
        WHERE group_id = \(bind: group) AND user_id = \(bind: user.rawValue)
        """).run()
    }

    func progress(title: TitleID, users: [UserID]) async throws -> [UserID: TitleProgress] {
        struct Row: Decodable {
            let userId: UUID
            let status: String
            let season: Int?
            let episode: Int?
        }
        let rows = try await sql.raw("""
        SELECT li.user_id, li.status, last.season, last.episode
        FROM library_items li
        LEFT JOIN LATERAL (
            SELECT ep.season, ep.episode FROM episode_progress ep WHERE ep.library_item_id = li.id
            ORDER BY ep.season DESC, ep.episode DESC LIMIT 1
        ) last ON true
        WHERE li.title_id = \(bind: title.rawValue) AND li.user_id = ANY(\(bind: users.map(\.rawValue)))
        """).all(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)
        var progress: [UserID: TitleProgress] = [:]
        for row in rows {
            guard let status = LibraryStatus(rawValue: row.status) else { continue }
            let furthest = row.season
                .flatMap { season in row.episode.map { EpisodePoint(season: season, episode: $0) } }
            progress[UserID(row.userId)] = TitleProgress(status: status, furthest: furthest)
        }
        return progress
    }

    // MARK: Shelf

    func shelfItems(_ channel: UUID, viewer: UserID) async throws -> [ShelfItem] {
        struct Row: Decodable {
            let titleId: UUID
            let addedBy: UUID?
            let handle: String?
            let displayName: String?
            let addedAt: Date
            let position: Int
            let myStatus: String?
        }
        return try await sql.raw("""
        SELECT i.title_id, i.added_by, p.handle, u.display_name, i.added_at, i.position, li.status AS my_status
        FROM group_channel_items i
        LEFT JOIN profiles p ON p.user_id = i.added_by LEFT JOIN users u ON u.id = i.added_by
        LEFT JOIN library_items li ON li.title_id = i.title_id AND li.user_id = \(bind: viewer.rawValue)
        WHERE i.channel_id = \(bind: channel)
        ORDER BY i.position, i.added_at
        """).all(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase).map { row in
            ShelfItem(
                titleID: TitleID(row.titleId),
                addedBy: row.addedBy.flatMap { id in
                    row.handle.map { SocialUser(id: UserID(id), handle: $0, displayName: row.displayName) }
                },
                addedAt: row.addedAt,
                position: row.position,
                myStatus: row.myStatus.flatMap(LibraryStatus.init(rawValue:))
            )
        }
    }

    func addShelfItem(_ channel: UUID, title: TitleID, by user: UserID, now: Date) async throws -> Bool {
        struct Row: Decodable { let titleId: UUID }
        return try await sql.raw("""
        INSERT INTO group_channel_items (channel_id, title_id, added_by, position, added_at)
        SELECT \(bind: channel), \(bind: title.rawValue), \(bind: user.rawValue),
               coalesce(max(position), 0) + 1, \(bind: now)
        FROM group_channel_items WHERE channel_id = \(bind: channel)
        ON CONFLICT (channel_id, title_id) DO NOTHING
        RETURNING title_id
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase) != nil
    }

    func removeShelfItem(_ channel: UUID, title: TitleID) async throws -> Bool {
        struct Row: Decodable { let titleId: UUID }
        return try await sql.raw("""
        DELETE FROM group_channel_items WHERE channel_id = \(bind: channel) AND title_id = \(bind: title.rawValue)
        RETURNING title_id
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase) != nil
    }

    // MARK: Watch

    func latestParty(_ channel: UUID) async throws -> WatchParty? {
        struct Row: Decodable {
            let id: UUID
            let channelId: UUID
            let titleId: UUID
            let season: Int?
            let episode: Int?
            let createdBy: UUID?
            let handle: String?
            let displayName: String?
            let startsAt: Date?
            let endedAt: Date?
            let createdAt: Date
        }
        struct ReadyRow: Decodable {
            let userId: UUID
            let handle: String
            let displayName: String?
        }
        guard let row = try await sql.raw("""
        SELECT s.id, s.channel_id, s.title_id, s.season, s.episode, s.created_by, p.handle, u.display_name,
               s.starts_at, s.ended_at, s.created_at
        FROM watch_sessions s
        LEFT JOIN profiles p ON p.user_id = s.created_by LEFT JOIN users u ON u.id = s.created_by
        WHERE s.channel_id = \(bind: channel)
        ORDER BY s.created_at DESC LIMIT 1
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase) else { return nil }
        let ready = try await sql.raw("""
        SELECT r.user_id, p.handle, u.display_name
        FROM watch_ready r JOIN profiles p ON p.user_id = r.user_id JOIN users u ON u.id = r.user_id
        WHERE r.session_id = \(bind: row.id)
        ORDER BY p.handle
        """).all(decoding: ReadyRow.self, keyDecodingStrategy: .convertFromSnakeCase).map {
            SocialUser(id: UserID($0.userId), handle: $0.handle, displayName: $0.displayName)
        }
        return WatchParty(
            id: row.id, channelID: row.channelId, titleID: TitleID(row.titleId),
            episode: row.season.flatMap { season in row.episode.map { EpisodePoint(season: season, episode: $0) } },
            createdBy: row.createdBy.flatMap { id in
                row.handle.map { SocialUser(id: UserID(id), handle: $0, displayName: row.displayName) }
            },
            startsAt: row.startsAt, endedAt: row.endedAt, createdAt: row.createdAt, ready: ready
        )
    }

    func createSession(_ session: WatchParty) async throws {
        try await mappingConflicts("A watch party is already open here.") {
            try await sql.raw("""
            INSERT INTO watch_sessions (id, channel_id, title_id, season, episode, created_by, created_at)
            VALUES (\(bind: session.id), \(bind: session.channelID), \(bind: session.titleID.rawValue),
                    \(bind: session.episode?.season), \(bind: session.episode?.episode),
                    \(bind: session.createdBy?.id.rawValue), \(bind: session.createdAt))
            """).run()
        }
    }

    func setReady(_ session: UUID, user: UserID, ready: Bool) async throws {
        if ready {
            try await sql.raw("""
            INSERT INTO watch_ready (session_id, user_id) VALUES (\(bind: session), \(bind: user.rawValue))
            ON CONFLICT DO NOTHING
            """).run()
        } else {
            try await sql.raw("""
            DELETE FROM watch_ready WHERE session_id = \(bind: session) AND user_id = \(bind: user.rawValue)
            """).run()
        }
    }

    func startSession(_ session: UUID, at startsAt: Date) async throws {
        try await sql.raw("""
        UPDATE watch_sessions SET starts_at = \(bind: startsAt) WHERE id = \(bind: session) AND ended_at IS NULL
        """).run()
    }

    func endSession(_ session: UUID, now: Date) async throws {
        try await sql.raw("""
        UPDATE watch_sessions SET ended_at = \(bind: now) WHERE id = \(bind: session) AND ended_at IS NULL
        """).run()
    }
}
