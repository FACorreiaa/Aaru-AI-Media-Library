import AaruCore
import FluentSQL
import Foundation

struct PostgresWatchEventStore: WatchEventStore {
    let sql: any SQLDatabase

    private struct Row: Decodable {
        let id: UUID
        let titleId: UUID?
        let positionMs: Int64
        let durationMs: Int64
    }

    func record(
        _ report: PlaybackReport, titleID: TitleID?, userID: UserID, agentTokenID: UUID?, now: Date
    ) async throws -> WatchSession {
        let row = try await sql.raw("""
        INSERT INTO watch_events
            (id, user_id, agent_token_id, source, external_ref, title_id, season, episode, state,
             position_ms, duration_ms, started_at, updated_at)
        VALUES (\(bind: UUID()), \(bind: userID.rawValue), \(bind: agentTokenID), \(bind: report.source.rawValue),
                \(bind: report.externalRef), \(bind: titleID?.rawValue), \(bind: report.episode?.season),
                \(bind: report.episode?.episode), \(bind: report.action.state), \(bind: report.positionMs),
                \(bind: report.durationMs), \(bind: now), \(bind: now))
        ON CONFLICT (user_id, source, external_ref) WHERE stopped_at IS NULL DO UPDATE SET
            state = EXCLUDED.state,
            position_ms = EXCLUDED.position_ms,
            duration_ms = greatest(watch_events.duration_ms, EXCLUDED.duration_ms),
            title_id = coalesce(EXCLUDED.title_id, watch_events.title_id),
            updated_at = EXCLUDED.updated_at
        RETURNING id, title_id, position_ms, duration_ms
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)
        guard let row else { throw AppError.notFound() }
        return WatchSession(
            id: row.id, titleID: row.titleId.map(TitleID.init), positionMs: row.positionMs, durationMs: row.durationMs
        )
    }

    func close(_ id: UUID, at: Date) async throws {
        try await sql.raw("""
        UPDATE watch_events SET stopped_at = \(bind: at), state = 'stopped', updated_at = \(bind: at)
        WHERE id = \(bind: id)
        """).run()
    }

    func stoppedRecently(userID: UserID, source: WatchSource, externalRef: String, since: Date) async throws -> Bool {
        struct Found: Decodable { let id: UUID }
        return try await sql.raw("""
        SELECT id FROM watch_events
        WHERE user_id = \(bind: userID.rawValue) AND source = \(bind: source.rawValue)
          AND external_ref = \(bind: externalRef) AND stopped_at >= \(bind: since)
        LIMIT 1
        """).first(decoding: Found.self) != nil
    }
}
