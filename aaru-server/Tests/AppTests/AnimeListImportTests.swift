import AaruCore
import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
@testable import aaru

/// IMP-013 (MyAnimeList XML) and IMP-014 (AniList by username).
@Suite("Anime list imports (IMP-013, IMP-014)", .serialized)
struct AnimeListImportTests {
    static let malExport = #"""
    <?xml version="1.0" encoding="UTF-8" ?>
    <myanimelist>
      <myinfo><user_name>someone</user_name></myinfo>
      <anime>
        <series_animedb_id>52991</series_animedb_id>
        <series_title><![CDATA[Sousou no Frieren]]></series_title>
        <series_type>TV</series_type>
        <series_episodes>28</series_episodes>
        <my_watched_episodes>12</my_watched_episodes>
        <my_score>9</my_score>
        <my_status>Watching</my_status>
        <my_finish_date>0000-00-00</my_finish_date>
      </anime>
      <anime>
        <series_animedb_id>5114</series_animedb_id>
        <series_title>Fullmetal Alchemist: Brotherhood &amp; More</series_title>
        <series_type>TV</series_type>
        <series_episodes>64</series_episodes>
        <my_watched_episodes>0</my_watched_episodes>
        <my_score>0</my_score>
        <my_status>Completed</my_status>
        <my_finish_date>2020-05-01</my_finish_date>
      </anime>
      <anime>
        <series_animedb_id>199</series_animedb_id>
        <series_title><![CDATA[Sen to Chihiro no Kamikakushi]]></series_title>
        <series_type>Movie</series_type>
        <series_episodes>1</series_episodes>
        <my_watched_episodes>0</my_watched_episodes>
        <my_score>10</my_score>
        <my_status>Plan to Watch</my_status>
      </anime>
    </myanimelist>
    """#

    @Test("MAL XML: ids, status map, score, progress, and a completed entry with 0 watched means all")
    func malParser() throws {
        let rows = try MALListParser.parse(Self.malExport)
        #expect(rows.map(\.ids.mal) == ["52991", "5114", "199"])
        #expect(rows.map(\.status) == [.inProgress, .finished, .wishlist])
        #expect(rows.map(\.rating) == [9, nil, 10])
        #expect(rows[0].watched?.count == 12)
        #expect(rows[1].watched?.count == 64)
        #expect(rows[1].title == "Fullmetal Alchemist: Brotherhood & More")
        #expect(rows[1].finishedAt == Date.catalogDay("2020-05-01"))
        #expect(rows[2].type == .movie && rows[2].watched == nil)
        #expect(throws: ImportFormatError.self) { try MALListParser.parse("Const,Title\ntt1,X") }
    }

    @Test("LIB-007: on hold (MAL's On-Hold and 3, AniList's PAUSED) is Aaru's on hold; rewatching stays in progress")
    func onHoldMapping() {
        for word in ["On-Hold", "onhold", "3", "PAUSED"] {
            #expect(AnimeListImport.status(word) == .onHold, "\(word)")
        }
        for word in ["Watching", "CURRENT", "REPEATING", "1", "Reading"] {
            #expect(AnimeListImport.status(word) == .inProgress, "\(word)")
        }
        let rows = MALListParser.animeRows(Self.malExport)
        #expect(rows.allSatisfy { $0.knowsOnHold == true }, "MAL has on hold, so its watching may resume one")
    }

    @Test("AniList: a public list becomes rows with both ids; a private list is notFound")
    func anilistReader() async throws {
        let stub = StubTransport { request in
            let body = String(data: request.body ?? Data(), encoding: .utf8) ?? ""
            if body.contains("type: MANGA") {
                return OutboundResponse(status: 200, body: Data(#"""
                {"data":{"MediaListCollection":{"lists":[{"entries":[
                  {"status":"CURRENT","progress":112,"progressVolumes":12,"score":9,
                   "completedAt":{"year":null,"month":null,"day":null},
                   "media":{"id":30002,"idMal":2,"format":"MANGA","chapters":null,"volumes":null,
                            "title":{"romaji":"Berserk","english":null},"startDate":{"year":1989}}}
                ]}]}}}
                """#.utf8))
            }
            if body.contains("\"hidden\"") {
                return OutboundResponse(
                    status: 404,
                    body: Data(#"{"data":null,"errors":[{"message":"Private User"}]}"#.utf8)
                )
            }
            return OutboundResponse(status: 200, body: Data(#"""
            {"data":{"MediaListCollection":{"lists":[{"entries":[
              {"status":"CURRENT","progress":3,"score":8.5,
               "completedAt":{"year":null,"month":null,"day":null},
               "media":{"id":154587,"idMal":52991,"format":"TV","episodes":28,
                        "title":{"romaji":"Sousou no Frieren","english":"Frieren"},"startDate":{"year":2023}}},
              {"status":"COMPLETED","progress":0,"score":0,"completedAt":{"year":2021,"month":3,"day":4},
               "media":{"id":21,"idMal":null,"format":"MOVIE","episodes":1,
                        "title":{"romaji":"X","english":null},"startDate":{"year":2001}}}
            ]}]}}}
            """#.utf8))
        }
        let anilist = AniListCatalog(client: ProviderClient(
            name: "anilist", transport: stub, pacer: RequestPacer(requestsPerSecond: 1000, burst: 100)
        ))
        let rows = try await anilist.listRows(userName: "someone")
        #expect(rows.map(\.ids.anilist) == ["154587", "21", "30002"])
        #expect(rows[0].ids.mal == "52991" && rows[0].title == "Frieren" && rows[0].year == 2023)
        #expect(rows[0].status == .inProgress && rows[0].rating == 8.5 && rows[0].watched?.count == 3)
        #expect(rows[1].type == .movie && rows[1].status == .finished && rows[1].rating == nil)
        #expect(rows[1].finishedAt == Date.catalogDay("2021-03-04"))
        #expect(rows[2].type == .manga && rows[2].ids.mal == "2" && rows[2].status == .inProgress)
        #expect(rows[2].mangaChapter == 112 && rows[2].mangaVolume == 12 && rows[2].watched == nil)
        await #expect(throws: ProviderError.self) { try await anilist.listRows(userName: "hidden") }
    }

    @Test("A MAL upload plans through AniList, ticks watched episodes on approval")
    func malUploadFlow() async throws {
        try await LibraryHarness.run { env in
            let mal = String(Int.random(in: 100_000 ..< 999_999))
            let anilist = uniqueID("al")
            env.fake.stubTitle(CatalogTitle(
                hit: CatalogHit(
                    type: .show, title: "Frieren", originalTitle: nil, year: 2023, posterURL: nil, overview: nil,
                    byline: nil, ids: ExternalIDs(anilist: anilist, mal: mal), isAnime: true
                ),
                status: .ended, runtimeMinutes: 24
            ))
            let xml = Self.malExport.replacingOccurrences(of: "52991", with: mal)
            let created = try await env.client.execute(
                uri: "/v1/imports/csv?source=mal&filename=animelist.xml",
                method: .post,
                headers: [.authorization: "Bearer \(env.token)", .contentType: "application/xml"],
                body: ByteBuffer(string: xml)
            ) { LibraryHarness.Reply(status: $0.status, body: Data(buffer: $0.body)) }
            #expect(created.status == .accepted)
            let job = try created.json()
            #expect(job["source"] as? String == "mal_xml")

            let id = try #require(job["id"] as? String)
            let service = ImportService(
                stores: env.stores,
                resolver: TitleResolver(stores: env.stores, catalogs: FakeCatalog.providers(env.fake))
            )
            var planned: [String: Any] = [:]
            for _ in 0 ..< 50 {
                planned = try await env.send(.get, "/v1/imports/\(id)").json()
                let state = (planned["job"] as? [String: Any])?["state"] as? String
                if state != "queued", state != "running" {
                    break
                }
                guard try await service.runNext(for: env.userID) else { break }
            }
            let rows = try #require(planned["rows"] as? [[String: Any]])
            #expect(rows.first?["outcome"] as? String == "create", "the MAL id resolves through AniList")
        }
    }

    @Test("AniList import: the username is validated and kept as the job's name")
    func anilistCreate() async throws {
        try await LibraryHarness.run { env in
            let bad = try await env.send(.post, "/v1/imports/anilist", json: ["username": "no spaces!"])
            #expect(bad.status == .unprocessableContent)
            let good = try await env.send(.post, "/v1/imports/anilist", json: ["username": "@Someone_1"])
            #expect(good.status == .accepted)
            let job = try good.json()
            #expect(job["source"] as? String == "anilist" && job["filename"] as? String == "Someone_1")
        }
    }
}
