import AaruCore
import FluentSQL
import Foundation

struct PostgresAgentTokenStore: AgentTokenStore {
    let sql: any SQLDatabase

    private struct Row: Decodable {
        let id: UUID
        let userId: UUID
        let name: String
        let kind: String
        let scopes: [String]
        let createdAt: Date
        let lastUsedAt: Date?

        var token: AgentToken? {
            guard let kind = AgentTokenKind(rawValue: kind) else { return nil }
            return AgentToken(
                id: id, name: name, kind: kind, scopes: Set(scopes.compactMap(AgentScope.init(rawValue:))),
                createdAt: createdAt, lastUsedAt: lastUsedAt
            )
        }
    }

    private static let columns = "id, user_id, name, kind, scopes, created_at, last_used_at"

    func create(_ token: AgentToken, tokenHash: String, userID: UserID) async throws {
        try await sql.raw("""
        INSERT INTO agent_tokens (id, user_id, name, kind, token_hash, scopes, created_at)
        VALUES (\(bind: token.id), \(bind: userID.rawValue), \(bind: token.name), \(bind: token.kind.rawValue),
                \(bind: tokenHash), \(bind: token.scopes.map(\.rawValue).sorted()), \(bind: token.createdAt))
        """).run()
    }

    func tokens(userID: UserID) async throws -> [AgentToken] {
        try await sql.raw("""
        SELECT \(unsafeRaw: Self.columns) FROM agent_tokens
        WHERE user_id = \(bind: userID.rawValue) AND revoked_at IS NULL
        ORDER BY created_at DESC
        """).all(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase).compactMap(\.token)
    }

    func revoke(id: UUID, userID: UserID, now: Date) async throws -> Bool {
        struct Revoked: Decodable { let id: UUID }
        // A revoked token's waiting plans expire with it: nothing it asked for lands later.
        return try await sql.raw("""
        WITH revoked AS (
            UPDATE agent_tokens SET revoked_at = \(bind: now)
            WHERE id = \(bind: id) AND user_id = \(bind: userID.rawValue) AND revoked_at IS NULL
            RETURNING id
        ), expired AS (
            UPDATE agent_plans SET status = 'expired', decided_at = \(bind: now)
            WHERE agent_token_id IN (SELECT id FROM revoked) AND status = 'pending'
        )
        SELECT id FROM revoked
        """).first(decoding: Revoked.self) != nil
    }

    func token(forHash hash: String, now: Date) async throws -> (token: AgentToken, userID: UserID)? {
        guard let row = try await sql.raw("""
        SELECT \(unsafeRaw: Self.columns) FROM agent_tokens
        WHERE token_hash = \(bind: hash) AND revoked_at IS NULL
          AND (expires_at IS NULL OR expires_at > \(bind: now))
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase),
            let token = row.token
        else { return nil }
        return (token, UserID(row.userId))
    }

    func touch(id: UUID, at date: Date) async throws {
        try await sql.raw("UPDATE agent_tokens SET last_used_at = \(bind: date) WHERE id = \(bind: id)").run()
    }
}
