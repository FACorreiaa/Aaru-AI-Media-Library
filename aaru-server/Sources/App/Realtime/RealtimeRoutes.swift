import aaruAPI
import AaruCore
import Foundation
import Hummingbird
import HummingbirdWebSocket

/// `GET /v1/ws` (GRP-006): one socket per signed-in client, events out, typing and watch-party
/// reactions in.
///
/// It has its own router, so only upgrade requests reach it. Apps send their bearer token on the
/// upgrade; a browser cannot, so it brings a single-use ticket from `POST /v1/realtime/ticket`.
/// A ticket only works from an allowed `Origin`, so another site cannot open a socket with it.
struct RealtimeRoutes {
    let hub: RealtimeHub
    let groups: GroupService
    let sessions: any SessionStore
    let allowedOrigins: Set<String>

    /// Largest frame a client may send; a typing command is about 120 bytes.
    static let maxInboundBytes = 1024
    /// Typing frames per channel per connection count at most this often.
    static let typingInterval: TimeInterval = 3
    /// Watch-party reactions per connection count at most this often.
    static let reactionInterval: TimeInterval = 1

    enum Command: Equatable {
        case typing(group: UUID, channel: UUID)
        case react(group: UUID, channel: UUID, emoji: String)
    }

    func router() -> Router<AppRequestContext> {
        let router = Router(context: AppRequestContext.self)
        router.addMiddleware {
            ErrorMiddleware()
            RealtimeAuthMiddleware(hub: hub, sessions: sessions, allowedOrigins: allowedOrigins)
        }
        router.ws("/v1/ws") { _, context in
            context.userID == nil ? .dontUpgrade : .upgrade([:])
        } onUpgrade: { inbound, outbound, context in
            guard let user = context.requestContext.userID else { return }
            let connection = await hub.connect(user) { frame in
                try await outbound.write(.text(frame))
            }
            defer { Task { await hub.disconnect(user, connection: connection) } }
            if let ready = RealtimeHub.frame(.init(_type: .ready)) {
                try await outbound.write(.text(ready))
            }
            var lastTyping: [UUID: Date] = [:]
            var lastReaction = Date.distantPast
            for try await message in inbound.messages(maxSize: Self.maxInboundBytes) {
                guard case let .text(text) = message, let command = Self.command(text) else { continue }
                let now = Date()
                // A frame for a group the user is not in is dropped like a malformed one.
                switch command {
                case let .typing(group, channel):
                    if let last = lastTyping[channel], now.timeIntervalSince(last) < Self.typingInterval {
                        continue
                    }
                    lastTyping[channel] = now
                    try? await groups.typing(group, channel: channel, viewer: user)
                case let .react(group, channel, emoji):
                    guard now.timeIntervalSince(lastReaction) >= Self.reactionInterval else { continue }
                    lastReaction = now
                    try? await groups.react(group, channel: channel, emoji: emoji, viewer: user)
                }
            }
        }
        return router
    }

    /// A command, or nil for anything malformed.
    static func command(_ text: String) -> Command? {
        guard let command = try? JSONDecoder().decode(Components.Schemas.RealtimeCommand.self, from: Data(text.utf8)),
              let group = UUID(uuidString: command.groupId),
              let channel = UUID(uuidString: command.channelId)
        else { return nil }
        switch command._type {
        case .typing:
            return .typing(group: group, channel: channel)
        case .react:
            return command.emoji.map { .react(group: group, channel: channel, emoji: $0) }
        }
    }
}

/// Signs in an upgrade by bearer token, or by ticket from an allowed `Origin`. A bearer token
/// cannot come from a browser socket, so its `Origin` (some clients send one) is not checked.
struct RealtimeAuthMiddleware: RouterMiddleware {
    typealias Context = AppRequestContext

    let hub: RealtimeHub
    let sessions: any SessionStore
    let allowedOrigins: Set<String>

    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        var context = context
        if let token = AuthMiddleware.bearerToken(request) {
            context.userID = try await sessions.userID(forTokenHash: OpaqueToken.hash(token), now: .now)
        } else if let ticket = request.uri.queryParameters["ticket"] {
            // Only a browser brings a ticket, and a browser always says where the page came from.
            guard let origin = request.headers[.origin], allowedOrigins.contains(origin) else {
                throw AppError(status: .forbidden, code: "forbidden", message: "This origin may not open a socket.")
            }
            context.userID = await hub.redeem(String(ticket), now: .now)
        }
        guard context.userID != nil else { throw AppError.unauthorized() }
        return try await next(request, context)
    }
}
