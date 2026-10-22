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

    func close(_ id: UUID, at date: Date) async throws {
        try await sql.raw("""
        UPDATE watch_events SET stopped_at = \(bind: date), state = 'stopped', updated_at = \(bind: date)
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

    func openSessions(userID: UserID, source: WatchSource?, limit: Int) async throws -> [OpenSession] {
        struct OpenRow: Decodable {
            let id: UUID
            let source: String
            let externalRef: String
            let titleId: UUID
            let itemId: UUID?
            let season: Int?
            let episode: Int?
            let episodeName: String?
            let runtimeMinutes: Int?
            let state: String
            let positionMs: Int64
            let durationMs: Int64
            let updatedAt: Date
        }
        let bySource: SQLQueryString = source.map { "AND we.source = \(bind: $0.rawValue)" } ?? ""
        return try await sql.raw("""
        SELECT we.id, we.source, we.external_ref, we.title_id, li.id AS item_id, we.season, we.episode,
            se.name AS episode_name, coalesce(se.runtime_minutes, t.runtime_minutes) AS runtime_minutes,
            we.state, we.position_ms, we.duration_ms, we.updated_at
        FROM watch_events we
        JOIN titles t ON t.id = we.title_id
        LEFT JOIN library_items li ON li.user_id = we.user_id AND li.title_id = we.title_id
        LEFT JOIN show_episodes se ON se.title_id = we.title_id AND se.season = we.season
            AND se.episode = we.episode
        WHERE we.user_id = \(bind: userID.rawValue) AND we.stopped_at IS NULL \(bySource)
        ORDER BY we.updated_at DESC
        LIMIT \(literal: limit)
        """).all(decoding: OpenRow.self, keyDecodingStrategy: .convertFromSnakeCase).compactMap { row in
            guard let source = WatchSource(rawValue: row.source),
                  let state = OpenSession.State(rawValue: row.state)
            else { return nil }
            let episode = row.season.flatMap { season in
                row.episode.flatMap { try? EpisodeKey(season: season, episode: $0) }
            }
            return OpenSession(
                id: row.id, source: source, externalRef: row.externalRef, titleID: TitleID(row.titleId),
                libraryItemID: row.itemId.map(LibraryItemID.init), episode: episode,
                episodeName: row.episodeName, runtimeMinutes: row.runtimeMinutes, state: state,
                positionMs: row.positionMs, durationMs: row.durationMs, updatedAt: row.updatedAt
            )
        }
    }

    func claimLiveActivityStart(_ id: UUID, at date: Date) async throws -> Bool {
        struct Found: Decodable { let id: UUID }
        return try await sql.raw("""
        UPDATE watch_events SET live_activity_started_at = \(bind: date)
        WHERE id = \(bind: id) AND live_activity_started_at IS NULL
        RETURNING id
        """).first(decoding: Found.self) != nil
    }

    func registerLiveActivity(_ token: LiveActivityToken, userID: UserID, now: Date) async throws -> Bool {
        struct Found: Decodable { let token: String }
        return try await sql.raw("""
        INSERT INTO live_activity_tokens (token, user_id, kind, environment, topic, watch_event_id, updated_at)
        SELECT \(bind: token.token), \(bind: userID.rawValue), \(bind: token.kind.rawValue),
            \(bind: token.environment.rawValue), \(bind: token.topic), \(bind: token.watchEventID), \(bind: now)
        WHERE \(bind: token.watchEventID)::uuid IS NULL OR EXISTS (
            SELECT 1 FROM watch_events WHERE id = \(bind: token.watchEventID) AND user_id = \(bind: userID.rawValue)
        )
        ON CONFLICT (token) DO UPDATE SET user_id = EXCLUDED.user_id, kind = EXCLUDED.kind,
            environment = EXCLUDED.environment, topic = EXCLUDED.topic,
            watch_event_id = EXCLUDED.watch_event_id, updated_at = EXCLUDED.updated_at
        RETURNING token
        """).first(decoding: Found.self) != nil
    }

    func liveActivityStartTokens(userID: UserID) async throws -> [LiveActivityToken] {
        try await tokens(where: "user_id = \(bind: userID.rawValue) AND kind = 'start'")
    }

    func liveActivityUpdateTokens(watchEventID: UUID) async throws -> [LiveActivityToken] {
        try await tokens(where: "watch_event_id = \(bind: watchEventID) AND kind = 'update'")
    }

    func forgetLiveActivity(token: String) async throws {
        try await sql.raw("DELETE FROM live_activity_tokens WHERE token = \(bind: token)").run()
    }

    private func tokens(where filter: SQLQueryString) async throws -> [LiveActivityToken] {
        struct TokenRow: Decodable {
            let token: String
            let kind: String
            let environment: String
            let topic: String
            let watchEventId: UUID?
        }
        return try await sql.raw("""
        SELECT token, kind, environment, topic, watch_event_id FROM live_activity_tokens WHERE \(filter)
        """).all(decoding: TokenRow.self, keyDecodingStrategy: .convertFromSnakeCase).compactMap { row in
            guard let kind = LiveActivityToken.Kind(rawValue: row.kind),
                  let environment = PushEnvironment(rawValue: row.environment)
            else { return nil }
            return LiveActivityToken(
                token: row.token, kind: kind, environment: environment, topic: row.topic,
                watchEventID: row.watchEventId
            )
        }
    }
}
