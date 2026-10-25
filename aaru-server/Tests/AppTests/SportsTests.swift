import AaruCore
import Foundation
import Testing
@testable import aaru

@Suite("Sports over the API (SPT-001, SPT-002)", .serialized)
struct SportsAPITests {
    static let arsenal = SportEntity(
        kind: .team, id: "133604", name: "Arsenal", sport: "Soccer",
        badgeURL: URL(string: "https://r2.thesportsdb.com/arsenal.png"), country: "England", leagueID: "4328"
    )
    static let pereira = SportEntity(
        kind: .player, id: "34215679", name: "Alex Pereira", sport: "Fighting", teamID: "135481",
        teamName: "UFC Heavyweight"
    )
    static let heavyweight = SportEntity(
        kind: .team, id: "135481", name: "UFC Heavyweight", sport: "Fighting", leagueID: "4443"
    )
    static let nba = SportEntity(kind: .league, id: "4387", name: "NBA", sport: "Basketball", leagueID: "4387")

    func provider() -> FakeSports {
        let fake = FakeSports()
        for entity in [Self.arsenal, Self.pereira, Self.heavyweight, Self.nba] {
            fake.entities["\(entity.kind.rawValue):\(entity.id)"] = entity
        }
        return fake
    }

    @Test("Off without a provider: settings say so, lists come back unavailable, following is a 503")
    func off() async throws {
        try await LibraryHarness.run { env in
            let settings = try await env.send(.get, "/v1/me/sport-settings").json()
            #expect(settings["available"] as? Bool == false)
            let picks = try await env.send(.get, "/v1/sports/suggested").json()
            #expect(picks["unavailable"] as? Bool == true)
            #expect((picks["items"] as? [Any])?.count == SportsService.suggested.count)
            let favorites = try await env.send(.get, "/v1/sports/favorites").json()
            #expect(favorites["unavailable"] as? Bool == true)
            let search = try await env.send(.get, "/v1/sports/search?q=arsenal").json()
            #expect(search["unavailable"] as? Bool == true)
            let schedule = try await env.send(.get, "/v1/sports/schedule?date=2026-10-24").json()
            #expect(schedule["unavailable"] as? Bool == true)
            let follow = try await env.send(.put, "/v1/me/sport-follows/team/133604")
            #expect(follow.status == .serviceUnavailable)
            #expect(try follow.json()["code"] as? String == "sports_unavailable")
        }
    }

    @Test("Following looks the entity up and keeps a snapshot; a fighter gets the promotion as league")
    func follows() async throws {
        let fake = provider()
        try await LibraryHarness.run(sports: fake) { env in
            let team = try await env.send(.put, "/v1/me/sport-follows/team/133604").json()
            #expect(team["name"] as? String == "Arsenal" && team["following"] as? Bool == true)
            #expect(team["leagueId"] as? String == "4328")

            let fighter = try await env.send(.put, "/v1/me/sport-follows/player/34215679").json()
            #expect(fighter["teamId"] as? String == "135481")
            #expect(fighter["leagueId"] as? String == "4443", "the division's league: UFC")

            let again = try await env.send(.put, "/v1/me/sport-follows/team/133604")
            #expect(again.status == .ok, "following twice is fine")

            let unknown = try await env.send(.put, "/v1/me/sport-follows/team/999")
            #expect(unknown.status == .notFound)
            let junk = try await env.send(.put, "/v1/me/sport-follows/team/abc")
            #expect(junk.status == .notFound)

            let list = try #require(try await env.send(.get, "/v1/me/sport-follows")
                .json()["items"] as? [[String: Any]])
            #expect(list.map { $0["id"] as? String } == ["133604", "34215679"])

            fake.fail(true)
            let offline = try #require(
                try await env.send(.get, "/v1/me/sport-follows").json()["items"] as? [[String: Any]]
            )
            #expect(
                offline.first?["badgeUrl"] as? String == "https://r2.thesportsdb.com/arsenal.png",
                "the snapshot renders while the provider is down"
            )
            fake.fail(false)

            #expect(try await env.send(.delete, "/v1/me/sport-follows/team/133604").status == .noContent)
            #expect(try await env.send(.delete, "/v1/me/sport-follows/team/133604").status == .noContent)
            let after = try #require(try await env.send(.get, "/v1/me/sport-follows").json()["items"] as? [Any])
            #expect(after.count == 1)
        }
    }

    @Test("At the limit a new follow is refused; refreshing one already followed is not")
    func limit() async throws {
        try await LibraryHarness.run(sports: provider()) { env in
            let store = env.stores.sports
            let first = try await store.follow(Self.arsenal, userID: env.userID, limit: 1, now: Date())
            let second = try await store.follow(Self.nba, userID: env.userID, limit: 1, now: Date())
            let refresh = try await store.follow(Self.arsenal, userID: env.userID, limit: 1, now: Date())
            #expect(first && !second && refresh)
        }
    }

    @Test("Favorites: live, next and last per follow, with the live line laid over listed events")
    func favorites() async throws {
        let fake = provider()
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-24T15:00:00Z"))
        fake.schedules["next:team:133604"] = [
            sampleMatch("live1", home: "133604", away: "133615", at: "2026-10-24T14:00:00Z"),
            sampleMatch("n2", home: "133601", away: "133604", at: "2026-11-01T15:00:00Z"),
        ]
        fake.schedules["previous:team:133604"] = [
            sampleMatch("p1", home: "133604", away: "1", at: "2026-10-04T15:00:00Z", homeScore: 3, awayScore: 0),
            sampleMatch("p2", home: "2", away: "133604", at: "2026-10-18T15:00:00Z", homeScore: 1, awayScore: 1),
        ]
        var line = sampleMatch(
            "live1", home: "133604", away: "133615", at: "2026-10-24T14:00:00Z", status: .live, homeScore: 1,
            awayScore: 0
        )
        line.progress = "67"
        fake.liveEvents = [line]
        fake.schedules["next:league:4443"] = [SportEvent(
            id: "ufc333", sport: "Fighting", name: "UFC 333", leagueID: "4443", league: "UFC", startsAt: now
                .addingTimeInterval(3600), day: "2026-10-24", status: .scheduled
        )]
        try await LibraryHarness.run(sports: fake) { env in
            var service = env.services.sports
            service.now = { now }
            _ = try await service.follow(.team, id: "133604", userID: env.userID)
            _ = try await service.follow(.player, id: "34215679", userID: env.userID)
            let favorites = try await service.favorites(userID: env.userID)
            #expect(!favorites.unavailable)
            let team = try #require(favorites.items.first { $0.entity.kind == .team })
            #expect(team.live.map(\.id) == ["live1"] && team.live.first?.progress == "67")
            #expect(team.live.first?.home?.score == 1)
            #expect(team.next?.id == "n2", "the game being played is live, not next")
            #expect(team.last?.id == "p2", "the most recent result")
            #expect(!team.pending)
            let fighter = try #require(favorites.items.first { $0.entity.kind == .player })
            #expect(fighter.next?.id == "ufc333", "a fighter's fixtures are the promotion's cards")
            #expect(fake.asked.contains("schedule:next:league:4443"))

            let calls = fake.asked.count
            _ = try await service.favorites(userID: env.userID)
            #expect(fake.asked.count == calls, "everything is cached")
        }
    }

    @Test("A slow provider: favorites answer within patience, pending, and are ready next time")
    func pending() async throws {
        let fake = provider()
        fake.schedules["next:team:133604"] = [sampleMatch("n1", home: "133604", away: "2", at: "2099-01-01T15:00:00Z")]
        try await LibraryHarness.run(sports: fake) { env in
            var service = env.services.sports
            service.patience = .milliseconds(100)
            _ = try await service.follow(.team, id: "133604", userID: env.userID)
            fake.delay(.milliseconds(400))
            let first = try await service.favorites(userID: env.userID)
            #expect(first.items.first?.pending == true && first.items.first?.next == nil)
            try await Task.sleep(for: .milliseconds(700))
            let second = try await service.favorites(userID: env.userID)
            #expect(second.items.first?.pending == false && second.items.first?.next?.id == "n1")
        }
    }

    @Test("Schedule: one local day across two UTC days, followed teams highlighted and their leagues first")
    func schedule() async throws {
        let fake = provider()
        // Lisbon is UTC+1 on 2026-10-24 (summer time ends the next day): the local day runs from
        // 23:00Z on the 23rd to 23:00Z on the 24th.
        fake.days["4328:2026-10-23"] = [
            sampleMatch("late", home: "133604", away: "5", at: "2026-10-23T23:30:00Z"),
            sampleMatch("before", home: "6", away: "7", at: "2026-10-23T20:00:00Z"),
        ]
        fake.days["4328:2026-10-24"] = [
            sampleMatch("noon", home: "8", away: "9", at: "2026-10-24T12:00:00Z"),
            sampleMatch("after", home: "8", away: "9", at: "2026-10-24T23:30:00Z"),
        ]
        fake.days["4387:2026-10-24"] = [SportEvent(
            id: "nba1", sport: "Basketball", name: "Lakers vs Celtics", leagueID: "4387", league: "NBA",
            startsAt: ISO8601DateFormatter().date(from: "2026-10-24T01:00:00Z"), day: "2026-10-24", status: .scheduled
        )]
        fake.schedules["next:team:133604"] = [
            sampleMatch("cup", home: "133604", away: "3", league: "4480", at: "2026-10-24T19:00:00Z"),
        ]
        try await LibraryHarness.run(sports: fake) { env in
            _ = try await env.send(.put, "/v1/me/sport-follows/team/133604")
            _ = try await env.send(.put, "/v1/me/sport-follows/league/4387")
            let day = try await env.send(.get, "/v1/sports/schedule?date=2026-10-24&tz=Europe/Lisbon").json()
            #expect(day["pending"] as? Bool == false)
            let groups = try #require(day["groups"] as? [[String: Any]])
            #expect(
                groups.map { $0["leagueId"] as? String } == ["4328", "4480", "4387"],
                "leagues with a followed team first, then by name"
            )
            let premier = try #require(groups.first { $0["leagueId"] as? String == "4328" })
            let ids = (premier["events"] as? [[String: Any]])?.compactMap { $0["id"] as? String }
            #expect(ids == ["late", "noon"], "only the local day, in order")
            let late = (premier["events"] as? [[String: Any]])?.first
            #expect(late?["isFavorite"] as? Bool == true)
            #expect(fake.asked.contains("day:4328:2026-10-23") && fake.asked.contains("day:4328:2026-10-24"))

            #expect(try await env.send(.get, "/v1/sports/schedule?date=2026-02-30").status == .unprocessableContent)
            #expect(try await env.send(.get, "/v1/sports/schedule?date=2026-10-24&tz=Mars/Base").status
                == .unprocessableContent)
        }
    }

    @Test("Event: where to watch, the chosen country first; the rest by country")
    func event() async throws {
        let fake = provider()
        fake.events["42"] = sampleMatch(
            "42", home: "133604", away: "133615", at: "2026-10-18T14:00:00Z", homeScore: 2, awayScore: 0
        )
        fake.channels["42"] = [
            SportBroadcast(channel: "Sport TV1", country: "Portugal"),
            SportBroadcast(channel: "Sky Sports", country: "United Kingdom"),
            SportBroadcast(channel: "Peacock", country: "USA"),
        ]
        try await LibraryHarness.run(sports: fake) { env in
            var detail = try await env.send(.get, "/v1/sports/events/42").json()
            #expect((detail["inYourCountry"] as? [Any])?.isEmpty == true, "no country chosen yet")
            #expect((detail["elsewhere"] as? [Any])?.count == 3)
            #expect(
                (detail["event"] as? [String: Any])?["status"] as? String == "finished",
                "a past event with a score is finished"
            )

            let saved = try await env.send(.put, "/v1/me/sport-settings", json: ["watchCountryCode": "us"]).json()
            #expect(saved["watchCountryCode"] as? String == "US" && saved["available"] as? Bool == true)
            detail = try await env.send(.get, "/v1/sports/events/42").json()
            let mine = (detail["inYourCountry"] as? [[String: Any]])?.compactMap { $0["channel"] as? String }
            #expect(mine == ["Peacock"], "USA matches US")
            let rest = (detail["elsewhere"] as? [[String: Any]])?.compactMap { $0["channel"] as? String }
            #expect(rest == ["Sport TV1", "Sky Sports"])

            let bad = try await env.send(.put, "/v1/me/sport-settings", json: ["watchCountryCode": "USA"])
            #expect(bad.status == .unprocessableContent)
            let cleared = try await env.send(.put, "/v1/me/sport-settings", json: [String: Any]()).json()
            #expect(cleared["watchCountryCode"] == nil)
            #expect(try await env.send(.get, "/v1/sports/events/7").status == .notFound)
        }
    }

    @Test("Sports stay in Sports: no library row, action, point or activity; the export carries them")
    func isolation() async throws {
        try await LibraryHarness.run(sports: provider()) { env in
            let before = try await rowsReferencing(env.userID)
            _ = try await env.send(.put, "/v1/me/sport-follows/team/133604")
            _ = try await env.send(.put, "/v1/me/sport-settings", json: ["watchCountryCode": "PT"])
            _ = try await env.send(.get, "/v1/sports/favorites")
            let after = try await rowsReferencing(env.userID)
            let touched = Set(after.filter { before[$0.key] != $0.value }.keys)
            #expect(touched == ["sport_follows", "sport_settings"], "touched \(touched)")
            #expect(try await env.actionCount() == 0)

            let export = try await env.send(.get, "/v1/me/export").json()
            let sports = try #require(export["sports"] as? [String: Any])
            #expect((sports["follows"] as? [[String: Any]])?.first?["id"] as? String == "133604")
            #expect(sports["watchCountryCode"] as? String == "PT")
        }
    }

    @Test("Search: all three kinds in order, each marked when already followed")
    func search() async throws {
        let fake = provider()
        fake.searchHits = [Self.arsenal, SportEntity(kind: .league, id: "1", name: "Arsenal League", sport: "Soccer")]
        try await LibraryHarness.run(sports: fake) { env in
            _ = try await env.send(.put, "/v1/me/sport-follows/team/133604")
            let found = try #require(try await env.send(.get, "/v1/sports/search?q=Arsenal").json()["items"]
                as? [[String: Any]])
            #expect(found.map { $0["kind"] as? String } == ["league", "team"])
            #expect(found.last?["following"] as? Bool == true && found.first?["following"] as? Bool == false)
            #expect(try await env.send(.get, "/v1/sports/search?q=a").status == .unprocessableContent)
            let teamsOnly = try #require(try await env.send(.get, "/v1/sports/search?q=Arsenal&kind=team")
                .json()["items"]
                as? [Any])
            #expect(teamsOnly.count == 1)
        }
    }
}
