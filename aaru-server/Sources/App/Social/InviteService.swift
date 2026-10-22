import AaruCore
import Foundation

/// What an invite link shows before anyone signs in: who sent it and the title it carries.
/// Never library data.
struct InvitePreview: Sendable {
    var invite: FriendInvite
    var inviter: SocialUser
    var title: Title?
    /// Where the signed-in viewer stands with the inviter; nil when signed out.
    var relationship: Relationship?
}

/// Friend invite links (SOC-002). One link per invite, spent by the first person who accepts it
/// while it is live. Accepting makes both people friends at once: the inviter asked by sending
/// it, the invitee by opening it.
///
/// Every dead end reads the same: an unknown, expired, revoked or spent code, an inviter who
/// left, and a block either way all answer one 404, so a link reveals nothing it shouldn't.
struct InviteService: Sendable {
    let stores: Stores
    /// Adds the invite's title exactly as a tap would; its resolver reads the title a link carries.
    let library: LibraryService
    /// The web origin a link opens on; the apps claim the same paths as universal links.
    var webBaseURL = URL(string: "https://aaruapp.com")!
    var now: @Sendable () -> Date = { Date() }

    static let lifetime: TimeInterval = 14 * 24 * 60 * 60
    static let maxOpenInvites = 20
    static let codeLength = 12
    private static let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")

    /// Previews are public, so they are limited per client address; redeems per user.
    let previewLimiter = FixedWindowRateLimiter(limit: 120, window: 60 * 60)
    let redeemLimiter = FixedWindowRateLimiter(limit: 20, window: 60 * 60)

    var social: SocialService {
        SocialService(stores: stores, now: now)
    }

    static let noSuchInvite = AppError.notFound("This invite isn't valid anymore.")

    func url(_ invite: FriendInvite) -> URL {
        webBaseURL.appending(path: "i/\(invite.code)")
    }

    // MARK: Inviter

    /// Makes a link, optionally carrying one title. Needs the inviter's handle, so the person
    /// opening it sees who sent it.
    func create(_ viewer: UserID, title ref: MediaRef?) async throws -> (FriendInvite, Title?) {
        _ = try await social.requireHandle(viewer)
        guard try await stores.social.openInvites(viewer, now: now()).count < Self.maxOpenInvites else {
            throw AppError(
                status: .unprocessableContent, code: "too_many_invites",
                message: "You have \(Self.maxOpenInvites) invites waiting. Revoke some first."
            )
        }
        var title: Title?
        if let ref {
            title = try await library.resolver.resolve(ref)
        }
        let created = now()
        for _ in 0 ..< 3 {
            let invite = FriendInvite(
                id: UUID(), code: Self.newCode(), inviter: viewer, titleID: title?.id,
                createdAt: created, expiresAt: created.addingTimeInterval(Self.lifetime)
            )
            do {
                try await stores.social.createInvite(invite)
                return (invite, title)
            } catch is StoreConflict {
                continue
            }
        }
        throw AppError(status: .internalServerError, code: "internal", message: "Couldn't make an invite. Try again.")
    }

    func open(_ viewer: UserID) async throws -> [(FriendInvite, Title?)] {
        let invites = try await stores.social.openInvites(viewer, now: now())
        let titles = try await titles(for: invites)
        return invites.map { ($0, $0.titleID.flatMap { titles[$0] }) }
    }

    func revoke(code: String, viewer: UserID) async throws {
        guard try await stores.social.revokeInvite(code: code, inviter: viewer, now: now()) else {
            throw Self.noSuchInvite
        }
    }

    // MARK: Invitee

    /// What the link shows. `viewer` is nil when the person opening it is signed out.
    func preview(code: String, viewer: UserID?, clientAddress: String) async throws -> InvitePreview {
        guard await previewLimiter.allow(clientAddress, now: now()) else { throw Self.rateLimited }
        guard let invite = try await stores.social.invite(code: code), invite.isOpen(at: now()),
              let inviter = try await stores.social.socialUser(invite.inviter)
        else { throw Self.noSuchInvite }
        var relationship: Relationship?
        if let viewer {
            do {
                relationship = try await social.relationship(viewer, inviter.id)
            } catch is AppError {
                throw Self.noSuchInvite
            }
        }
        var title: Title?
        if let titleID = invite.titleID {
            title = try await stores.titles.title(id: titleID)
        }
        return InvitePreview(invite: invite, inviter: inviter, title: title, relationship: relationship)
    }

    /// Accepts the invite: the two become friends and the link is spent. Already friends is a
    /// success that leaves the link unspent. `addTitle` puts the invite's title on the viewer's
    /// Plan to watch exactly as a tap would, and never touches a title they already have.
    func redeem(
        code: String,
        viewer: UserID,
        addTitle: Bool
    ) async throws -> (friend: SocialUser, titleAdded: Bool) {
        guard await redeemLimiter.allow(viewer.description, now: now()) else { throw Self.rateLimited }
        _ = try await social.requireHandle(viewer)
        guard let invite = try await stores.social.invite(code: code), invite.isOpen(at: now()),
              let inviter = try await stores.social.socialUser(invite.inviter)
        else { throw Self.noSuchInvite }
        let relationship: Relationship
        do {
            relationship = try await social.relationship(viewer, inviter.id)
        } catch is AppError {
            throw Self.noSuchInvite
        }
        switch relationship {
        case .self:
            throw AppError(
                status: .conflict,
                code: "own_invite",
                message: "This is your own invite. Send it to a friend."
            )
        case .friend:
            break
        case .none, .incoming, .outgoing:
            guard try await stores.social.redeemInvite(code: code, redeemer: viewer, now: now()) != nil else {
                throw Self.noSuchInvite
            }
        }
        var titleAdded = false
        if addTitle, let titleID = invite.titleID, let title = try await stores.titles.title(id: titleID) {
            let existing = try await stores.library.item(userID: viewer, titleID: titleID)
            if existing == nil {
                _ = try await library.add(
                    MediaRef(titleID: title.id, type: title.type),
                    status: .wishlist,
                    userID: viewer
                )
                titleAdded = true
            }
        }
        return (inviter, titleAdded)
    }

    // MARK: Rules

    static func newCode() -> String {
        var generator = SystemRandomNumberGenerator()
        return String((0 ..< codeLength).map { _ in alphabet[Int.random(in: 0 ..< alphabet.count, using: &generator)] })
    }

    private static let rateLimited = AppError(
        status: .tooManyRequests, code: "rate_limited", message: "Too many invite attempts. Try again later."
    )

    private func titles(for invites: [FriendInvite]) async throws -> [TitleID: Title] {
        let ids = Array(Set(invites.compactMap(\.titleID)))
        guard !ids.isEmpty else { return [:] }
        return try await Dictionary(stores.titles.titles(ids: ids).map { ($0.id, $0) }) { first, _ in first }
    }
}
