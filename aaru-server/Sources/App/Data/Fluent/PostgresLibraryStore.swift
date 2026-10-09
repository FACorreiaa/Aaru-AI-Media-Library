import AaruCore
import FluentKit
import FluentSQL
import Foundation

/// The library, its journal, and undo — over one Postgres transaction per write.
struct PostgresLibraryStore: LibraryStore {
    let database: any Database

    // MARK: Writes

    func apply(
        _ op: LibraryOp,
        userID: UserID,
        actor: Actor,
        kind: String,
        summary: String
    ) async throws -> ActionRecord {
        do {
            return try await database.transaction { database in
                let sql = try sqlDatabase(database)
                let inverse = try await Self.run(op, userID: userID, sql: sql)
                let entry = JournalEntry(
                    inverse: inverse, itemIDs: op.itemIDs, actor: actor, kind: kind, summary: summary, undoOf: nil
                )
                return try await Self.journal(entry, userID: userID, sql: sql)
            }
        } catch let error as any DatabaseError where error.isConstraintFailure {
            throw StoreConflict(message: "This title is already in the library.")
        }
    }

    func undo(actionID: UUID, userID: UserID) async throws -> ActionRecord {
        struct Row: Decodable {
            let summary: String
            let inverse: LibraryOp
            let itemIds: [UUID]
            let undoneAt: Date?
        }
        do {
            return try await database.transaction { database in
                let sql = try sqlDatabase(database)
                guard let action = try await sql.raw("""
                SELECT summary, inverse, item_ids, undone_at FROM actions
                WHERE id = \(bind: actionID) AND user_id = \(bind: userID.rawValue) FOR UPDATE
                """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)
                else { throw AppError.notFound("No such action.") }
                guard action.undoneAt == nil else { throw ActionConflict(message: "That action was already undone.") }
                let redo: LibraryOp
                do {
                    redo = try await Self.run(action.inverse, userID: userID, sql: sql)
                } catch let error as AppError where error.status == .notFound {
                    throw ActionConflict(message: "The library changed since; that action can no longer be undone.")
                }
                try await sql.raw("UPDATE actions SET undone_at = now() WHERE id = \(bind: actionID)").run()
                let entry = JournalEntry(
                    inverse: redo, itemIDs: action.itemIds.map(LibraryItemID.init), actor: .user,
                    kind: "undo", summary: "Undid: \(action.summary)", undoOf: actionID
                )
                return try await Self.journal(entry, userID: userID, sql: sql)
            }
        } catch let error as any DatabaseError where error.isConstraintFailure {
            throw ActionConflict(message: "The library changed since; that action can no longer be undone.")
        }
    }

    /// Runs one op inside the caller's transaction and returns its inverse.
    static func run(_ op: LibraryOp, userID: UserID, sql: any SQLDatabase) async throws -> LibraryOp {
        switch op {
        case .insertList, .deleteList, .renameList, .setListMembers:
            return try await runListOp(op, userID: userID, sql: sql)
        case let .batch(ops):
            var inverses: [LibraryOp] = []
            for child in ops {
                try await inverses.append(run(child, userID: userID, sql: sql))
            }
            return .batch(inverses.reversed())
        default:
            return try await runItemOp(op, userID: userID, sql: sql)
        }
    }

    private static func runItemOp(_ op: LibraryOp, userID: UserID, sql: any SQLDatabase) async throws -> LibraryOp {
        switch op {
        case let .insertItem(snapshot):
            try await insert(snapshot, userID: userID, sql: sql)
            return .deleteItem(snapshot.id)
        case let .deleteItem(id):
            return try await .insertItem(delete(id, userID: userID, sql: sql))
        case let .setFields(id, fields):
            let previous = try await lockedFields(id, userID: userID, sql: sql)
            try await sql.raw("""
            UPDATE library_items SET status = \(bind: fields.status.rawValue), rating = \(bind: fields.rating),
                notes = \(bind: fields.notes), is_owned = \(bind: fields.isOwned),
                finished_at = \(bind: fields.finishedAt), book_page = \(bind: fields.bookPage),
                book_percent = \(bind: fields.bookPercent), updated_at = now()
            WHERE id = \(bind: id.rawValue)
            """).run()
            return .setFields(id, previous)
        case let .setEpisodes(id, watch, unwatch):
            return try await setEpisodes(id, watch: watch, unwatch: unwatch, userID: userID, sql: sql)
        default:
            preconditionFailure("runItemOp got a non-item op")
        }
    }

    private static func setEpisodes(
        _ id: LibraryItemID,
        watch: [EpisodeKey],
        unwatch: [EpisodeKey],
        userID: UserID,
        sql: any SQLDatabase
    ) async throws -> LibraryOp {
        _ = try await lockedFields(id, userID: userID, sql: sql)
        let current = try await watchedKeys(id, sql: sql)
        let added = watch.filter { !current.contains($0) }
        let removed = unwatch.filter { current.contains($0) }
        for key in added {
            try await sql.raw("""
            INSERT INTO episode_progress (id, library_item_id, season, episode)
            VALUES (\(bind: UUID()), \(bind: id.rawValue), \(bind: key.season), \(bind: key.episode))
            ON CONFLICT (library_item_id, season, episode) DO NOTHING
            """).run()
        }
        for key in removed {
            try await sql.raw("""
            DELETE FROM episode_progress WHERE library_item_id = \(bind: id.rawValue)
            AND season = \(bind: key.season) AND episode = \(bind: key.episode)
            """).run()
        }
        try await sql.raw("UPDATE library_items SET updated_at = now() WHERE id = \(bind: id.rawValue)").run()
        return .setEpisodes(id, watch: removed, unwatch: added)
    }

    private static func insert(_ snapshot: ItemSnapshot, userID: UserID, sql: any SQLDatabase) async throws {
        let fields = snapshot.fields
        try await sql.raw("""
        INSERT INTO library_items (id, user_id, title_id, status, is_owned, rating, notes, added_at,
            updated_at, finished_at, book_page, book_percent)
        VALUES (\(bind: snapshot.id.rawValue), \(bind: userID.rawValue), \(bind: snapshot.titleID.rawValue),
            \(bind: fields.status.rawValue), \(bind: fields.isOwned), \(bind: fields.rating), \(bind: fields.notes),
            \(bind: snapshot.addedAt), now(), \(bind: fields.finishedAt), \(bind: fields.bookPage),
            \(bind: fields.bookPercent))
        """).run()
        for key in snapshot.watched {
            try await sql.raw("""
            INSERT INTO episode_progress (id, library_item_id, season, episode)
            VALUES (\(bind: UUID()), \(bind: snapshot.id.rawValue), \(bind: key.season), \(bind: key.episode))
            """).run()
        }
        try await sql.raw("""
        DELETE FROM library_tombstones
        WHERE user_id = \(bind: userID.rawValue) AND library_item_id = \(bind: snapshot.id.rawValue)
        """).run()
    }

    private static func delete(_ id: LibraryItemID, userID: UserID, sql: any SQLDatabase) async throws -> ItemSnapshot {
        struct Row: Decodable {
            let titleId: UUID
            let addedAt: Date
        }
        let fields = try await lockedFields(id, userID: userID, sql: sql)
        guard let row = try await sql
            .raw("SELECT title_id, added_at FROM library_items WHERE id = \(bind: id.rawValue)")
            .first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)
        else { throw AppError.notFound() }
        let watched = try await watchedKeys(id, sql: sql).sorted()
        try await sql.raw("DELETE FROM library_items WHERE id = \(bind: id.rawValue)").run()
        try await sql.raw("""
        INSERT INTO library_tombstones (user_id, library_item_id)
        VALUES (\(bind: userID.rawValue), \(bind: id.rawValue))
        ON CONFLICT (user_id, library_item_id) DO UPDATE SET deleted_at = now()
        """).run()
        return ItemSnapshot(
            id: id,
            titleID: TitleID(row.titleId),
            fields: fields,
            addedAt: row.addedAt,
            watched: watched
        )
    }

    /// Locks the user's item row and returns its fields. Another user's item is 404.
    private static func lockedFields(
        _ id: LibraryItemID,
        userID: UserID,
        sql: any SQLDatabase
    ) async throws -> ItemFields {
        guard let row = try await sql.raw("""
        SELECT status, rating, notes, is_owned, finished_at, book_page, book_percent FROM library_items
        WHERE id = \(bind: id.rawValue) AND user_id = \(bind: userID.rawValue) FOR UPDATE
        """).first(decoding: FieldsRow.self, keyDecodingStrategy: .convertFromSnakeCase),
            let fields = row.fields
        else { throw AppError.notFound() }
        return fields
    }

    static func watchedKeys(_ id: LibraryItemID, sql: any SQLDatabase) async throws -> Set<EpisodeKey> {
        struct Row: Decodable {
            let season: Int
            let episode: Int
        }
        let rows = try await sql
            .raw("SELECT season, episode FROM episode_progress WHERE library_item_id = \(bind: id.rawValue)")
            .all(decoding: Row.self)
        return Set(rows.compactMap { try? EpisodeKey(season: $0.season, episode: $0.episode) })
    }

    /// One `actions` row: the inverse of a write, and who made it.
    struct JournalEntry {
        var inverse: LibraryOp
        var itemIDs: [LibraryItemID]
        var actor: Actor
        var kind: String
        var summary: String
        var undoOf: UUID?
    }

    private static func journal(
        _ entry: JournalEntry,
        userID: UserID,
        sql: any SQLDatabase
    ) async throws -> ActionRecord {
        let id = UUID()
        let row = try await sql.raw("""
        INSERT INTO actions (id, user_id, actor, kind, summary, item_ids, inverse, undo_of)
        VALUES (\(bind: id), \(bind: userID.rawValue), \(bind: entry.actor.rawValue), \(bind: entry.kind),
            \(bind: entry.summary), \(bind: entry.itemIDs.map(\.rawValue)), \(bind: entry.inverse),
            \(bind: entry.undoOf))
        RETURNING created_at
        """).first(decoding: CreatedRow.self, keyDecodingStrategy: .convertFromSnakeCase)
        return ActionRecord(
            id: id, actor: entry.actor, kind: entry.kind, summary: entry.summary, itemIDs: entry.itemIDs,
            createdAt: row?.createdAt ?? Date(), undoneAt: nil, undoOf: entry.undoOf
        )
    }
}

private struct CreatedRow: Decodable {
    let createdAt: Date
}

private struct FieldsRow: Decodable {
    let status: String
    let rating: Double?
    let notes: String?
    let isOwned: Bool
    let finishedAt: Date?
    let bookPage: Int?
    let bookPercent: Double?

    var fields: ItemFields? {
        LibraryStatus(rawValue: status).map {
            ItemFields(
                status: $0, rating: rating, notes: notes, isOwned: isOwned, finishedAt: finishedAt,
                bookPage: bookPage, bookPercent: bookPercent
            )
        }
    }
}

extension LibraryOp {
    /// Items this op touches, for the journal's `item_ids`.
    var itemIDs: [LibraryItemID] {
        switch self {
        case let .insertItem(snapshot): [snapshot.id]
        case let .deleteItem(id), let .setFields(id, _), let .setEpisodes(id, _, _): [id]
        case .insertList, .deleteList, .renameList, .setListMembers: []
        case let .batch(ops): Array(Set(ops.flatMap(\.itemIDs)))
            .sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
        }
    }
}
