import AaruCore
import Foundation

/// GRP-012: alerts for mentions and invites. An alert names who and where, never what was said,
/// and carries the link a tap opens.
extension GroupService {
    /// Alerts the members a message tags, except the author, anyone who blocked the author, and
    /// anyone who muted the group or turned mention alerts off. Best effort: the message is posted.
    func alertMentions(_ message: GroupMessage, in channel: GroupChannel, blockedBy: Set<UserID>) async {
        guard let push, let author = message.author else { return }
        let tagged = message.mentions.filter { $0 != author.id && !blockedBy.contains($0) }
        guard !tagged.isEmpty,
              let recipients = try? await stores.push.mentionRecipients(group: channel.groupID, users: tagged),
              !recipients.isEmpty,
              let group = try? await stores.groups.summary(channel.groupID, viewer: author.id)
        else { return }
        let alert = Self.mentionAlert(by: author, group: group.name, channel: channel)
        await withTaskGroup(of: Void.self) { sends in
            for user in recipients {
                sends.addTask { await push.send(alert, userID: user) }
            }
        }
    }

    /// Alerts a friend who was just invited, if they turned invite alerts on.
    func alertInvite(_ invitee: UserID, to group: UUID, by inviter: SocialUser) async {
        guard let push,
              (try? await stores.push.notificationSettings(userID: invitee))?.groupInvites == true,
              let summary = try? await stores.groups.summary(group, viewer: inviter.id)
        else { return }
        await push.send(Self.inviteAlert(by: inviter, group: summary.name), userID: invitee)
    }

    static func mentionAlert(by author: SocialUser, group: String, channel: GroupChannel) -> PushMessage {
        let (groupID, channelID) = (channel.groupID.uuidString, channel.id.uuidString)
        return PushMessage(
            title: group,
            body: "\(author.alertName) mentioned you in #\(channel.name)",
            payload: [
                "groupId": groupID,
                "channelId": channelID,
                "url": "aaru://group/\(groupID)/channel/\(channelID)",
            ]
        )
    }

    static func inviteAlert(by inviter: SocialUser, group: String) -> PushMessage {
        PushMessage(
            title: "Group invite",
            body: "\(inviter.alertName) invited you to \(group)",
            payload: ["groupInvite": "1", "url": "aaru://groups"]
        )
    }
}

extension SocialUser {
    /// How an alert names someone: what their friends call them, else their handle.
    var alertName: String {
        displayName.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 } ?? "@\(handle)"
    }
}
