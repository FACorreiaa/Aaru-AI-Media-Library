import AaruCore
import Foundation

// Groups half of the data layer boundary (GRP-001…GRP-003).

enum GroupRole: String, Sendable, Comparable {
    case owner
    case admin
    case member

    /// Owner and admins manage channels and members.
    var manages: Bool {
        self != .member
    }

    private var rank: Int {
        switch self {
        case .owner: 2
        case .admin: 1
        case .member: 0
        }
    }

    static func < (lhs: GroupRole, rhs: GroupRole) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// One group as the viewer's rail shows it.
struct GroupSummary: Sendable, Equatable {
    var id: UUID
    var name: String
    var role: GroupRole
    var defaultChannelID: UUID
    /// Messages from others since the viewer last read, across every channel.
    var unread: Int
    var mentions: Int
}

/// A text channel. M4 adds the title, watch and shelf kinds.
struct GroupChannel: Sendable, Equatable {
    var id: UUID
    var groupID: UUID
    var name: String
    var topic: String?
    var position: Int
    var isDefault: Bool
    var createdAt: Date
    var unread = 0
    var mentions = 0
}

struct GroupMember: Sendable, Equatable {
    var user: SocialUser
    var role: GroupRole
    var joinedAt: Date
}

/// A pending invite into a group. It stops existing once accepted or declined.
struct GroupInvite: Sendable, Equatable {
    var id: UUID
    var groupID: UUID
    var groupName: String
    var inviter: SocialUser
    var invitee: SocialUser
    var createdAt: Date
}

/// One message in a channel. `author` is nil once the author deleted their account; a deleted
/// message keeps its row with an empty body so the history around it still reads in order.
struct GroupMessage: Sendable, Equatable {
    var id: UUID
    var channelID: UUID
    var author: SocialUser?
    var body: String
    var mentions: [UserID]
    var mentionsAgent: Bool
    var createdAt: Date
    var editedAt: Date?
    var deletedAt: Date?
    /// The author's retry key. Only the author is ever shown it.
    var clientNonce: String?
}

/// Where a page of messages starts: older than one message, newer than one, or the latest.
enum MessageCursor: Sendable, Equatable {
    case latest
    case before(UUID)
    case after(UUID)
}

/// A message the user wrote, for the account export.
struct ExportedGroupMessage: Sendable, Equatable {
    var group: String
    var channel: String
    var body: String
    var createdAt: Date
}

/// Groups, members, invites, channels and messages. Membership rules live in `GroupService`;
/// the store only answers what is asked and keeps multi-row changes in one transaction.
protocol GroupStore: Sendable {
    /// The viewer's groups, in the order they joined them.
    func groups(for user: UserID) async throws -> [GroupSummary]
    /// One of the viewer's groups; nil when they are not a member.
    func summary(_ group: UUID, viewer: UserID) async throws -> GroupSummary?
    func ownedCount(_ user: UserID) async throws -> Int
    /// Inserts the group, its owner and its default text channel together.
    func createGroup(id: UUID, name: String, owner: UserID, general: GroupChannel, now: Date) async throws
    func renameGroup(_ group: UUID, name: String, now: Date) async throws
    func deleteGroup(_ group: UUID) async throws

    func members(_ group: UUID) async throws -> [GroupMember]
    func role(_ group: UUID, user: UserID) async throws -> GroupRole?
    func setRole(_ group: UUID, user: UserID, role: GroupRole) async throws
    /// Removes a member and their read state in the group.
    func removeMember(_ group: UUID, user: UserID) async throws
    /// The new owner takes the role; the old owner becomes an admin.
    func transferOwnership(_ group: UUID, from previous: UserID, to next: UserID) async throws

    /// Inserts an invite; a second invite to the same person is ignored.
    func createInvite(id: UUID, group: UUID, inviter: UserID, invitee: UserID, now: Date) async throws
    func invites(to user: UserID) async throws -> [GroupInvite]
    func invitesPending(_ group: UUID) async throws -> [GroupInvite]
    /// Turns an invite to `invitee` into a membership, with every channel read up to now.
    /// Returns the group, or nil when no such invite is pending.
    func acceptInvite(id: UUID, invitee: UserID, now: Date) async throws -> UUID?
    /// Deletes an invite the invitee declines or the inviter cancels. Returns its group and
    /// invitee, or nil when none was pending.
    func deleteInvite(id: UUID, party: UserID) async throws -> (group: UUID, invitee: UserID)?

    /// Channels by position, with the viewer's unread and mention counts.
    func channels(_ group: UUID, viewer: UserID) async throws -> [GroupChannel]
    func channel(_ id: UUID, group: UUID) async throws -> GroupChannel?
    /// `StoreConflict` when the group already has a channel with that name.
    func createChannel(_ channel: GroupChannel) async throws
    /// A nil field is left alone; an empty topic clears it. `StoreConflict` on a taken name.
    func updateChannel(_ id: UUID, name: String?, topic: String??) async throws
    /// Deletes a channel and its messages. The default channel is never deleted.
    func deleteChannel(_ id: UUID) async throws -> Bool

    /// Up to `limit` messages in order, oldest first.
    func messages(_ channel: UUID, cursor: MessageCursor, limit: Int) async throws -> [GroupMessage]
    func message(_ id: UUID, channel: UUID) async throws -> GroupMessage?
    /// Inserts a message. A retry with the same author and nonce returns the first one instead.
    func postMessage(_ message: GroupMessage, nonce: String?) async throws -> GroupMessage
    func editMessage(_ id: UUID, body: String, mentions: [UserID], mentionsAgent: Bool, now: Date) async throws
    /// Empties the body and mentions and stamps `deletedAt`.
    func deleteMessage(_ id: UUID, now: Date) async throws
    /// Moves the viewer's read point forward to that message; never backward.
    func markRead(_ user: UserID, channel: UUID, upTo message: UUID) async throws

    func exportMessages(_ user: UserID) async throws -> [ExportedGroupMessage]
}
