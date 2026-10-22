import aaruAPI
import AaruCore
import Foundation
import OpenAPIRuntime

/// SOC-002 friend invite links.
extension APIImplementation {
    func listFriendInvites(_: Operations.ListFriendInvites.Input) async throws -> Operations.ListFriendInvites.Output {
        let invites = try await services.invites.open(currentUser())
        return .ok(.init(body: .json(.init(items: invites.map { invite($0.0, title: $0.1) }))))
    }

    func createFriendInvite(_ input: Operations.CreateFriendInvite.Input) async throws
        -> Operations.CreateFriendInvite.Output
    {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let (created, title) = try await services.invites.create(currentUser(), title: body.title.map(MediaRef.init))
        return .ok(.init(body: .json(invite(created, title: title))))
    }

    func revokeFriendInvite(_ input: Operations.RevokeFriendInvite.Input) async throws
        -> Operations.RevokeFriendInvite.Output
    {
        try await services.invites.revoke(code: input.path.code, viewer: currentUser())
        return .noContent(.init())
    }

    func redeemFriendInvite(_ input: Operations.RedeemFriendInvite.Input) async throws
        -> Operations.RedeemFriendInvite.Output
    {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let (friend, titleAdded) = try await services.invites.redeem(
            code: input.path.code, viewer: currentUser(), addTitle: body.addTitle
        )
        return .ok(.init(body: .json(.init(friend: .init(friend), titleAdded: titleAdded))))
    }

    func getInvitePreview(_ input: Operations.GetInvitePreview.Input) async throws
        -> Operations.GetInvitePreview.Output
    {
        let context = try currentContext()
        let preview = try await services.invites.preview(
            code: input.path.code, viewer: context.userID, clientAddress: context.clientAddressForRateLimit
        )
        return .ok(.init(body: .json(.init(
            inviter: .init(preview.inviter),
            title: preview.title.map { .init($0) },
            expiresAt: preview.invite.expiresAt,
            relationship: preview.relationship.flatMap { .init(rawValue: $0.rawValue) }
        ))))
    }

    private func invite(_ invite: FriendInvite, title: Title?) -> Components.Schemas.FriendInvite {
        .init(
            code: invite.code,
            url: services.invites.url(invite).absoluteString,
            createdAt: invite.createdAt,
            expiresAt: invite.expiresAt,
            title: title.map { .init($0) }
        )
    }
}
