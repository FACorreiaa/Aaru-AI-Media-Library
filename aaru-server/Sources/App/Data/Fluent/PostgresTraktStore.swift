import AaruCore
import FluentSQL
import Foundation

struct PostgresTraktStore: TraktStore {
    let sql: any SQLDatabase

    func createAuthRequest(stateHash: String, request: TraktAuthRequest, expiresAt: Date) async throws {
        try await sql.raw("""
        INSERT INTO trakt_auth_requests (state_hash, user_id, code_verifier, return_to, expires_at)
        VALUES (\(bind: stateHash), \(bind: request.userID.rawValue), \(bind: request.codeVerifier),
            \(bind: request.returnTo), \(bind: expiresAt))
        """).run()
    }

    func consumeAuthRequest(stateHash: String, now: Date) async throws -> TraktAuthRequest? {
        struct Row: Decodable {
            let userId: UUID
            let codeVerifier: String
            let returnTo: String
            let expiresAt: Date
        }
        // One statement: a replayed callback finds nothing.
        guard let row = try await sql.raw("""
        DELETE FROM trakt_auth_requests WHERE state_hash = \(bind: stateHash)
        RETURNING user_id, code_verifier, return_to, expires_at
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase),
            row.expiresAt > now
        else { return nil }
        return TraktAuthRequest(userID: UserID(row.userId), codeVerifier: row.codeVerifier, returnTo: row.returnTo)
    }

    func saveConnection(_ connection: TraktConnectionRecord, userID: UserID) async throws {
        try await sql.raw("""
        INSERT INTO trakt_connections (user_id, access_token, refresh_token, expires_at, username, connected_at)
        VALUES (\(bind: userID.rawValue), \(bind: connection.sealedAccessToken), \(bind: connection.sealedRefreshToken),
            \(bind: connection.expiresAt), \(bind: connection.username), \(bind: connection.connectedAt))
        ON CONFLICT (user_id) DO UPDATE SET access_token = EXCLUDED.access_token,
            refresh_token = EXCLUDED.refresh_token, expires_at = EXCLUDED.expires_at,
            username = COALESCE(EXCLUDED.username, trakt_connections.username)
        """).run()
    }

    func connection(userID: UserID) async throws -> TraktConnectionRecord? {
        try await connection(userID: userID, on: sql, lock: false)
    }

    func refreshConnection(
        userID: UserID,
        _ refresh: @escaping @Sendable (TraktConnectionRecord) async throws -> TraktConnectionRecord
    ) async throws -> TraktConnectionRecord? {
        try await sql.transaction { sql in
            guard let current = try await connection(userID: userID, on: sql, lock: true) else { return nil }
            let next = try await refresh(current)
            guard next != current else { return current }
            try await sql.raw("""
            UPDATE trakt_connections SET access_token = \(bind: next.sealedAccessToken),
                refresh_token = \(bind: next.sealedRefreshToken), expires_at = \(bind: next.expiresAt)
            WHERE user_id = \(bind: userID.rawValue)
            """).run()
            return next
        }
    }

    private func connection(userID: UserID, on sql: any SQLDatabase, lock: Bool) async throws
        -> TraktConnectionRecord?
    {
        struct Row: Decodable {
            let accessToken: String
            let refreshToken: String
            let expiresAt: Date
            let username: String?
            let connectedAt: Date
        }
        return try await sql.raw("""
        SELECT access_token, refresh_token, expires_at, username, connected_at FROM trakt_connections
        WHERE user_id = \(bind: userID.rawValue) \(unsafeRaw: lock ? "FOR UPDATE" : "")
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase).map {
            TraktConnectionRecord(
                sealedAccessToken: $0.accessToken, sealedRefreshToken: $0.refreshToken,
                expiresAt: $0.expiresAt, username: $0.username, connectedAt: $0.connectedAt
            )
        }
    }

    func deleteConnection(userID: UserID) async throws {
        try await sql.raw("DELETE FROM trakt_connections WHERE user_id = \(bind: userID.rawValue)").run()
    }
}
