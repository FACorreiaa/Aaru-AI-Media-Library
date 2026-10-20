import AaruCore
import Foundation

/// Where another user stands with the viewer.
enum Relationship: String, Sendable {
    case none
    case friend
    /// The viewer asked them.
    case outgoing
    /// They asked the viewer.
    case incoming
    case `self`
}

/// Handles, friends, blocks and reports (SOC-001 / SOC-002, minimal; pulled forward for groups).
///
/// A block is invisible: a blocked pair answer each other with the same 404 as a handle nobody
/// holds (X-011). Social acts need the actor to have a handle, so the other side always sees who
/// is asking.
struct SocialService: Sendable {
    let stores: Stores
    var now: @Sendable () -> Date = { Date() }

    /// Pending requests a user may have out at once.
    static let maxOutgoingRequests = 50
    static let maxDisplayNameLength = 50
    /// Handles nobody may claim. `aaru` is how a group message tags the agent.
    static let reservedHandles: Set<String> = [
        "aaru", "admin", "administrator", "everyone", "help", "here", "me", "moderator", "null",
        "official", "root", "staff", "support", "system", "undefined",
    ]

    // MARK: Profile

    func saveProfile(_ userID: UserID, handle: String, displayName: String??) async throws -> SocialUser {
        let handle = try Self.validHandle(handle)
        let displayName = try displayName.map(Self.validDisplayName)
        try await stores.social.saveProfile(userID, handle: handle, displayName: displayName)
        guard let user = try await stores.social.socialUser(userID) else { throw AppError.unauthorized() }
        return user
    }

    func lookup(handle: String, viewer: UserID) async throws -> (user: SocialUser, relationship: Relationship) {
        let handle = handle.trimmingCharacters(in: .whitespaces).lowercased()
        guard let user = try await stores.social.socialUser(handle: handle) else { throw Self.noSuchUser }
        return try await (user, relationship(viewer, user.id))
    }

    // MARK: Requests

    /// Asks a user to be friends. Asking someone who already asked you accepts their request;
    /// asking a friend or asking twice changes nothing.
    func sendRequest(from viewer: UserID, toHandle handle: String) async throws -> (SocialUser, Relationship) {
        _ = try await requireHandle(viewer)
        let (target, current) = try await lookup(handle: handle, viewer: viewer)
        switch current {
        case .self:
            throw Self.invalid("handle", "You can't add yourself.")
        case .friend, .outgoing:
            return (target, current)
        case .incoming:
            if let id = try await stores.social.pendingRequest(sender: target.id, recipient: viewer) {
                _ = try await stores.social.acceptRequest(id: id, recipient: viewer, now: now())
            }
            return (target, .friend)
        case .none:
            guard try await stores.social.outgoingRequests(viewer).count < Self.maxOutgoingRequests else {
                throw Self.invalid("handle", "You have too many requests waiting. Withdraw some first.")
            }
            try await stores.social.createRequest(id: UUID(), sender: viewer, recipient: target.id, now: now())
            return (target, .outgoing)
        }
    }

    func requests(_ viewer: UserID) async throws -> (incoming: [FriendRequest], outgoing: [FriendRequest]) {
        try await (stores.social.incomingRequests(viewer), stores.social.outgoingRequests(viewer))
    }

    /// Accepts a request addressed to the viewer and returns the new friend.
    func accept(_ requestID: UUID, viewer: UserID) async throws -> SocialUser {
        guard let sender = try await stores.social.acceptRequest(id: requestID, recipient: viewer, now: now()),
              let friend = try await stores.social.socialUser(sender)
        else { throw AppError.notFound("No such request.") }
        return friend
    }

    /// Declines a request to the viewer, or cancels one the viewer sent.
    func withdraw(_ requestID: UUID, viewer: UserID) async throws {
        guard try await stores.social.deleteRequest(id: requestID, party: viewer)
        else { throw AppError.notFound("No such request.") }
    }

    // MARK: Friends and blocks

    func friends(_ viewer: UserID) async throws -> [SocialUser] {
        try await stores.social.friends(viewer)
    }

    func unfriend(_ friend: UserID, viewer: UserID) async throws {
        guard try await stores.social.unfriend(viewer, friend) else { throw AppError.notFound("Not a friend.") }
    }

    func block(_ target: UserID, viewer: UserID) async throws {
        guard target != viewer else { throw Self.invalid("userId", "You can't block yourself.") }
        guard try await stores.social.socialUser(target) != nil else { throw Self.noSuchUser }
        try await stores.social.block(viewer, target, now: now())
    }

    func unblock(_ target: UserID, viewer: UserID) async throws {
        guard try await stores.social.unblock(viewer, target) else { throw AppError.notFound("Not blocked.") }
    }

    func blocked(_ viewer: UserID) async throws -> [SocialUser] {
        try await stores.social.blocked(by: viewer)
    }

    func report(_ target: UserID, reason: ReportReason, note: String?, viewer: UserID) async throws {
        guard target != viewer, try await stores.social.socialUser(target) != nil else { throw Self.noSuchUser }
        let note = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let note, note.count > 1000 {
            throw Self.invalid("note", "Keep the note under 1,000 characters.")
        }
        try await stores.social.report(UserReport(
            id: UUID(), reporter: viewer, target: target, reason: reason,
            note: note?.isEmpty == false ? note : nil, createdAt: now()
        ))
    }

    // MARK: Rules

    /// The viewer's social identity, or 422 when they have not claimed a handle yet.
    func requireHandle(_ viewer: UserID) async throws -> SocialUser {
        guard let user = try await stores.social.socialUser(viewer) else {
            throw AppError(
                status: .unprocessableContent, code: "handle_required",
                message: "Choose a handle first, so friends can see who you are."
            )
        }
        return user
    }

    /// Where `other` stands with `viewer`. A block either way reads as nobody being there.
    func relationship(_ viewer: UserID, _ other: UserID) async throws -> Relationship {
        if viewer == other {
            return .self
        }
        if try await stores.social.isBlocked(viewer, other) {
            throw Self.noSuchUser
        }
        if try await stores.social.areFriends(viewer, other) {
            return .friend
        }
        if try await stores.social.pendingRequest(sender: viewer, recipient: other) != nil {
            return .outgoing
        }
        if try await stores.social.pendingRequest(sender: other, recipient: viewer) != nil {
            return .incoming
        }
        return .none
    }

    static let noSuchUser = AppError.notFound("No one has that handle.")

    static func validHandle(_ raw: String) throws -> String {
        let handle = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard handle.wholeMatch(of: /[a-z0-9_]{3,20}/) != nil else {
            throw invalid("handle", "Use 3–20 letters, numbers or underscores.")
        }
        guard !reservedHandles.contains(handle) else { throw invalid("handle", "That handle is taken.") }
        return handle
    }

    /// Trimmed; empty clears the name.
    static func validDisplayName(_ raw: String?) throws -> String? {
        guard let name = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        guard name.count <= maxDisplayNameLength else {
            throw invalid("displayName", "Keep your name under \(maxDisplayNameLength) characters.")
        }
        return name
    }

    private static func invalid(_ field: String, _ message: String) -> AppError {
        AppError(status: .unprocessableContent, code: "validation_failed", message: message, details: [field: message])
    }
}
