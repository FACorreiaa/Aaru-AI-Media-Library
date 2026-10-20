import AaruCore
import FluentSQL
import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
@testable import aaru

/// Airing-episode pushes against a fake APNs. No real key, no network.
@Suite("Push", .serialized)
struct PushTests {
    /// Records what would have gone to Apple; some tokens are "dead".
    final class FakeSender: PushSending, @unchecked Sendable {
        // @unchecked: test-only; `lock` guards `sent`.
        private let lock = NSLock()
        private var sent: [(PushMessage, PushDevice)] = []
        let dead: Set<String>

        init(dead: Set<String> = []) {
            self.dead = dead
        }

        var messages: [(PushMessage, PushDevice)] {
            lock.withLock { sent }
        }

        func send(_ message: PushMessage, to device: PushDevice) async throws -> PushOutcome {
            if dead.contains(device.token) {
                return .deadToken
            }
            lock.withLock { sent.append((message, device)) }
            return .sent
        }
    }

    static func token() -> String {
        (0 ..< 32).map { _ in String(format: "%02x", UInt8.random(in: 0 ... 255)) }.joined()
    }

    func register(_ env: LibraryHarness, _ token: String, environment: String = "production") async throws
        -> LibraryHarness.Reply
    {
        try await env.send(.put, "/v1/devices", json: [
            "token": token, "environment": environment, "bundleId": "com.fernandocorreia.aaru.beta",
        ])
    }

    @Test("Devices register per user and environment; bad tokens and unknown apps are refused")
    func registration() async throws {
        try await LibraryHarness.run { env in
            let token = Self.token()
            #expect(try await register(env, token).status == .noContent)
            #expect(try await env.stores.push.devices(userID: env.userID)
                == [PushDevice(token: token, environment: .production, topic: "com.fernandocorreia.aaru.beta")])
            #expect(try await register(env, "not-a-token").status == .unprocessableContent)
            let foreign = try await env.send(.put, "/v1/devices", json: [
                "token": Self.token(), "environment": "sandbox", "bundleId": "com.example.other",
            ])
            #expect(foreign.status == .unprocessableContent)
            #expect(try await env.send(.delete, "/v1/devices/\(token)").status == .noContent)
            #expect(try await env.stores.push.devices(userID: env.userID).isEmpty)
        }
    }

    @Test("The airing setting is off until turned on")
    func setting() async throws {
        try await LibraryHarness.run { env in
            #expect(try await env.send(.get, "/v1/me/notifications").json()["airing"] as? Bool == false)
            let enabled = try await env.send(.put, "/v1/me/notifications", json: ["airing": true]).json()
            #expect(enabled["airing"] as? Bool == true)
        }
    }

    @Test("A new episode of a show you are watching is announced once; old, watched and future ones are not")
    func announcesOnce() async throws {
        try await LibraryHarness.run { env in
            let optIn = Date()
            let title = Title(type: .show, title: "Severance", ids: ExternalIDs(tmdb: uniqueID("tmdb")))
            try await env.stores.titles.insert(title, status: .returning, runtimeMinutes: 50)
            let hour: TimeInterval = 3600
            try await withSQL { sql in
                for (episode, airs) in [(1, -24 * hour), (2, hour), (3, hour), (4, 5 * hour)] {
                    try await sql.raw("""
                    INSERT INTO show_episodes (id, title_id, season, episode, name, airs_at)
                    VALUES (\(bind: UUID()), \(bind: title.id.rawValue), 1, \(bind: episode),
                        \(bind: "Episode \(episode)"), \(bind: optIn.addingTimeInterval(airs)))
                    """).run()
                }
            }
            let item = try await env.send(.post, "/v1/library/items", json: [
                "mediaRef": ["titleId": title.id.description, "type": "show"], "status": "in_progress",
            ]).json()
            let itemID = try #require(item["id"] as? String)
            _ = try await env.send(.put, "/v1/library/items/\(itemID)/episodes/1/3", json: ["watched": true])
            let (live, dead) = (Self.token(), Self.token())
            _ = try await register(env, live)
            _ = try await register(env, dead, environment: "sandbox")
            try await env.stores.push.setAiring(true, userID: env.userID, now: optIn)

            let sender = FakeSender(dead: [dead])
            var notifier = AiringNotifier(stores: env.stores, sender: sender)
            notifier.now = { optIn.addingTimeInterval(2 * hour) }
            try await notifier.runOnce()
            try await notifier.runOnce()

            let mine = sender.messages.filter { $0.0.payload["titleId"] == title.id.description }
            #expect(mine.count == 1, "episode 2 only, and only once")
            #expect(mine.first?.0.title == "Severance")
            #expect(mine.first?.0.body == "S1 E2 · “Episode 2” is out")
            #expect(mine.first?.0.payload["libraryItemId"] == itemID, "a tap opens the library item")
            #expect(mine.first?.1.token == live)
            #expect(
                try await env.stores.push.devices(userID: env.userID).map(\.token) == [live],
                "dead token forgotten"
            )
        }
    }

    @Test("Nothing is announced to someone who has not turned airing on")
    func optedOut() async throws {
        try await LibraryHarness.run { env in
            let title = Title(type: .show, title: "Quiet Show", ids: ExternalIDs(tmdb: uniqueID("tmdb")))
            try await env.stores.titles.insert(title, status: .returning, runtimeMinutes: 30)
            try await withSQL { sql in
                try await sql.raw("""
                INSERT INTO show_episodes (id, title_id, season, episode, airs_at)
                VALUES (\(bind: UUID()), \(bind: title.id.rawValue), 1, 1, \(bind: Date().addingTimeInterval(-60)))
                """).run()
            }
            _ = try await env.send(.post, "/v1/library/items", json: [
                "mediaRef": ["titleId": title.id.description, "type": "show"], "status": "in_progress",
            ])
            _ = try await register(env, Self.token())
            let sender = FakeSender()
            try await AiringNotifier(stores: env.stores, sender: sender).runOnce()
            #expect(sender.messages.allSatisfy { $0.0.payload["titleId"] != title.id.description })
        }
    }
}
