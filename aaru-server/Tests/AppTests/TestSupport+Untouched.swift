import AaruCore
import Foundation
@testable import aaru

/// Later halves of `UntouchedStore`, kept apart so TestSupport stays under the file-length limit.
extension UntouchedStore: AgentTokenStore, WatchEventStore {
    func record(
        _: PlaybackReport, titleID _: TitleID?, userID _: UserID, agentTokenID _: UUID?, now _: Date
    ) async throws -> WatchSession {
        throw Touched()
    }

    func close(_: UUID, at _: Date) async throws {
        throw Touched()
    }

    func stoppedRecently(userID _: UserID, source _: WatchSource, externalRef _: String, since _: Date) async throws
        -> Bool
    {
        throw Touched()
    }

    func create(_: AgentToken, tokenHash _: String, userID _: UserID) async throws {
        throw Touched()
    }

    func tokens(userID _: UserID) async throws -> [AgentToken] {
        throw Touched()
    }

    func revoke(id _: UUID, userID _: UserID, now _: Date) async throws -> Bool {
        throw Touched()
    }

    func token(forHash _: String, now _: Date) async throws -> (token: AgentToken, userID: UserID)? {
        throw Touched()
    }

    func touch(id _: UUID, at _: Date) async throws {
        throw Touched()
    }
}

extension UntouchedStore {
    func upsertMany(_: [AnimeMapping]) async throws {
        throw Touched()
    }

    func staleTrackedShows(now _: Date, retryAfter _: Date, limit _: Int) async throws -> [TitleID] {
        throw Touched()
    }

    func markEpisodesAttempted(_: TitleID, at _: Date) async throws {
        throw Touched()
    }

    func apply(_: LibraryOp, userID _: UserID, caller _: Caller, kind _: String, summary _: String) async throws
        -> ActionRecord
    {
        throw Touched()
    }
}

extension UntouchedStore: SocialStore {
    func socialUser(_: UserID) async throws -> SocialUser? {
        throw Touched()
    }

    func socialUser(handle _: String) async throws -> SocialUser? {
        throw Touched()
    }

    func saveProfile(_: UserID, handle _: String, displayName _: String??) async throws {
        throw Touched()
    }

    func isBlocked(_: UserID, _: UserID) async throws -> Bool {
        throw Touched()
    }

    func areFriends(_: UserID, _: UserID) async throws -> Bool {
        throw Touched()
    }

    func pendingRequest(sender _: UserID, recipient _: UserID) async throws -> UUID? {
        throw Touched()
    }

    func createRequest(id _: UUID, sender _: UserID, recipient _: UserID, now _: Date) async throws {
        throw Touched()
    }

    func incomingRequests(_: UserID) async throws -> [FriendRequest] {
        throw Touched()
    }

    func outgoingRequests(_: UserID) async throws -> [FriendRequest] {
        throw Touched()
    }

    func acceptRequest(id _: UUID, recipient _: UserID, now _: Date) async throws -> UserID? {
        throw Touched()
    }

    func deleteRequest(id _: UUID, party _: UserID) async throws -> Bool {
        throw Touched()
    }

    func friends(_: UserID) async throws -> [SocialUser] {
        throw Touched()
    }

    func unfriend(_: UserID, _: UserID) async throws -> Bool {
        throw Touched()
    }

    func block(_: UserID, _: UserID, now _: Date) async throws {
        throw Touched()
    }

    func unblock(_: UserID, _: UserID) async throws -> Bool {
        throw Touched()
    }

    func blocked(by _: UserID) async throws -> [SocialUser] {
        throw Touched()
    }

    func report(_: UserReport) async throws {
        throw Touched()
    }
}
