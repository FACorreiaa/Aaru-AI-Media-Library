import AaruCore
import Foundation
import Testing
@testable import aaru

/// CAT-011 against canned TVmaze JSON. No network.
@Suite("TVmaze air times (CAT-011)")
struct TVmazeAirTimesTests {
    func refiner(_ stub: StubTransport) -> TVmazeAirTimes {
        TVmazeAirTimes(client: ProviderClient(
            name: "tvmaze", transport: stub, pacer: RequestPacer(requestsPerSecond: 1000, burst: 100)
        ))
    }

    /// TMDB's view: date-only episodes at midnight UTC.
    func tmdbEpisodes(_ dates: [String]) -> CatalogEpisodes {
        CatalogEpisodes(
            status: .returning,
            episodes: dates.enumerated().map { index, date in
                CatalogEpisode(
                    season: 1, episode: index + 1, name: nil, airsAt: Date.catalogDay(date),
                    runtimeMinutes: 50, tmdbEpisodeID: nil
                )
            },
            network: "TMDB Network"
        )
    }

    @Test("Exact airstamps replace TMDB dates; the TVmaze network wins; looked up by TVDB id")
    func refines() async throws {
        let stub = StubTransport { request in
            switch request.url.path {
            case "/lookup/shows":
                #expect(request.url.query == "thetvdb=81189")
                return OutboundResponse(status: 200, body: Data(#"{"id":169,"network":{"name":"AMC"}}"#.utf8))
            case "/shows/169/episodes":
                return OutboundResponse(status: 200, body: Data(#"""
                [{"season":1,"number":1,"airstamp":"2026-10-20T01:00:00+00:00"},
                 {"season":1,"number":2,"airstamp":"2026-10-27T01:00:00+00:00"},
                 {"season":0,"number":null,"airstamp":"2026-10-01T01:00:00+00:00"}]
                """#.utf8))
            default:
                return OutboundResponse(status: 404, body: Data())
            }
        }
        let refined = try await refiner(stub).refine(
            tmdbEpisodes(["2026-10-20", "2026-10-27", "2026-11-03"]),
            ids: ExternalIDs(imdb: "tt0903747", tvdb: "81189")
        )
        let exact = ISO8601DateFormatter().date(from: "2026-10-20T01:00:00Z")
        #expect(refined.episodes[0].airsAt == exact)
        #expect(refined.episodes.map(\.airTimeKnown) == [true, true, false])
        #expect(refined.episodes[2].airsAt == Date.catalogDay("2026-11-03"), "no TVmaze row: TMDB date kept")
        #expect(refined.network == "AMC")
    }

    @Test("A time whose date disagrees with TMDB is ignored (different season numbering)")
    func ignoresMismatchedNumbering() async throws {
        let stub = StubTransport { request in
            request.url.path == "/lookup/shows"
                ? OutboundResponse(status: 200, body: Data(#"{"id":7,"webChannel":{"name":"Netflix"}}"#.utf8))
                : OutboundResponse(
                    status: 200,
                    body: Data(#"[{"season":1,"number":1,"airstamp":"2020-01-01T08:00:00+00:00"}]"#.utf8)
                )
        }
        let refined = try await refiner(stub).refine(tmdbEpisodes(["2026-10-20"]), ids: ExternalIDs(tvdb: "1"))
        #expect(refined.episodes[0].airTimeKnown == false)
        #expect(refined.episodes[0].airsAt == Date.catalogDay("2026-10-20"))
        #expect(refined.network == "Netflix", "a streaming-only show's web channel is its network")
    }

    @Test("A show TVmaze does not know comes back unchanged, after trying TVDB then IMDb")
    func unknownShow() async throws {
        let stub = StubTransport { _ in OutboundResponse(status: 404, body: Data()) }
        let original = tmdbEpisodes(["2026-10-20"])
        let refined = try await refiner(stub).refine(original, ids: ExternalIDs(imdb: "tt1", tvdb: "2"))
        #expect(refined == original)
        #expect(stub.requests.compactMap(\.url.query) == ["thetvdb=2", "imdb=tt1"])
    }
}
