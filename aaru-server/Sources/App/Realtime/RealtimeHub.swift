import aaruAPI
import AaruCore
import Foundation
import Logging

/// Something that happened in a group, for the members' open sockets (GRP-006). Writes stay on
/// REST; a service publishes after its write commits, so an event never announces a row that
/// is not there.
enum GroupEvent: Sendable, Equatable {
    /// `blockedBy`: recipients who blocked the author, who get the message flagged.
    /// `veiledFor`: recipients behind the message's spoiler stamp, who get it veiled.
    case messageCreated(group: UUID, GroupMessage, blockedBy: Set<UserID>, veiledFor: Set<UserID>)
    case messageUpdated(group: UUID, GroupMessage, blockedBy: Set<UserID>, veiledFor: Set<UserID>)
    case messageDeleted(group: UUID, channel: UUID, message: UUID)
    case typing(group: UUID, channel: UUID, SocialUser)
    /// The recipient read a channel on another device.
    case read(group: UUID, channel: UUID)
    /// Name, channels, members or invites changed: refetch the group.
    case groupUpdated(group: UUID)
    /// The recipient is no longer in the group, or it is gone.
    case groupRemoved(group: UUID)
    /// The recipient's invites changed.
    case invitesChanged
    case shelfUpdated(group: UUID, channel: UUID)
    /// The party in a watch channel opened, changed state, gained or lost a ready member.
    case watchUpdated(group: UUID, channel: UUID)
    case watchReaction(group: UUID, channel: UUID, SocialUser, String)
    /// `@aaru` is working on an answer to that mention.
    case agentThinking(group: UUID, channel: UUID, mention: UUID)
}

protocol GroupEventPublishing: Sendable {
    func publish(_ event: GroupEvent, to recipients: [UserID]) async
}

/// Every open socket on this replica, by user, and the browser tickets that open them.
///
/// One replica, as RT-001 assumes. A second replica needs cross-pod fan-out (ARCHITECTURE.md:
/// Valkey pub/sub); that is documented, not built.
actor RealtimeHub: GroupEventPublishing {
    /// Writes one text frame to one socket.
    typealias Sink = @Sendable (String) async throws -> Void

    static let ticketLifetime: TimeInterval = 60

    private var sinks: [UserID: [UUID: Sink]] = [:]
    private var tickets: [String: (user: UserID, expiresAt: Date)] = [:]
    private let logger = Logger(label: "aaru-realtime")

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    // MARK: Connections

    func connect(_ user: UserID, sink: @escaping Sink) -> UUID {
        let id = UUID()
        sinks[user, default: [:]][id] = sink
        return id
    }

    func disconnect(_ user: UserID, connection: UUID) {
        sinks[user]?[connection] = nil
        if sinks[user]?.isEmpty == true {
            sinks[user] = nil
        }
    }

    func connectionCount(_ user: UserID) -> Int {
        sinks[user]?.count ?? 0
    }

    // MARK: Tickets

    /// A single-use ticket for a browser socket, valid for `ticketLifetime`.
    func issueTicket(for user: UserID, now: Date) -> (ticket: String, expiresAt: Date) {
        tickets = tickets.filter { $0.value.expiresAt > now }
        let ticket = OpaqueToken.generate()
        let expiresAt = now.addingTimeInterval(Self.ticketLifetime)
        tickets[ticket] = (user, expiresAt)
        return (ticket, expiresAt)
    }

    /// The ticket's user, once. A second use or an expired ticket is nil.
    func redeem(_ ticket: String, now: Date) -> UserID? {
        guard let entry = tickets.removeValue(forKey: ticket), entry.expiresAt > now else { return nil }
        return entry.user
    }

    // MARK: Publishing

    func publish(_ event: GroupEvent, to recipients: [UserID]) async {
        struct Delivery {
            let user: UserID
            let connection: UUID
            let sink: Sink
            let frame: String
        }
        var deliveries: [Delivery] = []
        for user in Set(recipients) {
            guard let connections = sinks[user], let frame = Self.frame(event, for: user) else { continue }
            for (id, sink) in connections {
                deliveries.append(Delivery(user: user, connection: id, sink: sink, frame: frame))
            }
        }
        // One slow socket must not hold up the rest.
        let failed = await withTaskGroup(of: (UserID, UUID)?.self) { group in
            for delivery in deliveries {
                group.addTask {
                    do {
                        try await delivery.sink(delivery.frame)
                        return nil
                    } catch {
                        return (delivery.user, delivery.connection)
                    }
                }
            }
            return await group.reduce(into: [(UserID, UUID)]()) { failed, result in
                if let result {
                    failed.append(result)
                }
            }
        }
        for (user, id) in failed {
            logger.debug("Dropping a socket that failed a write", metadata: ["user": "\(user)"])
            disconnect(user, connection: id)
        }
    }

    /// The JSON frame `RealtimeEvent` for one recipient.
    static func frame(_ event: GroupEvent, for recipient: UserID) -> String? {
        frame(dto(event, for: recipient))
    }

    static func frame(_ event: Components.Schemas.RealtimeEvent) -> String? {
        (try? encoder.encode(event)).flatMap { String(bytes: $0, encoding: .utf8) }
    }

    // One case per event type; splitting it would only hide the mapping.
    // swiftlint:disable:next cyclomatic_complexity
    static func dto(_ event: GroupEvent, for recipient: UserID) -> Components.Schemas.RealtimeEvent {
        switch event {
        case let .messageCreated(group, message, blockedBy, veiledFor):
            .init(
                _type: .message_created, groupId: group.uuidString, channelId: message.channelID.uuidString,
                messageId: message.id.uuidString,
                message: .init(
                    message, fromBlocked: blockedBy.contains(recipient), viewer: recipient,
                    veiled: veiledFor.contains(recipient)
                )
            )
        case let .messageUpdated(group, message, blockedBy, veiledFor):
            .init(
                _type: .message_updated, groupId: group.uuidString, channelId: message.channelID.uuidString,
                messageId: message.id.uuidString,
                message: .init(
                    message, fromBlocked: blockedBy.contains(recipient), viewer: recipient,
                    veiled: veiledFor.contains(recipient)
                )
            )
        case let .messageDeleted(group, channel, message):
            .init(
                _type: .message_deleted, groupId: group.uuidString, channelId: channel.uuidString,
                messageId: message.uuidString
            )
        case let .typing(group, channel, user):
            .init(_type: .typing, groupId: group.uuidString, channelId: channel.uuidString, user: .init(user))
        case let .read(group, channel):
            .init(_type: .read, groupId: group.uuidString, channelId: channel.uuidString)
        case let .groupUpdated(group):
            .init(_type: .group_updated, groupId: group.uuidString)
        case let .groupRemoved(group):
            .init(_type: .group_removed, groupId: group.uuidString)
        case .invitesChanged:
            .init(_type: .invites_changed)
        case let .shelfUpdated(group, channel):
            .init(_type: .shelf_updated, groupId: group.uuidString, channelId: channel.uuidString)
        case let .watchUpdated(group, channel):
            .init(_type: .watch_updated, groupId: group.uuidString, channelId: channel.uuidString)
        case let .watchReaction(group, channel, user, emoji):
            .init(
                _type: .watch_reaction, groupId: group.uuidString, channelId: channel.uuidString, user: .init(user),
                emoji: emoji
            )
        case let .agentThinking(group, channel, mention):
            .init(
                _type: .agent_thinking, groupId: group.uuidString, channelId: channel.uuidString,
                messageId: mention.uuidString
            )
        }
    }
}
