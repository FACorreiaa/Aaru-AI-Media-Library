import AaruCore
import FluentKit
import FluentSQL
import Foundation

/// Tonight's reads and its two small tables (AG-005).
struct PostgresTonightStore: TonightStore {
    let sql: any SQLDatabase

    func reading(userID: UserID, limit: Int) async throws -> [ReadingEntry] {
        let query: SQLQueryString = """
        SELECT li.id AS item_id, \(PostgresScheduleStore.titleColumns), t.page_count, li.book_page,
            li.book_percent, li.updated_at
        FROM library_items li JOIN titles t ON t.id = li.title_id AND t.type = 'book'
        WHERE li.user_id = \(bind: userID.rawValue) AND li.status = 'in_progress'
        ORDER BY li.updated_at DESC, li.id DESC
        LIMIT \(literal: limit)
        """
        return try await sql.raw(query).all(decoding: ReadingRow.self, keyDecodingStrategy: .convertFromSnakeCase)
            .compactMap { row in
                row.title.asTitle.map {
                    ReadingEntry(
                        libraryItemID: LibraryItemID(row.itemId), title: $0, pageCount: row.pageCount,
                        bookPage: row.bookPage, bookPercent: row.bookPercent, lastChange: row.updatedAt
                    )
                }
            }
    }

    func itemDates(_ ids: [LibraryItemID], userID: UserID) async throws -> [LibraryItemID: ItemDates] {
        struct Row: Decodable {
            let id: UUID
            let addedAt: Date
            let updatedAt: Date
        }
        guard !ids.isEmpty else { return [:] }
        let rows = try await sql.raw("""
        SELECT id, added_at, updated_at FROM library_items
        WHERE user_id = \(bind: userID.rawValue) AND id = ANY(\(bind: ids.map(\.rawValue)))
        """).all(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)
        return Dictionary(uniqueKeysWithValues: rows.map {
            (LibraryItemID($0.id), ItemDates(addedAt: $0.addedAt, lastChange: $0.updatedAt))
        })
    }

    func feedback(userID: UserID, since: Date) async throws -> [TonightFeedback] {
        struct Row: Decodable {
            let libraryItemId: UUID
            let verdict: String
            let day: String
            let createdAt: Date
        }
        return try await sql.raw("""
        SELECT library_item_id, verdict, day::text AS day, created_at FROM tonight_feedback
        WHERE user_id = \(bind: userID.rawValue) AND created_at >= \(bind: since)
        ORDER BY created_at
        """).all(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase).compactMap { row in
            guard let verdict = TonightVerdict(rawValue: row.verdict), let day = LocalDay(row.day) else { return nil }
            return TonightFeedback(
                libraryItemID: LibraryItemID(row.libraryItemId), verdict: verdict, day: day, createdAt: row.createdAt
            )
        }
    }

    func saveFeedback(_ feedback: TonightFeedback, userID: UserID) async throws -> TonightFeedback? {
        struct Row: Decodable { let id: UUID }
        // Through `library_items`, so an item that is not the user's writes nothing.
        let row = try await sql.raw("""
        INSERT INTO tonight_feedback (id, user_id, library_item_id, verdict, day, created_at)
        SELECT \(bind: UUID()), li.user_id, li.id, \(bind: feedback.verdict.rawValue),
            \(bind: feedback.day.description)::date, \(bind: feedback.createdAt)
        FROM library_items li
        WHERE li.id = \(bind: feedback.libraryItemID.rawValue) AND li.user_id = \(bind: userID.rawValue)
        RETURNING id
        """).first(decoding: Row.self)
        return row == nil ? nil : feedback
    }

    func clearFeedback(itemID: LibraryItemID, day: LocalDay, userID: UserID) async throws {
        try await sql.raw("""
        DELETE FROM tonight_feedback
        WHERE user_id = \(bind: userID.rawValue) AND library_item_id = \(bind: itemID.rawValue)
          AND day = \(bind: day.description)::date
        """).run()
    }

    func recordPicks(_ ids: [LibraryItemID], day: LocalDay, userID: UserID, servedAt: Date) async throws -> Bool {
        struct Row: Decodable { let shown: Bool }
        guard !ids.isEmpty else { return false }
        let before = try await sql.raw("""
        SELECT EXISTS (
            SELECT 1 FROM tonight_picks
            WHERE user_id = \(bind: userID.rawValue) AND day = \(bind: day.description)::date
        ) AS shown
        """).first(decoding: Row.self)
        for (rank, id) in ids.enumerated() {
            try await sql.raw("""
            INSERT INTO tonight_picks (user_id, day, library_item_id, rank, served_at)
            VALUES (\(bind: userID.rawValue), \(bind: day.description)::date, \(bind: id.rawValue), \(bind: rank),
                \(bind: servedAt))
            ON CONFLICT (user_id, day, library_item_id)
                DO UPDATE SET rank = EXCLUDED.rank, served_at = EXCLUDED.served_at
            """).run()
        }
        return before?.shown == false
    }
}

extension PostgresTonightStore {
    /// After a progress write on `ids`: marks picks shown in the last six hours as taken. Returns
    /// the days on which this is the first pick taken, which is what `tonight_accepted` counts.
    static func acceptPicks(_ ids: [LibraryItemID], userID: UserID, sql: any SQLDatabase) async throws -> [String] {
        struct Row: Decodable { let day: String }
        guard !ids.isEmpty else { return [] }
        // The outer SELECT reads the snapshot before the UPDATE: "already taken" means taken earlier.
        return try await sql.raw("""
        WITH taken AS (
            UPDATE tonight_picks SET accepted_at = now()
            WHERE user_id = \(bind: userID.rawValue) AND library_item_id = ANY(\(bind: ids.map(\.rawValue)))
              AND accepted_at IS NULL AND served_at > now() - interval '6 hours'
            RETURNING day
        )
        SELECT DISTINCT taken.day::text AS day FROM taken
        WHERE NOT EXISTS (
            SELECT 1 FROM tonight_picks p
            WHERE p.user_id = \(bind: userID.rawValue) AND p.day = taken.day AND p.accepted_at IS NOT NULL
        )
        """).all(decoding: Row.self).map(\.day)
    }
}

extension PostgresLibraryStore {
    /// Kinds that are progress on an item: episode, season and whole-show ticks, and field edits
    /// (status, pages).
    static let progressKinds: Set<String> = ["episode", "season", "show", "update"]

    /// Counts a committed write: the library action, and, when it is progress on a Tonight pick
    /// shown in the last six hours, that pick as taken (AG-005). Counting never fails or slows the
    /// write it follows, so errors are dropped.
    func countWrite(_ ids: [LibraryItemID], kind: String, actor: Actor, userID: UserID) async {
        ProductEvents.capture(.libraryAction, userID: userID, ["kind": kind, "actor": actor.rawValue])
        guard Self.progressKinds.contains(kind), let sql = try? sqlDatabase(database),
              let days = try? await PostgresTonightStore.acceptPicks(ids, userID: userID, sql: sql)
        else { return }
        for _ in days {
            ProductEvents.capture(.tonightAccepted, userID: userID)
        }
    }
}

private struct ReadingRow: Decodable {
    let itemId: UUID
    let title: TitleColumns
    let pageCount: Int?
    let bookPage: Int?
    let bookPercent: Double?
    let updatedAt: Date

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        itemId = try container.decode(UUID.self, forKey: .itemId)
        pageCount = try container.decodeIfPresent(Int.self, forKey: .pageCount)
        bookPage = try container.decodeIfPresent(Int.self, forKey: .bookPage)
        bookPercent = try container.decodeIfPresent(Double.self, forKey: .bookPercent)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        title = try TitleColumns(from: decoder)
    }

    enum CodingKeys: String, CodingKey {
        case itemId, pageCount, bookPage, bookPercent, updatedAt
    }
}
