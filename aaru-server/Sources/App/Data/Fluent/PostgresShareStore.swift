import AaruCore
import FluentKit
import FluentSQL
import Foundation

/// SHR-002: `shares`, one row per share link.
struct PostgresShareStore: ShareStore {
    let database: any Database

    private struct Row: Decodable {
        let code: String
        let senderId: UUID?
        let kind: String
        let titleId: UUID?
        let sportEventId: String?
        let concertId: String?
        let note: String?
        let createdAt: Date

        var share: Share? {
            let target: ShareTarget? = switch kind {
            case "title": titleId.map { .title(TitleID($0)) }
            case "sport_event": sportEventId.map { .sportEvent($0) }
            case "concert": concertId.map { .concert($0) }
            default: nil
            }
            guard let target else { return nil }
            return Share(
                code: code, senderID: senderId.map { UserID($0) }, target: target, note: note, createdAt: createdAt
            )
        }
    }

    private static let columns = "code, sender_id, kind, title_id, sport_event_id, concert_id, note, created_at"

    /// The target's one filled column; the other two stay null.
    private struct TargetColumns {
        var title: UUID?
        var sport: String?
        var concert: String?

        init(_ target: ShareTarget) {
            switch target {
            case let .title(id): title = id.rawValue
            case let .sportEvent(id): sport = id
            case let .concert(id): concert = id
            }
        }
    }

    func createShare(_ share: Share) async throws {
        let ids = TargetColumns(share.target)
        try await mappingConflicts("That share code is taken.") {
            try await sqlDatabase(database).raw("""
            INSERT INTO shares (\(unsafeRaw: Self.columns))
            VALUES (\(bind: share.code), \(bind: share.senderID?.rawValue), \(bind: share.target.kind),
                    \(bind: ids.title), \(bind: ids.sport), \(bind: ids.concert), \(bind: share.note),
                    \(bind: share.createdAt))
            """).run()
        }
    }

    func share(code: String) async throws -> Share? {
        try await sqlDatabase(database).raw("""
        SELECT \(unsafeRaw: Self.columns) FROM shares WHERE code = \(bind: code)
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)?.share
    }

    func existingShare(sender: UserID, target: ShareTarget, note: String?) async throws -> Share? {
        let ids = TargetColumns(target)
        return try await sqlDatabase(database).raw("""
        SELECT \(unsafeRaw: Self.columns) FROM shares
        WHERE sender_id = \(bind: sender.rawValue) AND kind = \(bind: target.kind)
          AND title_id IS NOT DISTINCT FROM \(bind: ids.title)::uuid
          AND sport_event_id IS NOT DISTINCT FROM \(bind: ids.sport)::text
          AND concert_id IS NOT DISTINCT FROM \(bind: ids.concert)::text
          AND note IS NOT DISTINCT FROM \(bind: note)::text
        ORDER BY created_at DESC LIMIT 1
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)?.share
    }
}
