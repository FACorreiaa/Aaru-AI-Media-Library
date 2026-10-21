import AaruCore
import Foundation
import Testing
@testable import aaru

/// The Seasons view (DISC-002): season keys, provider queries, the page cache and the route.
@Suite("Discover seasons (DISC-002)")
struct DiscoverSeasonTests {
    /// 2026-10-20T12:00:00Z, in Fall 2026.
    static let now = DiscoverTests.now

    func client(_ transport: StubTransport, _ name: String) -> ProviderClient {
        ProviderClient(name: name, transport: transport, pacer: RequestPacer(requestsPerSecond: 1000, burst: 100))
    }

    func stub(_ body: String) -> StubTransport {
        StubTransport { _ in OutboundResponse(status: 200, body: Data(body.utf8)) }
    }

    // MARK: Season keys

    @Test("Next and previous cross the year end")
    func shifting() {
        let fall = SeasonKey(season: .fall, year: 2026)
        #expect(fall.next == SeasonKey(season: .winter, year: 2027))
        #expect(fall.next.previous == fall)
        #expect(SeasonKey(season: .spring, year: 2026).previous == SeasonKey(season: .winter, year: 2026))
        #expect(fall.title == "Fall 2026")
    }

    @Test(
        "A season's days are its quarter",
        arguments: [
            (SeasonOfYear.winter, "2026-01-01", "2026-03-31"), (.spring, "2026-04-01", "2026-06-30"),
            (.summer, "2026-07-01", "2026-09-30"), (.fall, "2026-10-01", "2026-12-31"),
        ]
    )
    func days(_ season: SeasonOfYear, _ first: String, _ last: String) {
        let days = SeasonKey(season: season, year: 2026).days
        #expect(days.first == first)
        #expect(days.last == last)
    }

    // MARK: Providers

    @Test("AniList asks for the season with variables, popular first, one page at a time")
    func aniList() async throws {
        let transport = stub(#"""
        {"data":{"Page":{"pageInfo":{"hasNextPage":true,"total":84},"media":[
          {"id":195516,"idMal":1,"format":"TV","status":"RELEASING","title":{"english":"Apothecary Diaries"},
           "startDate":{"year":2026},"coverImage":{"large":"https://img/a.jpg"}}]}}}
        """#)
        let page = try await AniListCatalog(client: client(transport, "anilist"))
            .season(SeasonKey(season: .spring, year: 2025), kind: .anime, page: 2, now: Self.now)
        #expect(page.hits.map(\.ids.anilist) == ["195516"])
        #expect(page.hasMore)
        #expect(page.total == 84)
        let data = try #require(transport.requests.first?.body)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let variables = try #require(body["variables"] as? [String: Any])
        #expect(variables["season"] as? String == "SPRING")
        #expect(variables["year"] as? Int == 2025)
        #expect(variables["page"] as? Int == 2)
        let query = try #require(body["query"] as? String)
        #expect(query.contains("sort: POPULARITY_DESC"))
        #expect(query.contains("isAdult: false"))
    }

    @Test(
        "TMDB filters each kind by the season's dates",
        arguments: [
            (SeasonKind.showsNew, "/discover/tv", ["first_air_date.gte=2026-10-01", "first_air_date.lte=2026-12-31"]),
            (.showsReturning, "/discover/tv", [
                "air_date.gte=2026-10-01", "air_date.lte=2026-12-31", "first_air_date.lte=2026-09-30",
            ]),
            (
                .movies,
                "/discover/movie",
                ["primary_release_date.gte=2026-10-01", "primary_release_date.lte=2026-12-31"]
            ),
        ]
    )
    func tmdb(_ kind: SeasonKind, _ path: String, _ expected: [String]) async throws {
        let transport = stub(#"{"results":[],"total_pages":3,"total_results":55}"#)
        let page = try await TMDBCatalog(client: client(transport, "tmdb"), apiKey: "k")
            .season(SeasonKey(season: .fall, year: 2026), kind: kind, page: 1, now: Self.now)
        let request = try #require(transport.requests.first)
        #expect(request.url.path.hasSuffix(path))
        let query = try #require(request.url.query)
        for part in expected {
            #expect(query.contains(part))
        }
        #expect(query.contains("sort_by=popularity.desc"))
        // The current season has no votes yet: no floor.
        #expect(!query.contains("vote_count"))
        #expect(page.hasMore)
        #expect(page.total == 55)
    }

    @Test("An ended season keeps a vote floor; the last page has no more")
    func tmdbPastSeason() async throws {
        let transport = stub(#"""
        {"results":[
          {"id":1,"name":"Drama","poster_path":"/d.jpg","genre_ids":[18],"original_language":"en"},
          {"id":2,"name":"Anime","poster_path":"/a.jpg","genre_ids":[16],"original_language":"ja"}],
         "total_pages":2,"total_results":30}
        """#)
        let page = try await TMDBCatalog(client: client(transport, "tmdb"), apiKey: "k")
            .season(SeasonKey(season: .summer, year: 2025), kind: .showsNew, page: 2, now: Self.now)
        #expect(transport.requests.first?.url.query?.contains("vote_count.gte=10") == true)
        // Anime shows come from AniList's tab.
        #expect(page.hits.map(\.title) == ["Drama"])
        #expect(!page.hasMore)
    }

    // MARK: Cache

    @Test("Pages are cached by key and the cache stays bounded")
    func cache() async {
        let cache = SeasonCache()
        let calls = Calls()
        let fetch: @Sendable () async throws -> SeasonPage = {
            await calls.bump()
            return SeasonPage(hits: [], hasMore: false)
        }
        _ = await cache.page("a", ttl: 60, now: Self.now, fetch: fetch)
        _ = await cache.page("a", ttl: 60, now: Self.now.addingTimeInterval(30), fetch: fetch)
        #expect(await calls.value == 1)
        _ = await cache.page("a", ttl: 60, now: Self.now.addingTimeInterval(61), fetch: fetch)
        #expect(await calls.value == 2)
        for index in 0 ... SeasonCache.capacity {
            _ = await cache.page("k\(index)", ttl: 60, now: Self.now.addingTimeInterval(Double(index)), fetch: fetch)
        }
        #expect(await cache.count == SeasonCache.capacity)
    }

    @Test("A provider that fails with nothing cached reads as unavailable, not empty")
    func unavailable() async throws {
        try await withMigratedStores { stores in
            let service = DiscoverService(stores: stores, providers: [Broken()])
            let result = try await service.season(
                SeasonKey(season: .fall, year: 2026), kind: .anime, page: 1, userID: UserID()
            )
            #expect(result.unavailable)
            #expect(result.items.isEmpty)
        }
    }

    // MARK: Route

    @Test("GET /v1/discover/season marks owned titles and drops poster-less hits")
    func route() async throws {
        try await LibraryHarness.run { env in
            let owned = env.stubMovie("Owned")
            let added = try await env.send(.post, "/v1/library/items", json: [
                "mediaRef": ["type": "movie", "ids": ["tmdb": owned]],
            ])
            let itemID = try #require(try added.json()["id"] as? String)
            env.fake.stubSeason(.movies, [
                DiscoverTests.hit("Owned", tmdb: owned), DiscoverTests.hit("New", tmdb: "x-1"),
                DiscoverTests.hit("No poster", tmdb: "x-2", poster: false),
            ])
            let reply = try await env.send(.get, "/v1/discover/season?kind=movies&season=fall&year=2026")
            #expect(reply.status == .ok)
            let body = try reply.json()
            #expect(body["title"] as? String == "Fall 2026")
            #expect(body["from"] as? String == "2026-10-01")
            #expect(body["until"] as? String == "2026-12-31")
            #expect(body["unavailable"] as? Bool == false)
            let items = try #require(body["items"] as? [[String: Any]])
            #expect(items.map { $0["title"] as? String } == ["Owned", "New"])
            #expect(items.map { $0["libraryItemId"] as? String } == [itemID, nil])
        }
    }

    @Test(
        "Years and pages out of range are 422",
        arguments: ["year=1969", "year=2028", "year=2026&page=0", "year=2026&page=21"]
    )
    func outOfRange(_ query: String) async throws {
        try await LibraryHarness.run { env in
            let reply = try await env.send(.get, "/v1/discover/season?kind=anime&season=fall&\(query)")
            #expect(reply.status == .unprocessableContent)
            #expect(try reply.json()["code"] as? String == "validation_failed")
        }
    }

    @Test("Next year's seasons are open; seasons need a session")
    func nextYearAndSession() async throws {
        try await LibraryHarness.run { env in
            let next = try await env.send(.get, "/v1/discover/season?kind=anime&season=winter&year=2027")
            #expect(next.status == .ok)
            let anonymous = try await env.send(
                .get, "/v1/discover/season?kind=anime&season=fall&year=2026", token: "nope"
            )
            #expect(anonymous.status == .unauthorized)
        }
    }
}

private actor Calls {
    private(set) var value = 0

    func bump() {
        value += 1
    }
}

private struct Broken: SeasonBrowsing {
    var seasonKinds: Set<SeasonKind> {
        [.anime]
    }

    func season(_: SeasonKey, kind _: SeasonKind, page _: Int, now _: Date) async throws -> SeasonPage {
        throw ProviderError(provider: "anilist", kind: .unauthorized)
    }
}
