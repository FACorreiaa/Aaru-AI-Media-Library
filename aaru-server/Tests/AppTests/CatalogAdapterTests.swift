import AaruCore
import Foundation
import Testing
@testable import aaru

/// Adapters against canned provider JSON. No network, no real keys.
@Suite("Catalog adapters (CAT-002, CAT-003, CAT-007)")
struct CatalogAdapterTests {
    /// Routes by URL path to canned JSON bodies; anything else is a 404.
    func transport(_ routes: [String: String]) -> StubTransport {
        StubTransport { request in
            let path = request.url.path
            guard let body = routes.first(where: { path.hasSuffix($0.key) })?.value else {
                return OutboundResponse(status: 404, body: Data())
            }
            return OutboundResponse(status: 200, body: Data(body.utf8))
        }
    }

    func client(_ transport: StubTransport, _ name: String) -> ProviderClient {
        ProviderClient(name: name, transport: transport, pacer: RequestPacer(requestsPerSecond: 1000, burst: 100))
    }

    @Test("TMDB search returns hits carrying tmdb and imdb ids, with posters as URLs")
    func tmdbSearch() async throws {
        let stub = transport([
            "/search/movie": #"""
            {"results":[{"id":603,"title":"The Matrix","original_title":"The Matrix","release_date":"1999-03-30",
             "poster_path":"/p.jpg","overview":"Neo.","genre_ids":[28],"original_language":"en"}]}
            """#,
            "/movie/603/external_ids": #"{"imdb_id":"tt0133093"}"#,
        ])
        let hits = try await TMDBCatalog(client: client(stub, "tmdb"), apiKey: "v3key").search(
            query: "matrix",
            type: .movie
        )
        #expect(hits == [CatalogHit(
            type: .movie, title: "The Matrix", originalTitle: nil, year: 1999,
            posterURL: URL(string: "https://image.tmdb.org/t/p/w500/p.jpg"), overview: "Neo.", byline: nil,
            ids: ExternalIDs(tmdb: "603", imdb: "tt0133093"), isAnime: false
        )])
        let query = try #require(stub.requests.first?.url.query)
        #expect(query.contains("api_key=v3key"))
    }

    @Test("A v4 read token goes in the Authorization header, not the URL")
    func tmdbBearer() async throws {
        let stub = transport(["/search/tv": #"{"results":[]}"#])
        _ = try await TMDBCatalog(client: client(stub, "tmdb"), apiKey: "eyJ.header.sig").search(
            query: "x",
            type: .show
        )
        let request = try #require(stub.requests.first)
        #expect(request.url.query?.contains("api_key") == false)
        #expect(request.headers.contains { $0 == ("Authorization", "Bearer eyJ.header.sig") })
    }

    @Test("TMDB show episodes span every season, with status")
    func tmdbEpisodes() async throws {
        let stub = transport([
            "/tv/1399": #"""
            {"id":1399,"name":"GoT","status":"Ended","episode_run_time":[60],
             "seasons":[{"season_number":1},{"season_number":2}]}
            """#,
            "/tv/1399/season/1": #"""
            {"episodes":[{"id":1,"season_number":1,"episode_number":1,"name":"Winter Is Coming",
              "air_date":"2011-04-17","runtime":62}]}
            """#,
            "/tv/1399/season/2": #"""
            {"episodes":[{"id":2,"season_number":2,"episode_number":1,"name":"The North Remembers",
              "air_date":"2012-04-01"}]}
            """#,
        ])
        let result = try #require(try await TMDBCatalog(client: client(stub, "tmdb"), apiKey: "k")
            .episodes(ids: ExternalIDs(tmdb: "1399")))
        #expect(result.status == .ended)
        #expect(result.episodes.map { "\($0.season)x\($0.episode)" } == ["1x1", "2x1"])
        #expect(result.episodes[1].runtimeMinutes == 60, "falls back to the show's episode run time")
    }

    @Test("Open Library search normalizes ISBNs to ISBN-13 and keeps the work id")
    func openLibrarySearch() async throws {
        let stub = transport(["/search.json": #"""
        {"docs":[{"key":"/works/OL893415W","title":"Dune","first_publish_year":1965,
                  "isbn":["0441172717","9780441172719"],"cover_i":123,"author_name":["Frank Herbert"]}]}
        """#])
        let hits = try await OpenLibraryCatalog(client: client(stub, "ol"), userAgent: "Aaru-test").search(
            query: "dune",
            type: .book
        )
        #expect(hits.first?.ids == ExternalIDs(isbn: "9780441172719", openLibrary: "OL893415W"))
        #expect(hits.first?.byline == "Frank Herbert")
        #expect(stub.requests.first?.headers.contains { $0 == ("User-Agent", "Aaru-test") } == true)
    }

    @Test("AniList search marks anime and carries AniList and MAL ids; movies are movies")
    func aniListSearch() async throws {
        let stub = transport(["": #"""
        {"data":{"Page":{"media":[
          {"id":16498,"idMal":16498,"format":"TV","status":"FINISHED","episodes":25,"duration":24,
           "title":{"romaji":"Shingeki no Kyojin","english":"Attack on Titan","native":"進撃の巨人"},
           "startDate":{"year":2013},"coverImage":{"large":"https://img/aot.jpg"},"description":"Titans."},
          {"id":199,"idMal":199,"format":"MOVIE","status":"FINISHED","episodes":1,"duration":125,
           "title":{"romaji":"Sen to Chihiro","english":"Spirited Away","native":null},
           "startDate":{"year":2001},"coverImage":null,"description":null}]}}}
        """#])
        let hits = try await AniListCatalog(client: client(stub, "anilist")).search(query: "x", type: .show)
        #expect(hits.map(\.type) == [.show, .movie])
        #expect(hits.allSatisfy { $0.isAnime })
        #expect(hits[0].ids == ExternalIDs(anilist: "16498", mal: "16498"))
        #expect(hits[0].title == "Attack on Titan")
        #expect(stub.requests.first?.method == "POST")
    }

    @Test("AniList episodes come from the schedule plus the next airing episode")
    func aniListEpisodes() async throws {
        let stub = transport(["": #"""
        {"data":{"Media":{"id":1,"idMal":null,"format":"TV","status":"RELEASING","episodes":null,"duration":24,
          "title":{"romaji":"X","english":null,"native":null},"startDate":{"year":2026},
          "coverImage":null,"description":null,
          "airingSchedule":{"nodes":[{"episode":1,"airingAt":1790000000},{"episode":2,"airingAt":1790604800}]},
          "nextAiringEpisode":{"episode":3,"airingAt":1791209600}}}}
        """#])
        let result = try #require(try await AniListCatalog(client: client(stub, "anilist"))
            .episodes(ids: ExternalIDs(anilist: "1")))
        #expect(result.status == .returning)
        #expect(result.episodes.map(\.episode) == [1, 2, 3])
        #expect(result.episodes.allSatisfy { $0.season == 1 && $0.airsAt != nil })
    }
}
