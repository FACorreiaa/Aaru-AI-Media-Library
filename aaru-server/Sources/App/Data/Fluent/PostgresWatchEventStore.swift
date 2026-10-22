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

    func registerLiveActivity(_ token: LiveActivityToken, userID: UserID, now: Date) async throws {
        try await sql.raw("""
        INSERT INTO live_activity_tokens (token, user_id, kind, environment, topic, updated_at)
        VALUES (\(bind: token.token), \(bind: userID.rawValue), \(bind: token.kind.rawValue),
            \(bind: token.environment.rawValue), \(bind: token.topic), \(bind: now))
        ON CONFLICT (token) DO UPDATE SET user_id = EXCLUDED.user_id, kind = EXCLUDED.kind,
            environment = EXCLUDED.environment, topic = EXCLUDED.topic, updated_at = EXCLUDED.updated_at
        """).run()
    }

    func hasLiveActivityTokens(userID: UserID) async throws -> Bool {
        struct Found: Decodable { let token: String }
        return try await sql.raw("""
        SELECT token FROM live_activity_tokens WHERE user_id = \(bind: userID.rawValue) LIMIT 1
        """).first(decoding: Found.self) != nil
    }

    func liveActivityStartTokens(userID: UserID) async throws -> [LiveActivityToken] {
        try await tokens(where: "user_id = \(bind: userID.rawValue) AND kind = 'start'")
    }

    func liveActivityUpdateTokens(userID: UserID) async throws -> [LiveActivityToken] {
        try await tokens(where: "user_id = \(bind: userID.rawValue) AND kind = 'update'")
    }

    func forgetLiveActivity(token: String) async throws {
        try await sql.raw("DELETE FROM live_activity_tokens WHERE token = \(bind: token)").run()
    }

    func forgetLiveActivityUpdates(userID: UserID) async throws {
        try await sql.raw("""
        DELETE FROM live_activity_tokens WHERE user_id = \(bind: userID.rawValue) AND kind = 'update'
        """).run()
    }

    func savePlay(_ play: LivePlay, userID: UserID, agentTokenID: UUID) async throws {
        try await sql.raw("""
        INSERT INTO live_plays
            (user_id, agent_token_id, kind, id, source, ref, title, subtitle, service, artwork_url, origin_url,
             state, position_ms, duration_ms, started_at, updated_at, expires_at)
        VALUES (\(bind: userID.rawValue), \(bind: agentTokenID), \(bind: play.kind.rawValue), \(bind: play.id),
                \(bind: play.source.rawValue), \(bind: play.ref), \(bind: play.title), \(bind: play.subtitle),
                \(bind: play.service), \(bind: play.artworkURL), \(bind: play.originURL), \(bind: play.state.rawValue),
                \(bind: play.positionMs), \(bind: play.durationMs), \(bind: play.startedAt), \(bind: play.updatedAt),
                \(bind: play.expiresAt))
        ON CONFLICT (user_id, kind, agent_token_id) DO UPDATE SET
            id = CASE WHEN live_plays.ref = EXCLUDED.ref THEN live_plays.id ELSE EXCLUDED.id END,
            started_at = CASE WHEN live_plays.ref = EXCLUDED.ref THEN live_plays.started_at
                ELSE EXCLUDED.started_at END,
            source = EXCLUDED.source, ref = EXCLUDED.ref, title = EXCLUDED.title, subtitle = EXCLUDED.subtitle,
            service = EXCLUDED.service, artwork_url = EXCLUDED.artwork_url, origin_url = EXCLUDED.origin_url,
            state = EXCLUDED.state, position_ms = EXCLUDED.position_ms, duration_ms = EXCLUDED.duration_ms,
            updated_at = EXCLUDED.updated_at, expires_at = EXCLUDED.expires_at
        """).run()
    }

    func removePlay(_ kind: LivePlay.Kind, userID: UserID, agentTokenID: UUID) async throws {
        try await sql.raw("""
        DELETE FROM live_plays WHERE user_id = \(bind: userID.rawValue) AND kind = \(bind: kind.rawValue)
            AND agent_token_id = \(bind: agentTokenID)
        """).run()
    }

    func livePlays(userID: UserID, now: Date) async throws -> [LivePlay] {
        struct PlayRow: Decodable {
            let id: UUID
            let kind: String
            let source: String
            let ref: String
            let title: String
            let subtitle: String?
            let service: String?
            let artworkUrl: String?
            let originUrl: String?
            let state: String
            let positionMs: Int64
            let durationMs: Int64
            let startedAt: Date
            let updatedAt: Date
            let expiresAt: Date
        }
        try await sql.raw("""
        DELETE FROM live_plays WHERE user_id = \(bind: userID.rawValue) AND expires_at <= \(bind: now)
        """).run()
        return try await sql.raw("""
        SELECT id, kind, source, ref, title, subtitle, service, artwork_url, origin_url, state, position_ms,
            duration_ms, started_at, updated_at, expires_at
        FROM live_plays WHERE user_id = \(bind: userID.rawValue)
        ORDER BY updated_at DESC
        """).all(decoding: PlayRow.self, keyDecodingStrategy: .convertFromSnakeCase).compactMap { row in
            guard let kind = LivePlay.Kind(rawValue: row.kind), let source = LivePlay.Source(rawValue: row.source),
                  let state = OpenSession.State(rawValue: row.state)
            else { return nil }
            return LivePlay(
                id: row.id, kind: kind, source: source, ref: row.ref, title: row.title, subtitle: row.subtitle,
                service: row.service, artworkURL: row.artworkUrl, originURL: row.originUrl, state: state,
                positionMs: row.positionMs, durationMs: row.durationMs, startedAt: row.startedAt,
                updatedAt: row.updatedAt, expiresAt: row.expiresAt
            )
        }
    }

    func liveActivityState(userID: UserID) async throws -> LiveActivityState {
        struct StateRow: Decodable {
            let pushed: String?
            let lingering: String
            let version: Int
            let nextCheckAt: Date?
        }
        try await sql.raw("""
        INSERT INTO live_activity_states (user_id) VALUES (\(bind: userID.rawValue)) ON CONFLICT DO NOTHING
        """).run()
        guard let row = try await sql.raw("""
        SELECT pushed::text AS pushed, lingering::text AS lingering, version, next_check_at
        FROM live_activity_states WHERE user_id = \(bind: userID.rawValue)
        """).first(decoding: StateRow.self, keyDecodingStrategy: .convertFromSnakeCase)
        else { return .fresh }
        let decoder = JSONDecoder()
        return try LiveActivityState(
            pushed: row.pushed.map { try decoder.decode(NowPlayingActivityState.self, from: Data($0.utf8)) },
            lingering: decoder.decode([LiveActivityState.Lingering].self, from: Data(row.lingering.utf8)),
            version: row.version, nextCheckAt: row.nextCheckAt
        )
    }

    func saveLiveActivityState(_ state: LiveActivityState, userID: UserID) async throws -> Bool {
        struct Found: Decodable { let version: Int }
        let encoder = JSONEncoder()
        let pushed = try state.pushed.flatMap { try String(bytes: encoder.encode($0), encoding: .utf8) }
        let lingering = try String(bytes: encoder.encode(state.lingering), encoding: .utf8) ?? "[]"
        return try await sql.raw("""
        UPDATE live_activity_states SET pushed = \(bind: pushed)::jsonb, lingering = \(bind: lingering)::jsonb,
            version = version + 1, next_check_at = \(bind: state.nextCheckAt)
        WHERE user_id = \(bind: userID.rawValue) AND version = \(bind: state.version)
        RETURNING version
        """).first(decoding: Found.self) != nil
    }

    func scheduleLiveActivityCheck(userID: UserID, at date: Date) async throws {
        try await sql.raw("""
        UPDATE live_activity_states SET next_check_at = \(bind: date)
        WHERE user_id = \(bind: userID.rawValue) AND (next_check_at IS NULL OR next_check_at > \(bind: date))
        """).run()
    }

    func claimDueLiveActivityChecks(now: Date, limit: Int) async throws -> [UserID] {
        struct Due: Decodable { let userId: UUID }
        return try await sql.raw("""
        UPDATE live_activity_states SET next_check_at = NULL
        WHERE user_id IN (
            SELECT user_id FROM live_activity_states WHERE next_check_at <= \(bind: now)
            ORDER BY next_check_at LIMIT \(literal: limit) FOR UPDATE SKIP LOCKED
        )
        RETURNING user_id
        """).all(decoding: Due.self, keyDecodingStrategy: .convertFromSnakeCase).map { UserID($0.userId) }
    }

    private func tokens(where filter: SQLQueryString) async throws -> [LiveActivityToken] {
        struct TokenRow: Decodable {
            let token: String
            let kind: String
            let environment: String
            let topic: String
        }
        return try await sql.raw("""
        SELECT token, kind, environment, topic FROM live_activity_tokens WHERE \(filter)
        """).all(decoding: TokenRow.self, keyDecodingStrategy: .convertFromSnakeCase).compactMap { row in
            guard let kind = LiveActivityToken.Kind(rawValue: row.kind),
                  let environment = PushEnvironment(rawValue: row.environment)
            else { return nil }
            return LiveActivityToken(token: row.token, kind: kind, environment: environment, topic: row.topic)
        }
    }
}
