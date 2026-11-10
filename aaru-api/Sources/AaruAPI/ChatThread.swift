import Foundation
import OpenAPIRuntime
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// One Chat with Aaru: creates it on the first Chat turn, sends each turn, reads the answer's
/// event stream into a `ChatReply` (ASK-009).
///
/// Holds no UI state. A chat continues for 15 minutes after its last turn; `reopen()` is the only
/// place that expires it.
public actor ChatThread {
    private static let idleLimit: TimeInterval = 15 * 60
    private static let busyTries = 3

    private let client: Client
    private let busyRetryDelay: Duration
    private let now: @Sendable () -> Date
    private var chatID: String?
    private var lastUsed: Date
    /// Bumped by `reset()`; a send that started before it must not touch the chat afterwards.
    private var generation = 0

    public init(
        client: Client,
        busyRetryDelay: Duration = .seconds(1),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.client = client
        self.busyRetryDelay = busyRetryDelay
        self.now = now
        lastUsed = now()
    }

    /// Called on opening the card. True: the same chat continues. False: over 15 minutes idle,
    /// so the next send starts a new one. True when there is no chat yet: nothing expired.
    public func reopen() -> Bool {
        guard chatID != nil else { return true }
        if now().timeIntervalSince(lastUsed) > Self.idleLimit {
            chatID = nil
            return false
        }
        return true
    }

    /// Continues a chat opened from history (ASK-011): its 15 minutes start again.
    public func adopt(_ id: String) {
        generation += 1
        chatID = id
        lastUsed = now()
    }

    /// Forgets the chat: New chat, sign-out and Delete my chats.
    public func reset() {
        generation += 1
        chatID = nil
    }

    /// Sends one Chat turn, with the files attached to it. `onUpdate` gets the reply after every
    /// frame. Returns the final reply; never throws.
    public func send(
        _ body: String,
        hint: Components.Schemas.ChatHint?,
        attachments: [String] = [],
        onUpdate: @escaping @Sendable (ChatReply) async -> Void
    ) async -> ChatReply {
        lastUsed = now()
        var reply = ChatReply()
        await run(Turn(body: body, hint: hint, attachments: attachments), reply: &reply, onUpdate: onUpdate)
        lastUsed = now()
        return reply
    }

    /// What one turn sends.
    private struct Turn {
        let body: String
        let hint: Components.Schemas.ChatHint?
        let attachments: [String]
    }

    /// A turn's retries so far: one new chat after a 404, a few waits on a busy one.
    private struct Retries {
        var recreated = false
        var busyAttempts = 0
    }

    private func run(
        _ turn: Turn,
        reply: inout ChatReply,
        onUpdate: @Sendable (ChatReply) async -> Void
    ) async {
        let started = generation
        var retries = Retries()
        while true {
            if Task.isCancelled || generation != started {
                reply.cancel()
                return
            }
            guard let id = await turnChatID(started: started, reply: &reply),
                  let output = await sendTurn(chat: id, turn: turn, started: started, reply: &reply)
            else { return }
            switch output {
            case let .ok(answer):
                await read(answer, into: &reply, onUpdate: onUpdate)
                return
            case let .default(status, response):
                let message = (try? response.body.json.message) ?? Self.unreachable
                // Files belong to the chat they went into: a new chat would not have them.
                if status == 404, !turn.attachments.isEmpty {
                    reply.fail(Self.filesGone)
                    return
                }
                guard await retry(status: status, chat: id, message: message, retries: &retries, reply: &reply)
                else { return }
            }
        }
    }

    /// The chat this turn goes to, made first when there is none; nil when the reply has ended.
    private func turnChatID(started: Int, reply: inout ChatReply) async -> String? {
        if let known = chatID {
            return known
        }
        switch await createChat() {
        case let .id(created):
            if generation != started {
                reply.cancel()
                return nil
            }
            chatID = created
            return created
        case .cancelled:
            reply.cancel()
            return nil
        case let .failed(problem):
            reply.fail(problem)
            return nil
        }
    }

    /// The turn's request; nil when it failed or a reset ran meanwhile, with the reply ended.
    private func sendTurn(
        chat id: String,
        turn: Turn,
        started: Int,
        reply: inout ChatReply
    ) async -> Operations.CreateChatTurn.Output? {
        let output: Operations.CreateChatTurn.Output
        do {
            output = try await client.createChatTurn(
                path: .init(id: id),
                body: .json(.init(
                    body: turn.body, hint: turn.hint, attachments: turn.attachments.isEmpty ? nil : turn.attachments
                ))
            )
        } catch {
            if Self.isCancellation(error) || generation != started {
                reply.cancel()
            } else {
                reply.fail(Self.unreachable)
            }
            return nil
        }
        if generation != started {
            reply.cancel()
            return nil
        }
        return output
    }

    /// Whether to try the turn again after this refusal; false ends the reply.
    private func retry(
        status: Int,
        chat id: String,
        message: String,
        retries: inout Retries,
        reply: inout ChatReply
    ) async -> Bool {
        switch status {
        case 404 where !retries.recreated:
            retries.recreated = true
            if chatID == id {
                chatID = nil
            }
            return true
        case 409:
            retries.busyAttempts += 1
            if retries.busyAttempts >= Self.busyTries {
                reply.fail("Aaru is still finishing the last answer. Try again in a moment.")
                return false
            }
            do {
                try await Task.sleep(for: busyRetryDelay)
            } catch {
                reply.cancel()
                return false
            }
            // The loop head stops if a reset ran during the wait.
            return true
        default:
            reply.fail(message)
            return false
        }
    }

    private func read(
        _ answer: Operations.CreateChatTurn.Output.Ok,
        into reply: inout ChatReply,
        onUpdate: @Sendable (ChatReply) async -> Void
    ) async {
        var parser = ChatFrameParser()
        do {
            for try await chunk in try answer.body.textEventStream {
                for frame in parser.consume(chunk) {
                    reply.apply(frame)
                    await onUpdate(reply)
                }
                if reply.state != .working {
                    return
                }
            }
        } catch {
            if Self.isCancellation(error) {
                reply.cancel()
            } else {
                reply.streamEnded()
            }
            return
        }
        if Task.isCancelled {
            reply.cancel()
        } else {
            reply.streamEnded()
        }
    }

    private enum Created {
        case id(String)
        case cancelled
        case failed(String)
    }

    private func createChat() async -> Created {
        let output: Operations.CreateChat.Output
        do {
            output = try await client.createChat()
        } catch {
            return Self.isCancellation(error) ? .cancelled : .failed(Self.unreachable)
        }
        switch output {
        case let .created(created):
            guard let chat = try? created.body.json else { return .failed(Self.unreachable) }
            return .id(chat.id)
        case let .default(_, response):
            return .failed((try? response.body.json.message) ?? Self.unreachable)
        }
    }

    private static let unreachable = "Aaru could not reach the server."
    private static let filesGone = "Those files are no longer here. Attach them again."

    private static func isCancellation(_ error: any Error) -> Bool {
        if Task.isCancelled || error is CancellationError {
            return true
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        if let wrapped = (error as? ClientError)?.underlyingError {
            return isCancellation(wrapped)
        }
        return false
    }
}

// MARK: - Files (ASK-010)

public extension ChatThread {
    /// The chat files were attached to, or nil when there is none now.
    func current() -> String? {
        chatID
    }

    /// One file into the chat (ASK-010), made first when there is none, for the next turn to
    /// carry. The server reads the bytes and decides what the file is; a refusal says why.
    func attach(_ data: Data, name: String) async -> ChatAttachResult {
        lastUsed = now()
        let started = generation
        let chat: String
        if let known = chatID {
            chat = known
        } else {
            switch await createChat() {
            case let .id(created):
                guard generation == started else { return .refused(Self.unreachable) }
                chatID = created
                chat = created
            case .cancelled:
                return .refused(Self.unreachable)
            case let .failed(problem):
                return .refused(problem)
            }
        }
        let output: Operations.CreateChatAttachment.Output
        do {
            output = try await client.createChatAttachment(
                path: .init(id: chat),
                query: .init(filename: name.isEmpty ? nil : name),
                body: .binary(HTTPBody(data))
            )
        } catch {
            return .refused(Self.unreachable)
        }
        switch output {
        case let .created(created):
            guard let file = try? created.body.json else { return .refused(Self.unreachable) }
            return .attached(chat: chat, file: ChatFile(file))
        case let .default(_, response):
            return .refused((try? response.body.json.message) ?? Self.unreachable)
        }
    }

    /// A file taken back off before sending. A failure only leaves it to expire in an hour.
    func detach(chat: String, id: String) async {
        _ = try? await client.deleteChatAttachment(path: .init(id: chat, attachmentId: id))
    }
}
