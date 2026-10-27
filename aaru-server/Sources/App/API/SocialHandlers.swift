import aaruAPI
import AaruCore
import Foundation
import OpenAPIRuntime

extension APIImplementation {
    func updateProfile(_ input: Operations.UpdateProfile.Input) async throws -> Operations.UpdateProfile.Output {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        // Absent keeps a field; an empty name clears it.
        let profile = try await services.social.saveProfile(currentUser(), .init(
            handle: body.handle, firstName: body.firstName, lastName: body.lastName, displayName: body.displayName
        ))
        return .ok(.init(body: .json(.init(profile))))
    }

    func getSocialUser(_ input: Operations.GetSocialUser.Input) async throws -> Operations.GetSocialUser.Output {
        let (user, relationship) = try await services.social.lookup(handle: input.path.handle, viewer: currentUser())
        return .ok(.init(body: .json(.init(user: .init(user), relationship: .init(relationship)))))
    }

    func listFriendRequests(_: Operations.ListFriendRequests.Input) async throws
        -> Operations.ListFriendRequests.Output
    {
        let (incoming, outgoing) = try await services.social.requests(currentUser())
        return .ok(.init(body: .json(.init(
            incoming: incoming.map { .init(id: $0.id.uuidString, user: .init($0.sender), createdAt: $0.createdAt) },
            outgoing: outgoing.map { .init(id: $0.id.uuidString, user: .init($0.recipient), createdAt: $0.createdAt) }
        ))))
    }

    func sendFriendRequest(_ input: Operations.SendFriendRequest.Input) async throws
        -> Operations.SendFriendRequest.Output
    {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let (user, relationship) = try await services.social.sendRequest(from: currentUser(), toHandle: body.handle)
        return .ok(.init(body: .json(.init(user: .init(user), relationship: .init(relationship)))))
    }

    func withdrawFriendRequest(_ input: Operations.WithdrawFriendRequest.Input) async throws
        -> Operations.WithdrawFriendRequest.Output
    {
        try await services.social.withdraw(requestID(input.path.id), viewer: currentUser())
        return .noContent(.init())
    }

    func acceptFriendRequest(_ input: Operations.AcceptFriendRequest.Input) async throws
        -> Operations.AcceptFriendRequest.Output
    {
        let friend = try await services.social.accept(requestID(input.path.id), viewer: currentUser())
        return .ok(.init(body: .json(.init(friend))))
    }

    func listFriends(_: Operations.ListFriends.Input) async throws -> Operations.ListFriends.Output {
        try await .ok(.init(body: .json(.init(items: services.social.friends(currentUser()).map { .init($0) }))))
    }

    func removeFriend(_ input: Operations.RemoveFriend.Input) async throws -> Operations.RemoveFriend.Output {
        try await services.social.unfriend(socialUserID(input.path.userId), viewer: currentUser())
        return .noContent(.init())
    }

    func listBlocks(_: Operations.ListBlocks.Input) async throws -> Operations.ListBlocks.Output {
        try await .ok(.init(body: .json(.init(items: services.social.blocked(currentUser()).map { .init($0) }))))
    }

    func blockUser(_ input: Operations.BlockUser.Input) async throws -> Operations.BlockUser.Output {
        try await services.social.block(socialUserID(input.path.userId), viewer: currentUser())
        return .noContent(.init())
    }

    func unblockUser(_ input: Operations.UnblockUser.Input) async throws -> Operations.UnblockUser.Output {
        try await services.social.unblock(socialUserID(input.path.userId), viewer: currentUser())
        return .noContent(.init())
    }

    func reportUser(_ input: Operations.ReportUser.Input) async throws -> Operations.ReportUser.Output {
        guard case let .json(body) = input.body,
              let reason = ReportReason(rawValue: body.reason.rawValue)
        else { throw AppError.badRequest() }
        try await services.social.report(
            socialUserID(body.userId), reason: reason, note: body.note, viewer: currentUser()
        )
        return .noContent(.init())
    }

    private func requestID(_ raw: String) throws -> UUID {
        guard let id = UUID(uuidString: raw) else { throw AppError.notFound("No such request.") }
        return id
    }

    private func socialUserID(_ raw: String) throws -> UserID {
        guard let id = UUID(uuidString: raw) else { throw SocialService.noSuchUser }
        return UserID(id)
    }
}

extension Components.Schemas.SocialUser {
    init(_ user: SocialUser) {
        self.init(
            userId: user.id.description,
            handle: user.handle,
            displayName: user.displayName,
            avatarUrl: user.avatarVersion.map { SocialService.avatarPath(user.id, version: $0) }
        )
    }
}

extension Components.Schemas.SocialUserView.RelationshipPayload {
    init(_ relationship: Relationship) {
        switch relationship {
        case .none: self = .none
        case .friend: self = .friend
        case .outgoing: self = .outgoing
        case .incoming: self = .incoming
        case .self: self = ._self
        }
    }
}
