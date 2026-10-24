import AaruCore
import Foundation
@testable import aaru

/// A MyAnimeList store that must not be touched by the test using it.
struct UntouchedMALStore: MALStore {
    func createAuthRequest(stateHash _: String, request _: MALAuthRequest, expiresAt _: Date) async throws {
        throw UntouchedStore.Touched()
    }

    func consumeAuthRequest(stateHash _: String, now _: Date) async throws -> MALAuthRequest? {
        throw UntouchedStore.Touched()
    }

    func saveConnection(_: MALConnectionRecord, cursor _: Date, userID _: UserID) async throws {
        throw UntouchedStore.Touched()
    }

    func connection(userID _: UserID) async throws -> MALConnectionRecord? {
        throw UntouchedStore.Touched()
    }

    func refreshConnection(
        userID _: UserID,
        _: @escaping @Sendable (MALConnectionRecord) async throws -> MALConnectionRecord
    ) async throws -> MALConnectionRecord? {
        throw UntouchedStore.Touched()
    }

    func deleteConnection(userID _: UserID) async throws {
        throw UntouchedStore.Touched()
    }

    func markRevoked(userID _: UserID, revokedAt _: Date) async throws {
        throw UntouchedStore.Touched()
    }

    func pushesDue() async throws -> [MALPushDue] {
        throw UntouchedStore.Touched()
    }

    func advanceCursor(userID _: UserID, cursor _: Date) async throws {
        throw UntouchedStore.Touched()
    }

    func entryStates(userID _: UserID, malIDs _: [String]) async throws -> [String: MALEntryState] {
        throw UntouchedStore.Touched()
    }

    func saveEntryState(_: MALEntryState, title _: String?, userID _: UserID) async throws {
        throw UntouchedStore.Touched()
    }

    func requestPull(userID _: UserID, now _: Date, notBefore _: Date) async throws -> Bool {
        throw UntouchedStore.Touched()
    }

    func claimPulls(now _: Date, staleBefore _: Date, fullBefore _: Date, limit _: Int) async throws
        -> [MALPullDue]
    {
        throw UntouchedStore.Touched()
    }

    func finishPull(userID _: UserID, cursor _: Date, fullReadAt _: Date?) async throws {
        throw UntouchedStore.Touched()
    }

    func markRemoved(userID _: UserID, listed _: [String], now _: Date) async throws {
        throw UntouchedStore.Touched()
    }

    func removedEntries(userID _: UserID) async throws -> [MALRemovedEntry] {
        throw UntouchedStore.Touched()
    }
}
