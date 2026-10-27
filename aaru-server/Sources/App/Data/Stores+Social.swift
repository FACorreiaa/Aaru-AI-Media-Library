import AaruCore
import Foundation

// Social half of the data layer boundary, kept apart so Stores.swift stays under the
// file-length limit.

/// Another user as social surfaces show them: only people with a handle appear anywhere social.
struct SocialUser: Sendable, Equatable {
    var id: UserID
    var handle: String
    var displayName: String?
    /// Changes on every upload; nil without an avatar (SOC-001b).
    var avatarVersion: Int64?
}

/// A first and a last name, both optional (SOC-001b). Others see them joined.
struct PersonName: Sendable, Equatable {
    var first: String?
    var last: String?

    /// The two names joined, or nil with neither.
    var displayName: String? {
        let joined = [first, last].compactMap { $0 }.joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }
}

extension PersonName {
    /// One name as an older app or a sign-in sends it: the first word, then the rest. The
    /// migration splits saved names the same way.
    init(splitting raw: String?) {
        let name = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let space = name.firstIndex(where: \.isWhitespace) else {
            self.init(first: name.isEmpty ? nil : name, last: nil)
            return
        }
        let last = name[space...].trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(first: String(name[..<space]), last: last.isEmpty ? nil : last)
    }
}

/// A pending friend request. It stops existing once accepted, declined or cancelled.
struct FriendRequest: Sendable, Equatable {
    var id: UUID
    var sender: SocialUser
    var recipient: SocialUser
    var createdAt: Date
}

enum ReportReason: String, Sendable {
    case spam
    case harassment
    case impersonation
    case other
}

/// One report of a user to Aaru. The reported user is never told.
struct UserReport: Sendable {
    var id: UUID
    var reporter: UserID
    var target: UserID
    var reason: ReportReason
    var note: String?
    var createdAt: Date
}

/// One friend invite link (SOC-002). Open while it is unredeemed, unrevoked and unexpired.
struct FriendInvite: Sendable, Equatable {
    var id: UUID
    var code: String
    var inviter: UserID
    var titleID: TitleID?
    var createdAt: Date
    var expiresAt: Date
    var redeemedBy: UserID?
    var redeemedAt: Date?
    var revokedAt: Date?

    func isOpen(at now: Date) -> Bool {
        redeemedAt == nil && revokedAt == nil && expiresAt > now
    }
}

/// Handles, friends, blocks and reports (SOC-001 / SOC-002, minimal). Callers check blocks
/// before revealing anything; the store only answers what is asked.
protocol SocialStore: Sendable {
    /// The user's social identity; nil until they claim a handle.
    func socialUser(_ id: UserID) async throws -> SocialUser?
    func socialUser(handle: String) async throws -> SocialUser?
    /// Claims or changes the handle when one is given, and replaces both names when they are.
    /// `StoreConflict` when another user holds the handle.
    func saveProfile(_ id: UserID, handle: String?, name: PersonName?) async throws
    /// Replaces the avatar and gives it a new version (SOC-001b).
    func saveAvatar(_ id: UserID, image: Data) async throws
    func deleteAvatar(_ id: UserID) async throws
    /// The avatar's JPEG bytes, if the user has one.
    func avatar(_ id: UserID) async throws -> Data?
    /// True when either user blocked the other.
    func isBlocked(_ first: UserID, _ second: UserID) async throws -> Bool
    func areFriends(_ first: UserID, _ second: UserID) async throws -> Bool
    /// The pending request from one user to another, if any.
    func pendingRequest(sender: UserID, recipient: UserID) async throws -> UUID?
    /// Inserts a request; a duplicate is ignored.
    func createRequest(id: UUID, sender: UserID, recipient: UserID, now: Date) async throws
    func incomingRequests(_ id: UserID) async throws -> [FriendRequest]
    func outgoingRequests(_ id: UserID) async throws -> [FriendRequest]
    /// Turns a request addressed to `recipient` into a friendship. Returns the sender, or nil
    /// when no such request is pending.
    func acceptRequest(id: UUID, recipient: UserID, now: Date) async throws -> UserID?
    /// Deletes a request either side of it is withdrawing. True when one was pending.
    func deleteRequest(id: UUID, party: UserID) async throws -> Bool
    /// Friends with a handle, by handle.
    func friends(_ id: UserID) async throws -> [SocialUser]
    func unfriend(_ first: UserID, _ second: UserID) async throws -> Bool
    /// Blocks, and in the same transaction ends any friendship and pending requests both ways.
    func block(_ blocker: UserID, _ blocked: UserID, now: Date) async throws
    func unblock(_ blocker: UserID, _ blocked: UserID) async throws -> Bool
    func blocked(by id: UserID) async throws -> [SocialUser]
    /// Everyone who blocked this user.
    func blockers(of id: UserID) async throws -> Set<UserID>
    func report(_ report: UserReport) async throws
    /// Inserts an invite. `StoreConflict` when the code is taken.
    func createInvite(_ invite: FriendInvite) async throws
    func invite(code: String) async throws -> FriendInvite?
    /// The inviter's invites still open at `now`, newest first.
    func openInvites(_ inviter: UserID, now: Date) async throws -> [FriendInvite]
    /// Revokes an open invite the inviter made. True when one was open.
    func revokeInvite(code: String, inviter: UserID, now: Date) async throws -> Bool
    /// Spends an open invite on `redeemer` and, in the same transaction, makes the two friends
    /// and drops any pending requests between them. Returns the inviter, or nil when the invite
    /// was not open (a concurrent redeem lost).
    func redeemInvite(code: String, redeemer: UserID, now: Date) async throws -> UserID?
}
