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

    func saveEntryState(_: MALEntryState, userID _: UserID) async throws {
        throw UntouchedStore.Touched()
    }
}
