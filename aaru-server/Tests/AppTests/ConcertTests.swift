import AaruCore
import Foundation
import Testing
@testable import aaru

/// A concert provider that records what it was asked. Test-only.
final class FakeConcerts: ConcertListing, AlbumArtistListing, @unchecked Sendable {
    // @unchecked: `lock` guards every mutable field.
    private let lock = NSLock()
    struct NearCall {
        var point: GeoPoint
        var radiusKm: Int
        var page: Int
    }

    struct SearchCall {
        var keyword: String
        var point: GeoPoint?
        var radiusKm: Int?
        var page: Int
    }

    private var nearCalls: [NearCall] = []
    private var searchCalls: [SearchCall] = []
    private var performingCalls: [[String]] = []
    private var attractionCalls: [String] = []
    private var failing = false
    var nearConcerts: [Concert] = []
    var searchConcerts: [Concert] = []
    var byAttraction: [String: [Concert]] = [:]
    var attractionsByName: [String: [ConcertAttraction]] = [:]
    var artistsByAlbum: [String: [MusicArtist]] = [:]

    var asked: [NearCall] {
        lock.withLock { nearCalls }
    }

    var searched: [SearchCall] {
        lock.withLock { searchCalls }
    }

    var performers: [[String]] {
        lock.withLock { performingCalls }
    }

    var lookedUp: [String] {
        lock.withLock { attractionCalls }
    }

    func fail(_ fails: Bool) {
        lock.withLock { failing = fails }
    }

    private func check() throws {
        if lock.withLock({ failing }) {
            throw ProviderError(provider: "ticketmaster", kind: .unavailable)
        }
    }

    func near(_ point: GeoPoint, radiusKm: Int, page: Int, from _: Date) async throws -> ConcertResults {
        lock.withLock { nearCalls.append(NearCall(point: point, radiusKm: radiusKm, page: page)) }
        try check()
        return ConcertResults(concerts: nearConcerts, hasMore: false)
    }

    func search(_ keyword: String, near: (point: GeoPoint, radiusKm: Int)?, page: Int, from _: Date) async throws
        -> ConcertResults
    {
        lock.withLock {
            searchCalls.append(SearchCall(keyword: keyword, point: near?.point, radiusKm: near?.radiusKm, page: page))
        }
        try check()
        return ConcertResults(concerts: searchConcerts, hasMore: false)
    }

    func performing(_ attractionIDs: [String], from _: Date) async throws -> [Concert] {
        lock.withLock { performingCalls.append(attractionIDs) }
        try check()
        return attractionIDs.flatMap { byAttraction[$0] ?? [] }
    }

    func attractions(named name: String) async throws -> [ConcertAttraction] {
        lock.withLock { attractionCalls.append(name) }
        try check()
        return attractionsByName[name] ?? []
    }

    func artists(releaseGroup mbid: String) async throws -> [MusicArtist]? {
        artistsByAlbum[mbid]
    }
}

func sampleConcert(_ id: String, _ day: String, time: String? = nil) -> Concert {
    Concert(
        id: id, name: "Show \(id)", artists: ["Band \(id)"], startsAt: nil, localDate: day, localTime: time,
        venue: "Coliseu", city: "Lisboa", country: "Portugal", distanceKm: 1.234,
        url: URL(filePath: "/event/\(id)"), imageURL: nil
    )
}

@Suite("Concerts: points and the Ticketmaster adapter (MUS-003)")
struct ConcertAdapterTests {
    @Test("A point is rounded to two decimals and hashed to a ~5 km cell")
    func points() throws {
        let point = try #require(GeoPoint(latitude: 38.72345, longitude: -9.13987))
        #expect(point.latitude == 38.72 && point.longitude == -9.14)
        #expect(GeoPoint(latitude: 91, longitude: 0) == nil)
        #expect(GeoPoint(latitude: .nan, longitude: 0) == nil)
        // Wikipedia's worked example.
        #expect(GeoPoint(latitude: 42.6, longitude: -5.6)?.geohash() == "ezs42")
    }

    func adapter(_ stub: StubTransport, budget: Int = 100) -> TicketmasterConcerts {
        TicketmasterConcerts(
            client: ProviderClient(
                name: "ticketmaster", transport: stub, pacer: RequestPacer(requestsPerSecond: 1000, burst: 100)
            ),
            apiKey: "test-key", budget: CallBudget(limit: budget)
        )
    }

    static let events = #"""
    {"_embedded":{"events":[
      {"id":"E1","name":"Radiohead","url":"https://www.ticketmaster.pt/event/E1",
       "dates":{"start":{"localDate":"2026-11-02","localTime":"21:00:00","dateTime":"2026-11-02T21:00:00Z"},
                "status":{"code":"onsale"}},
       "distance":3.4,"units":"KILOMETERS",
       "images":[{"url":"https://s1.ticketm.net/fallback.jpg","ratio":"16_9","width":640,"fallback":true},
                 {"url":"https://s1.ticketm.net/small.jpg","ratio":"16_9","width":205,"fallback":false},
                 {"url":"https://s1.ticketm.net/wide.jpg","ratio":"16_9","width":640,"fallback":false}],
       "_embedded":{"venues":[{"name":"MEO Arena","city":{"name":"Lisboa"},"country":{"name":"Portugal"}}],
                    "attractions":[{"name":"Radiohead"},{"name":"Support"}]}},
      {"id":"E2","name":"Cancelled","url":"https://www.ticketmaster.pt/event/E2",
       "dates":{"start":{"localDate":"2026-11-03"},"status":{"code":"cancelled"}}},
      {"id":"E3","name":"Time to be announced","url":"https://www.ticketmaster.pt/event/E3","distance":10,
       "units":"MILES","dates":{"start":{"localDate":"2026-11-04","localTime":"20:00:00","timeTBA":true}}},
      {"id":"E4","name":"No date","url":"https://www.ticketmaster.pt/event/E4","dates":{"start":{}}}
    ]},"page":{"size":50,"totalElements":120,"totalPages":3,"number":0}}
    """#

    @Test("Near sends the cell, radius and paging; reads the date, venue, distance and image")
    func near() async throws {
        let stub = StubTransport { _ in OutboundResponse(status: 200, body: Data(Self.events.utf8)) }
        let point = try #require(GeoPoint(latitude: 42.6, longitude: -5.6))
        let from = Date(timeIntervalSince1970: 1_792_000_000)
        let results = try await adapter(stub).near(point, radiusKm: 50, page: 1, from: from)

        let request = try #require(stub.requests.first)
        let items = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(query["geoPoint"] == "ezs42")
        #expect(query["radius"] == "50" && query["unit"] == "km")
        #expect(query["classificationName"] == "music" && query["sort"] == "date,asc")
        #expect(query["page"] == "0" && query["size"] == "50")
        #expect(query["startDateTime"] == "2026-10-14T17:46:40Z")
        #expect(query["apikey"] == "test-key")
        #expect(query["latlong"] == nil, "the exact point is never sent, only its cell")

        #expect(results.concerts.map(\.id) == ["E1", "E3"], "cancelled and undated events are left out")
        #expect(results.hasMore)
        let first = try #require(results.concerts.first)
        #expect(first.localDate == "2026-11-02" && first.localTime == "21:00")
        #expect(first.startsAt == Date(timeIntervalSince1970: 1_793_653_200))
        #expect(first.venue == "MEO Arena" && first.city == "Lisboa" && first.country == "Portugal")
        #expect(first.artists == ["Radiohead", "Support"])
        #expect(first.distanceKm == 3.4)
        #expect(first.imageURL?.absoluteString == "https://s1.ticketm.net/wide.jpg")
        let tba = try #require(results.concerts.last)
        #expect(tba.localTime == nil && tba.startsAt == nil, "a time to be announced is not shown")
        #expect(abs((tba.distanceKm ?? 0) - 16.09) < 0.01, "miles become kilometres")
    }

    @Test("Performers keep their MusicBrainz ids, lowercased")
    func attractions() async throws {
        let stub = StubTransport { _ in OutboundResponse(status: 200, body: Data(#"""
        {"_embedded":{"attractions":[
          {"id":"K8vZ917G","name":"Radiohead",
           "externalLinks":{"musicbrainz":[{"id":"A74B1B7F-71A5-4011-9441-D0B5E4122711"}]}},
          {"id":"K8vZ999","name":"Radiohead Tribute"}
        ]}}
        """#.utf8)) }
        let found = try await adapter(stub).attractions(named: "Radiohead")
        #expect(found == [
            ConcertAttraction(
                id: "K8vZ917G",
                name: "Radiohead",
                musicbrainzIDs: ["a74b1b7f-71a5-4011-9441-d0b5e4122711"]
            ),
            ConcertAttraction(id: "K8vZ999", name: "Radiohead Tribute", musicbrainzIDs: []),
        ])
        let query = try URLComponents(url: #require(stub.requests.first).url, resolvingAgainstBaseURL: false)
        #expect(query?.queryItems?.contains(URLQueryItem(name: "keyword", value: "Radiohead")) == true)
    }

    @Test("A spent daily budget fails fast without calling Ticketmaster, and resets the next UTC day")
    func budget() async throws {
        let budget = CallBudget(limit: 1)
        let day = Date(timeIntervalSince1970: 1_792_000_000)
        #expect(await budget.take(now: day))
        #expect(await !budget.take(now: day))
        #expect(await budget.take(now: day.addingTimeInterval(24 * 60 * 60)))

        let stub = StubTransport { _ in OutboundResponse(status: 200, body: Data("{}".utf8)) }
        await #expect(throws: ProviderError(provider: "ticketmaster", kind: .unavailable)) {
            try await adapter(stub, budget: 0).attractions(named: "Radiohead")
        }
        #expect(stub.requests.isEmpty)
    }

    @Test("The city search is not logged with its query")
    func redaction() {
        #expect(RedactedLogRequestsMiddleware<AppRequestContext>.redacted("/v1/concerts/places", query: "q=Lisboa")
            == "/v1/concerts/places")
    }
}

@Suite("Concerts over the API (MUS-003)", .serialized)
struct ConcertAPITests {
    @Test("Off without a provider: the setting says so and lists come back unavailable")
    func off() async throws {
        try await LibraryHarness.run { env in
            let setting = try await env.send(.get, "/v1/me/concert-place").json()
            #expect(setting["available"] as? Bool == false)
            let near = try await env.send(.post, "/v1/concerts/near", json: ["radiusKm": 50]).json()
            #expect(near["unavailable"] as? Bool == true)
            let artists = try await env.send(.get, "/v1/concerts/artists").json()
            #expect(artists["unavailable"] as? Bool == true)
        }
    }

    @Test("Near uses the saved city, or a one-off rounded point; neither is a 409")
    func near() async throws {
        let fake = FakeConcerts()
        fake.nearConcerts = [sampleConcert("E1", "2026-11-02", time: "21:00")]
        try await LibraryHarness.run(concerts: fake) { env in
            let missing = try await env.send(.post, "/v1/concerts/near", json: ["radiusKm": 50])
            #expect(missing.status == .conflict)
            #expect(try missing.json()["code"] as? String == "no_place")

            let saved = try await env.send(.put, "/v1/me/concert-place", json: [
                "name": " Lisbon ", "country": "Portugal", "countryCode": "pt",
                "latitude": 38.71667, "longitude": -9.13333,
            ]).json()
            #expect(saved["available"] as? Bool == true)
            let place = try #require(saved["place"] as? [String: Any])
            #expect(place["name"] as? String == "Lisbon" && place["countryCode"] as? String == "PT")
            #expect(place["latitude"] as? Double == 38.72 && place["longitude"] as? Double == -9.13)

            let fromCity = try await env.send(.post, "/v1/concerts/near", json: ["radiusKm": 25]).json()
            #expect((fromCity["place"] as? [String: Any])?["name"] as? String == "Lisbon")
            let items = try #require(fromCity["items"] as? [[String: Any]])
            #expect(items.first?["id"] as? String == "E1")
            #expect(items.first?["distanceKm"] as? Double == 1.2)
            #expect(fake.asked.last?.point == GeoPoint(latitude: 38.72, longitude: -9.13))
            #expect(fake.asked.last?.radiusKm == 25)

            let oneOff = try await env.send(.post, "/v1/concerts/near", json: [
                "latitude": 41.14961, "longitude": -8.61099, "radiusKm": 100,
            ]).json()
            #expect(oneOff["place"] == nil, "a one-off position is not the saved city")
            #expect(fake.asked.last?.point == GeoPoint(latitude: 41.15, longitude: -8.61))

            let half = try await env.send(.post, "/v1/concerts/near", json: ["latitude": 41.1, "radiusKm": 50])
            #expect(half.status == .unprocessableContent)
            let farPage = try await env.send(.post, "/v1/concerts/near", json: ["radiusKm": 50, "page": 11])
            #expect(farPage.status == .unprocessableContent)

            #expect(try await env.send(.delete, "/v1/me/concert-place").status == .noContent)
            #expect(try await env.send(.get, "/v1/me/concert-place").json()["place"] == nil)
        }
    }

    @Test("The same area is asked once per six hours; a failed refresh serves the stale copy")
    func cache() async throws {
        let fake = FakeConcerts()
        fake.nearConcerts = [sampleConcert("E1", "2026-11-02")]
        try await LibraryHarness.run(concerts: fake) { env in
            var service = env.services.concerts
            let start = Date()
            service.now = { start }
            let lisbon = GeoPoint(latitude: 38.72, longitude: -9.14)
            // A point in the same ~5 km cell shares the answer.
            let nearby = GeoPoint(latitude: 38.73, longitude: -9.13)
            _ = try await service.near(userID: env.userID, point: lisbon, radiusKm: 50, page: 1)
            let second = try await service.near(userID: env.userID, point: nearby, radiusKm: 50, page: 1)
            #expect(fake.asked.count == 1)
            #expect(second.results.concerts.map(\.id) == ["E1"])

            fake.fail(true)
            service.now = { start.addingTimeInterval(7 * 60 * 60) }
            let stale = try await service.near(userID: env.userID, point: lisbon, radiusKm: 50, page: 1)
            #expect(fake.asked.count == 2)
            #expect(stale.results.concerts.map(\.id) == ["E1"] && !stale.unavailable)

            let elsewhere = try await service.near(
                userID: env.userID, point: GeoPoint(latitude: 41.15, longitude: -8.61), radiusKm: 50, page: 1
            )
            #expect(elsewhere.unavailable, "nothing cached for that area")
        }
    }

    @Test("Your artists on tour: artists come from MusicBrainz and match Ticketmaster by MusicBrainz id only")
    func artists() async throws {
        let fake = FakeConcerts()
        try await LibraryHarness.run(concerts: fake) { env in
            let album = AlbumLibraryTests().stubAlbum(env, "OK Computer")
            let radiohead = uniqueID("artist")
            let namesake = uniqueID("artist")
            fake.artistsByAlbum[album] = [
                MusicArtist(musicbrainzID: radiohead, name: "Radiohead \(radiohead)"),
                MusicArtist(musicbrainzID: namesake, name: "Namesake \(namesake)"),
                MusicArtist(musicbrainzID: ConcertRefresher.variousArtists, name: "Various Artists"),
            ]
            fake.attractionsByName["Radiohead \(radiohead)"] = [
                ConcertAttraction(id: "K-tribute", name: "Radiohead \(radiohead)", musicbrainzIDs: ["someone-else"]),
                ConcertAttraction(id: "K-real", name: "Radiohead", musicbrainzIDs: [radiohead]),
            ]
            // Same name, no MusicBrainz link: never a match.
            fake.attractionsByName["Namesake \(namesake)"] = [
                ConcertAttraction(id: "K-namesake", name: "Namesake \(namesake)", musicbrainzIDs: []),
            ]
            fake.byAttraction["K-real"] = [sampleConcert("E9", "2026-12-01"), sampleConcert("E8", "2026-11-20")]
            _ = try await env.send(.post, "/v1/library/items", json: [
                "mediaRef": ["type": "album", "ids": ["musicbrainz": album]],
            ])

            let before = try await env.send(.get, "/v1/concerts/artists").json()
            #expect(before["matched"] as? Int == 0 && (before["items"] as? [Any])?.isEmpty == true)

            var refresher = ConcertRefresher(stores: env.stores, artists: fake, listing: fake)
            refresher.albumLimit = 10000
            refresher.artistLimit = 10000
            _ = try await refresher.fillAlbumArtists()
            let pending = try await env.send(.get, "/v1/concerts/artists").json()
            // Various Artists is one shared row; an earlier run may have checked it already.
            #expect((pending["pending"] as? Int ?? 0) >= 2)

            _ = try await refresher.matchArtists()
            #expect(!fake.lookedUp.contains("Various Artists"))
            let after = try await env.send(.get, "/v1/concerts/artists").json()
            #expect(after["matched"] as? Int == 1 && after["pending"] as? Int == 0)
            let items = try #require(after["items"] as? [[String: Any]])
            #expect(items.compactMap { $0["id"] as? String } == ["E8", "E9"], "soonest first")
            #expect(fake.performers.last == ["K-real"])

            _ = try await refresher.matchArtists()
            #expect(fake.lookedUp.count { $0.contains(radiohead) } == 1, "a matched artist waits a month")
        }
    }
}
