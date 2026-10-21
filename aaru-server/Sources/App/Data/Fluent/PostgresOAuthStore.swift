import AaruCore
import FluentKit
import FluentSQL
import Foundation

struct PostgresOAuthStore: OAuthStore {
    let database: any Database

    private var sql: any SQLDatabase {
        get throws { try sqlDatabase(database) }
    }

    func register(_ client: OAuthClient) async throws {
        try await sql.raw("""
        INSERT INTO oauth_clients (id, name, redirect_uris, created_at)
        VALUES (\(bind: client.id), \(bind: client.name), \(bind: client.redirectURIs), \(bind: client.createdAt))
        """).run()
    }

    func client(id: String) async throws -> OAuthClient? {
        struct Row: Decodable {
            let id: String
            let name: String
            let redirectUris: [String]
            let createdAt: Date
        }
        return try await sql.raw("""
        SELECT id, name, redirect_uris, created_at FROM oauth_clients WHERE id = \(bind: id)
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase).map {
            OAuthClient(id: $0.id, name: $0.name, redirectURIs: $0.redirectUris, createdAt: $0.createdAt)
        }
    }

    func createRequest(_ request: OAuthRequest) async throws {
        try await sql.raw("""
        INSERT INTO oauth_requests (id, client_id, redirect_uri, state, code_challenge, resource, binding_hash,
            expires_at)
        VALUES (\(bind: request.id), \(bind: request.clientID), \(bind: request.redirectURI), \(bind: request.state),
            \(bind: request.codeChallenge), \(bind: request.resource), \(bind: request.bindingHash),
            \(bind: request.expiresAt))
        """).run()
    }

    private struct RequestRow: Decodable {
        let id: UUID
        let clientId: String
        let redirectUri: String
        let state: String?
        let codeChallenge: String
        let resource: String?
        let bindingHash: String
        let expiresAt: Date

        var request: OAuthRequest {
            OAuthRequest(
                id: id, clientID: clientId, redirectURI: redirectUri, state: state, codeChallenge: codeChallenge,
                resource: resource, bindingHash: bindingHash, expiresAt: expiresAt
            )
        }
    }

    private static let requestColumns =
        "id, client_id, redirect_uri, state, code_challenge, resource, binding_hash, expires_at"

    func request(id: UUID, now: Date) async throws -> OAuthRequest? {
        try await sql.raw("""
        SELECT \(unsafeRaw: Self.requestColumns) FROM oauth_requests
        WHERE id = \(bind: id) AND consumed_at IS NULL AND expires_at > \(bind: now)
        """).first(decoding: RequestRow.self, keyDecodingStrategy: .convertFromSnakeCase)?.request
    }

    func consumeRequest(id: UUID, now: Date) async throws -> OAuthRequest? {
        try await sql.raw("""
        UPDATE oauth_requests SET consumed_at = \(bind: now)
        WHERE id = \(bind: id) AND consumed_at IS NULL AND expires_at > \(bind: now)
        RETURNING \(unsafeRaw: Self.requestColumns)
        """).first(decoding: RequestRow.self, keyDecodingStrategy: .convertFromSnakeCase)?.request
    }

    func createCode(_ code: OAuthCode, hash: String) async throws {
        try await sql.raw("""
        INSERT INTO oauth_codes (code_hash, client_id, user_id, redirect_uri, code_challenge, resource, name, kind,
            allow_writes, expires_at)
        VALUES (\(bind: hash), \(bind: code.clientID), \(bind: code.userID.rawValue), \(bind: code.redirectURI),
            \(bind: code.codeChallenge), \(bind: code.resource), \(bind: code.name), \(bind: code.kind.rawValue),
            \(bind: code.allowWrites), \(bind: code.expiresAt))
        """).run()
    }

    func redeemCode(hash: String, now: Date) async throws -> CodeRedemption? {
        struct Row: Decodable {
            let clientId: String
            let userId: UUID
            let redirectUri: String
            let codeChallenge: String
            let resource: String?
            let name: String
            let kind: String
            let allowWrites: Bool
            let expiresAt: Date
            let consumedAt: Date?
            let agentTokenId: UUID?
        }
        return try await database.transaction { database in
            let sql = try sqlDatabase(database)
            guard let row = try await sql.raw("""
            SELECT client_id, user_id, redirect_uri, code_challenge, resource, name, kind, allow_writes, expires_at,
                consumed_at, agent_token_id
            FROM oauth_codes WHERE code_hash = \(bind: hash) FOR UPDATE
            """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)
            else { return nil }
            if row.consumedAt != nil {
                if let token = row.agentTokenId {
                    try await Self.revokeToken(token, now: now, sql: sql)
                }
                return .reused
            }
            guard row.expiresAt > now, let kind = AgentTokenKind(rawValue: row.kind) else { return nil }
            try await sql.raw("UPDATE oauth_codes SET consumed_at = \(bind: now) WHERE code_hash = \(bind: hash)").run()
            return .fresh(OAuthCode(
                clientID: row.clientId, userID: UserID(row.userId), redirectURI: row.redirectUri,
                codeChallenge: row.codeChallenge, resource: row.resource, name: row.name, kind: kind,
                allowWrites: row.allowWrites, expiresAt: row.expiresAt
            ))
        }
    }

    // swiftlint:disable:next function_parameter_count
    func issue(
        _ token: AgentToken,
        userID: UserID,
        clientID: String,
        codeHash: String,
        accessHash: String,
        accessExpiresAt: Date,
        refreshHash: String,
        refreshExpiresAt: Date
    ) async throws {
        try await database.transaction { database in
            let sql = try sqlDatabase(database)
            try await sql.raw("""
            INSERT INTO agent_tokens (id, user_id, name, kind, token_hash, scopes, created_at, expires_at, issuance,
                oauth_client_id)
            VALUES (\(bind: token.id), \(bind: userID.rawValue), \(bind: token.name), \(bind: token.kind.rawValue),
                \(bind: accessHash), \(bind: token.scopes.map(\.rawValue).sorted()), \(bind: token.createdAt),
                \(bind: accessExpiresAt), 'oauth', \(bind: clientID))
            """).run()
            try await sql.raw("""
            INSERT INTO oauth_refresh_tokens (token_hash, agent_token_id, client_id, expires_at)
            VALUES (\(bind: refreshHash), \(bind: token.id), \(bind: clientID), \(bind: refreshExpiresAt))
            """).run()
            try await sql.raw("""
            UPDATE oauth_codes SET agent_token_id = \(bind: token.id) WHERE code_hash = \(bind: codeHash)
            """).run()
        }
    }

    // swiftlint:disable:next function_parameter_count
    func rotate(
        refreshHash: String,
        clientID: String,
        now: Date,
        accessHash: String,
        accessExpiresAt: Date,
        newRefreshHash: String,
        refreshExpiresAt: Date
    ) async throws -> RefreshOutcome {
        struct Row: Decodable {
            let agentTokenId: UUID
            let clientId: String
            let expiresAt: Date
            let consumedAt: Date?
            let revokedAt: Date?
            let scopes: [String]
        }
        return try await database.transaction { database in
            let sql = try sqlDatabase(database)
            guard let row = try await sql.raw("""
            SELECT r.agent_token_id, r.client_id, r.expires_at, r.consumed_at, t.revoked_at, t.scopes
            FROM oauth_refresh_tokens r JOIN agent_tokens t ON t.id = r.agent_token_id
            WHERE r.token_hash = \(bind: refreshHash) FOR UPDATE
            """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)
            else { return .invalid }
            if row.consumedAt != nil {
                try await Self.revokeToken(row.agentTokenId, now: now, sql: sql)
                return .reused
            }
            guard row.clientId == clientID, row.expiresAt > now, row.revokedAt == nil else { return .invalid }
            try await sql.raw("""
            UPDATE oauth_refresh_tokens SET consumed_at = \(bind: now) WHERE token_hash = \(bind: refreshHash)
            """).run()
            try await sql.raw("""
            INSERT INTO oauth_refresh_tokens (token_hash, agent_token_id, client_id, expires_at)
            VALUES (\(bind: newRefreshHash), \(bind: row.agentTokenId), \(bind: clientID), \(bind: refreshExpiresAt))
            """).run()
            try await sql.raw("""
            UPDATE agent_tokens SET token_hash = \(bind: accessHash), expires_at = \(bind: accessExpiresAt)
            WHERE id = \(bind: row.agentTokenId)
            """).run()
            return .rotated(scopes: Set(row.scopes.compactMap(AgentScope.init(rawValue:))))
        }
    }

    func revoke(tokenHash: String, now: Date) async throws {
        struct Row: Decodable { let id: UUID }
        let sql = try sql
        let found = try await sql.raw("""
        SELECT id FROM agent_tokens WHERE issuance = 'oauth' AND (token_hash = \(bind: tokenHash) OR id IN (
            SELECT agent_token_id FROM oauth_refresh_tokens WHERE token_hash = \(bind: tokenHash)
        ))
        """).first(decoding: Row.self)
        if let found {
            try await Self.revokeToken(found.id, now: now, sql: sql)
        }
    }

    /// As Settings' revoke does: the token stops at once and its waiting plans expire with it.
    private static func revokeToken(_ id: UUID, now: Date, sql: any SQLDatabase) async throws {
        try await sql.raw("""
        UPDATE agent_tokens SET revoked_at = \(bind: now) WHERE id = \(bind: id) AND revoked_at IS NULL
        """).run()
        try await sql.raw("""
        UPDATE agent_plans SET status = 'expired', decided_at = \(bind: now)
        WHERE agent_token_id = \(bind: id) AND status = 'pending'
        """).run()
    }
}
