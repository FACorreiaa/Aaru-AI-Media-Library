import AaruCore
import Foundation
import Testing
@testable import aaru

@Suite("Concerts by artist: the Ticketmaster adapter (MUS-010)")
struct ConcertSearchAdapterTests {
    static let events = #"""
    {"_embedded":{"events":[
      {"id":"E1","name":"Radiohead","url":"https://www.ticketmaster.es/event/E1",
       "dates":{"start":{"localDate":"2026-11-02"}},
       "_embedded":{"venues":[{"name":"WiZink Center","city":{"name":"Madrid"},
                               "location":{"longitude":"-3.67200","latitude":"40.42400"}}]}},
      {"id":"E2","name":"Radiohead","url":"https://www.ticketmaster.es/event/E2",
       "dates":{"start":{"localDate":"2026-11-03"}},
       "_embedded":{"venues":[{"name":"Somewhere","location":{"longitude":"","latitude":"x"}}]}}
    ]},"page":{"totalPages":1,"number":0}}
    """#

    @Test("Search sends the keyword, plus the cell and radius only when near; reads the venue's position")
    func search() async throws {
        let stub = StubTransport { _ in OutboundResponse(status: 200, body: Data(Self.events.utf8)) }
        let concerts = TicketmasterConcerts(
            client: ProviderClient(
                name: "ticketmaster", transport: stub, pacer: RequestPacer(requestsPerSecond: 1000, burst: 100)
            ),
            apiKey: "test-key", budget: CallBudget(limit: 100)
        )
        let point = try #require(GeoPoint(latitude: 42.6, longitude: -5.6))
        let from = Date(timeIntervalSince1970: 1_792_000_000)

        let near = try await concerts.search(.keyword("Radiohead"), near: (point, 100), page: 2, from: from)
        let anywhere = try await concerts.search(.keyword("Radiohead"), near: nil, page: 1, from: from)
        _ = try await concerts.search(.performer(id: "K8vZ917G"), near: nil, page: 1, from: from)

        let queries = stub.requests.map { request in
            let items = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        }
        #expect(queries[0]["keyword"] == "Radiohead" && queries[0]["classificationName"] == "music")
        #expect(queries[0]["geoPoint"] == "ezs42" && queries[0]["radius"] == "100" && queries[0]["unit"] == "km")
        #expect(queries[0]["page"] == "1" && queries[0]["sort"] == "date,asc")
        #expect(queries[1]["keyword"] == "Radiohead")
        #expect(queries[1]["geoPoint"] == nil && queries[1]["radius"] == nil, "anywhere sends no area")
        #expect(queries[2]["attractionId"] == "K8vZ917G" && queries[2]["keyword"] == nil, "a picked performer, by id")
        #expect(!near.hasMore)
        #expect(anywhere.concerts.map(\.venuePoint) == [GeoPoint(latitude: 40.424, longitude: -3.672), nil])
    }

    @Test("Performers carry a picture when Ticketmaster has a real one")
    func performerImages() async throws {
        let stub = StubTransport { _ in OutboundResponse(status: 200, body: Data(#"""
        {"_embedded":{"attractions":[
          {"id":"K1","name":"Radiohead","images":[
            {"url":"https://s1.ticketm.net/fallback.jpg","ratio":"16_9","width":205,"fallback":true},
            {"url":"https://s1.ticketm.net/big.jpg","ratio":"16_9","width":1024,"fallback":false},
            {"url":"https://s1.ticketm.net/small.jpg","ratio":"16_9","width":205,"fallback":false}]},
          {"id":"K2","name":"Radiohead Tribute"}
        ]}}
        """#.utf8)) }
        let concerts = TicketmasterConcerts(
            client: ProviderClient(
                name: "ticketmaster", transport: stub, pacer: RequestPacer(requestsPerSecond: 1000, burst: 100)
            ),
            apiKey: "test-key", budget: CallBudget(limit: 100)
        )
        let found = try await concerts.attractions(named: "Radiohead")
        #expect(found.map(\.imageURL?.absoluteString) == ["https://s1.ticketm.net/small.jpg", nil])
    }

    @Test("Distances between points are great-circle kilometres")
    func distance() throws {
        let lisbon = try #require(GeoPoint(latitude: 38.72, longitude: -9.14))
        let madrid = try #require(GeoPoint(latitude: 40.42, longitude: -3.70))
        #expect(abs(lisbon.distanceKm(to: madrid) - 502) < 3)
        #expect(lisbon.distanceKm(to: lisbon) == 0)
    }
}

@Suite("Concerts by artist over the API (MUS-010)", .serialized)
struct ConcertSearchAPITests {
    static func fake() -> FakeConcerts {
        let fake = FakeConcerts()
        var madrid = sampleConcert("E1", "2026-11-02")
        madrid.distanceKm = nil
        madrid.venuePoint = GeoPoint(latitude: 40.42, longitude: -3.70)
        var unknown = sampleConcert("E2", "2026-11-03")
        unknown.distanceKm = nil
        fake.searchConcerts = [madrid, unknown]
        return fake
    }

    @Test("Off without a provider: a search comes back unavailable")
    func off() async throws {
        try await LibraryHarness.run { env in
            let search = try await env.send(.post, "/v1/concerts/search", json: [
                "q": "Radiohead", "scope": "anywhere", "radiusKm": 50,
            ]).json()
            #expect(search["unavailable"] as? Bool == true)
        }
    }

    @Test("Near needs a place: the saved city or a one-off rounded point, else a 409")
    func near() async throws {
        let fake = Self.fake()
        try await LibraryHarness.run(concerts: fake) { env in
            let name = uniqueID("Radiohead")
            let missing = try await env.send(.post, "/v1/concerts/search", json: [
                "q": name, "scope": "near", "radiusKm": 50,
            ])
            #expect(missing.status == .conflict)
            #expect(try missing.json()["code"] as? String == "no_place")
            #expect(fake.searched.isEmpty)

            _ = try await env.send(.put, "/v1/me/concert-place", json: [
                "name": "Lisbon", "latitude": 38.72, "longitude": -9.14,
            ])
            let fromCity = try await env.send(.post, "/v1/concerts/search", json: [
                "q": name, "scope": "near", "radiusKm": 25,
            ]).json()
            #expect(fromCity["radiusKm"] as? Int == 25 && fromCity["scope"] as? String == "near")
            #expect((fromCity["place"] as? [String: Any])?["name"] as? String == "Lisbon")
            #expect(fake.searched.last?.point == GeoPoint(latitude: 38.72, longitude: -9.14))
            #expect(fake.searched.last?.radiusKm == 25)

            let oneOff = try await env.send(.post, "/v1/concerts/search", json: [
                "q": name, "scope": "near", "radiusKm": 50, "latitude": 41.14961, "longitude": -8.61099,
            ]).json()
            #expect(oneOff["place"] == nil, "a one-off position is not the saved city")
            #expect(fake.searched.last?.point == GeoPoint(latitude: 41.15, longitude: -8.61))
        }
    }

    @Test("Anywhere needs no place, sends no area, and measures from the saved city on the server")
    func anywhere() async throws {
        let fake = Self.fake()
        try await LibraryHarness.run(concerts: fake) { env in
            let name = uniqueID("Radiohead")
            let nowhere = try await env.send(.post, "/v1/concerts/search", json: [
                "q": " \(name) ", "scope": "anywhere", "radiusKm": 50,
            ]).json()
            #expect(nowhere["query"] as? String == name && nowhere["scope"] as? String == "anywhere")
            #expect(nowhere["radiusKm"] == nil && nowhere["place"] == nil)
            let bare = try #require(nowhere["items"] as? [[String: Any]])
            #expect(bare.count == 2 && bare.allSatisfy { $0["distanceKm"] == nil }, "no centre, no distance")
            #expect(fake.searched.last?.match == .keyword(name) && fake.searched.last?.point == nil)

            _ = try await env.send(.put, "/v1/me/concert-place", json: [
                "name": "Lisbon", "latitude": 38.72, "longitude": -9.14,
            ])
            let fromCity = try await env.send(.post, "/v1/concerts/search", json: [
                "q": name.uppercased(), "scope": "anywhere", "radiusKm": 50,
            ]).json()
            #expect(fake.searched.count == 1, "the same name in any case is one cached search")
            #expect((fromCity["place"] as? [String: Any])?["name"] as? String == "Lisbon")
            let measured = try #require(fromCity["items"] as? [[String: Any]])
            let distance = try #require(measured.first?["distanceKm"] as? Double)
            #expect(abs(distance - 502) < 3, "Lisbon to Madrid, worked out by the server")
            #expect(measured.last?["distanceKm"] == nil, "a venue without a position has no distance")
            #expect(measured.first?["venuePoint"] == nil, "the venue's position stays on the server")
        }
    }

    @Test("Performers for a name: Ticketmaster's list, each once, at most eight, cached by name")
    func performers() async throws {
        let fake = Self.fake()
        let name = uniqueID("Radiohead")
        fake.attractionsByName[name] = (1 ... 10).map {
            ConcertAttraction(id: "K\($0)", name: "\(name) \($0)", musicbrainzIDs: [])
        } + [ConcertAttraction(id: "K1", name: name, musicbrainzIDs: [])]
        try await LibraryHarness.run(concerts: fake) { env in
            let list = try await env.send(.post, "/v1/concerts/performers", json: ["q": " \(name) "]).json()
            let items = try #require(list["items"] as? [[String: Any]])
            #expect(items.compactMap { $0["id"] as? String } == (1 ... 8).map { "K\($0)" })
            #expect(list["unavailable"] as? Bool == false)
            _ = try await env.send(.post, "/v1/concerts/performers", json: ["q": name.uppercased()])
            #expect(fake.lookedUp.count { $0.lowercased() == name.lowercased() } == 1, "one call per name")

            let short = try await env.send(.post, "/v1/concerts/performers", json: ["q": "R"])
            #expect(short.status == .unprocessableContent)
        }
        try await LibraryHarness.run { env in
            let off = try await env.send(.post, "/v1/concerts/performers", json: ["q": "Radiohead"]).json()
            #expect(off["unavailable"] as? Bool == true && (off["items"] as? [Any])?.isEmpty == true)
        }
    }

    @Test("A picked performer is searched by id, apart from the same name as free text")
    func byPerformer() async throws {
        let fake = Self.fake()
        try await LibraryHarness.run(concerts: fake) { env in
            let name = uniqueID("Radiohead")
            let picked = try await env.send(.post, "/v1/concerts/search", json: [
                "q": name, "performerId": "K8vZ917G", "scope": "anywhere", "radiusKm": 50,
            ]).json()
            #expect(picked["performerId"] as? String == "K8vZ917G" && picked["query"] as? String == name)
            #expect(fake.searched.last?.match == .performer(id: "K8vZ917G"))

            _ = try await env.send(.post, "/v1/concerts/search", json: [
                "q": name, "scope": "anywhere", "radiusKm": 50,
            ])
            #expect(fake.searched.count == 2, "free text is its own search, not the performer's cache")
            #expect(fake.searched.last?.match == .keyword(name))

            for bad in ["", "K8v Z9", "K8vZ917G?x=1", String(repeating: "K", count: 65)] {
                let response = try await env.send(.post, "/v1/concerts/search", json: [
                    "q": name, "performerId": bad, "scope": "anywhere", "radiusKm": 50,
                ])
                #expect(response.status == .unprocessableContent)
            }
        }
    }

    @Test("The name is 2 to 100 characters after trimming; coordinates come in pairs")
    func validation() async throws {
        try await LibraryHarness.run(concerts: Self.fake()) { env in
            for bad in ["R", String(repeating: "x", count: 101), "   "] {
                let response = try await env.send(.post, "/v1/concerts/search", json: [
                    "q": bad, "scope": "anywhere", "radiusKm": 50,
                ])
                #expect(response.status == .unprocessableContent)
            }
            let half = try await env.send(.post, "/v1/concerts/search", json: [
                "q": "Radiohead", "scope": "anywhere", "radiusKm": 50, "latitude": 41.1,
            ])
            #expect(half.status == .unprocessableContent)
        }
    }
}
