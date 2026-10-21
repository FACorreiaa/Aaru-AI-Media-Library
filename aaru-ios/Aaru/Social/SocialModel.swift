import AaruAPI
import Foundation
import Observation

typealias SocialUser = Components.Schemas.SocialUser
typealias FriendRequest = Components.Schemas.FriendRequest

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
    private(set) var hasLoaded = false
    var problem: String?
    /// A one-line result of the last request ("Request sent to @ana.").
    var notice: String?

    @ObservationIgnored private let api: Client?

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
            hasLoaded = true
        } catch {
            problem = "Your friends could not be loaded. Aaru could not reach the server."
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

    private struct Failure: Error {
        let message: String?
        init(_ message: String?) {
            self.message = message
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

extension SocialUser {
    /// "Ana · @ana", or "@ana" when there is no name.
    var label: String {
        displayName.map { "\($0) · @\(handle)" } ?? "@\(handle)"
    }

    /// One or two letters for a monogram.
    var monogram: String {
        let words = (displayName ?? "").split(whereSeparator: \.isWhitespace)
        if words.count >= 2, let first = words[0].first, let second = words[1].first {
            return "\(first)\(second)".uppercased()
        }
        return String(words.first?.first ?? handle.first ?? "?").uppercased()
    }
}
