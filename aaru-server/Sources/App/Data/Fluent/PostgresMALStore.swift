import AaruCore
import FluentSQL
import Foundation

struct PostgresMALStore: MALStore {
    let sql: any SQLDatabase

    func createAuthRequest(stateHash: String, request: MALAuthRequest, expiresAt: Date) async throws {
        try await sql.raw("""
        INSERT INTO mal_auth_requests (state_hash, user_id, code_verifier, return_to, expires_at)
        VALUES (\(bind: stateHash), \(bind: request.userID.rawValue), \(bind: request.codeVerifier),
            \(bind: request.returnTo), \(bind: expiresAt))
        """).run()
    }

    func consumeAuthRequest(stateHash: String, now: Date) async throws -> MALAuthRequest? {
        struct Row: Decodable {
            let userId: UUID
            let codeVerifier: String
            let returnTo: String
            let expiresAt: Date
        }
        // One statement: a replayed callback finds nothing.
        guard let row = try await sql.raw("""
        DELETE FROM mal_auth_requests WHERE state_hash = \(bind: stateHash)
        RETURNING user_id, code_verifier, return_to, expires_at
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase),
            row.expiresAt > now
        else { return nil }
        return MALAuthRequest(userID: UserID(row.userId), codeVerifier: row.codeVerifier, returnTo: row.returnTo)
    }

    func saveConnection(_ connection: MALConnectionRecord, cursor: Date, userID: UserID) async throws {
        try await sql.raw("""
        INSERT INTO mal_connections
            (user_id, access_token, refresh_token, expires_at, username, connected_at, push_cursor)
        VALUES (\(bind: userID.rawValue), \(bind: connection.sealedAccessToken),
            \(bind: connection.sealedRefreshToken), \(bind: connection.expiresAt), \(bind: connection.username),
            \(bind: connection.connectedAt), \(bind: cursor))
        ON CONFLICT (user_id) DO UPDATE SET access_token = EXCLUDED.access_token,
            refresh_token = EXCLUDED.refresh_token, expires_at = EXCLUDED.expires_at,
            username = COALESCE(EXCLUDED.username, mal_connections.username), revoked_at = NULL
        """).run()
    }

    func connection(userID: UserID) async throws -> MALConnectionRecord? {
        try await connection(userID: userID, on: sql, lock: false)
    }

    func refreshConnection(
        userID: UserID,
        _ refresh: @escaping @Sendable (MALConnectionRecord) async throws -> MALConnectionRecord
    ) async throws -> MALConnectionRecord? {
        try await sql.transaction { sql in
            guard let current = try await connection(userID: userID, on: sql, lock: true) else { return nil }
            let next = try await refresh(current)
            guard next != current else { return current }
            try await sql.raw("""
            UPDATE mal_connections SET access_token = \(bind: next.sealedAccessToken),
                refresh_token = \(bind: next.sealedRefreshToken), expires_at = \(bind: next.expiresAt)
            WHERE user_id = \(bind: userID.rawValue)
            """).run()
            return next
        }
    }

    private func connection(userID: UserID, on sql: any SQLDatabase, lock: Bool) async throws
        -> MALConnectionRecord?
    {
        struct Row: Decodable {
            let accessToken: String
            let refreshToken: String
            let expiresAt: Date
            let username: String?
            let connectedAt: Date
            let revokedAt: Date?
            let pulledAt: Date?
        }
        return try await sql.raw("""
        SELECT access_token, refresh_token, expires_at, username, connected_at, revoked_at, pulled_at
        FROM mal_connections
        WHERE user_id = \(bind: userID.rawValue) \(unsafeRaw: lock ? "FOR UPDATE" : "")
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase).map {
            MALConnectionRecord(
                sealedAccessToken: $0.accessToken, sealedRefreshToken: $0.refreshToken,
                expiresAt: $0.expiresAt, username: $0.username, connectedAt: $0.connectedAt,
                revokedAt: $0.revokedAt, pulledAt: $0.pulledAt
            )
        }
    }

    func deleteConnection(userID: UserID) async throws {
        try await sql.transaction { sql in
            try await sql.raw("DELETE FROM mal_entry_states WHERE user_id = \(bind: userID.rawValue)").run()
            try await sql.raw("DELETE FROM mal_connections WHERE user_id = \(bind: userID.rawValue)").run()
        }
    }

    func markRevoked(userID: UserID, revokedAt: Date) async throws {
        try await sql.raw("""
        UPDATE mal_connections SET revoked_at = \(bind: revokedAt) WHERE user_id = \(bind: userID.rawValue)
        """).run()
    }

    func pushesDue() async throws -> [MALPushDue] {
        struct Row: Decodable {
            let userId: UUID
            let pushCursor: Date
        }
        return try await sql.raw("""
        SELECT c.user_id, c.push_cursor FROM mal_connections c
        WHERE c.revoked_at IS NULL AND EXISTS (
            SELECT 1 FROM library_items li WHERE li.user_id = c.user_id AND li.updated_at > c.push_cursor
        )
        """).all(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase).map {
            MALPushDue(userID: UserID($0.userId), cursor: $0.pushCursor)
        }
    }

    func advanceCursor(userID: UserID, cursor: Date) async throws {
        try await sql.raw("""
        UPDATE mal_connections SET push_cursor = GREATEST(push_cursor, \(bind: cursor))
        WHERE user_id = \(bind: userID.rawValue)
        """).run()
    }

    func entryStates(userID: UserID, malIDs: [String]) async throws -> [String: MALEntryState] {
        guard !malIDs.isEmpty else { return [:] }
        struct Row: Decodable {
            let malId: String
            let status: String
            let episodes: Int
            let score: Int
        }
        let rows = try await sql.raw("""
        SELECT mal_id, status, episodes, score FROM mal_entry_states
        WHERE user_id = \(bind: userID.rawValue) AND mal_id = ANY(\(bind: Array(Set(malIDs))))
        """).all(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)
        return Dictionary(rows.compactMap { row in
            MALListStatus(rawValue: row.status).map {
                (row.malId, MALEntryState(malID: row.malId, status: $0, episodes: row.episodes, score: row.score))
            }
        }, uniquingKeysWith: { first, _ in first })
    }

    func saveEntryState(_ state: MALEntryState, title: String?, userID: UserID) async throws {
        try await sql.raw("""
        INSERT INTO mal_entry_states (user_id, mal_id, status, episodes, score, title, updated_at)
        VALUES (\(bind: userID.rawValue), \(bind: state.malID), \(bind: state.status.rawValue),
            \(bind: state.episodes), \(bind: state.score), \(bind: title), now())
        ON CONFLICT (user_id, mal_id) DO UPDATE SET status = EXCLUDED.status, episodes = EXCLUDED.episodes,
            score = EXCLUDED.score, title = COALESCE(EXCLUDED.title, mal_entry_states.title),
            removed_at = NULL, updated_at = now()
        """).run()
    }

    // MARK: Reading back (SCR-010)

    func requestPull(userID: UserID, now: Date, notBefore: Date) async throws -> Bool {
        struct Row: Decodable { let userId: UUID }
        return try await sql.raw("""
        UPDATE mal_connections SET pull_requested_at = \(bind: now)
        WHERE user_id = \(bind: userID.rawValue) AND revoked_at IS NULL
            AND (pulled_at IS NULL OR pulled_at < \(bind: notBefore))
        RETURNING user_id
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase) != nil
    }

    func claimPulls(now: Date, staleBefore: Date, fullBefore: Date, limit: Int) async throws -> [MALPullDue] {
        struct Row: Decodable {
            let userId: UUID
            let cursor: Date
            let fullRead: Bool
        }
        // Asked-for reads first; SKIP LOCKED keeps two replicas off the same connection.
        return try await sql.raw("""
        UPDATE mal_connections c SET pulled_at = \(bind: now), pull_requested_at = NULL
        WHERE c.user_id IN (
            SELECT user_id FROM mal_connections
            WHERE revoked_at IS NULL
                AND (pull_requested_at IS NOT NULL OR pulled_at IS NULL OR pulled_at < \(bind: staleBefore))
            ORDER BY pull_requested_at NULLS LAST, pulled_at NULLS FIRST
            LIMIT \(bind: limit)
            FOR UPDATE SKIP LOCKED
        )
        RETURNING c.user_id, COALESCE(c.pull_cursor, c.connected_at) AS cursor,
            (c.full_read_at IS NULL OR c.full_read_at < \(bind: fullBefore)) AS full_read
        """).all(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase).map {
            MALPullDue(userID: UserID($0.userId), cursor: $0.cursor, fullRead: $0.fullRead)
        }
    }

    func finishPull(userID: UserID, cursor: Date, fullReadAt: Date?) async throws {
        try await sql.raw("""
        UPDATE mal_connections
        SET pull_cursor = GREATEST(COALESCE(pull_cursor, connected_at), \(bind: cursor)),
            full_read_at = COALESCE(\(bind: fullReadAt), full_read_at)
        WHERE user_id = \(bind: userID.rawValue)
        """).run()
    }

    func markRemoved(userID: UserID, listed: [String], now: Date) async throws {
        try await sql.raw("""
        UPDATE mal_entry_states SET removed_at = CASE
            WHEN mal_id = ANY(\(bind: Array(Set(listed)))) THEN NULL ELSE COALESCE(removed_at, \(bind: now)) END
        WHERE user_id = \(bind: userID.rawValue)
        """).run()
    }

    func removedEntries(userID: UserID) async throws -> [MALRemovedEntry] {
        struct Row: Decodable {
            let malId: String
            let title: String?
            let removedAt: Date
        }
        return try await sql.raw("""
        SELECT mal_id, title, removed_at FROM mal_entry_states
        WHERE user_id = \(bind: userID.rawValue) AND removed_at IS NOT NULL
        ORDER BY removed_at DESC, title LIMIT 100
        """).all(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase).map {
            MALRemovedEntry(malID: $0.malId, title: $0.title, removedAt: $0.removedAt)
        }
    }
}
