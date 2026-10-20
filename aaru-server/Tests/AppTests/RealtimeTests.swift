import AaruCore
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import HummingbirdWSTesting
import Testing
@testable import aaru

/// Frames one fake socket received.
actor Frames {
    private(set) var raw: [String] = []

    func append(_ frame: String) {
        raw.append(frame)
    }

    var types: [String] {
        raw.compactMap { Frames.object($0)["type"] as? String }
    }

    static func object(_ frame: String?) -> [String: Any] {
        frame.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] } ?? [:]
    }
}

@Suite("Realtime gateway (GRP-006)", .serialized)
struct RealtimeTests {
    let groups = GroupTests()

    @Test("The hub delivers only to the recipients' sockets and drops a socket that fails")
    func hubFanOut() async {
        let hub = RealtimeHub()
        let (ana, kai) = (UserID(UUID()), UserID(UUID()))
        let (phone, laptop, other) = (Frames(), Frames(), Frames())
        _ = await hub.connect(ana) { await phone.append($0) }
        _ = await hub.connect(ana) { await laptop.append($0) }
        _ = await hub.connect(kai) { await other.append($0) }
        _ = await hub.connect(kai) { _ in throw CancellationError() }

        await hub.publish(.groupUpdated(group: UUID()), to: [ana])
        #expect(await phone.types == ["group.updated"])
        #expect(await laptop.types == ["group.updated"])
        #expect(await other.types.isEmpty)

        await hub.publish(.invitesChanged, to: [kai])
        #expect(await other.types == ["invites.changed"])
        #expect(await hub.connectionCount(kai) == 1)
    }

    @Test("A ticket works once and only for a minute")
    func tickets() async {
        let hub = RealtimeHub()
        let user = UserID(UUID())
        let now = Date()
        let (ticket, expiresAt) = await hub.issueTicket(for: user, now: now)
        #expect(expiresAt == now.addingTimeInterval(60))
        #expect(await hub.redeem(ticket, now: now) == user)
        #expect(await hub.redeem(ticket, now: now) == nil)
        let (late, _) = await hub.issueTicket(for: user, now: now)
        #expect(await hub.redeem(late, now: now.addingTimeInterval(61)) == nil)
    }

    @Test("Group writes reach every member's socket, flagged for those who blocked the author")
    func groupEvents() async throws {
        try await LibraryHarness.run { env in
            let mine = try await groups.claimHandle(env)
            let ana = try await groups.friend(env, of: mine)
            let (group, general) = try await groups.createGroup(env)
            let anaID = try #require(UUID(uuidString: ana.id)).asUser
            let anaSocket = Frames()
            _ = await env.realtime.connect(anaID) { await anaSocket.append($0) }
            let (strangerID, _) = try await signedInUser(env.stores)
            let strangerSocket = Frames()
            _ = await env.realtime.connect(strangerID) { await strangerSocket.append($0) }

            try await groups.join(env, ana, group: group)
            #expect(await anaSocket.types.contains("group.updated"))

            let channel = "/v1/groups/\(group)/channels/\(general)"
            let posted = try await groups.post(env, channel, "hello")
            let created = await Frames.object(anaSocket.raw.last)
            #expect(created["type"] as? String == "message.created")
            #expect(created["channelId"] as? String == general)
            #expect((created["message"] as? [String: Any])?["id"] as? String == posted["id"] as? String)
            #expect((created["message"] as? [String: Any])?["fromBlocked"] as? Bool == false)

            _ = try await env.send(.put, "/v1/social/blocks/\(env.userID)", token: ana.token)
            _ = try await groups.post(env, channel, "still me")
            let flagged = try #require(await Frames.object(anaSocket.raw.last)["message"] as? [String: Any])
            #expect(flagged["fromBlocked"] as? Bool == true)

            // Typing goes to the others, never back to the typist.
            let mySocket = Frames()
            _ = await env.realtime.connect(env.userID) { await mySocket.append($0) }
            let groupID = try #require(UUID(uuidString: group))
            let channelID = try #require(UUID(uuidString: general))
            try await env.services.groups.typing(groupID, channel: channelID, viewer: env.userID)
            #expect(await anaSocket.types.last == "typing")
            #expect(await mySocket.types.isEmpty)

            // Removing Ana tells her she is out.
            #expect(try await env.send(.delete, "/v1/groups/\(group)/members/\(ana.id)").status == .noContent)
            #expect(await anaSocket.types.last == "group.removed")
            #expect(await strangerSocket.raw.isEmpty)
        }
    }

    @Test("GET /v1/ws upgrades with a bearer token or a ticket, says ready, and refuses foreign origins")
    func socket() async throws {
        try await withMigratedStores { stores in
            let (_, token) = try await signedInUser(stores)
            let auth = AuthService(stores: stores, apple: UntouchedAppleVerifier(), magicLinks: nil)
            let services = Services.make(stores: stores, catalogs: FakeCatalog.providers(FakeCatalog()), auth: auth)
            let realtime = RealtimeRoutes(
                hub: services.realtime, groups: services.groups, sessions: stores.sessions,
                // WSClient always sends its own `Origin: ws://localhost`.
                allowedOrigins: ["ws://localhost"]
            )
            let app = try Application(
                router: buildRouter(stores: stores, services: services),
                server: .http1WebSocketUpgrade(webSocketRouter: realtime.router())
            )
            try await app.test(.live) { client in
                let bearer = Frames()
                try await client.ws(
                    "/v1/ws", configuration: .init(additionalHeaders: [.authorization: "Bearer \(token)"])
                ) { inbound, outbound, _ in
                    for try await message in inbound.messages(maxSize: 4096) {
                        if case let .text(text) = message {
                            await bearer.append(text)
                        }
                        try await outbound.close(.normalClosure, reason: nil)
                    }
                }
                #expect(await bearer.types == ["ready"])

                let ticket = try await client.execute(
                    uri: "/v1/realtime/ticket", method: .post, headers: [.authorization: "Bearer \(token)"]
                ) { response in
                    try JSONSerialization.jsonObject(with: Data(buffer: response.body)) as? [String: Any]
                }
                let value = try #require(ticket?["ticket"] as? String)
                #expect((ticket?["url"] as? String)?.hasPrefix("wss://api.aaruapp.com/v1/ws?ticket=") == true)

                let viaTicket = Frames()
                try await client.ws("/v1/ws?ticket=\(value)") { inbound, outbound, _ in
                    for try await message in inbound.messages(maxSize: 4096) {
                        if case let .text(text) = message {
                            await viaTicket.append(text)
                        }
                        try await outbound.close(.normalClosure, reason: nil)
                    }
                }
                #expect(await viaTicket.types == ["ready"])
                // Spent.
                await #expect(throws: (any Error).self) {
                    try await client.ws("/v1/ws?ticket=\(value)") { _, _, _ in }
                }
                await #expect(throws: (any Error).self) {
                    try await client.ws("/v1/ws") { _, _, _ in }
                }
            }
        }
    }
}

extension RealtimeTests {
    @Test("Only a well-formed typing frame is a command")
    func commands() {
        let (group, channel) = (UUID(), UUID())
        let typing = #"{"type":"typing","groupId":"\#(group)","channelId":"\#(channel)"}"#
        #expect(RealtimeRoutes.command(typing) == .typing(group: group, channel: channel))
        let react = #"{"type":"react","groupId":"\#(group)","channelId":"\#(channel)","emoji":"🔥"}"#
        #expect(RealtimeRoutes.command(react) == .react(group: group, channel: channel, emoji: "🔥"))
        #expect(RealtimeRoutes.command(#"{"type":"typing","groupId":"x","channelId":"y"}"#) == nil)
        #expect(RealtimeRoutes.command(#"{"type":"shout","groupId":"\#(group)","channelId":"\#(channel)"}"#) == nil)
        #expect(RealtimeRoutes.command("not json") == nil)
    }

    @Test("A ticket from a foreign origin is refused and stays unspent")
    func foreignOrigin() async throws {
        let hub = RealtimeHub()
        let user = UserID(UUID())
        let (ticket, _) = await hub.issueTicket(for: user, now: Date())
        let stores = fakeStores()
        let services = Services.make(
            stores: stores, catalogs: FakeCatalog.providers(FakeCatalog()),
            auth: AuthService(stores: stores, apple: UntouchedAppleVerifier(), magicLinks: nil)
        )
        let routes = RealtimeRoutes(
            hub: hub,
            groups: services.groups,
            sessions: UntouchedStore(),
            allowedOrigins: ["https://aaruapp.com"]
        )
        try await Application(router: routes.router()).test(.router) { client in
            for origin in ["https://evil.example", nil] {
                var headers: HTTPFields = [.upgrade: "websocket", .connection: "upgrade"]
                headers[.origin] = origin
                let status = try await client.execute(uri: "/v1/ws?ticket=\(ticket)", method: .get, headers: headers) {
                    $0.status
                }
                #expect(status == .forbidden)
            }
        }
        #expect(await hub.redeem(ticket, now: Date()) == user)
    }
}

extension UUID {
    var asUser: UserID {
        UserID(self)
    }
}
