import aaruAPI
import AaruCore
import Foundation
import OpenAPIRuntime

extension APIImplementation {
    func listGroups(_: Operations.ListGroups.Input) async throws -> Operations.ListGroups.Output {
        try await .ok(.init(body: .json(.init(items: services.groups.groups(currentUser()).map { .init($0) }))))
    }

    func createGroup(_ input: Operations.CreateGroup.Input) async throws -> Operations.CreateGroup.Output {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        return try await .ok(.init(body: .json(.init(services.groups.create(name: body.name, viewer: currentUser())))))
    }

    func getGroup(_ input: Operations.GetGroup.Input) async throws -> Operations.GetGroup.Output {
        try await .ok(.init(body: .json(.init(services.groups.detail(
            groupID(input.path.groupId),
            viewer: currentUser()
        )))))
    }

    func updateGroup(_ input: Operations.UpdateGroup.Input) async throws -> Operations.UpdateGroup.Output {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let detail = try await services.groups.rename(
            groupID(input.path.groupId),
            name: body.name,
            viewer: currentUser()
        )
        return .ok(.init(body: .json(.init(detail))))
    }

    func deleteGroup(_ input: Operations.DeleteGroup.Input) async throws -> Operations.DeleteGroup.Output {
        try await services.groups.delete(groupID(input.path.groupId), viewer: currentUser())
        return .noContent(.init())
    }

    func updateGroupMember(_ input: Operations.UpdateGroupMember.Input) async throws
        -> Operations.UpdateGroupMember.Output
    {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        try await services.groups.setRole(
            groupID(input.path.groupId), user: memberID(input.path.userId),
            role: body.role == .admin ? .admin : .member, viewer: currentUser()
        )
        return .noContent(.init())
    }

    func removeGroupMember(_ input: Operations.RemoveGroupMember.Input) async throws
        -> Operations.RemoveGroupMember.Output
    {
        try await services.groups.remove(
            groupID(input.path.groupId), user: memberID(input.path.userId), viewer: currentUser()
        )
        return .noContent(.init())
    }

    func transferGroup(_ input: Operations.TransferGroup.Input) async throws -> Operations.TransferGroup.Output {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        try await services.groups.transfer(
            groupID(input.path.groupId),
            to: memberID(body.userId),
            viewer: currentUser()
        )
        return .noContent(.init())
    }

    func inviteToGroup(_ input: Operations.InviteToGroup.Input) async throws -> Operations.InviteToGroup.Output {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        guard let user = UUID(uuidString: body.userId) else { throw SocialService.noSuchUser }
        try await services.groups.invite(groupID(input.path.groupId), user: UserID(user), viewer: currentUser())
        return .noContent(.init())
    }

    func listGroupInvites(_: Operations.ListGroupInvites.Input) async throws -> Operations.ListGroupInvites.Output {
        try await .ok(.init(body: .json(.init(items: services.groups.invites(currentUser()).map { .init($0) }))))
    }

    func acceptGroupInvite(_ input: Operations.AcceptGroupInvite.Input) async throws
        -> Operations.AcceptGroupInvite.Output
    {
        let group = try await services.groups.accept(inviteID(input.path.id), viewer: currentUser())
        return .ok(.init(body: .json(.init(group))))
    }

    func declineGroupInvite(_ input: Operations.DeclineGroupInvite.Input) async throws
        -> Operations.DeclineGroupInvite.Output
    {
        try await services.groups.decline(inviteID(input.path.id), viewer: currentUser())
        return .noContent(.init())
    }

    func createChannel(_ input: Operations.CreateChannel.Input) async throws -> Operations.CreateChannel.Output {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let channel = try await services.groups.createChannel(
            groupID(input.path.groupId), name: body.name, topic: body.topic, viewer: currentUser()
        )
        return .ok(.init(body: .json(.init(channel))))
    }

    func updateChannel(_ input: Operations.UpdateChannel.Input) async throws -> Operations.UpdateChannel.Output {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let channel = try await services.groups.updateChannel(
            groupID(input.path.groupId), channel: channelID(input.path.channelId),
            name: body.name, topic: body.topic, viewer: currentUser()
        )
        return .ok(.init(body: .json(.init(channel))))
    }

    func deleteChannel(_ input: Operations.DeleteChannel.Input) async throws -> Operations.DeleteChannel.Output {
        try await services.groups.deleteChannel(
            groupID(input.path.groupId), channel: channelID(input.path.channelId), viewer: currentUser()
        )
        return .noContent(.init())
    }

    func listMessages(_ input: Operations.ListMessages.Input) async throws -> Operations.ListMessages.Output {
        let cursor: MessageCursor = if let before = input.query.before {
            try .before(messageID(before))
        } else if let after = input.query.after {
            try .after(messageID(after))
        } else {
            .latest
        }
        let viewer = try currentUser()
        let page = try await services.groups.messages(
            groupID(input.path.groupId), channel: channelID(input.path.channelId), cursor: cursor,
            limit: input.query.limit, viewer: viewer
        )
        return .ok(.init(body: .json(.init(items: page.messages.map {
            .init($0, fromBlocked: $0.author.map { page.blocked.contains($0.id) } ?? false, viewer: viewer)
        }))))
    }

    func postMessage(_ input: Operations.PostMessage.Input) async throws -> Operations.PostMessage.Output {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let message = try await services.groups.post(
            groupID(input.path.groupId), channel: channelID(input.path.channelId), body: body.body,
            nonce: body.clientNonce, viewer: currentUser()
        )
        return try .ok(.init(body: .json(.init(message, fromBlocked: false, viewer: currentUser()))))
    }

    func editMessage(_ input: Operations.EditMessage.Input) async throws -> Operations.EditMessage.Output {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let message = try await services.groups.edit(
            groupID(input.path.groupId), channel: channelID(input.path.channelId),
            message: messageID(input.path.messageId), body: body.body, viewer: currentUser()
        )
        return try .ok(.init(body: .json(.init(message, fromBlocked: false, viewer: currentUser()))))
    }

    func deleteMessage(_ input: Operations.DeleteMessage.Input) async throws -> Operations.DeleteMessage.Output {
        try await services.groups.deleteMessage(
            groupID(input.path.groupId), channel: channelID(input.path.channelId),
            message: messageID(input.path.messageId), viewer: currentUser()
        )
        return .noContent(.init())
    }

    func markChannelRead(_ input: Operations.MarkChannelRead.Input) async throws
        -> Operations.MarkChannelRead.Output
    {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        try await services.groups.markRead(
            groupID(input.path.groupId), channel: channelID(input.path.channelId),
            upTo: messageID(body.messageId), viewer: currentUser()
        )
        return .noContent(.init())
    }

    // MARK: Path ids: a malformed id reads as one that does not exist.

    private func groupID(_ raw: String) throws -> UUID {
        guard let id = UUID(uuidString: raw) else { throw GroupService.noSuchGroup }
        return id
    }

    private func channelID(_ raw: String) throws -> UUID {
        guard let id = UUID(uuidString: raw) else { throw AppError.notFound("No such channel.") }
        return id
    }

    private func messageID(_ raw: String) throws -> UUID {
        guard let id = UUID(uuidString: raw) else { throw AppError.notFound("No such message.") }
        return id
    }

    private func inviteID(_ raw: String) throws -> UUID {
        guard let id = UUID(uuidString: raw) else { throw GroupService.noSuchInvite }
        return id
    }

    private func memberID(_ raw: String) throws -> UserID {
        guard let id = UUID(uuidString: raw) else { throw GroupService.noSuchMember }
        return UserID(id)
    }
}

extension Components.Schemas.GroupRole {
    init(_ role: GroupRole) {
        switch role {
        case .owner: self = .owner
        case .admin: self = .admin
        case .member: self = .member
        }
    }
}

extension Components.Schemas.GroupSummary {
    init(_ group: GroupSummary) {
        self.init(
            id: group.id.uuidString, name: group.name, role: .init(group.role),
            defaultChannelId: group.defaultChannelID.uuidString, unread: group.unread, mentions: group.mentions
        )
    }
}

extension Components.Schemas.Channel {
    init(_ channel: GroupChannel) {
        self.init(
            id: channel.id.uuidString, kind: .text, name: channel.name, topic: channel.topic,
            position: channel.position, isDefault: channel.isDefault, unread: channel.unread,
            mentions: channel.mentions
        )
    }
}

extension Components.Schemas.GroupDetail {
    init(_ detail: GroupService.Detail) {
        self.init(
            group: .init(detail.summary),
            channels: detail.channels.map { .init($0) },
            members: detail.members.map { .init(user: .init($0.user), role: .init($0.role), joinedAt: $0.joinedAt) },
            invited: detail.invited.map { .init($0) }
        )
    }
}

extension Components.Schemas.GroupInvite {
    init(_ invite: GroupInvite) {
        self.init(
            id: invite.id.uuidString, groupId: invite.groupID.uuidString, groupName: invite.groupName,
            inviter: .init(invite.inviter), createdAt: invite.createdAt
        )
    }
}

extension Components.Schemas.GroupMessage {
    /// `viewer` sees the nonce only on their own messages, to match a pending send to its echo.
    init(_ message: GroupMessage, fromBlocked: Bool, viewer: UserID) {
        self.init(
            id: message.id.uuidString, channelId: message.channelID.uuidString,
            author: message.author.map { .init($0) },
            body: message.body, mentions: message.mentions.map(\.description), mentionsAgent: message.mentionsAgent,
            fromBlocked: fromBlocked, deleted: message.deletedAt != nil, createdAt: message.createdAt,
            editedAt: message.editedAt,
            clientNonce: message.author?.id == viewer ? message.clientNonce : nil
        )
    }
}

extension APIImplementation {
    func createRealtimeTicket(_: Operations.CreateRealtimeTicket.Input) async throws
        -> Operations.CreateRealtimeTicket.Output
    {
        let (ticket, expiresAt) = try await services.realtime.issueTicket(for: currentUser(), now: Date())
        let base = services.agentTokens.publicBaseURL
        var url = URLComponents()
        url.scheme = base.scheme == "http" ? "ws" : "wss"
        url.host = base.host
        url.port = base.port
        url.path = "/v1/ws"
        url.queryItems = [URLQueryItem(name: "ticket", value: ticket)]
        return .ok(.init(body: .json(.init(ticket: ticket, url: url.string ?? "", expiresAt: expiresAt))))
    }
}
