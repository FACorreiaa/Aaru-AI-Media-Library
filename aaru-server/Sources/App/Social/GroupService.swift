import AaruCore
import Foundation

/// Groups, their members, invites, text channels and messages (GRP-001…GRP-003).
///
/// Friends-only by the owner's decision: you can invite only a friend, and nobody finds a group
/// any other way. Everything about a group answers 404 to a non-member, the same as a group that
/// does not exist. Messages are server-visible and labelled so in the clients.
struct GroupService: Sendable {
    let stores: Stores
    var now: @Sendable () -> Date = { Date() }

    static let maxMembers = 50
    static let maxChannels = 20
    static let maxOwnedGroups = 10
    static let maxNameLength = 50
    static let maxChannelNameLength = 32
    static let maxTopicLength = 200
    static let maxMessageLength = 4000
    static let defaultPageSize = 50
    static let maxPageSize = 100
    /// The handle a message uses to tag the agent. Reserved in `SocialService`.
    static let agentHandle = "aaru"

    /// Everything a member's group screen shows.
    struct Detail: Sendable, Equatable {
        var summary: GroupSummary
        var channels: [GroupChannel]
        var members: [GroupMember]
        var invited: [SocialUser]
    }

    /// A page of messages and the authors the viewer blocked, whose messages arrive collapsed.
    struct Page: Sendable {
        var messages: [GroupMessage]
        var blocked: Set<UserID>
    }

    // MARK: Groups

    func groups(_ viewer: UserID) async throws -> [GroupSummary] {
        try await stores.groups.groups(for: viewer)
    }

    /// Creates a group with the viewer as owner and a `#general` text channel.
    func create(name: String, viewer: UserID) async throws -> Detail {
        _ = try await social.requireHandle(viewer)
        let name = try Self.validName(name)
        guard try await stores.groups.ownedCount(viewer) < Self.maxOwnedGroups else {
            throw Self.invalid("name", "You own \(Self.maxOwnedGroups) groups already. Delete one first.")
        }
        let id = UUID()
        let general = GroupChannel(
            id: UUID(), groupID: id, name: "general", topic: nil, position: 0, isDefault: true, createdAt: now()
        )
        try await stores.groups.createGroup(id: id, name: name, owner: viewer, general: general, now: now())
        return try await detail(id, viewer: viewer)
    }

    func detail(_ group: UUID, viewer: UserID) async throws -> Detail {
        guard let summary = try await stores.groups.summary(group, viewer: viewer) else { throw Self.noSuchGroup }
        async let channels = stores.groups.channels(group, viewer: viewer)
        async let members = stores.groups.members(group)
        async let invited = stores.groups.invitesPending(group)
        return try await Detail(
            summary: summary, channels: channels, members: members, invited: invited.map(\.invitee)
        )
    }

    func rename(_ group: UUID, name: String, viewer: UserID) async throws -> Detail {
        try await requireManager(group, viewer)
        try await stores.groups.renameGroup(group, name: Self.validName(name), now: now())
        return try await detail(group, viewer: viewer)
    }

    func delete(_ group: UUID, viewer: UserID) async throws {
        guard try await role(group, viewer) == .owner
        else { throw Self.forbidden("Only the owner can delete the group.") }
        try await stores.groups.deleteGroup(group)
    }

    // MARK: Members

    /// The owner makes a member an admin or back. Ownership moves only through `transfer`.
    func setRole(_ group: UUID, user: UserID, role newRole: GroupRole, viewer: UserID) async throws {
        guard try await role(group, viewer) == .owner else { throw Self.forbidden("Only the owner can change roles.") }
        guard newRole != .owner else { throw Self.invalid("role", "Transfer ownership instead.") }
        guard let current = try await stores.groups.role(group, user: user) else { throw Self.noSuchMember }
        guard current != .owner else { throw Self.invalid("role", "Transfer ownership instead.") }
        try await stores.groups.setRole(group, user: user, role: newRole)
    }

    /// Removes a member. Removing yourself is leaving; the owner transfers or deletes first.
    /// Admins remove members; the owner removes anyone.
    func remove(_ group: UUID, user: UserID, viewer: UserID) async throws {
        let mine = try await role(group, viewer)
        if user == viewer {
            guard mine != .owner else {
                throw Self.invalid("userId", "Transfer ownership or delete the group before leaving.")
            }
        } else {
            guard let theirs = try await stores.groups.role(group, user: user) else { throw Self.noSuchMember }
            guard mine.manages, theirs < mine else { throw Self.forbidden("You can't remove that member.") }
        }
        try await stores.groups.removeMember(group, user: user)
    }

    func transfer(_ group: UUID, to user: UserID, viewer: UserID) async throws {
        guard try await role(group, viewer) == .owner else { throw Self.forbidden("Only the owner can transfer.") }
        guard user != viewer, try await stores.groups.role(group, user: user) != nil else { throw Self.noSuchMember }
        try await stores.groups.transferOwnership(group, from: viewer, to: user)
    }

    // MARK: Invites

    /// Invites a friend. Asking again, or asking someone already in, changes nothing.
    func invite(_ group: UUID, user: UserID, viewer: UserID) async throws {
        _ = try await role(group, viewer)
        _ = try await social.requireHandle(viewer)
        guard try await stores.social.areFriends(viewer, user) else {
            throw Self.invalid("userId", "You can only invite friends.")
        }
        let members = try await stores.groups.members(group)
        guard !members.contains(where: { $0.user.id == user }) else { return }
        guard members.count < Self.maxMembers else {
            throw Self.invalid("userId", "A group holds \(Self.maxMembers) people.")
        }
        try await stores.groups.createInvite(id: UUID(), group: group, inviter: viewer, invitee: user, now: now())
    }

    func invites(_ viewer: UserID) async throws -> [GroupInvite] {
        try await stores.groups.invites(to: viewer)
    }

    /// Joins the group an invite is for, and returns it.
    func accept(_ invite: UUID, viewer: UserID) async throws -> GroupSummary {
        guard let pending = try await stores.groups.invites(to: viewer).first(where: { $0.id == invite }) else {
            throw Self.noSuchInvite
        }
        guard try await stores.groups.members(pending.groupID).count < Self.maxMembers else {
            throw Self.invalid("id", "That group is full.")
        }
        guard let group = try await stores.groups.acceptInvite(id: invite, invitee: viewer, now: now()),
              let summary = try await stores.groups.summary(group, viewer: viewer)
        else { throw Self.noSuchInvite }
        return summary
    }

    /// Declines an invite to the viewer, or cancels one the viewer sent.
    func decline(_ invite: UUID, viewer: UserID) async throws {
        guard try await stores.groups.deleteInvite(id: invite, party: viewer) else { throw Self.noSuchInvite }
    }

    // MARK: Channels

    func createChannel(_ group: UUID, name: String, topic: String?, viewer: UserID) async throws -> GroupChannel {
        try await requireManager(group, viewer)
        let existing = try await stores.groups.channels(group, viewer: viewer)
        guard existing.count < Self.maxChannels else {
            throw Self.invalid("name", "A group holds \(Self.maxChannels) channels.")
        }
        let channel = try GroupChannel(
            id: UUID(), groupID: group, name: Self.channelName(name), topic: Self.validTopic(topic),
            position: (existing.map(\.position).max() ?? 0) + 1, isDefault: false, createdAt: now()
        )
        try await stores.groups.createChannel(channel)
        return channel
    }

    func updateChannel(
        _ group: UUID, channel: UUID, name: String?, topic: String?, viewer: UserID
    ) async throws -> GroupChannel {
        try await requireManager(group, viewer)
        _ = try await requireChannel(group, channel)
        try await stores.groups.updateChannel(
            channel, name: name.map(Self.channelName), topic: topic.map { try Self.validTopic($0) }
        )
        return try await requireChannel(group, channel)
    }

    func deleteChannel(_ group: UUID, channel: UUID, viewer: UserID) async throws {
        try await requireManager(group, viewer)
        guard try await !requireChannel(group, channel).isDefault else {
            throw Self.invalid("channelId", "The first channel stays; rename it instead.")
        }
        _ = try await stores.groups.deleteChannel(channel)
    }

    // MARK: Messages

    func messages(
        _ group: UUID, channel: UUID, cursor: MessageCursor, limit: Int?, viewer: UserID
    ) async throws -> Page {
        _ = try await role(group, viewer)
        _ = try await requireChannel(group, channel)
        let limit = min(max(limit ?? Self.defaultPageSize, 1), Self.maxPageSize)
        async let messages = stores.groups.messages(channel, cursor: cursor, limit: limit)
        async let blocked = stores.social.blocked(by: viewer)
        return try await Page(messages: messages, blocked: Set(blocked.map(\.id)))
    }

    /// Posts a message. A retry with the same `nonce` returns the first message.
    func post(_ group: UUID, channel: UUID, body: String, nonce: String?, viewer: UserID) async throws -> GroupMessage {
        _ = try await role(group, viewer)
        _ = try await requireChannel(group, channel)
        let author = try await social.requireHandle(viewer)
        let body = try Self.validBody(body)
        let nonce = nonce?.trimmingCharacters(in: .whitespaces)
        if let nonce, nonce.count > 64 {
            throw Self.invalid("clientNonce", "Keep the nonce under 64 characters.")
        }
        let (mentions, agent) = try await Self.mentions(in: body, members: stores.groups.members(group))
        return try await stores.groups.postMessage(
            GroupMessage(
                id: UUID(), channelID: channel, author: author, body: body, mentions: mentions,
                mentionsAgent: agent, createdAt: now()
            ),
            nonce: nonce?.isEmpty == false ? nonce : nil
        )
    }

    /// Only the author edits a message.
    func edit(_ group: UUID, channel: UUID, message: UUID, body: String, viewer: UserID) async throws -> GroupMessage {
        _ = try await role(group, viewer)
        let original = try await requireMessage(group, channel, message)
        guard original.author?.id == viewer, original.deletedAt == nil else {
            throw Self.forbidden("You can only edit your own messages.")
        }
        let body = try Self.validBody(body)
        let (mentions, agent) = try await Self.mentions(in: body, members: stores.groups.members(group))
        try await stores.groups.editMessage(message, body: body, mentions: mentions, mentionsAgent: agent, now: now())
        return try await requireMessage(group, channel, message)
    }

    /// The author, an admin or the owner deletes a message. Deleting twice changes nothing.
    func deleteMessage(_ group: UUID, channel: UUID, message: UUID, viewer: UserID) async throws {
        let mine = try await role(group, viewer)
        let original = try await requireMessage(group, channel, message)
        guard original.author?.id == viewer || mine.manages else {
            throw Self.forbidden("You can only delete your own messages.")
        }
        try await stores.groups.deleteMessage(message, now: now())
    }

    func markRead(_ group: UUID, channel: UUID, upTo message: UUID, viewer: UserID) async throws {
        _ = try await role(group, viewer)
        _ = try await requireMessage(group, channel, message)
        try await stores.groups.markRead(viewer, channel: channel, upTo: message)
    }

    // MARK: Rules

    private var social: SocialService {
        SocialService(stores: stores, now: now)
    }

    /// The viewer's role, or the same 404 as a group that does not exist.
    private func role(_ group: UUID, _ viewer: UserID) async throws -> GroupRole {
        guard let role = try await stores.groups.role(group, user: viewer) else { throw Self.noSuchGroup }
        return role
    }

    private func requireManager(_ group: UUID, _ viewer: UserID) async throws {
        guard try await role(group, viewer).manages else {
            throw Self.forbidden("Only the owner and admins can do that.")
        }
    }

    private func requireChannel(_ group: UUID, _ channel: UUID) async throws -> GroupChannel {
        guard let found = try await stores.groups.channel(channel, group: group) else {
            throw AppError.notFound("No such channel.")
        }
        return found
    }

    private func requireMessage(_ group: UUID, _ channel: UUID, _ message: UUID) async throws -> GroupMessage {
        _ = try await requireChannel(group, channel)
        guard let found = try await stores.groups.message(message, channel: channel) else {
            throw AppError.notFound("No such message.")
        }
        return found
    }
}

// MARK: Validation and parsing

extension GroupService {
    /// Members tagged with `@handle`, and whether `@aaru` was. A tag inside a word or an email
    /// address is not a mention.
    static func mentions(in body: String, members: [GroupMember]) -> (users: [UserID], agent: Bool) {
        let byHandle = Dictionary(members.map { ($0.user.handle, $0.user.id) }, uniquingKeysWith: { first, _ in first })
        var users: [UserID] = []
        var agent = false
        for match in body.matches(of: /@([A-Za-z0-9_]{3,20})/) {
            let before = match.range.lowerBound == body
                .startIndex ? nil : body[body.index(before: match.range.lowerBound)]
            let after = match.range.upperBound == body.endIndex ? nil : body[match.range.upperBound]
            guard !(before.map(isHandleCharacter) ?? false), !(after.map(isHandleCharacter) ?? false) else { continue }
            let handle = match.output.1.lowercased()
            if handle == agentHandle {
                agent = true
            } else if let id = byHandle[handle], !users.contains(id) {
                users.append(id)
            }
        }
        return (users, agent)
    }

    private static func isHandleCharacter(_ character: Character) -> Bool {
        character == "_" || character == "@" || character.isLetter || character.isNumber
    }

    /// Lowercase, spaces to dashes, letters, numbers, dashes and underscores only: `Movie Night`
    /// becomes `movie-night`.
    static func channelName(_ raw: String) throws -> String {
        let words = raw.lowercased().split(whereSeparator: { $0.isWhitespace || $0 == "-" })
        let name = words.map { $0.filter { $0.isLetter || $0.isNumber || $0 == "_" } }
            .filter { !$0.isEmpty }.joined(separator: "-")
        guard !name.isEmpty, name.count <= maxChannelNameLength else {
            throw invalid("name", "Use 1–\(maxChannelNameLength) letters or numbers.")
        }
        return name
    }

    static func validName(_ raw: String) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= maxNameLength else {
            throw invalid("name", "Use 1–\(maxNameLength) characters.")
        }
        return name
    }

    /// Trimmed; empty clears it.
    static func validTopic(_ raw: String?) throws -> String? {
        guard let topic = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !topic.isEmpty else { return nil }
        guard topic.count <= maxTopicLength else {
            throw invalid("topic", "Keep the topic under \(maxTopicLength) characters.")
        }
        return topic
    }

    static func validBody(_ raw: String) throws -> String {
        let body = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw invalid("body", "Write something first.") }
        guard body.count <= maxMessageLength else {
            throw invalid("body", "Keep messages under \(maxMessageLength) characters.")
        }
        return body
    }

    static let noSuchGroup = AppError.notFound("No such group.")
    static let noSuchMember = AppError.notFound("Not a member of this group.")
    static let noSuchInvite = AppError.notFound("No such invite.")

    private static func forbidden(_ message: String) -> AppError {
        AppError(status: .forbidden, code: "forbidden", message: message)
    }

    private static func invalid(_ field: String, _ message: String) -> AppError {
        AppError(status: .unprocessableContent, code: "validation_failed", message: message, details: [field: message])
    }
}
