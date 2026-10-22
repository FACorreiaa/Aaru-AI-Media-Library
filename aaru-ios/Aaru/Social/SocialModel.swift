import AaruAPI
import Foundation
import Observation

typealias SocialUser = Components.Schemas.SocialUser
typealias FriendRequest = Components.Schemas.FriendRequest
typealias FriendInvite = Components.Schemas.FriendInvite
typealias ActivityItem = Components.Schemas.ActivityItem
typealias RecommendationItem = Components.Schemas.RecommendationItem

/// SOC-001 / SOC-002: the user's handle, friends, requests both ways, and blocks. Friends are
/// added by exact handle; nobody can browse or search for anyone.
@MainActor
@Observable
final class SocialModel {
    private(set) var handle: String?
    private(set) var displayName: String?
    private(set) var friends: [SocialUser] = []
    private(set) var incoming: [FriendRequest] = []
    private(set) var outgoing: [FriendRequest] = []
    private(set) var blocked: [SocialUser] = []
    /// Invite links still waiting to be opened (SOC-002), newest first.
    private(set) var invites: [FriendInvite] = []
    /// Friends' last two weeks (SOC-003), newest first, and where the next page starts.
    private(set) var activity: [ActivityItem] = []
    private(set) var activityNext: Date?
    /// Titles friends sent you, waiting (SOC-006).
    private(set) var recommendations: [RecommendationItem] = []
    /// Friends see your library (SOC-001). On unless you turn it off.
    private(set) var shareLibrary = true
    private(set) var hasLoaded = false
    /// Why the first load failed; Friends shows Try again instead of an empty page (UX-063).
    private(set) var loadProblem: String?
    var problem: String?
    /// A one-line result of the last request ("Request sent to @ana.").
    var notice: String?

    @ObservationIgnored let api: Client?

    init(api: Client?) {
        self.api = api
    }

    /// The handle as the server stores it: no leading @, lowercase, trimmed.
    static func normalized(_ handle: String) -> String {
        var handle = handle.trimmingCharacters(in: .whitespaces).lowercased()
        if handle.hasPrefix("@") {
            handle.removeFirst()
        }
        return handle
    }

    /// Why a handle would be refused, or nil when it is well formed. Taken handles are the server's call.
    static func handleProblem(_ handle: String) -> String? {
        let handle = normalized(handle)
        if handle.isEmpty {
            return "Enter a handle."
        }
        guard handle.wholeMatch(of: /[a-z0-9_]{3,20}/) != nil else {
            return "Use 3–20 letters, numbers or underscores."
        }
        return nil
    }

    func load() async {
        guard let api else { return }
        do {
            async let meCall = api.getMe()
            async let friendsCall = api.listFriends()
            async let requestsCall = api.listFriendRequests()
            async let blocksCall = api.listBlocks()
            async let invitesCall = api.listFriendInvites()
            async let activityCall = api.listFriendActivity()
            async let settingsCall = api.getSocialSettings()
            async let recommendationsCall = api.listRecommendations()
            if case let .ok(response) = try await meCall, let account = try? response.body.json {
                handle = account.handle
                displayName = account.displayName
            }
            if case let .ok(response) = try await friendsCall {
                friends = try response.body.json.items
            }
            if case let .ok(response) = try await requestsCall {
                let both = try response.body.json
                incoming = both.incoming
                outgoing = both.outgoing
            }
            if case let .ok(response) = try await blocksCall {
                blocked = try response.body.json.items
            }
            if case let .ok(response) = try await invitesCall {
                invites = try response.body.json.items
            }
            if case let .ok(response) = try await activityCall {
                let page = try response.body.json
                activity = page.items
                activityNext = page.nextBefore
            }
            if case let .ok(response) = try await settingsCall {
                shareLibrary = try response.body.json.shareLibraryWithFriends
            }
            if case let .ok(response) = try await recommendationsCall {
                recommendations = try response.body.json.items
            }
            hasLoaded = true
            loadProblem = nil
        } catch {
            failLoad("Your friends could not be loaded. Aaru could not reach the server.")
        }
    }

    /// Claims or changes the handle; an empty name clears it. True when saved.
    func saveProfile(handle: String, displayName: String) async -> Bool {
        if let invalid = Self.handleProblem(handle) {
            problem = invalid
            return false
        }
        guard let api else { return false }
        let body = Components.Schemas.ProfileUpdate(handle: Self.normalized(handle), displayName: displayName)
        return await run("Your handle was not saved.") {
            switch try await api.updateProfile(body: .json(body)) {
            case let .ok(response):
                let user = try response.body.json
                self.handle = user.handle
                self.displayName = user.displayName
            case let .default(_, error): throw Failure(try? error.body.json.message)
            }
        }
    }

    /// Asks someone by handle. Asking someone who already asked you makes you friends.
    func send(to handle: String) async -> Bool {
        if let invalid = Self.handleProblem(handle) {
            problem = invalid
            return false
        }
        guard let api else { return false }
        let body = Components.Schemas.FriendRequestCreate(handle: Self.normalized(handle))
        return await run("That request was not sent.") {
            switch try await api.sendFriendRequest(body: .json(body)) {
            case let .ok(response):
                let view = try response.body.json
                notice = view.relationship == .friend
                    ? "You and @\(view.user.handle) are friends."
                    : "Request sent to @\(view.user.handle)."
            case let .default(_, error): throw Failure(try? error.body.json.message)
            }
            await load()
        }
    }

    func accept(_ request: FriendRequest) async {
        guard let api else { return }
        await run("That request could not be accepted.") {
            switch try await api.acceptFriendRequest(path: .init(id: request.id)) {
            case let .ok(response): notice = try "You and @\(response.body.json.handle) are friends."
            case let .default(_, error): throw Failure(try? error.body.json.message)
            }
            await load()
        }
    }

    /// Declines a request to the user, or cancels one they sent.
    func withdraw(_ request: FriendRequest) async {
        guard let api else { return }
        await run("That request is already gone.") {
            switch try await api.withdrawFriendRequest(path: .init(id: request.id)) {
            case .noContent: break
            case let .default(_, error): throw Failure(try? error.body.json.message)
            }
            await load()
        }
    }

    func remove(_ friend: SocialUser) async {
        guard let api else { return }
        await run("That friend was not removed.") {
            switch try await api.removeFriend(path: .init(userId: friend.userId)) {
            case .noContent: break
            case let .default(_, error): throw Failure(try? error.body.json.message)
            }
            await load()
        }
    }

    func block(_ person: SocialUser) async {
        guard let api else { return }
        await run("That person was not blocked.") {
            switch try await api.blockUser(path: .init(userId: person.userId)) {
            case .noContent: break
            case let .default(_, error): throw Failure(try? error.body.json.message)
            }
            await load()
        }
    }

    func unblock(_ person: SocialUser) async {
        guard let api else { return }
        await run("That person was not unblocked.") {
            switch try await api.unblockUser(path: .init(userId: person.userId)) {
            case .noContent: break
            case let .default(_, error): throw Failure(try? error.body.json.message)
            }
            await load()
        }
    }

    func reset() {
        handle = nil
        displayName = nil
        friends = []
        incoming = []
        outgoing = []
        blocked = []
        invites = []
        activity = []
        activityNext = nil
        recommendations = []
        shareLibrary = true
        hasLoaded = false
        loadProblem = nil
        problem = nil
        notice = nil
    }

    private struct Failure: Error {
        let message: String?
        init(_ message: String?) {
            self.message = message
        }
    }

    /// A first load that fails is a Try again (UX-063); a later one keeps what is shown.
    private func failLoad(_ message: String) {
        if hasLoaded {
            problem = message
        } else {
            loadProblem = message
        }
    }

    /// Runs one write and turns any failure into one visible message. True when it succeeded.
    @discardableResult
    private func run(_ fallback: String, _ call: () async throws -> Void) async -> Bool {
        problem = nil
        notice = nil
        do {
            try await call()
            return true
        } catch let failure as Failure {
            problem = failure.message ?? fallback
        } catch {
            problem = "\(fallback) Aaru could not reach the server."
        }
        return false
    }
}

/// Activity, sharing, reactions, recommendations and invite links, apart from the graph above.
extension SocialModel {
    // MARK: Activity and sharing (SOC-001 / SOC-003)

    func loadEarlierActivity() async {
        guard let api, let before = activityNext else { return }
        await run("Earlier activity could not be loaded.") {
            switch try await api.listFriendActivity(query: .init(before: before)) {
            case let .ok(response):
                let page = try response.body.json
                activity += page.items
                activityNext = page.nextBefore
            case let .default(_, error): throw Failure(try? error.body.json.message)
            }
        }
    }

    /// Turns sharing on or off at once, and back if the server says no.
    func setShareLibrary(_ share: Bool) async {
        guard let api else { return }
        let previous = shareLibrary
        shareLibrary = share
        let saved = await run("Your sharing setting was not saved.") {
            switch try await api.updateSocialSettings(body: .json(.init(shareLibraryWithFriends: share))) {
            case .ok: break
            case let .default(_, error): throw Failure(try? error.body.json.message)
            }
        }
        if !saved {
            shareLibrary = previous
        }
    }

    // MARK: Reactions and recommendations (SOC-007 / SOC-006)

    static let reactions = ["❤️", "😂", "😮", "😭", "🔥", "👏"]

    /// Sets the viewer's reaction on a friend's row (the same emoji again clears it), at once, and
    /// puts the row back if the server says no.
    func react(_ emoji: String, to item: ActivityItem) async {
        guard let api, let index = activity.firstIndex(where: { $0.id == item.id }) else { return }
        let chosen = item.myReaction == emoji ? nil : emoji
        let before = activity[index]
        activity[index] = Self.reacted(item, chosen)
        let saved = await run("That reaction was not saved.") {
            if let chosen, let value = Components.Schemas.ReactionSet.EmojiPayload(rawValue: chosen) {
                switch try await api.setActivityReaction(path: .init(id: item.id), body: .json(.init(emoji: value))) {
                case .noContent: break
                case let .default(_, error): throw Failure(try? error.body.json.message)
                }
            } else {
                switch try await api.clearActivityReaction(path: .init(id: item.id)) {
                case .noContent: break
                case let .default(_, error): throw Failure(try? error.body.json.message)
                }
            }
        }
        if !saved, let index = activity.firstIndex(where: { $0.id == item.id }) {
            activity[index] = before
        }
    }

    /// Adds a recommendation to Plan to watch, or dismisses it. Either way it leaves the list.
    func answer(_ item: RecommendationItem, add: Bool) async {
        guard let api else { return }
        let before = recommendations
        recommendations.removeAll { $0.id == item.id }
        let saved = await run("That recommendation is gone.") {
            if add {
                switch try await api.addRecommendation(path: .init(id: item.id)) {
                case .noContent: break
                case let .default(_, error): throw Failure(try? error.body.json.message)
                }
            } else {
                switch try await api.dismissRecommendation(path: .init(id: item.id)) {
                case .noContent: break
                case let .default(_, error): throw Failure(try? error.body.json.message)
                }
            }
        }
        if !saved {
            recommendations = before
        }
        if add, saved {
            let kind = MediaKind(type: item.title._type, isAnime: item.title.isAnime)
            notice = "\(item.title.title) is on your \(LibraryStatus.wishlist.label(for: kind))."
        }
    }

    /// Sends a title to friends with an optional note. True when sent.
    func recommend(_ ref: MediaRef, to friends: [String], note: String) async -> Bool {
        guard let api else { return false }
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = Components.Schemas.RecommendationCreate(to: friends, title: ref, note: note.isEmpty ? nil : note)
        return await run("That recommendation was not sent.") {
            switch try await api.recommendTitle(body: .json(body)) {
            case .noContent: break
            case let .default(_, error): throw Failure(try? error.body.json.message)
            }
        }
    }

    // MARK: Invite links (SOC-002)

    /// Makes a one-use link, optionally carrying a title to watch together. Nil when it failed.
    func invite(with title: CatalogHit?) async -> FriendInvite? {
        guard let api else { return nil }
        let ref = title.map { MediaRef(_type: $0._type, ids: $0.ids, title: $0.title, year: $0.year) }
        var made: FriendInvite?
        await run("The invite was not made.") {
            switch try await api.createFriendInvite(body: .json(.init(title: ref))) {
            case let .ok(response): made = try response.body.json
            case let .default(_, error): throw Failure(try? error.body.json.message)
            }
            await load()
        }
        return made
    }

    func revoke(_ invite: FriendInvite) async {
        guard let api else { return }
        await run("That invite is already gone.") {
            switch try await api.revokeFriendInvite(path: .init(code: invite.code)) {
            case .noContent: break
            case let .default(_, error): throw Failure(try? error.body.json.message)
            }
            await load()
        }
    }
}
