import AaruCore
import FluentKit
import FluentSQL
import Foundation

struct PostgresAgentStore: AgentStore {
    let sql: any SQLDatabase

    /// States that count toward the caps: the model was, or will be, called.
    private static let counted: SQLQueryString = "state IN ('queued', 'running', 'done', 'failed')"

    func enqueue(_ job: AgentReplyJob, state: AgentReplyState, now: Date) async throws {
        try await sql.raw("""
        INSERT INTO agent_replies (id, message_id, group_id, channel_id, tagger_id, state, created_at, updated_at)
        VALUES (\(bind: job.id), \(bind: job.messageID), \(bind: job.groupID), \(bind: job.channelID),
                \(bind: job.tagger.rawValue), \(bind: state.rawValue), \(bind: now), \(bind: now))
        ON CONFLICT (message_id) DO NOTHING
        """).run()
    }

    func load(tagger: UserID, group: UUID, dayStart: Date, hourStart: Date) async throws -> AgentLoad {
        struct Row: Decodable {
            let userToday: Int
            let groupHour: Int
            let userNoted: Bool
            let groupNoted: Bool
        }
        let row = try await sql.raw("""
        SELECT
            (SELECT count(*) FROM agent_replies WHERE tagger_id = \(bind: tagger.rawValue)
                AND created_at >= \(bind: dayStart) AND \(Self.counted)) AS user_today,
            (SELECT count(*) FROM agent_replies WHERE group_id = \(bind: group)
                AND created_at >= \(bind: hourStart) AND \(Self.counted)) AS group_hour,
            EXISTS (SELECT 1 FROM agent_replies WHERE tagger_id = \(bind: tagger.rawValue)
                AND created_at >= \(bind: dayStart) AND state = 'capped') AS user_noted,
            EXISTS (SELECT 1 FROM agent_replies WHERE group_id = \(bind: group)
                AND created_at >= \(bind: hourStart) AND state = 'capped') AS group_noted
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)
        return AgentLoad(
            userToday: row?.userToday ?? 0, groupHour: row?.groupHour ?? 0, userNoted: row?.userNoted ?? false,
            groupNoted: row?.groupNoted ?? false
        )
    }

    func claim(now: Date, lease: TimeInterval) async throws -> AgentReplyJob? {
        struct Row: Decodable {
            let id: UUID
            let messageId: UUID
            let groupId: UUID
            let channelId: UUID
            let taggerId: UUID
            let attempts: Int
        }
        // One statement: SKIP LOCKED means two workers never lease the same mention.
        return try await sql.raw("""
        UPDATE agent_replies SET state = 'running', attempts = attempts + 1,
            locked_until = \(bind: now.addingTimeInterval(lease)), updated_at = \(bind: now)
        WHERE id = (
            SELECT id FROM agent_replies
            WHERE (state = 'queued' AND (locked_until IS NULL OR locked_until <= \(bind: now)))
               OR (state = 'running' AND locked_until < \(bind: now))
            ORDER BY created_at
            FOR UPDATE SKIP LOCKED
            LIMIT 1
        )
        RETURNING id, message_id, group_id, channel_id, tagger_id, attempts
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase).map {
            AgentReplyJob(
                id: $0.id, messageID: $0.messageId, groupID: $0.groupId, channelID: $0.channelId,
                tagger: UserID($0.taggerId), attempts: $0.attempts
            )
        }
    }

    func finish(_ id: UUID, state: AgentReplyState, error: String?, now: Date) async throws {
        try await sql.raw("""
        UPDATE agent_replies SET state = \(bind: state.rawValue), error = \(bind: error), locked_until = NULL,
            updated_at = \(bind: now)
        WHERE id = \(bind: id)
        """).run()
    }

    func retry(_ id: UUID, error: String, notBefore: Date, now: Date) async throws {
        try await sql.raw("""
        UPDATE agent_replies SET state = 'queued', error = \(bind: error), locked_until = \(bind: notBefore),
            updated_at = \(bind: now)
        WHERE id = \(bind: id)
        """).run()
    }

    func recordUsage(_ user: UserID, day: Date, inputTokens: Int, outputTokens: Int, costMicros: Int) async throws {
        try await sql.raw("""
        INSERT INTO agent_usage (user_id, day, requests, input_tokens, output_tokens, cost_micros)
        VALUES (\(bind: user.rawValue), (\(bind: day) AT TIME ZONE 'UTC')::date, 1, \(bind: inputTokens),
                \(bind: outputTokens), \(bind: costMicros))
        ON CONFLICT (user_id, day) DO UPDATE SET requests = agent_usage.requests + 1,
            input_tokens = agent_usage.input_tokens + EXCLUDED.input_tokens,
            output_tokens = agent_usage.output_tokens + EXCLUDED.output_tokens,
            cost_micros = agent_usage.cost_micros + EXCLUDED.cost_micros
        """).run()
    }

    func usage(_ user: UserID, day: Date) async throws -> AgentUsage {
        struct Row: Decodable {
            let requests: Int
            let inputTokens: Int
            let outputTokens: Int
            let costMicros: Int
        }
        let row = try await sql.raw("""
        SELECT requests, input_tokens, output_tokens, cost_micros FROM agent_usage
        WHERE user_id = \(bind: user.rawValue) AND day = (\(bind: day) AT TIME ZONE 'UTC')::date
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)
        return AgentUsage(
            requests: row?.requests ?? 0, inputTokens: row?.inputTokens ?? 0, outputTokens: row?.outputTokens ?? 0,
            costMicros: row?.costMicros ?? 0
        )
    }
}
