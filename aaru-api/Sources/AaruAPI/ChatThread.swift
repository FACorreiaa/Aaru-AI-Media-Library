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

    /// Forgets the chat: sign-out and Delete my chats.
    public func reset() {
        chatID = nil
    }

    /// Sends one Chat turn. `onUpdate` gets the reply after every frame. Returns the final reply;
    /// never throws.
    public func send(
        _ body: String,
        hint: Components.Schemas.ChatHint?,
        onUpdate: @escaping @Sendable (ChatReply) async -> Void
    ) async -> ChatReply {
        lastUsed = now()
        var reply = ChatReply()
        await run(body, hint: hint, reply: &reply, onUpdate: onUpdate)
        lastUsed = now()
        return reply
    }

    private func run(
        _ body: String,
        hint: Components.Schemas.ChatHint?,
        reply: inout ChatReply,
        onUpdate: @Sendable (ChatReply) async -> Void
    ) async {
        var recreated = false
        var busyAttempts = 0
        while true {
            if Task.isCancelled {
                reply.cancel()
                return
            }
            let id: String
            if let known = chatID {
                id = known
            } else {
                switch await createChat() {
                case let .id(created):
                    chatID = created
                    id = created
                case .cancelled:
                    reply.cancel()
                    return
                case let .failed(problem):
                    reply.fail(problem)
                    return
                }
            }

            let output: Operations.CreateChatTurn.Output
            do {
                output = try await client.createChatTurn(
                    path: .init(id: id),
                    body: .json(.init(body: body, hint: hint))
                )
            } catch {
                if Self.isCancellation(error) {
                    reply.cancel()
                } else {
                    reply.fail(Self.unreachable)
                }
                return
            }

            switch output {
            case let .ok(ok):
                await read(ok, into: &reply, onUpdate: onUpdate)
                return
            case let .default(status, response):
                let message = (try? response.body.json.message) ?? Self.unreachable
                switch status {
                case 404 where !recreated:
                    recreated = true
                    chatID = nil
                case 409:
                    busyAttempts += 1
                    if busyAttempts >= Self.busyTries {
                        reply.fail("Aaru is still finishing the last answer. Try again in a moment.")
                        return
                    }
                    do {
                        try await Task.sleep(for: busyRetryDelay)
                    } catch {
                        reply.cancel()
                        return
                    }
                default:
                    reply.fail(message)
                    return
                }
            }
        }
    }

    private func read(
        _ ok: Operations.CreateChatTurn.Output.Ok,
        into reply: inout ChatReply,
        onUpdate: @Sendable (ChatReply) async -> Void
    ) async {
        var parser = ChatFrameParser()
        do {
            for try await chunk in try ok.body.textEventStream {
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
