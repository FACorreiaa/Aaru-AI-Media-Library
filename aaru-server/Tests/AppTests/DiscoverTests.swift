import AaruCore
import Foundation
import Testing
@testable import aaru

/// Discover rows (DISC-001): provider lists, the shared cache, and the library mark.
@Suite("Discover (DISC-001)")
struct DiscoverTests {
    /// 2026-10-20T12:00:00Z.
    static let now = Date(timeIntervalSince1970: 1_792_497_600)

    func transport(_ routes: [String: String]) -> StubTransport {
        StubTransport { request in
            guard let body = routes.first(where: { request.url.path.hasSuffix($0.key) })?.value else {
                return OutboundResponse(status: 404, body: Data())
            }
            return OutboundResponse(status: 200, body: Data(body.utf8))
        }
    }

    func client(_ transport: StubTransport, _ name: String) -> ProviderClient {
        ProviderClient(name: name, transport: transport, pacer: RequestPacer(requestsPerSecond: 1000, burst: 100))
    }

    static func hit(_ title: String, type: MediaType = .movie, tmdb: String, poster: Bool = true) -> CatalogHit {
        CatalogHit(
            type: type, title: title, originalTitle: nil, year: 2026,
            posterURL: poster ? URL(string: "https://img/\(tmdb).jpg") : nil, overview: nil, byline: nil,
            ids: ExternalIDs(tmdb: tmdb), isAnime: false
        )
    }

    // MARK: Providers

    @Test("TMDB TV rows leave out anime and talk shows; anime comes from AniList")
    func tmdbTrendingTV() async throws {
        let stub = transport(["/trending/tv/week": #"""
        {"results":[
          {"id":1,"name":"Drama","poster_path":"/d.jpg","genre_ids":[18],"original_language":"en"},
          {"id":2,"name":"Anime","poster_path":"/a.jpg","genre_ids":[16],"original_language":"ja"},
          {"id":3,"name":"Talk","poster_path":"/t.jpg","genre_ids":[10767],"original_language":"en"}]}
        """#])
        let hits = try await TMDBCatalog(client: client(stub, "tmdb"), apiKey: "k").list(.tvTrending, now: Self.now)
        #expect(hits.map(\.title) == ["Drama"])
        #expect(hits.first?.type == .show)
        #expect(stub.requests.first?.url.query?.contains("include_adult=false") == true)
    }

    @Test("New shows premiered in the last 90 days, by popularity")
    func tmdbNewShows() async throws {
        let stub = transport(["/discover/tv": #"{"results":[]}"#])
        _ = try await TMDBCatalog(client: client(stub, "tmdb"), apiKey: "k").list(.tvNew, now: Self.now)
        let query = try #require(stub.requests.first?.url.query)
        #expect(query.contains("first_air_date.gte=2026-07-22"))
        #expect(query.contains("first_air_date.lte=2026-10-20"))
        #expect(query.contains("sort_by=popularity.desc"))
    }

    @Test("TMDB movie rows keep movies as movies")
    func tmdbMovies() async throws {
        let stub = transport(["/movie/now_playing": #"""
        {"results":[{"id":9,"title":"Film","release_date":"2026-10-01","poster_path":"/f.jpg","genre_ids":[16],
          "original_language":"ja"}]}
        """#])
        let hits = try await TMDBCatalog(client: client(stub, "tmdb"), apiKey: "k")
            .list(.moviesInTheaters, now: Self.now)
        #expect(hits.map(\.ids.tmdb) == ["9"])
        #expect(hits.first?.type == .movie)
    }

    @Test("AniList's season row asks for this season, popular first, no adult titles")
    func aniListSeason() async throws {
        let stub = transport(["": #"""
        {"data":{"Page":{"media":[
          {"id":195516,"idMal":1,"format":"TV","status":"RELEASING","title":{"english":"Apothecary Diaries"},
           "startDate":{"year":2026},"coverImage":{"large":"https://img/a.jpg"}}]}}}
        """#])
        let hits = try await AniListCatalog(client: client(stub, "anilist")).list(.animeSeason, now: Self.now)
        #expect(hits.map(\.ids.anilist) == ["195516"])
        #expect(hits.allSatisfy { $0.isAnime })
        let body = try #require(stub.requests.first?.body.flatMap { String(bytes: $0, encoding: .utf8) })
        #expect(body.contains("season: FALL, seasonYear: 2026, sort: POPULARITY_DESC"))
        #expect(body.contains("isAdult: false"))
    }

    @Test("Open Library's weekly trending works become book hits")
    func openLibraryTrending() async throws {
        let stub = transport(["/trending/weekly.json": #"""
        {"works":[{"key":"/works/OL17930368W","title":"Atomic Habits","author_name":["James Clear"],
          "first_publish_year":2016,"cover_i":12539702}]}
        """#])
        let hits = try await OpenLibraryCatalog(client: client(stub, "openlibrary"), userAgent: "test")
            .list(.booksTrending, now: Self.now)
        #expect(hits.map(\.ids.openLibrary) == ["OL17930368W"])
        #expect(hits.first?.byline == "James Clear")
        #expect(hits.first?.posterURL?.absoluteString == "https://covers.openlibrary.org/b/id/12539702-L.jpg")
    }

    @Test(
        "The anime season follows the calendar quarter in UTC",
        arguments: [
            ("2026-01-01T00:00:00Z", AnimeSeason.winter), ("2026-03-31T23:59:59Z", .winter),
            ("2026-04-01T00:00:00Z", .spring), ("2026-07-01T00:00:00Z", .summer),
            ("2026-09-30T23:59:59Z", .summer), ("2026-10-01T00:00:00Z", .fall), ("2026-12-31T23:59:59Z", .fall),
        ]
    )
    func season(_ instant: String, _ expected: AnimeSeason) throws {
        let date = try #require(ISO8601DateFormatter().date(from: instant))
        #expect(AnimeSeason.current(date)?.season == expected)
        #expect(AnimeSeason.current(date)?.year == 2026)
    }

    @Test("The season row is titled for the season")
    func seasonTitle() {
        #expect(DiscoverList.animeSeason.title(now: Self.now) == "Fall 2026 anime")
    }

    // MARK: Cache

    @Test("A cached list is served until the TTL, then fetched again")
    func cacheTTL() async {
        let cache = DiscoverCache()
        let counter = Counter()
        let fetch: @Sendable () async throws -> DiscoverFetch = {
            await counter.bump()
            return DiscoverFetch(hits: [Self.hit("A", tmdb: "1")])
        }
        _ = await cache.hits(.moviesTrending, now: Self.now, fetch: fetch)
        _ = await cache.hits(.moviesTrending, now: Self.now.addingTimeInterval(60), fetch: fetch)
        #expect(await counter.value == 1)
        _ = await cache.hits(.moviesTrending, now: Self.now.addingTimeInterval(DiscoverService.ttl), fetch: fetch)
        #expect(await counter.value == 2)
    }

    @Test("Concurrent callers share one fetch")
    func cacheCoalesces() async {
        let cache = DiscoverCache()
        let counter = Counter()
        let fetch: @Sendable () async throws -> DiscoverFetch = {
            await counter.bump()
            try await Task.sleep(for: .milliseconds(30))
            return DiscoverFetch(hits: [Self.hit("A", tmdb: "1")])
        }
        async let first = cache.hits(.tvTrending, now: Self.now, fetch: fetch)
        async let second = cache.hits(.tvTrending, now: Self.now, fetch: fetch)
        let results = await [first, second]
        #expect(results.allSatisfy { $0?.hits.count == 1 })
        #expect(await counter.value == 1)
    }

    @Test("A failed refresh serves the stale copy and backs off")
    func cacheFailure() async {
        let cache = DiscoverCache()
        let counter = Counter()
        _ = await cache.hits(.booksTrending, now: Self.now) {
            DiscoverFetch(hits: [Self.hit("Old", type: .book, tmdb: "1")])
        }
        let failing: @Sendable () async throws -> DiscoverFetch = {
            await counter.bump()
            throw ProviderError(provider: "openlibrary", kind: .unavailable)
        }
        let stale = Self.now.addingTimeInterval(DiscoverService.ttl)
        let served = await cache.hits(.booksTrending, now: stale, fetch: failing)
        #expect(served?.hits.map(\.title) == ["Old"])
        let backedOff = await cache.hits(.booksTrending, now: stale.addingTimeInterval(60), fetch: failing)
        #expect(backedOff != nil)
        #expect(await counter.value == 1)
        _ = await cache.hits(.booksTrending, now: stale.addingTimeInterval(DiscoverService.retryAfter), fetch: failing)
        #expect(await counter.value == 2)
    }

    // MARK: Service and route

    @Test("A provider that fails drops its own row only")
    func failingProvider() async throws {
        try await withMigratedStores { stores in
            let service = DiscoverService(stores: stores, providers: [HalfBroken()])
            let rows = try await service.rows(userID: UserID())
            #expect(rows.map(\.list) == [.moviesTrending])
        }
    }

    @Test("While AniList is down, TMDB's Japanese animation fills the anime rows, briefly cached, with a note")
    func aniListOutageFallback() async throws {
        try await withMigratedStores { stores in
            let fallback = AnimeStandIn()
            let service = DiscoverService(stores: stores, providers: [DownAniList()], animeFallback: fallback)
            let rows = try await service.rows(userID: UserID())
            #expect(Set(rows.map(\.list)) == [.animeSeason, .animeTrending])
            #expect(rows.allSatisfy { $0.note == DiscoverService.animeFallbackNote })
            #expect(rows.allSatisfy { $0.items.allSatisfy(\.hit.isAnime) })
        }
        let cache = DiscoverCache()
        let counter = Counter()
        let fetch: @Sendable () async throws -> DiscoverFetch = {
            await counter.bump()
            return DiscoverFetch(hits: [Self.hit("A", tmdb: "1")], ttl: DiscoverService.fallbackTTL)
        }
        _ = await cache.hits(.animeSeason, now: Self.now, fetch: fetch)
        _ = await cache.hits(.animeSeason, now: Self.now.addingTimeInterval(60), fetch: fetch)
        _ = await cache.hits(.animeSeason, now: Self.now.addingTimeInterval(DiscoverService.fallbackTTL), fetch: fetch)
        #expect(await counter.value == 2, "a stand-in row is asked for again after 30 minutes, not 6 hours")
    }

    @Test("TMDB's stand-in anime query: Japanese animation in this season's window, or airing this fortnight")
    func tmdbAnimeQuery() throws {
        let season = try TMDBCatalog.animeQuery(.animeSeason, now: Self.now)
        #expect(season["with_genres"] == "16" && season["with_origin_country"] == "JP")
        #expect(season["first_air_date.gte"] == "2026-10-01" && season["first_air_date.lte"] == "2026-12-31")
        let trending = try TMDBCatalog.animeQuery(.animeTrending, now: Self.now)
        #expect(trending["air_date.gte"] == "2026-10-13" && trending["air_date.lte"] == "2026-10-27")
    }

    @Test("GET /v1/discover marks titles in the caller's library and drops poster-less hits")
    func route() async throws {
        try await LibraryHarness.run { env in
            let owned = env.stubMovie("Owned")
            let added = try await env.send(.post, "/v1/library/items", json: [
                "mediaRef": ["type": "movie", "ids": ["tmdb": owned]],
            ])
            let itemID = try #require(try added.json()["id"] as? String)
            env.fake.stubDiscover(.moviesTrending, [Self.hit("Owned", tmdb: owned), Self.hit("New", tmdb: "x-1")])
            // Same TMDB number, other type: never the owned movie.
            env.fake.stubDiscover(.tvTrending, [Self.hit("Show", type: .show, tmdb: owned)])
            env.fake.stubDiscover(.booksTrending, [Self.hit("No cover", type: .book, tmdb: "b", poster: false)])

            let reply = try await env.send(.get, "/v1/discover")
            #expect(reply.status == .ok)
            let rows = try #require(try reply.json()["rows"] as? [[String: Any]])
            #expect(rows.map { $0["id"] as? String } == ["tv_trending", "movies_trending"])
            let movies = try #require(rows.last?["items"] as? [[String: Any]])
            #expect(movies.map { $0["libraryItemId"] as? String } == [itemID, nil])
            let shows = try #require(rows.first?["items"] as? [[String: Any]])
            #expect(shows.first?["libraryItemId"] == nil)
        }
    }

    @Test("Discover needs a session")
    func needsSession() async throws {
        try await LibraryHarness.run { env in
            let reply = try await env.send(.get, "/v1/discover", token: "nope")
            #expect(reply.status == .unauthorized)
        }
    }
}

extension UntouchedStore {
    func itemIDs(userID _: UserID, matching _: Set<CatalogKey>) async throws -> [CatalogKey: LibraryItemID] {
        throw Touched()
    }
}

private actor Counter {
    private(set) var value = 0

    func bump() {
        value += 1
    }
}

/// Serves two lists; one always fails.
private struct HalfBroken: DiscoverListing {
    var discoverLists: Set<DiscoverList> {
        [.tvTrending, .moviesTrending]
    }

    func list(_ list: DiscoverList, now _: Date) async throws -> [CatalogHit] {
        guard list == .moviesTrending else { throw ProviderError(provider: "tmdb", kind: .unavailable) }
        return [DiscoverTests.hit("Film", tmdb: "1")]
    }
}

/// AniList answering "disabled".
private struct DownAniList: DiscoverListing {
    var discoverLists: Set<DiscoverList> {
        [.animeSeason, .animeTrending]
    }

    func list(_: DiscoverList, now _: Date) async throws -> [CatalogHit] {
        throw ProviderError(provider: "anilist", kind: .unavailable)
    }
}

private struct AnimeStandIn: DiscoverListing {
    var discoverLists: Set<DiscoverList> {
        []
    }

    func list(_ list: DiscoverList, now _: Date) async throws -> [CatalogHit] {
        var hit = DiscoverTests.hit("Frieren \(list.rawValue)", type: .show, tmdb: "209867")
        hit.isAnime = true
        return [hit]
    }
}
