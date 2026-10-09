import AaruCore
import FluentKit
import FluentSQL
import Foundation

/// List ops (LST-001, LST-002), applied inside a library transaction like every write.
extension PostgresLibraryStore {
    static func runListOp(_ op: LibraryOp, userID: UserID, sql: any SQLDatabase) async throws -> LibraryOp {
        switch op {
        case let .insertList(snapshot):
            try await insertList(snapshot, userID: userID, sql: sql)
            return .deleteList(snapshot.id)
        case let .deleteList(id):
            return try await .insertList(deleteList(id, userID: userID, sql: sql))
        case let .renameList(id, name):
            let previous = try await lockedList(id, userID: userID, sql: sql).name
            try await sql.raw("""
            UPDATE lists SET name = \(bind: name), updated_at = now() WHERE id = \(bind: id.rawValue)
            """).run()
            return .renameList(id, previous)
        case let .setListMembers(id, members):
            let previous = try await lockedList(id, userID: userID, sql: sql).members
            try await writeMembers(members, list: id, sql: sql)
            try await sql.raw("UPDATE lists SET updated_at = now() WHERE id = \(bind: id.rawValue)").run()
            return .setListMembers(id, previous)
        default:
            preconditionFailure("runListOp got a non-list op")
        }
    }

    fileprivate static func insertList(_ snapshot: ListSnapshot, userID: UserID, sql: any SQLDatabase) async throws {
        try await sql.raw("""
        INSERT INTO lists (id, user_id, name, created_at, updated_at)
        VALUES (\(bind: snapshot.id.rawValue), \(bind: userID.rawValue), \(bind: snapshot.name),
            \(bind: snapshot.createdAt), now())
        """).run()
        try await writeMembers(snapshot.members, list: snapshot.id, sql: sql)
    }

    fileprivate static func deleteList(
        _ id: ListID,
        userID: UserID,
        sql: any SQLDatabase
    ) async throws -> ListSnapshot {
        let snapshot = try await lockedList(id, userID: userID, sql: sql)
        try await sql.raw("DELETE FROM lists WHERE id = \(bind: id.rawValue)").run()
        return snapshot
    }

    /// Locks the user's list and returns it. Another user's list is 404.
    fileprivate static func lockedList(
        _ id: ListID,
        userID: UserID,
        sql: any SQLDatabase
    ) async throws -> ListSnapshot {
        struct Row: Decodable {
            let name: String
            let createdAt: Date
        }
        struct Member: Decodable { let titleId: UUID }
        guard let row = try await sql.raw("""
        SELECT name, created_at FROM lists WHERE id = \(bind: id.rawValue) AND user_id = \(bind: userID.rawValue)
        FOR UPDATE
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)
        else { throw AppError.notFound("No such list.") }
        let members = try await sql.raw("""
        SELECT title_id FROM list_items WHERE list_id = \(bind: id.rawValue) ORDER BY position
        """).all(decoding: Member.self, keyDecodingStrategy: .convertFromSnakeCase)
        return ListSnapshot(
            id: id,
            name: row.name,
            createdAt: row.createdAt,
            members: members.map { TitleID($0.titleId) }
        )
    }

    fileprivate static func writeMembers(_ members: [TitleID], list: ListID, sql: any SQLDatabase) async throws {
        try await sql.raw("DELETE FROM list_items WHERE list_id = \(bind: list.rawValue)").run()
        for (position, titleID) in members.enumerated() {
            try await sql.raw("""
            INSERT INTO list_items (id, list_id, title_id, position)
            VALUES (\(bind: UUID()), \(bind: list.rawValue), \(bind: titleID.rawValue), \(bind: position))
            """).run()
        }
    }
}
