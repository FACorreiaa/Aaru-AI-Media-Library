import AaruCore
import Foundation

extension GroupService {
    // MARK: Channels

    /// Adds a channel. A `title` channel needs the title, and takes its name when none is given.
    func createChannel(
        _ group: UUID, kind: ChannelKind = .text, name: String?, topic: String?, title ref: MediaRef? = nil,
        viewer: UserID
    ) async throws -> GroupChannel {
        try await requireManager(group, viewer)
        let existing = try await stores.groups.channels(group, viewer: viewer)
        guard existing.count < Self.maxChannels else {
            throw Self.invalid("name", "A group holds \(Self.maxChannels) channels.")
        }
        var title: Title?
        if kind == .title {
            guard let ref else { throw Self.invalid("title", "Pick the title this channel is about.") }
            title = try await resolver.resolve(ref)
        }
        guard let raw = name ?? title.map({ String($0.title.prefix(Self.maxChannelNameLength)) }) else {
            throw Self.invalid("name", "Name the channel.")
        }
        let channel = try GroupChannel(
            id: UUID(), groupID: group, kind: kind, titleID: title?.id, name: Self.channelName(raw),
            topic: Self.validTopic(topic), position: (existing.map(\.position).max() ?? 0) + 1, isDefault: false,
            createdAt: now()
        )
        try await stores.groups.createChannel(channel)
        await announce(.groupUpdated(group: group), in: group)
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
        await announce(.groupUpdated(group: group), in: group)
        return try await requireChannel(group, channel)
    }

    func deleteChannel(_ group: UUID, channel: UUID, viewer: UserID) async throws {
        try await requireManager(group, viewer)
        guard try await !requireChannel(group, channel).isDefault else {
            throw Self.invalid("channelId", "The first channel stays; rename it instead.")
        }
        _ = try await stores.groups.deleteChannel(channel)
        await announce(.groupUpdated(group: group), in: group)
    }
}
