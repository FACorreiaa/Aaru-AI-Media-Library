import AaruCore
import Foundation
import Logging
import Testing
@testable import aaru

/// SCR-010 against a stubbed MyAnimeList list, in the MAL suite so its passes never meet another
/// suite's connections. Reads run per connection: a pass would claim every due connection.
extension MALTests {
    func puller(_ env: LibraryHarness, _ fake: FakeMAL) -> MALPuller {
        let api = api(fake)
        return MALPuller(
            stores: env.stores, connect: MALConnectService(stores: env.stores, settings: api.settings, api: api),
            imports: env.services.imports, api: api, logger: Logger(label: "mal-pull-tests")
        )
    }

    /// MAL ids are numbers; random ones keep parallel suites off each other's anime mappings.
    func malID() -> String {
        String(Int.random(in: 10_000_000 ... 999_999_999))
    }

    /// One list entry as MAL's API writes it, `updated_at` with a `+00:00` offset.
    static func entry(
        _ malID: String, _ status: String, episodes: Int, score: Int = 0, updated: Date,
        title: String = "Frieren", type: String = "tv", total: Int = 3
    ) -> [String: Any] {
        let stamp = ISO8601DateFormatter().string(from: updated).replacingOccurrences(of: "Z", with: "+00:00")
        return [
            "node": ["id": Int(malID) ?? 0, "title": title, "media_type": type, "num_episodes": total],
            "list_status": [
                "status": status, "score": score, "num_episodes_watched": episodes, "is_rewatching": false,
                "updated_at": stamp,
            ],
        ]
    }

    func due(_ env: LibraryHarness, since cursor: Date, full: Bool = false) -> MALPullDue {
        MALPullDue(userID: env.userID, cursor: cursor, fullRead: full)
    }

    func watched(_ env: LibraryHarness, _ item: String) async throws -> [EpisodeKey] {
        try await env.stores.library.watched(itemID: LibraryItemID(#require(UUID(uuidString: item)))).sorted()
    }

    /// Leaves nothing due for a later test's push pass.
    func disconnect(_ env: LibraryHarness) async throws {
        #expect(try await env.send(.delete, "/v1/connections/mal").status == .noContent)
    }

    func itemStatus(_ env: LibraryHarness, _ item: String) async throws -> String? {
        try await env.send(.get, "/v1/library/items/\(item)").json()["status"] as? String
    }

    @Test("SCR-010: an episode ticked on MAL shows in Aaru; older entries stop the read; asks wait 10 min")
    func readsChangesSinceTheCursor() async throws {
        let fake = FakeMAL()
        try await LibraryHarness.run(mal: api(fake)) { env in
            let (mal1, older) = (malID(), malID())
            try await connect(env)
            let (_, item) = try await anime(env, seasons: [1: [mal1]])
            let now = Date()
            fake.setList([
                Self.entry(mal1, "watching", episodes: 2, updated: now.addingTimeInterval(60)),
                Self.entry(older, "completed", episodes: 12, updated: now.addingTimeInterval(-86400)),
            ])
            #expect(try await env.send(.post, "/v1/connections/mal/pull").status == .noContent)
            let claimed = try await env.stores.mal.claimPulls(
                now: now, staleBefore: now.addingTimeInterval(-MALPuller.interval), fullBefore: .distantPast,
                limit: 1000
            )
            let mine = try #require(claimed.first { $0.userID == env.userID }, "an asked-for read is due")

            #expect(try await puller(env, fake).pull(mine) == 1)
            #expect(try await watched(env, item).map(\.episode) == [1, 2])
            let action = try #require(try await env.stores.library.actions(userID: env.userID, limit: 1).first)
            #expect(action.summary.contains("MyAnimeList"), "the ribbon names MAL")
            #expect(try await env.send(.post, "/v1/actions/\(action.id.uuidString)/undo").status == .ok)

            #expect(try await !env.services.malConnect.requestPull(userID: env.userID), "read under 10 min ago")
            let status = try await env.send(.get, "/v1/connections/mal").json()
            #expect(status["pulledAt"] is String)

            fake.setList([Self.entry(mal1, "watching", episodes: 3, updated: now.addingTimeInterval(60))])
            #expect(
                try await puller(env, fake).pull(due(env, since: now.addingTimeInterval(60))) == 0,
                "not newer than the cursor: already read"
            )
            try await disconnect(env)
        }
    }

    @Test("SCR-010: Aaru's own push coming back changes nothing; MAL never moves a status back or past a hand-set one")
    func echoesAndBackwardMovesAreIgnored() async throws {
        let fake = FakeMAL()
        try await LibraryHarness.run(mal: api(fake)) { env in
            let (mal1, mal2) = (malID(), malID())
            try await connect(env)
            let (_, item) = try await anime(env, seasons: [1: [mal1]])
            for episode in 1 ... 3 {
                try await tick(env, item, 1, episode)
            }
            try await pusher(env, fake).runOnce()
            #expect(fake.patches.last?.fields["status"] == "completed")
            let actions = try await env.stores.library.actions(userID: env.userID, limit: 50).count

            let now = Date()
            fake.setList([Self.entry(mal1, "completed", episodes: 3, updated: now.addingTimeInterval(60))])
            #expect(try await puller(env, fake).pull(due(env, since: now)) == 0, "Aaru's own push")
            #expect(try await env.stores.library.actions(userID: env.userID, limit: 50).count == actions)

            fake.setList([Self.entry(mal1, "watching", episodes: 1, updated: now.addingTimeInterval(120))])
            #expect(try await puller(env, fake).pull(due(env, since: now.addingTimeInterval(60))) == 0)
            #expect(try await watched(env, item).count == 3, "MAL's fewer ticks untick nothing")

            let (_, planned) = try await anime(env, seasons: [1: [mal2]])
            _ = try await env.send(.patch, "/v1/library/items/\(planned)", json: ["status": "wishlist"])
            fake.setList([Self.entry(mal2, "completed", episodes: 3, updated: now.addingTimeInterval(180))])
            try await puller(env, fake).pull(due(env, since: now.addingTimeInterval(120)))
            #expect(try await itemStatus(env, planned) == "wishlist", "a status the user set by hand stays")
            try await disconnect(env)
        }
    }

    @Test("SCR-010: a full read lists entries removed on MAL; Aaru keeps its items")
    func removalsAreListedNotApplied() async throws {
        let fake = FakeMAL()
        try await LibraryHarness.run(mal: api(fake)) { env in
            let (mal1, mal2) = (malID(), malID())
            try await connect(env)
            let (_, item) = try await anime(env, seasons: [1: [mal1]])
            for (id, name) in [(mal1, "Frieren"), (mal2, "Dungeon Meshi")] {
                try await env.stores.mal.saveEntryState(
                    MALEntryState(malID: id, status: .watching, episodes: 1, score: 0), title: name,
                    userID: env.userID
                )
            }
            let now = Date()
            fake.setList([Self.entry(mal1, "watching", episodes: 1, updated: now.addingTimeInterval(-60))])
            try await puller(env, fake).pull(due(env, since: now, full: true))
            let removed = try await env.send(.get, "/v1/connections/mal").json()["removed"] as? [[String: Any]]
            #expect(removed?.map { $0["title"] as? String } == ["Dungeon Meshi"])
            #expect(try await itemStatus(env, item) == "in_progress")

            fake.setList([
                Self.entry(mal2, "watching", episodes: 1, updated: now.addingTimeInterval(-30)),
                Self.entry(mal1, "watching", episodes: 1, updated: now.addingTimeInterval(-60)),
            ])
            try await puller(env, fake).pull(due(env, since: now, full: true))
            let after = try await env.send(.get, "/v1/connections/mal").json()["removed"] as? [[String: Any]]
            #expect(after?.isEmpty == true, "back on MAL: no longer listed")
            try await disconnect(env)
        }
    }

    @Test("SCR-010: MAL refusing the token while reading marks the connection for reconnecting")
    func revokedWhileReading() async throws {
        let fake = FakeMAL()
        try await LibraryHarness.run(mal: api(fake)) { env in
            try await connect(env)
            fake.failList(401)
            #expect(try await puller(env, fake).pull(due(env, since: Date())) == 0)
            #expect(try await env.send(.get, "/v1/connections/mal").json()["needsReconnect"] as? Bool == true)
        }
    }

    @Test("SCR-010: entries read as IMP-013 reads MAL's export")
    func rowsAndStates() throws {
        let now = Date()
        func decode(_ entry: [String: Any]) throws -> MALListEntry {
            let page = try JSONSerialization.data(withJSONObject: ["data": [entry]])
            return try #require(try MALAPI.decoder.decode(MALListPage.self, from: page).data.first)
        }
        let onHold = try decode(Self.entry("7", "on_hold", episodes: 2, score: 8, updated: now))
        #expect(MALPuller.row(onHold).status == .inProgress)
        #expect(MALPuller.row(onHold).watched?.count == 2)
        #expect(MALPuller.row(onHold).rating == 8)
        #expect(MALPuller.state(onHold) == MALEntryState(malID: "7", status: .onHold, episodes: 2, score: 8))
        #expect(abs(onHold.listStatus.updatedAt.timeIntervalSince(now)) < 1, "the +00:00 offset is read")

        let planned = try decode(Self.entry("8", "plan_to_watch", episodes: 0, updated: now))
        #expect(MALPuller.row(planned).status == .wishlist)
        #expect(MALPuller.row(planned).rating == nil, "a score of 0 is no score")

        let film = try decode(Self.entry("9", "completed", episodes: 1, updated: now, type: "movie", total: 1))
        #expect(MALPuller.row(film).type == .movie)
        #expect(MALPuller.row(film).watched == nil)
    }
}
