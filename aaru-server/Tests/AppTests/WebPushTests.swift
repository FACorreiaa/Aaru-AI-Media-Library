import AaruCore
import FluentSQL
import Foundation
import Testing
@testable import aaru

/// Web push (2026-10-20): browsers subscribe with the VAPID key, only real push services are
/// accepted, and airing alerts fan out to browsers as they do to Apple devices. Part of the push
/// suite: every notifier run claims due airings across all users, so they must not overlap.
extension PushTests {
    final class FakeWebPush: WebPushSending, @unchecked Sendable {
        // @unchecked: test-only; `lock` guards `sent`.
        private let lock = NSLock()
        private var sent: [(PushMessage, WebPushSubscription)] = []
        let dead: Set<String>
        let publicKey = "BPublicKeyForTests_abcdefghijklmnop"

        init(dead: Set<String> = []) {
            self.dead = dead
        }

        var messages: [(PushMessage, WebPushSubscription)] {
            lock.withLock { sent }
        }

        func send(_ message: PushMessage, to subscription: WebPushSubscription) async throws -> PushOutcome {
            if dead.contains(subscription.endpoint) {
                return .deadToken
            }
            lock.withLock { sent.append((message, subscription)) }
            return .sent
        }
    }

    static let p256dh = "BNcRdreALRFXTkOOUHK1EtK2wtaz5Ry4YfYCA_0QTpQtUbVlUls0VJXg7A8u-Ts1XbjhazAkj7I99e8QcYP7DkM"
    static let auth = "tBHItJI5svbpez7KI4CCXg"

    static func endpoint() -> String {
        "https://fcm.googleapis.com/fcm/send/\(UUID().uuidString)"
    }

    func subscribe(_ env: LibraryHarness, _ endpoint: String) async throws -> LibraryHarness.Reply {
        try await env.send(.put, "/v1/web-push/subscriptions", json: [
            "endpoint": endpoint, "keys": ["p256dh": Self.p256dh, "auth": Self.auth],
        ])
    }

    @Test("Without a VAPID key the key route answers 503")
    func offWithoutKey() async throws {
        try await LibraryHarness.run { env in
            let reply = try await env.send(.get, "/v1/web-push/key")
            #expect(reply.status == .serviceUnavailable)
            #expect(try reply.json()["code"] as? String == "push_unavailable")
        }
    }

    @Test("A browser subscribes with the key; only push services are accepted; delete forgets it")
    func subscribe() async throws {
        let fake = FakeWebPush()
        try await LibraryHarness.run(webPush: fake) { env in
            #expect(try await env.send(.get, "/v1/web-push/key").json()["publicKey"] as? String == fake.publicKey)
            for bad in [
                "https://evil.example/push",
                "http://fcm.googleapis.com/fcm/send/x",
                "https://fcm.googleapis.com:8443/x",
            ] {
                #expect(try await subscribe(env, bad).status == .unprocessableContent, "\(bad) is refused")
            }
            let endpoint = Self.endpoint()
            #expect(try await subscribe(env, endpoint).status == .noContent)
            #expect(try await subscribe(env, endpoint).status == .noContent, "saving again is idempotent")
            let saved = try await env.stores.push.webPushSubscriptions(userID: env.userID)
            #expect(saved.map(\.endpoint) == [endpoint])
            #expect(saved.first?.vapidKeyID == fake.publicKey)

            let query = endpoint.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            #expect(try await env.send(.delete, "/v1/web-push/subscriptions?endpoint=\(query)").status == .noContent)
            #expect(try await env.stores.push.webPushSubscriptions(userID: env.userID).isEmpty)
        }
    }

    @Test("An airing alert reaches a browser-only user, opens the title, and a dead browser is forgotten")
    func fanOut() async throws {
        try await LibraryHarness.run { env in
            let optIn = Date()
            let title = Title(type: .show, title: "Pluribus", ids: ExternalIDs(tmdb: uniqueID("tmdb")))
            try await env.stores.titles.insert(title, status: .returning, runtimeMinutes: 50)
            try await withSQL { sql in
                try await sql.raw("""
                INSERT INTO show_episodes (id, title_id, season, episode, name, airs_at)
                VALUES (\(bind: UUID()), \(bind: title.id.rawValue), 1, 1, 'Pilot',
                    \(bind: optIn.addingTimeInterval(60)))
                """).run()
            }
            let item = try await env.send(.post, "/v1/library/items", json: [
                "mediaRef": ["titleId": title.id.description, "type": "show"], "status": "in_progress",
            ]).json()
            let itemID = try #require(item["id"] as? String)
            try await env.stores.push.setAiring(true, userID: env.userID, now: optIn)
            let (live, dead) = (Self.endpoint(), Self.endpoint())
            for endpoint in [live, dead] {
                try await env.stores.push.saveWebPush(
                    WebPushSubscription(endpoint: endpoint, p256dh: Self.p256dh, auth: Self.auth, vapidKeyID: "k"),
                    userID: env.userID
                )
            }

            let browser = FakeWebPush(dead: [dead])
            var notifier = AiringNotifier(stores: env.stores, sender: nil, webPush: browser)
            notifier.now = { optIn.addingTimeInterval(3600) }
            try await notifier.runOnce()

            let mine = browser.messages.filter { $0.0.payload["titleId"] == title.id.description }
            #expect(mine.count == 1)
            #expect(mine.first?.1.endpoint == live)
            #expect(mine.first?.0.payload["libraryItemId"] == itemID)
            #expect(try await env.stores.push.webPushSubscriptions(userID: env.userID).map(\.endpoint) == [live])
        }
    }

    @Test("Push service allowlist")
    func endpoints() {
        #expect(WebPushEndpoints.isAllowed("https://fcm.googleapis.com/fcm/send/abc"))
        #expect(WebPushEndpoints.isAllowed("https://updates.push.services.mozilla.com/wpush/v2/abc"))
        #expect(WebPushEndpoints.isAllowed("https://web.push.apple.com/QAbc"))
        #expect(WebPushEndpoints.isAllowed("https://wns2-par02p.notify.windows.com/w/?token=abc"))
        #expect(!WebPushEndpoints.isAllowed("https://fcm.googleapis.com.evil.example/x"))
        #expect(!WebPushEndpoints.isAllowed("https://localhost/x"))
        #expect(!WebPushEndpoints.isAllowed("https://user@fcm.googleapis.com/x"))
        #expect(!WebPushEndpoints.isAllowed("http://web.push.apple.com/x"))
    }
}
