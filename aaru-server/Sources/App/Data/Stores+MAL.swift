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
    /// When Aaru last read the MAL list back (SCR-010).
    var pulledAt: Date?
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

/// A connection due a read of its MAL list (SCR-010): a client asked, or the last read is old.
struct MALPullDue: Sendable, Equatable {
    var userID: UserID
    /// Entries MAL changed after this are new to Aaru. It starts at the connection time, so only
    /// changes made after connecting come across.
    var cursor: Date
    /// The whole list is read this time, to find entries removed on MAL.
    var fullRead: Bool
}

/// An entry Aaru knew on MAL that MAL no longer lists. Shown in settings; Aaru keeps its item.
struct MALRemovedEntry: Sendable, Equatable {
    var malID: String
    var title: String?
    var removedAt: Date
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
    /// Saves what Aaru and MAL agree on. `title`, when known, is what settings names the entry by
    /// if it goes missing on MAL. Saving an entry clears its removal.
    func saveEntryState(_ state: MALEntryState, title: String?, userID: UserID) async throws

    // MARK: Reading back (SCR-010)

    /// Asks for a read on the next pass, unless the last read started after `notBefore`. False
    /// when MAL is not connected, revoked, or read too recently.
    func requestPull(userID: UserID, now: Date, notBefore: Date) async throws -> Bool
    /// Takes up to `limit` live connections a client asked to read or last read before `staleBefore`,
    /// and stamps them read at `now`, so no other pass takes them. `fullBefore`: a connection whose
    /// whole list was last read before it gets a full read.
    func claimPulls(now: Date, staleBefore: Date, fullBefore: Date, limit: Int) async throws -> [MALPullDue]
    /// Moves the read cursor forward, never back, and stamps a full read.
    func finishPull(userID: UserID, cursor: Date, fullReadAt: Date?) async throws
    /// After a full read: known entries MAL no longer lists are marked removed, listed ones cleared.
    func markRemoved(userID: UserID, listed: [String], now: Date) async throws
    func removedEntries(userID: UserID) async throws -> [MALRemovedEntry]
}
