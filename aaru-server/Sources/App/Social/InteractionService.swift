import AaruCore
import Foundation

/// A waiting recommendation with who sent it and the title.
struct InboxItem: Sendable {
    var recommendation: Recommendation
    var from: SocialUser
    var title: Title
}

/// SOC-007 reactions and SOC-006 recommendations. Both are between friends only: anything else
/// is the same 404 as nobody being there. Agents get neither (VIEWS.md).
struct InteractionService: Sendable {
    let stores: Stores
    let library: LibraryService
    var now: @Sendable () -> Date = { Date() }

    static let maxRecipients = 10
    static let maxNoteLength = 140
    static let inboxLimit = 50
    /// Per sender, shared by every request (the service itself is made per request).
    static let sendLimiter = FixedWindowRateLimiter(limit: 30, window: 60 * 60)

    static let noSuchRow = AppError.notFound("That activity isn't there.")
    static let noSuchRecommendation = AppError.notFound("That recommendation is gone.")

    // MARK: Reactions

    /// Sets or clears the viewer's reaction on a friend's row. Your own rows take no reactions.
    func react(_ emoji: String?, on id: String, viewer: UserID) async throws {
        guard let row = ActivityKey(id: id), row.owner != viewer,
              try await canSee(row.owner, viewer: viewer),
              try await stores.interactions.hasTitle(row.owner, row.titleID)
        else { throw Self.noSuchRow }
        if let emoji, !Reaction.all.contains(emoji) {
            throw AppError(
                status: .unprocessableContent, code: "validation_failed",
                message: "Pick one of \(Reaction.all.joined(separator: " "))."
            )
        }
        try await stores.interactions.react(emoji, on: row, by: viewer, now: now())
    }

    // MARK: Recommendations

    /// Sends one title to up to ten friends, with an optional short note.
    func recommend(_ ref: MediaRef, note: String?, to recipients: [UserID], viewer: UserID) async throws {
        _ = try await SocialService(stores: stores, now: now).requireHandle(viewer)
        let recipients = Array(Set(recipients))
        guard !recipients.isEmpty, recipients.count <= Self.maxRecipients else {
            throw AppError(
                status: .unprocessableContent, code: "validation_failed",
                message: "Send it to between 1 and \(Self.maxRecipients) friends."
            )
        }
        let note = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let note, note.count > Self.maxNoteLength {
            throw AppError(
                status: .unprocessableContent, code: "validation_failed",
                message: "Keep the note under \(Self.maxNoteLength) characters."
            )
        }
        guard !recipients.contains(viewer) else { throw SocialService.noSuchUser }
        for recipient in recipients {
            guard try await isFriend(recipient, viewer) else { throw SocialService.noSuchUser }
        }
        guard await Self.sendLimiter.allow(viewer.description, now: now()) else {
            throw AppError(
                status: .tooManyRequests,
                code: "rate_limited",
                message: "Too many recommendations. Try later."
            )
        }
        let title = try await library.resolver.resolve(ref)
        let sent = now()
        try await stores.interactions.recommend(recipients.map {
            Recommendation(
                id: UUID(), sender: viewer, recipient: $0, titleID: title.id,
                note: note?.isEmpty == false ? note : nil, createdAt: sent
            )
        })
    }

    func inbox(_ viewer: UserID) async throws -> [InboxItem] {
        let waiting = try await stores.interactions.inbox(viewer, limit: Self.inboxLimit)
        guard !waiting.isEmpty else { return [] }
        let friends = try await Dictionary(stores.social.friends(viewer).map { ($0.id, $0) }) { first, _ in first }
        let titles = try await Dictionary(
            stores.titles.titles(ids: Array(Set(waiting.map(\.titleID)))).map { ($0.id, $0) }
        ) { first, _ in first }
        return waiting.compactMap { item in
            guard let from = friends[item.sender], let title = titles[item.titleID] else { return nil }
            return InboxItem(recommendation: item, from: from, title: title)
        }
    }

    /// Adds a recommended title to Plan to watch, as a tap would; a title already in the library
    /// keeps its status. The recommendation leaves the inbox either way.
    func add(_ id: UUID, viewer: UserID) async throws {
        guard let item = try await stores.interactions.resolve(id, to: viewer, added: true, now: now()),
              let title = try await stores.titles.title(id: item.titleID)
        else { throw Self.noSuchRecommendation }
        _ = try await library.add(MediaRef(titleID: title.id, type: title.type), status: .wishlist, userID: viewer)
    }

    func dismiss(_ id: UUID, viewer: UserID) async throws {
        guard try await stores.interactions.resolve(id, to: viewer, added: false, now: now()) != nil
        else { throw Self.noSuchRecommendation }
    }

    // MARK: Rules

    private func isFriend(_ other: UserID, _ viewer: UserID) async throws -> Bool {
        guard try await !stores.social.isBlocked(viewer, other) else { return false }
        return try await stores.social.areFriends(viewer, other)
    }

    /// A friend whose library is shown to friends.
    private func canSee(_ owner: UserID, viewer: UserID) async throws -> Bool {
        guard try await isFriend(owner, viewer) else { return false }
        return try await stores.friendViews.socialSettings(owner).shareLibraryWithFriends
    }
}
