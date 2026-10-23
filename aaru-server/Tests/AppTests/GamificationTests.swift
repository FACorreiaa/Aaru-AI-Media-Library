import AaruCore
import FluentSQL
import Foundation
import HTTPTypes
import Testing
@testable import aaru

@Suite("Points ledger, streaks and badges (GAM-001…004)", .serialized)
struct GamificationTests {
    let friendTests = FriendTests()

    func total(_ env: LibraryHarness, token: String? = nil) async throws -> Int {
        try #require(try await env.send(.get, "/v1/me/progress", token: token).json()["total"] as? Int)
    }

    func lastActionID(_ env: LibraryHarness) async throws -> String {
        let actions = try await env.send(.get, "/v1/actions?limit=1").json()
        return try #require((actions["items"] as? [[String: Any]])?.first?["id"] as? String)
    }

    func unseen(_ env: LibraryHarness, token: String? = nil) async throws -> (origin: String?, badges: [String]) {
        let unseen = try await env.send(.get, "/v1/me/progress", token: token).json()["unseen"] as? [String: Any]
        let items = unseen?["items"] as? [[String: Any]] ?? []
        return (unseen?["origin"] as? String, items.compactMap { $0["badge"] as? String })
    }

    @Test("GAM-001: a tick earns once; untick takes it back; undo then redo nets one award")
    func tickUndoRedo() async throws {
        try await LibraryHarness.run { env in
            let id = try await env.add("show", tmdb: env.stubShow("Andor", status: .returning, seasons: 1))
            _ = try await env.send(.put, "/v1/library/items/\(id)/episodes/1/1", json: ["watched": true])
            #expect(try await total(env) == 10)
            _ = try await env.send(.put, "/v1/library/items/\(id)/episodes/1/1", json: ["watched": true])
            #expect(try await total(env) == 10, "ticking again earns nothing")

            _ = try await env.send(.put, "/v1/library/items/\(id)/episodes/1/1", json: ["watched": false])
            #expect(try await total(env) == 0)
            _ = try await env.send(.put, "/v1/library/items/\(id)/episodes/1/1", json: ["watched": true])
            #expect(try await total(env) == 10)

            let tick = try await lastActionID(env)
            #expect(try await env.send(.post, "/v1/actions/\(tick)/undo").status == .ok)
            #expect(try await total(env) == 0)
            let undo = try await lastActionID(env)
            #expect(try await env.send(.post, "/v1/actions/\(undo)/undo").status == .ok)
            #expect(try await total(env) == 10, "undo then redo nets one award")

            let cached = try await env.stores.gamification.totalPoints(userID: env.userID)
            #expect(try await env.stores.gamification.rebuildTotal(userID: env.userID) == cached)
        }
    }

    @Test("GAM-001: a full season earns its bonus; undoing the mark takes all of it back")
    func seasonBonus() async throws {
        try await LibraryHarness.run { env in
            let id = try await env.add("show", tmdb: env.stubShow("Severance", status: .ended, seasons: 1))
            _ = try await env.send(.post, "/v1/library/items/\(id)/seasons/1/watched")
            #expect(try await total(env) == 3 * 10 + 30)
            #expect(try await env.send(.post, "/v1/actions/\(lastActionID(env))/undo").status == .ok)
            #expect(try await total(env) == 0)
        }
    }

    @Test("GAM-001: daily caps hold; a capped award still spends its root")
    func dailyCap() async throws {
        try await LibraryHarness.run { env in
            let id = try await env.add(
                "show", tmdb: env.stubShow("The Wire", status: .ended, seasons: 1, perSeason: 35)
            )
            _ = try await env.send(.post, "/v1/library/items/\(id)/seasons/1/watched")
            #expect(try await total(env) == 300 + 30, "episodes stop at 300 a day; the season bonus has its own cap")
        }
    }

    @Test("GAM-001: the same scrobble twice awards once, with the scrobble bonus on top")
    func scrobbleOnce() async throws {
        try await LibraryHarness.run { env in
            let catalogs = FakeCatalog.providers(env.fake)
            let resolver = TitleResolver(stores: env.stores, catalogs: catalogs)
            let library = LibraryService(
                stores: env.stores, resolver: resolver, catalog: CatalogService(stores: env.stores, catalogs: catalogs)
            )
            let minted = try await AgentTokenService(
                stores: env.stores, publicBaseURL: URL(string: "https://api.aaruapp.com")!
            ).create(userID: env.userID, kind: .stremio, name: nil, allowLibraryWrites: false)
            let scrobble = ScrobbleService(stores: env.stores, library: library, resolver: resolver)
            let caller = AgentCaller(userID: env.userID, token: minted.token)
            let tmdb = env.stubShow("Andor", status: .ended, seasons: 1)
            _ = try await env.add("show", tmdb: tmdb, status: "in_progress")
            let title = try #require(try await env.stores.titles.find(ids: ExternalIDs(tmdb: tmdb), type: .show))
            let key = try EpisodeKey(season: 1, episode: 2)
            #expect(try await scrobble.markWatched(title, episodes: [key], caller: caller))
            #expect(try await total(env) == 15)
            _ = try await scrobble.markWatched(title, episodes: [key], caller: caller)
            #expect(try await total(env) == 15, "a replayed scrobble earns nothing twice")
        }
    }

    @Test("GAM-001: imports and approved plans earn nothing per item, and no streak day")
    func importsEarnNothing() async throws {
        try await LibraryHarness.run { env in
            let id = try await env.add("show", tmdb: env.stubShow("Lost", status: .ended, seasons: 1))
            let item = try #require(LibraryItemID(uuidString: id))
            let keys = try [EpisodeKey(season: 1, episode: 1), EpisodeKey(season: 1, episode: 2)]
            for kind in ["import", "plan"] {
                try await env.stores.library.apply(
                    .setEpisodes(item, watch: keys, unwatch: []), userID: env.userID, actor: .user, kind: kind,
                    summary: kind
                )
            }
            #expect(try await total(env) == 0)
            #expect(try await env.stores.gamification.streakDays(userID: env.userID).isEmpty)
        }
    }

    @Test("GAM-001: a friendship earns both; unfriending within 7 days takes it back; re-friending earns nothing")
    func friendPoints() async throws {
        try await LibraryHarness.run { env in
            let ana = try await friendTests.friends(env)
            #expect(try await total(env) == 20)
            #expect(try await total(env, token: ana.token) == 20)
            #expect(try await env.send(.delete, "/v1/social/friends/\(ana.id)").status == .noContent)
            #expect(try await total(env) == 0)
            #expect(try await total(env, token: ana.token) == 0)

            let code = try #require(
                try await env.send(.post, "/v1/social/invites", json: [:] as [String: Any]).json()["code"] as? String
            )
            _ = try await env.send(
                .post,
                "/v1/social/invites/\(code)/redeem",
                json: ["addTitle": false],
                token: ana.token
            )
            #expect(try await total(env) == 0, "the pair's points were spent")
        }
    }

    @Test("GAM-003: the streak day is dated in X-Timezone and the zone is kept; imported ticks are no streak day")
    func streakDayZone() async throws {
        try await LibraryHarness.run { env in
            let id = try await env.add("show", tmdb: env.stubShow("Shogun", status: .ended, seasons: 1))
            var headers = HTTPFields()
            headers[.xTimezone] = "Pacific/Kiritimati"
            _ = try await env.send(
                .put, "/v1/library/items/\(id)/episodes/1/1", json: ["watched": true], headers: headers
            )
            let zone = try #require(TimeZone(identifier: "Pacific/Kiritimati"))
            let days = try await env.stores.gamification.streakDays(userID: env.userID)
            #expect(days.map(\.date) == [Streak.localDate(Date(), in: zone)])
            #expect(days.first?.timeZone == "Pacific/Kiritimati")
            #expect(
                try await env.stores.gamification.timeZone(userID: env.userID).identifier == "Pacific/Kiritimati",
                "a later request without the header uses the stored zone"
            )

            let progress = try await env.send(.get, "/v1/me/progress", headers: headers).json()
            let streak = try #require(progress["streak"] as? [String: Any])
            #expect(streak["current"] as? Int == 1)
            #expect(streak["today"] as? Bool == true)
            #expect((streak["days"] as? [[String: Any]])?.count == 7)
        }
    }

    @Test("GAM-004: a live finish shows as an unseen badge once; seen clears it; re-evaluating awards nothing")
    func liveBadge() async throws {
        try await LibraryHarness.run { env in
            _ = try await env.add("movie", tmdb: env.stubMovie("Arrival"), status: "finished")
            #expect(try await total(env) == 25)
            let fresh = try await unseen(env)
            #expect(fresh.origin == "live")
            #expect(fresh.badges.contains("first_film"))

            let badges = try await env.send(.get, "/v1/me/badges").json()["items"] as? [[String: Any]] ?? []
            let films = try #require(badges.first { $0["id"] as? String == "films" })
            #expect((films["progress"] as? [String: Any])?["current"] as? Int == 1)
            #expect((films["progress"] as? [String: Any])?["target"] as? Int == 10)
            let secret = try #require(badges.first { $0["id"] as? String == "silver_screen" })
            #expect(
                secret["name"] == nil && secret["description"] == nil && secret["progress"] == nil,
                "a hidden badge not yet earned says nothing"
            )

            let progress = try await env.send(.get, "/v1/me/progress").json()
            let ids = ((progress["unseen"] as? [String: Any])?["items"] as? [[String: Any]] ?? [])
                .compactMap { $0["id"] as? String }
            #expect(try await env.send(.post, "/v1/me/badges/seen", json: ["ids": ids]).status == .noContent)
            #expect(try await unseen(env).badges.isEmpty)

            let again = try await env.services.library.gamification.evaluate(env.userID, origin: .live, actionID: nil)
            #expect(again.isEmpty)
        }
    }

    @Test("GAM-004: undoing the action that earned a tier takes it back")
    func undoTakesBadgeBack() async throws {
        try await LibraryHarness.run { env in
            _ = try await env.add("movie", tmdb: env.stubMovie("Heat"), status: "finished")
            #expect(try await env.stores.gamification.badges(userID: env.userID).contains { $0.badge == "first_film" })
            #expect(try await env.send(.post, "/v1/actions/\(lastActionID(env))/undo").status == .ok)
            #expect(try await !env.stores.gamification.badges(userID: env.userID).contains { $0.badge == "first_film" })
        }
    }

    @Test("GAM-004: the first run over an existing library is one backfill, and imported history counts")
    func backfill() async throws {
        try await LibraryHarness.run { env in
            let movie = env.stubMovie("Casablanca")
            let id = try await env.add("movie", tmdb: movie, status: "finished")
            // As if the account predates achievements: never evaluated, nothing earned.
            try await withSQL { sql in
                try await sql
                    .raw("UPDATE user_progress SET evaluated_at = NULL WHERE user_id = \(bind: env.userID.rawValue)")
                    .run()
                try await sql.raw("DELETE FROM user_badges WHERE user_id = \(bind: env.userID.rawValue)").run()
            }
            _ = id
            let worker = GamificationWorker(
                gamification: GamificationService(stores: env.stores),
                logger: .init(label: "test")
            )
            var claimed = false
            for _ in 0 ..< 50 where !claimed {
                _ = try await worker.step()
                claimed = try await !env.stores.gamification.isFresh(userID: env.userID)
            }
            #expect(claimed)
            let after = try await unseen(env)
            #expect(after.origin == "backfill")
            #expect(after.badges.contains("first_film"))
        }
    }

    @Test("GAM-002: level is a pure function of total points")
    func levels() {
        let table: [(Int, Int)] = [
            (-5, 1),
            (0, 1),
            (99, 1),
            (100, 2),
            (299, 2),
            (300, 3),
            (599, 3),
            (600, 4),
            (1000, 5),
            (4500, 10),
            (4499, 9),
        ]
        for (total, level) in table {
            #expect(Levels.level(for: total) == level, "\(total)")
            #expect(Levels.threshold(level) <= max(total, 0))
        }
    }

    @Test("GAM-005: ISO weeks, Monday to Sunday")
    func weeks() {
        #expect(
            GamificationService.week(containing: "2026-10-22")
                == ISOWeek(name: "2026-W43", from: "2026-10-19", until: "2026-10-25")
        )
        #expect(GamificationService.week(containing: "2026-01-01").name == "2026-W01")
        #expect(GamificationService.week(containing: "2027-01-01").name == "2026-W53")
        #expect(GamificationService.week(containing: "2027-01-04").name == "2027-W01")
        #expect(GamificationService.week(named: "2026-W43")?.from == "2026-10-19")
        #expect(GamificationService.week(named: "2025-W53") == nil, "2025 has 52 weeks")
        #expect(GamificationService.week(named: "nonsense") == nil)
    }
}

extension LibraryService {
    var gamification: GamificationService {
        GamificationService(stores: stores, now: now)
    }
}
