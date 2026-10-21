import AaruAPI
import Foundation
import Observation

typealias RealtimeEvent = Components.Schemas.RealtimeEvent

/// GRP-006: the one socket to `GET /v1/ws`. It only announces; REST stays the source of truth, so
/// every `ready` (each connect and reconnect) is the cue to refetch what is on screen.
///
/// Open while signed in and the app is active, closed in the background. A dropped socket
/// reconnects with exponential backoff and jitter, from one second up to thirty.
@MainActor
@Observable
final class RealtimeClient {
    enum State: Equatable {
        case closed
        case connecting
        case open
    }

    private(set) var state: State = .closed
    /// When the socket was last wanted but not open; nil while open or stopped.
    private(set) var disconnectedSince: Date?

    @ObservationIgnored private let url: URL?
    @ObservationIgnored private let token: @MainActor () -> String?
    @ObservationIgnored private var socket: URLSessionWebSocketTask?
    @ObservationIgnored private var loop: Task<Void, Never>?
    /// Bumped by every start and stop, so a loop that was stopped never touches the next one's state.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var subscribers: [UUID: AsyncStream<RealtimeEvent>.Continuation] = [:]
    @ObservationIgnored private var lastTyping: [String: Date] = [:]
    @ObservationIgnored private var lastReaction = Date.distantPast

    static let typingInterval: TimeInterval = 3
    /// The server counts one reaction a second per socket; sending more only wastes frames.
    static let reactionInterval: TimeInterval = 1
    static let maxBackoff: Double = 30

    /// `baseURL` is the `/v1` host; nil (no API configured) never connects.
    init(baseURL: URL?, token: @escaping @MainActor () -> String?) {
        url = baseURL.flatMap(Self.socketURL)
        self.token = token
    }

    /// `https://host` → `wss://host/v1/ws`.
    static func socketURL(_ base: URL) -> URL? {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = components.scheme == "http" ? "ws" : "wss"
        components.path = "/v1/ws"
        components.query = nil
        return components.url
    }

    // MARK: Lifecycle

    func start() {
        guard loop == nil, url != nil else { return }
        if disconnectedSince == nil {
            disconnectedSince = Date()
        }
        generation += 1
        let current = generation
        loop = Task { [weak self] in await self?.run(current) }
    }

    func stop() {
        generation += 1
        loop?.cancel()
        loop = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        state = .closed
        disconnectedSince = nil
    }

    /// Sign-out: closed, and nothing remembered.
    func reset() {
        stop()
        lastTyping = [:]
        lastReaction = .distantPast
    }

    /// Every event from now until the caller stops iterating.
    func events() -> AsyncStream<RealtimeEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<RealtimeEvent>.makeStream(bufferingPolicy: .bufferingNewest(64))
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.subscribers[id] = nil }
        }
        return stream
    }

    /// Tells the channel's other members the user is typing, at most once every three seconds.
    func sendTyping(group: String, channel: String) {
        guard state == .open else { return }
        let now = Date()
        if let last = lastTyping[channel], now.timeIntervalSince(last) < Self.typingInterval {
            return
        }
        lastTyping[channel] = now
        send(Components.Schemas.RealtimeCommand(_type: .typing, groupId: group, channelId: channel))
    }

    /// A watch-party reaction from the fixed set. False when it was throttled or the socket is down.
    @discardableResult
    func sendReaction(group: String, channel: String, emoji: String) -> Bool {
        let now = Date()
        guard now.timeIntervalSince(lastReaction) >= Self.reactionInterval else { return false }
        let command = Components.Schemas.RealtimeCommand(
            _type: .react,
            emoji: emoji,
            groupId: group,
            channelId: channel
        )
        guard send(command) else { return false }
        lastReaction = now
        return true
    }

    @discardableResult
    private func send(_ command: Components.Schemas.RealtimeCommand) -> Bool {
        guard state == .open, let socket, let data = try? JSONEncoder().encode(command),
              let text = String(bytes: data, encoding: .utf8)
        else { return false }
        Task { try? await socket.send(.string(text)) }
        return true
    }

    // MARK: Connection

    private func run(_ current: Int) async {
        var attempt = 0
        while !Task.isCancelled, current == generation {
            guard let url, let token = token() else { break }
            state = .connecting
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let socket = URLSession.shared.webSocketTask(with: request)
            self.socket = socket
            socket.resume()
            if await listen(socket) {
                attempt = 0
            }
            socket.cancel(with: .goingAway, reason: nil)
            if self.socket === socket {
                self.socket = nil
            }
            guard !Task.isCancelled, current == generation else { break }
            if state == .open || disconnectedSince == nil {
                disconnectedSince = Date()
            }
            state = .connecting
            attempt += 1
            try? await Task.sleep(for: .seconds(Self.backoff(attempt: attempt)))
        }
        // Stopped from outside, or no session left to connect with.
        if current == generation {
            loop = nil
            state = .closed
        }
    }

    /// Delivers frames until the socket closes. True when it got as far as `ready`.
    private func listen(_ socket: URLSessionWebSocketTask) async -> Bool {
        var opened = false
        do {
            while !Task.isCancelled {
                let message = try await socket.receive()
                guard case let .string(text) = message, let event = Self.decode(text) else { continue }
                if event._type == .ready {
                    opened = true
                    state = .open
                    disconnectedSince = nil
                }
                for subscriber in subscribers.values {
                    subscriber.yield(event)
                }
            }
        } catch {
            // Closed, refused or unreachable: the caller backs off and tries again.
        }
        return opened
    }

    /// 1, 2, 4 … 30 seconds, each scaled by a random 0.5–1 so clients don't reconnect in step.
    static func backoff(attempt: Int) -> Double {
        min(maxBackoff, pow(2, Double(max(attempt - 1, 0)))) * Double.random(in: 0.5 ... 1)
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date(text, strategy: .iso8601) {
                return date
            }
            if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: text))
        }
        return decoder
    }()

    /// A frame, or nil for one this build does not understand (a newer event type).
    static func decode(_ text: String) -> RealtimeEvent? {
        try? decoder.decode(RealtimeEvent.self, from: Data(text.utf8))
    }
}
