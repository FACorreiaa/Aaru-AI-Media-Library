import AaruCore
import Foundation

/// A user's MyAnimeList connection (SCR-005), tokens still sealed.
struct MALConnectionRecord: Sendable, Equatable {
    var sealedAccessToken: String
    var sealedRefreshToken: String
    var expiresAt: Date
    var username: String?
    var connectedAt: Date
    /// Set when MAL refused the tokens; pushing stops until the user connects again.
    var revokedAt: Date?
}

/// One MAL sign-in in flight. MAL takes only the `plain` PKCE method, so the verifier is also
/// the challenge; it still never leaves the server before the browser comes back.
struct MALAuthRequest: Sendable, Equatable {
    var userID: UserID
    var codeVerifier: String
    var returnTo: String
}

/// What Aaru and MAL last agreed on for one MAL entry: what Aaru pushed, or (SCR-010) read.
/// A push sends only when Aaru's state differs, so the same state is never sent twice.
struct MALEntryState: Sendable, Equatable {
    var malID: String
    var status: MALListStatus
    var episodes: Int
    var score: Int
}

/// MAL's list statuses. `on_hold` has no Aaru status; Aaru never sends it, only keeps it.
enum MALListStatus: String, Sendable, Codable {
    case watching
    case completed
    case onHold = "on_hold"
    case dropped
    case planToWatch = "plan_to_watch"
}

/// A connection with library writes newer than its push cursor.
struct MALPushDue: Sendable, Equatable {
    var userID: UserID
    var cursor: Date
}

protocol MALStore: Sendable {
    func createAuthRequest(stateHash: String, request: MALAuthRequest, expiresAt: Date) async throws
    /// Single use: returns the request and deletes it. Nil when unknown or expired.
    func consumeAuthRequest(stateHash: String, now: Date) async throws -> MALAuthRequest?
    /// Saves the tokens and clears a revocation. A first connection starts pushing from `cursor`;
    /// a reconnection keeps its cursor, so writes made while revoked still go out.
    func saveConnection(_ connection: MALConnectionRecord, cursor: Date, userID: UserID) async throws
    func connection(userID: UserID) async throws -> MALConnectionRecord?
    /// Replaces the tokens with `refresh`'s result while holding the row, as `TraktStore` does.
    func refreshConnection(
        userID: UserID,
        _ refresh: @escaping @Sendable (MALConnectionRecord) async throws -> MALConnectionRecord
    ) async throws -> MALConnectionRecord?
    /// Forgets the tokens and every entry state.
    func deleteConnection(userID: UserID) async throws
    func markRevoked(userID: UserID, revokedAt: Date) async throws
    /// Live connections whose user has a library item changed after the push cursor.
    func pushesDue() async throws -> [MALPushDue]
    func advanceCursor(userID: UserID, cursor: Date) async throws
    func entryStates(userID: UserID, malIDs: [String]) async throws -> [String: MALEntryState]
    func saveEntryState(_ state: MALEntryState, userID: UserID) async throws
}
