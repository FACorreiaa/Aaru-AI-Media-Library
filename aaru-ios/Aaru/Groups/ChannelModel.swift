import AaruAPI
import Foundation
import Observation

/// GRP-003 / GRP-006: one channel's messages. Socket events keep it live; a reconnect (`ready`)
/// or the slow fallback poll fills any gap over REST. A send shows at once, dimmed until the
/// server confirms, with a retry on failure.
@MainActor
@Observable
final class ChannelModel {
    let groupID: String
    let channelID: String
    private(set) var messages: [GroupMessage] = []
    private(set) var outbox: [Outgoing] = []
    private(set) var hasLoaded = false
    private(set) var reachedStart = false
    private(set) var loadingOlder = false
    /// Where the "New" line goes: the first message the user had not read when the channel opened.
    private(set) var firstUnreadID: String?
    /// Who is typing, until when. A typing frame lasts five seconds unless renewed.
    private(set) var typing: [String: (user: SocialUser, until: Date)] = [:]
    var problem: String?

    @ObservationIgnored private let api: Client?
    @ObservationIgnored private let unreadAtOpen: Int
    @ObservationIgnored private let myUserID: String?
    @ObservationIgnored private var markedReadID: String?

    static let pageSize = 50
    static let maxLength = 4000
    static let typingLifetime: TimeInterval = 5

    /// A message on its way: the nonce makes a retry safe.
    struct Outgoing: Identifiable, Equatable {
        let id: String
        let body: String
        let createdAt: Date
        /// Title channels only; elsewhere the server ignores it.
        var spoiler: SpoilerChoice = .auto
        var failed = false
    }

    init(api: Client?, groupID: String, channelID: String, unread: Int, myUserID: String?) {
        self.api = api
        self.myUserID = myUserID
        self.groupID = groupID
        self.channelID = channelID
        unreadAtOpen = unread
    }

    private var path: Operations.ListMessages.Input.Path {
        .init(groupId: groupID, channelId: channelID)
    }

    // MARK: Reads

    func loadLatest() async {
        guard let api else { return }
        do {
            switch try await api.listMessages(path: path, query: .init(limit: Self.pageSize)) {
            case let .ok(response):
                let page = try response.body.json.items
                messages = page
                reachedStart = page.count < Self.pageSize
                if !hasLoaded {
                    firstUnreadID = Self.firstUnread(in: page, unread: unreadAtOpen, viewer: myUserID)
                }
                hasLoaded = true
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "This channel could not be loaded."
            }
        } catch {
            problem = "This channel could not be loaded. Aaru could not reach the server."
        }
    }

    func loadOlder() async {
        guard let api, let oldest = messages.first, !reachedStart, !loadingOlder else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        guard case let .ok(response) = try? await api.listMessages(
            path: path, query: .init(before: oldest.id, limit: Self.pageSize)
        ), let page = try? response.body.json.items else { return }
        reachedStart = page.count < Self.pageSize
        messages.insert(contentsOf: page.filter { new in !messages.contains { $0.id == new.id } }, at: 0)
    }

    /// Fetches anything newer than the last message, and refreshes edits and deletes on screen.
    func pollNewer() async {
        guard let api else { return }
        guard let newest = messages.last else {
            await loadLatest()
            return
        }
        guard case let .ok(response) = try? await api.listMessages(
            path: path, query: .init(after: newest.id, limit: Self.pageSize)
        ), let page = try? response.body.json.items else { return }
        merge(page)
        // Edits and deletes in the visible window arrive with the latest page.
        if case let .ok(latest) = try? await api.listMessages(path: path, query: .init(limit: Self.pageSize)),
           let recent = try? latest.body.json.items
        {
            merge(recent)
        }
    }

    // MARK: Writes

    func send(_ text: String, spoiler: SpoilerChoice = .auto) async {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, body.count <= Self.maxLength else { return }
        let outgoing = Outgoing(id: UUID().uuidString, body: body, createdAt: Date(), spoiler: spoiler)
        outbox.append(outgoing)
        await deliver(outgoing)
    }

    func retry(_ outgoing: Outgoing) async {
        guard let index = outbox.firstIndex(of: outgoing) else { return }
        outbox[index].failed = false
        await deliver(outbox[index])
    }

    func discard(_ outgoing: Outgoing) {
        outbox.removeAll { $0.id == outgoing.id }
    }

    private func deliver(_ outgoing: Outgoing) async {
        guard let api else { return }
        do {
            switch try await api.postMessage(
                path: .init(groupId: groupID, channelId: channelID),
                body: .json(.init(
                    body: outgoing.body, clientNonce: outgoing.id, spoiler: outgoing.spoiler.stamp,
                    spoilerFree: outgoing.spoiler == .free ? true : nil
                ))
            ) {
            case let .ok(response):
                let message = try response.body.json
                outbox.removeAll { $0.id == outgoing.id }
                merge([message])
                markedReadID = nil
                await markRead()
            case let .default(_, error):
                fail(outgoing, (try? error.body.json.message) ?? "That message was not sent.")
            }
        } catch {
            fail(outgoing, nil)
        }
    }

    private func fail(_ outgoing: Outgoing, _ message: String?) {
        if let index = outbox.firstIndex(where: { $0.id == outgoing.id }) {
            outbox[index].failed = true
        }
        if let message {
            problem = message
        }
    }

    func edit(_ message: GroupMessage, to text: String) async -> Bool {
        guard let api else { return false }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, body.count <= Self.maxLength else { return false }
        do {
            switch try await api.editMessage(
                path: .init(groupId: groupID, channelId: channelID, messageId: message.id),
                body: .json(.init(body: body))
            ) {
            case let .ok(response):
                try merge([response.body.json])
                return true
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "That message was not edited."
            }
        } catch {
            problem = "That message was not edited. Aaru could not reach the server."
        }
        return false
    }

    func delete(_ message: GroupMessage) async {
        guard let api else { return }
        do {
            switch try await api.deleteMessage(
                path: .init(groupId: groupID, channelId: channelID, messageId: message.id)
            ) {
            case .noContent:
                markDeleted(message.id)
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "That message was not deleted."
            }
        } catch {
            problem = "That message was not deleted. Aaru could not reach the server."
        }
    }

    /// Moves the read point to the newest message. True when it moved, so counts can refresh.
    @discardableResult
    func markRead() async -> Bool {
        guard let api, let newest = messages.last, newest.id != markedReadID else { return false }
        markedReadID = newest.id
        guard case .noContent = try? await api.markChannelRead(
            path: .init(groupId: groupID, channelId: channelID), body: .json(.init(messageId: newest.id))
        ) else {
            markedReadID = nil
            return false
        }
        return true
    }

    // MARK: Realtime

    /// Applies one socket event meant for this channel; others are ignored.
    func apply(_ event: RealtimeEvent) async {
        if event._type == .ready {
            await pollNewer()
            return
        }
        guard event.channelId == channelID else { return }
        switch event._type {
        case .message_created, .message_updated:
            if let message = event.message {
                received(message, isNew: event._type == .message_created)
            }
        case .message_deleted:
            if let id = event.messageId {
                markDeleted(id)
            }
        case .typing:
            if let user = event.user, user.userId != myUserID {
                startedTyping(user)
            }
        default:
            break
        }
    }

    private func received(_ message: GroupMessage, isNew: Bool) {
        if let author = message.author?.userId {
            typing[author] = nil
            // My own message, echoed before the send's response: the server returns my nonce on
            // my messages, so the pending copy it answers is exact.
            if author == myUserID, isNew, let nonce = message.clientNonce {
                outbox.removeAll { $0.id == nonce }
            }
        }
        merge([message])
    }

    private func markDeleted(_ id: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].body = ""
        messages[index].deleted = true
        messages[index].mentions = []
    }

    private func startedTyping(_ user: SocialUser) {
        typing[user.userId] = (user, Date().addingTimeInterval(Self.typingLifetime))
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.typingLifetime + 0.1))
            self?.expireTyping()
        }
    }

    /// "Kai is typing…", for the line above the composer; nil when nobody is.
    var typingLine: String? {
        let names = typing.values.sorted { $0.until < $1.until }.map { $0.user.displayName ?? "@\($0.user.handle)" }
        switch names.count {
        case 0: return nil
        case 1: return "\(names[0]) is typing…"
        case 2: return "\(names[0]) and \(names[1]) are typing…"
        default: return "Several people are typing…"
        }
    }

    private func expireTyping() {
        let now = Date()
        typing = typing.filter { $0.value.until > now }
    }

    // MARK: Helpers

    /// The first of the last `unread` messages from others: the server counts only those.
    static func firstUnread(in messages: [GroupMessage], unread: Int, viewer: String?) -> String? {
        guard unread > 0 else { return nil }
        var remaining = unread
        for message in messages.reversed() where !message.deleted && message.author?.userId != viewer {
            remaining -= 1
            if remaining == 0 {
                return message.id
            }
        }
        return messages.first?.id
    }
}

private extension ChannelModel {
    func merge(_ incoming: [GroupMessage]) {
        guard !incoming.isEmpty else { return }
        // One row per id, the newer copy winning, in the order rows arrived (the server's order).
        var merged = messages
        var position = Dictionary(merged.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        for message in incoming {
            if let index = position[message.id] {
                merged[index] = message
            } else {
                position[message.id] = merged.count
                merged.append(message)
            }
        }
        // Timestamps arrive in whole seconds, so ties keep arrival order; an id tie-break would
        // scramble messages sent in the same second.
        messages = merged.enumerated()
            .sorted { ($0.element.createdAt, $0.offset) < ($1.element.createdAt, $1.offset) }
            .map(\.element)
    }
}
