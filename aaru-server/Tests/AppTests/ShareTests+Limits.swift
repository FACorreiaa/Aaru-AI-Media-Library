import AaruCore
import Foundation
import Testing
@testable import aaru

/// SHR-002: a share link must not cost a provider call it can avoid, nor fail its public page
/// over a provider it does not need.
extension ShareTests {
    @Test("a shared show opens from the catalog row alone, even while the catalog is down")
    func titleNeedsNoProvider() async throws {
        try await LibraryHarness.run { env in
            let tmdb = env.stubShow("Severance", status: .returning)
            let created = try await env.send(
                .post, "/v1/shares", json: ["target": ["kind": "title", "ref": ["type": "show", "ids": ["tmdb": tmdb]]]]
            )
            let code = try code(created)
            env.fake.fail(with: ProviderError(provider: "tmdb", kind: .unavailable))
            let reply = try await env.send(.get, "/v1/shares/\(code)", token: signedOut)
            #expect(reply.status == .ok)
            let title = try #require(reply.json()["title"] as? [String: Any])
            #expect(title["title"] as? String == "Severance")
            #expect(title["seasons"] == nil, "no episode list on a public page")
        }
    }

    @Test("an event the provider doesn't know can't be shared")
    func unknownEventsRefused() async throws {
        try await LibraryHarness.run(concerts: FakeConcerts(), sports: FakeSports()) { env in
            let match = try await env.send(.post, "/v1/shares", json: ["target": ["kind": "sport_event", "id": "777"]])
            #expect(match.status == .unprocessableContent)
            let concert = try await env.send(.post, "/v1/shares", json: ["target": ["kind": "concert", "id": "Z404"]])
            #expect(concert.status == .unprocessableContent)
        }
        try await LibraryHarness.run { env in
            let off = try await env.send(.post, "/v1/shares", json: ["target": ["kind": "sport_event", "id": "42"]])
            #expect(off.status == .unprocessableContent, "sports off: nothing to share")
        }
    }

    @Test("share lookups that miss the cache stop at their own budget, not the whole provider's")
    func providerBudgets() async throws {
        try await withMigratedStores { stores in
            let concerts = FakeConcerts()
            concerts.events = ["Z1": sampleConcert("Z1", "2026-11-02"), "Z2": sampleConcert("Z2", "2026-11-03")]
            let service = ConcertService(
                stores: stores, listing: concerts, places: nil, shareLookups: CallBudget(limit: 1)
            )
            #expect(await service.concert(id: "Z1") != nil)
            #expect(await service.concert(id: "Z1") != nil, "a cached concert costs nothing")
            #expect(await service.concert(id: "Z2") == nil, "over the share budget")
            #expect(concerts.eventCalls == ["Z1"])

            let sports = FakeSports()
            sports.events["1"] = sampleMatch("1", home: "a", away: "b", at: "2026-10-18T14:00:00Z")
            sports.events["2"] = sampleMatch("2", home: "c", away: "d", at: "2026-10-18T14:00:00Z")
            let sportsService = SportsService(
                stores: stores, listing: sports, shareLookups: FixedWindowRateLimiter(limit: 1, window: 60)
            )
            let first = try await sportsService.publicEvent(id: "1")
            let second = try await sportsService.publicEvent(id: "2")
            #expect(first != nil)
            #expect(second == nil, "over the share budget")
        }
        #expect(ConcertService.shareCallsPerDay == 1000)
        #expect(SportsService.shareCallsPerMinute == 20)
    }

    @Test("a note is measured as the database measures it, so a long emoji note is a 422, not a 500")
    func emojiNote() async throws {
        try await LibraryHarness.run(sports: sportsWith(["42"])) { env in
            let thumbs = String(repeating: "👍🏽", count: 100)
            let reply = try await env.send(
                .post, "/v1/shares", json: ["target": ["kind": "sport_event", "id": "42"], "note": thumbs]
            )
            #expect(reply.status == .unprocessableContent)
        }
    }

    /// A sports provider that knows these event ids.
    func sportsWith(_ ids: [String]) -> FakeSports {
        let sports = FakeSports()
        for id in ids {
            sports.events[id] = sampleMatch(id, home: "a\(id)", away: "b\(id)", at: "2026-10-18T14:00:00Z")
        }
        return sports
    }
}
