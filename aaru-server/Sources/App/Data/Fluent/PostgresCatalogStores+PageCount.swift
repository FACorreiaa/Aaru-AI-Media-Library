import AaruCore
import FluentSQL
import Foundation

/// APP-017 · the page-count backfill's two queries.
extension PostgresTitleStore {
    /// Books on a shelf with no page count, in-progress ones first, not asked since `retryAfter`.
    func booksMissingPageCount(retryAfter: Date, limit: Int) async throws -> [Title] {
        struct IDRow: Decodable { let id: UUID }
        let ids = try await sql.raw("""
        SELECT t.id FROM titles t
        WHERE t.type = 'book' AND t.page_count IS NULL
          AND (t.page_count_attempted_at IS NULL OR t.page_count_attempted_at < \(bind: retryAfter))
          AND EXISTS (SELECT 1 FROM library_items li WHERE li.title_id = t.id)
        ORDER BY EXISTS (
                SELECT 1 FROM library_items li WHERE li.title_id = t.id AND li.status = 'in_progress'
            ) DESC,
            t.page_count_attempted_at NULLS FIRST, t.created_at, t.id
        LIMIT \(literal: limit)
        """).all(decoding: IDRow.self).map { TitleID($0.id) }
        return try await titles(ids: ids)
    }

    func fillPageCount(_ id: TitleID, _ pageCount: Int?, attemptedAt: Date) async throws {
        try await sql.raw("""
        UPDATE titles
        SET page_count = coalesce(page_count, \(bind: pageCount)), page_count_attempted_at = \(bind: attemptedAt)
        WHERE id = \(bind: id.rawValue)
        """).run()
    }
}
