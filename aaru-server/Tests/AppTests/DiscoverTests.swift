import AaruCore
import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
@testable import aaru

/// CAT-020 without a database: seasons, the cache, and the adapters' queries.
@Suite("Discover feed, pure (CAT-020)")
struct DiscoverTests {
    static let hour: TimeInterval = 3600

    func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: "\(text)T12:00:00Z") ?? .distantPast
    }

    func hit(_ title: String, _ type: AaruCore.MediaType = .show) -> CatalogHit {
        CatalogHit(
            type: type, title: title, originalTitle: nil, year: 2026, posterURL: nil, overview: nil, byline: nil,
            ids: ExternalIDs(tmdb: title), isAnime: false
        )
    }

    struct Rig {
        let tmdb = FakeCatalog()
        let anilist = FakeCatalog()
        let clock = TestClock(ISO8601DateFormatter().date(from: "2026-10-20T12:00:00Z") ?? .distantPast)

        var service: DiscoverService {
            let clock = clock
            return DiscoverService(tmdb: tmdb, anilist: anilist, cache: cache, now: { clock.now })
        }

        let cache = DiscoverCache()
    }

    @Test("CAT-020: December is next year's winter; fall rolls into winter of the next year")
    func seasons() {
        #expect(AnimeSeason.current(now: date("2026-12-15")) == AnimeSeason(name: .winter, year: 2027))
        #expect(AnimeSeason.current(now: date("2026-11-30")) == AnimeSeason(name: .fall, year: 2026))
        #expect(AnimeSeason.current(now: date("2027-02-28")) == AnimeSeason(name: .winter, year: 2027))
        #expect(AnimeSeason.current(now: date("2027-03-01")) == AnimeSeason(name: .spring, year: 2027))
        #expect(AnimeSeason.current(now: date("2027-08-31")) == AnimeSeason(name: .summer, year: 2027))
        #expect(AnimeSeason(name: .fall, year: 2026).next == AnimeSeason(name: .winter, year: 2027))
        #expect(AnimeSeason(name: .winter, year: 2027).next == AnimeSeason(name: .spring, year: 2027))
    }

    @Test("CAT-020: each section asks its provider the right question")
    func feeds() async throws {
        let rig = Rig()
        let sections = try await rig.service.sections(DiscoverSectionID.allCases)
        #expect(sections.map(\.id) == DiscoverSectionID.allCases)
        let today = LocalDay("2026-10-20") ?? LocalDay(year: 0, month: 1, day: 1)
        #expect(rig.tmdb.discoverFeeds.contains(.trending))
        #expect(rig.tmdb.discoverFeeds.contains(.onTheAir))
        #expect(rig.tmdb.discoverFeeds.contains(.upcomingMovies(from: today, until: today.adding(days: 60))))
        #expect(rig.tmdb.discoverFeeds.contains(.newShows(from: today.adding(days: -7), until: today.adding(days: 30))))
        #expect(rig.anilist.discoverFeeds.count == 2)
        #expect(rig.anilist.discoverFeeds.contains(.animeSeason(AnimeSeason(name: .fall, year: 2026))))
        #expect(rig.anilist.discoverFeeds.contains(.animeSeason(AnimeSeason(name: .winter, year: 2027))))
        #expect(sections.last?.animeSeason == AnimeSeason(name: .winter, year: 2027))
        #expect(sections.first?.animeSeason == nil)
    }

    @Test("CAT-020: a second request within 6 hours makes no provider call; after it, one")
    func cacheExpiry() async throws {
        let rig = Rig()
        rig.tmdb.stubDiscover("trending", [hit("Andor")])
        let first = try await rig.service.sections([.trending])
        rig.clock.advance(by: 6 * Self.hour - 60)
        let second = try await rig.service.sections([.trending])
        #expect(rig.tmdb.callCount("discover") == 1)
        #expect(first == second)
        rig.clock.advance(by: 120)
        rig.tmdb.stubDiscover("trending", [hit("Severance")])
        let third = try await rig.service.sections([.trending])
        #expect(rig.tmdb.callCount("discover") == 2)
        #expect(third.first?.items.map(\.title) == ["Severance"])
        #expect(third.first?.fetchedAt == rig.clock.now)
    }

    @Test("CAT-020: a failing provider serves the stale list for up to 24 hours, then the section is left out")
    func staleIfError() async throws {
        let rig = Rig()
        rig.tmdb.stubDiscover("trending", [hit("Andor")])
        rig.anilist.stubDiscover("animeSeason", [hit("Frieren")])
        _ = try await rig.service.sections([.trending])
        rig.tmdb.failDiscover("trending")
        rig.clock.advance(by: 7 * Self.hour)
        let stale = try await rig.service.sections([.trending, .animeSeason])
        #expect(stale.map(\.id) == [.trending, .animeSeason])
        #expect(stale.first?.items.map(\.title) == ["Andor"])

        rig.clock.advance(by: 18 * Self.hour)
        let partial = try await rig.service.sections([.trending, .animeSeason])
        #expect(partial.map(\.id) == [.animeSeason], "past 24 hours the failing section is left out")
        await #expect(throws: ProviderError.self) {
            _ = try await rig.service.sections([.trending])
        }
    }

    @Test("CAT-020: ten requests at once make one provider call")
    func singleFlight() async throws {
        let rig = Rig()
        rig.tmdb.stubDiscover("onTheAir", [hit("The Bear")])
        rig.tmdb.delay(.milliseconds(100))
        let service = rig.service
        let answers = try await withThrowingTaskGroup(of: [DiscoverSection].self) { group in
            for _ in 0 ..< 10 {
                group.addTask { try await service.sections([.onTheAir]) }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        #expect(answers.count == 10)
        #expect(Set(answers.compactMap { $0.first?.items.first?.title }) == ["The Bear"])
        #expect(rig.tmdb.callCount("discover") == 1)
    }

    // MARK: Adapters

    func client(_ transport: StubTransport) -> ProviderClient {
        ProviderClient(name: "stub", transport: transport, pacer: RequestPacer(requestsPerSecond: 1000, burst: 100))
    }

    @Test("CAT-020: TMDB lists use their own paths and queries; trending drops people and adult titles")
    func tmdbFeeds() async throws {
        let stub = StubTransport { request in
            let body = request.url.path.hasSuffix("/trending/all/week")
                ? #"""
                {"results":[{"id":1,"media_type":"movie","title":"Film","release_date":"2026-10-01"},
                  {"id":2,"media_type":"tv","name":"Show","first_air_date":"2026-09-01"},
                  {"id":3,"media_type":"person","name":"Someone"},
                  {"id":4,"media_type":"movie","title":"Adult","adult":true}]}
                """#
                : #"{"results":[{"id":9,"title":"X","name":"X"}]}"#
            return OutboundResponse(status: 200, body: Data(body.utf8))
        }
        let tmdb = TMDBCatalog(client: client(stub), apiKey: "k")
        let trending = try await tmdb.discover(.trending)
        #expect(trending.map(\.title) == ["Film", "Show"])
        #expect(trending.map(\.type) == [.movie, .show])
        #expect(trending.map(\.releaseDate) == ["2026-10-01", "2026-09-01"])

        let from = LocalDay(year: 2026, month: 10, day: 20)
        let movies = try await tmdb.discover(.upcomingMovies(from: from, until: from.adding(days: 60)))
        #expect(movies.first?.type == .movie)
        let shows = try await tmdb.discover(.newShows(from: from.adding(days: -7), until: from.adding(days: 30)))
        #expect(shows.first?.type == .show)
        _ = try await tmdb.discover(.onTheAir)
        let requests = stub.requests.map { ($0.url.path, $0.url.query ?? "") }
        let paths = ["/3/trending/all/week", "/3/discover/movie", "/3/discover/tv", "/3/tv/on_the_air"]
        #expect(requests.map(\.0) == paths)
        #expect(requests[1].1.contains("primary_release_date.gte=2026-10-20"))
        #expect(requests[1].1.contains("primary_release_date.lte=2026-12-19"))
        #expect(requests[1].1.contains("sort_by=popularity.desc") && requests[1].1.contains("include_adult=false"))
        #expect(requests[2].1.contains("first_air_date.gte=2026-10-13"))
        #expect(requests[2].1.contains("first_air_date.lte=2026-11-19"))
        #expect(!stub.requests.contains { $0.url.path.contains("external_ids") }, "no IMDb lookups")
        await #expect(throws: ProviderError.self) {
            _ = try await tmdb.discover(.animeSeason(AnimeSeason(name: .fall, year: 2026)))
        }
    }

    @Test("CAT-020: AniList asks for one season's anime by popularity, never adult")
    func aniListSeason() async throws {
        let stub = StubTransport { _ in
            OutboundResponse(status: 200, body: Data(#"""
            {"data":{"Page":{"media":[{"id":7,"format":"TV","title":{"english":"Frieren"},
              "startDate":{"year":2026,"month":10,"day":3}}]}}}
            """#.utf8))
        }
        let hits = try await AniListCatalog(client: client(stub))
            .discover(.animeSeason(AnimeSeason(name: .winter, year: 2027)))
        #expect(hits.map(\.title) == ["Frieren"] && hits.first?.isAnime == true)
        let body = try #require(stub.requests.first?.body.flatMap { String(bytes: $0, encoding: .utf8) })
        #expect(body.contains("isAdult: false") && body.contains("POPULARITY_DESC"))
        #expect(body.contains(#""season":"WINTER""#) && body.contains(#""year":2027"#))
    }
}

/// CAT-020 over HTTP.
@Suite("Discover route (CAT-020)", .serialized)
struct DiscoverRouteTests {
    func get(_ env: LibraryHarness, _ uri: String, token: String? = nil) async throws -> LibraryHarness.Reply {
        try await env.send(.get, uri, token: token)
    }

    @Test("CAT-020: every section by default, one on request, the same payload for every user")
    func sections() async throws {
        try await LibraryHarness.run { env in
            env.fake.stubDiscover("newShows", [CatalogHit(
                type: .show, title: "MobLand", originalTitle: nil, year: 2025, posterURL: nil, overview: nil,
                byline: nil, ids: ExternalIDs(tmdb: "247718"), isAnime: false, releaseDate: "2025-03-30"
            )])
            let all = try await get(env, "/v1/discover")
            #expect(all.status == .ok)
            let ids = try (all.json()["sections"] as? [[String: Any]])?.compactMap { $0["id"] as? String }
            #expect(ids == DiscoverSectionID.allCases.map(\.rawValue))

            let one = try await get(env, "/v1/discover?section=new_shows")
            let sections = try #require(try one.json()["sections"] as? [[String: Any]])
            #expect(sections.count == 1 && sections.first?["id"] as? String == "new_shows")
            let item = try #require((sections.first?["items"] as? [[String: Any]])?.first)
            #expect(item["releaseDate"] as? String == "2025-03-30")
            #expect(item["status"] == nil, "catalog data, no library fields")

            // Another user gets the cached bytes: nothing in it is about who asked.
            let (otherID, other) = try await signedInUser(env.stores)
            let theirs = try await get(env, "/v1/discover?section=new_shows", token: other)
            #expect(theirs.body == one.body)
            #expect(!one.text.contains(env.userID.description) && !theirs.text.contains(otherID.description))
            #expect(env.fake.callCount("discover") == DiscoverSectionID.allCases.count, "served from the cache")

            #expect(try await get(env, "/v1/discover?section=for_you").status == .badRequest)
        }
    }

    @Test("CAT-020: sign-in required; a failing section is left out; all failing is 502")
    func failures() async throws {
        try await LibraryHarness.run { env in
            try await env.client.execute(uri: "/v1/discover", method: .get) { response in
                #expect(response.status == .unauthorized)
            }
            env.fake.failDiscover("trending")
            let partial = try await get(env, "/v1/discover")
            #expect(partial.status == .ok)
            let ids = try (partial.json()["sections"] as? [[String: Any]])?.compactMap { $0["id"] as? String }
            #expect(ids?.contains("trending") == false && ids?.count == DiscoverSectionID.allCases.count - 1)

            let failed = try await get(env, "/v1/discover?section=trending")
            #expect(failed.status == .badGateway)
            #expect(failed.text.contains("provider_unavailable"))
        }
    }
}
