import AaruCore
import Foundation

/// `@aaru` mentions (GRP-011): the fair-use caps, the queue, and posting the agent's replies.
/// The model call itself runs in `AgentReplyService`, off the request path.
extension GroupService {
    static let agentDailyCapPerUser = 30
    static let agentHourlyCapPerGroup = 10
    static let restingNote = """
    I'm resting for now. I answer up to 30 questions a day for each person and 10 an hour in each \
    group. Ask me again later.
    """

    /// Queues an answer to a mention, or, over a cap, answers once that Aaru is resting and then
    /// stays quiet. Never calls the model. Failures only cost the answer, never the message.
    func mentionAgent(_ message: GroupMessage, group: UUID, tagger: UserID) async {
        guard agentAvailable else { return }
        let job = AgentReplyJob(
            id: UUID(), messageID: message.id, groupID: group, channelID: message.channelID, tagger: tagger, attempts: 0
        )
        do {
            let load = try await stores.agent.load(
                tagger: tagger, group: group, dayStart: Self.utcDayStart(now()),
                hourStart: now().addingTimeInterval(-3600)
            )
            let userCapped = load.userToday >= Self.agentDailyCapPerUser
            let groupCapped = load.groupHour >= Self.agentHourlyCapPerGroup
            guard userCapped || groupCapped else {
                try await stores.agent.enqueue(job, state: .queued, now: now())
                await announce(
                    .agentThinking(group: group, channel: message.channelID, mention: message.id), in: group
                )
                return
            }
            let noted = (userCapped && load.userNoted) || (groupCapped && load.groupNoted)
            try await stores.agent.enqueue(job, state: noted ? .skipped : .capped, now: now())
            if !noted {
                _ = try await postAgentReply(
                    group: group, channel: message.channelID, replyTo: message.id, body: Self.restingNote
                )
            }
        } catch {
            // The member's message is already saved; losing the answer is the lesser harm.
        }
    }

    /// Posts a message from `@aaru` and tells the members. Catalog cards only; no mentions, so a
    /// reply never notifies anyone.
    func postAgentReply(
        group: UUID, channel: UUID, replyTo: UUID, body: String, components: [MessageComponent] = [],
        spoiler: SpoilerStamp? = nil
    ) async throws -> GroupMessage {
        var posted = try await stores.groups.postMessage(
            GroupMessage(
                id: UUID(), channelID: channel, author: nil, body: String(body.prefix(Self.maxMessageLength)),
                mentions: [], mentionsAgent: false, createdAt: now(), spoiler: spoiler, fromAgent: true,
                replyTo: replyTo, components: components
            ),
            nonce: nil
        )
        posted.components = components
        let members = try await stores.groups.members(group)
        var progress: [UserID: TitleProgress]?
        if spoiler != nil, let title = try await requireChannel(group, channel).titleID {
            progress = try await stores.groupKinds.progress(title: title, users: members.map(\.user.id))
        }
        await events.publish(
            .messageCreated(
                group: group, posted, blockedBy: [],
                veiledFor: Self.veiledFor(posted, members: members, progress: progress)
            ),
            to: members.map(\.user.id)
        )
        return posted
    }

    /// Fills in the titles agent cards point to.
    func hydrateComponents(_ messages: [GroupMessage]) async throws -> [GroupMessage] {
        let ids = Set(messages.flatMap { $0.components.map(\.titleID) })
        guard !ids.isEmpty else { return messages }
        let titles = try await stores.titles.titles(ids: Array(ids))
        let byID = Dictionary(titles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return messages.map { message in
            var message = message
            message.components = message.components.compactMap { component in
                byID[component.titleID].map { MessageComponent(titleID: component.titleID, title: $0) }
            }
            return message
        }
    }

    static func utcDayStart(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar.startOfDay(for: date)
    }
}
