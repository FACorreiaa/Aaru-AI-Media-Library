import AaruCore
import Foundation
import Testing
@testable import aaru

/// AniList's manga against canned JSON. No network.
@Suite("AniList manga adapter (MNG-001)")
struct AniListMangaAdapterTests {
    func catalog(_ body: String) -> (AniListCatalog, StubTransport) {
        let stub = StubTransport { _ in OutboundResponse(status: 200, body: Data(body.utf8)) }
        let client = ProviderClient(
            name: "anilist", transport: stub, pacer: RequestPacer(requestsPerSecond: 1000, burst: 100)
        )
        return (AniListCatalog(client: client, userAgent: "Aaru-test"), stub)
    }

    @Test("Manga search asks AniList for MANGA without adult works, and credits the authors")
    func search() async throws {
        let (anilist, stub) = catalog(#"""
        {"data":{"Page":{"media":[
          {"id":30013,"idMal":13,"type":"MANGA","format":"MANGA","status":"RELEASING","chapters":null,"volumes":null,
           "title":{"romaji":"ONE PIECE","english":"One Piece","native":"ONE PIECE"},
           "startDate":{"year":1997},"coverImage":{"large":"https://img/op.jpg"},"description":"Pirates.",
           "staff":{"edges":[{"role":"Story & Art","node":{"name":{"full":"Eiichiro Oda"}}},
                             {"role":"Translator (English)","node":{"name":{"full":"Stephen Paul"}}}]}},
          {"id":30002,"idMal":2,"type":"MANGA","format":"MANGA","status":"FINISHED","chapters":364,"volumes":41,
           "title":{"romaji":"Berserk","english":null,"native":"ベルセルク"},"startDate":{"year":1989},
           "staff":{"edges":[{"role":"Story","node":{"name":{"full":"Kentarou Miura"}}},
                             {"role":"Art","node":{"name":{"full":"Kouji Mori"}}},
                             {"role":"Art","node":{"name":{"full":"Kentarou Miura"}}}]}}]}}}
        """#)
        let hits = try await anilist.search(query: "x", type: .manga)
        #expect(hits.map(\.type) == [.manga, .manga])
        #expect(hits.allSatisfy { !$0.isAnime && $0.network == nil })
        #expect(hits[0].ids == ExternalIDs(anilist: "30013", mal: "13"))
        #expect(hits[0].byline == "Eiichiro Oda", "translators are not authors")
        #expect(hits[0].chapterCount == nil, "a running series has no count yet")
        #expect(hits[1].byline == "Kentarou Miura, Kouji Mori")
        #expect(hits[1].chapterCount == 364 && hits[1].volumeCount == 41)
        let body = try #require(stub.requests.first?.body.flatMap { String(bytes: $0, encoding: .utf8) })
        #expect(body.contains("type: MANGA, isAdult: false"))
        #expect(body.contains("staff("))
    }

    @Test("Anime search is unchanged: ANIME, no credits asked")
    func animeStaysAnime() async throws {
        let (anilist, stub) = catalog(#"{"data":{"Page":{"media":[]}}}"#)
        _ = try await anilist.search(query: "x", type: .show)
        let body = try #require(stub.requests.first?.body.flatMap { String(bytes: $0, encoding: .utf8) })
        #expect(body.contains("type: ANIME"))
        #expect(!body.contains("staff("))
    }

    @Test("MAL batches ask for the list's own type: MAL numbers anime and manga apart")
    func malBatchType() async throws {
        let (anilist, stub) = catalog(#"""
        {"data":{"Page":{"media":[{"id":30002,"idMal":2,"type":"MANGA","format":"MANGA",
          "title":{"romaji":"Berserk"},"startDate":{"year":1989}}]}}}
        """#)
        let found = try await anilist.hydrate(malIDs: ["2"], type: .manga)
        #expect(found["2"]?.hit.type == .manga)
        let body = try #require(stub.requests.first?.body.flatMap { String(bytes: $0, encoding: .utf8) })
        #expect(body.contains("idMal_in: $ids, type: MANGA"))
    }
}

@Suite("Manga in the library (MNG-001)", .serialized)
struct MangaLibraryTests {
    func stubManga(_ env: LibraryHarness, _ name: String, mal: String? = nil, chapters: Int? = 364) -> String {
        let anilist = uniqueID("al")
        var hit = CatalogHit(
            type: .manga, title: name, originalTitle: nil, year: 1989, posterURL: nil, overview: nil,
            byline: "Kentarou Miura", ids: ExternalIDs(anilist: anilist, mal: mal), isAnime: false
        )
        hit.chapterCount = chapters
        hit.volumeCount = 41
        env.fake.stubTitle(CatalogTitle(hit: hit, status: .ended, runtimeMinutes: nil, genres: ["Action"]))
        return anilist
    }

    func addManga(_ env: LibraryHarness, _ anilist: String) async throws -> String {
        try #require(try await env.send(.post, "/v1/library/items", json: [
            "mediaRef": ["type": "manga", "ids": ["anilist": anilist]],
        ]).json()["id"] as? String)
    }

    @Test("A manga is added by its AniList id and carries its author and counts")
    func add() async throws {
        try await LibraryHarness.run { env in
            let added = try await env.send(.post, "/v1/library/items", json: [
                "mediaRef": ["type": "manga", "ids": ["anilist": stubManga(env, "Berserk")]],
            ]).json()
            let title = try #require(added["title"] as? [String: Any])
            #expect(title["type"] as? String == "manga")
            #expect(title["isAnime"] as? Bool == false)
            #expect(title["byline"] as? String == "Kentarou Miura")
            #expect(title["chapterCount"] as? Int == 364)
            #expect(title["volumeCount"] as? Int == 41)
            #expect(added["status"] as? String == "wishlist")
        }
    }

    @Test("Chapter and volume progress is journaled and undoable; books and shows refuse it")
    func progress() async throws {
        try await LibraryHarness.run { env in
            let item = try await addManga(env, stubManga(env, "Berserk"))
            let read = try await env.send(.patch, "/v1/library/items/\(item)", json: [
                "status": "in_progress", "mangaChapter": 112, "mangaVolume": 12,
            ]).json()
            #expect((read["mangaProgress"] as? [String: Any])?["chapter"] as? Int == 112)
            #expect((read["mangaProgress"] as? [String: Any])?["volume"] as? Int == 12)
            #expect(read["bookProgress"] == nil)

            let more = try await env.send(.patch, "/v1/library/items/\(item)", json: ["mangaChapter": 120]).json()
            #expect((more["mangaProgress"] as? [String: Any])?["chapter"] as? Int == 120)
            #expect((more["mangaProgress"] as? [String: Any])?["volume"] as? Int == 12, "the volume stays")

            let journal = try await env.send(.get, "/v1/actions?limit=10").json()
            let actions = try #require(journal["items"] as? [[String: Any]])
            #expect(actions.first?["summary"] as? String == "Read Berserk to chapter 120")
            let actionID = try #require(actions.first?["id"] as? String)
            _ = try await env.send(.post, "/v1/actions/\(actionID)/undo")
            let undone = try await env.send(.get, "/v1/library/items/\(item)").json()
            #expect((undone["mangaProgress"] as? [String: Any])?["chapter"] as? Int == 112)

            let cleared = try await env.send(.patch, "/v1/library/items/\(item)", json: ["clear": ["mangaProgress"]])
                .json()
            #expect(cleared["mangaProgress"] == nil)

            let negative = try await env.send(.patch, "/v1/library/items/\(item)", json: ["mangaChapter": -1])
            #expect(negative.status == .unprocessableContent)
            let movie = try await env.add("movie", tmdb: env.stubMovie("Dune"))
            let refused = try await env.send(.patch, "/v1/library/items/\(movie)", json: ["mangaChapter": 3])
            #expect(refused.status == .unprocessableContent)
        }
    }

    @Test("Manga reads Plan to read, Reading, Read; it filters by type")
    func labelsAndFilter() async throws {
        try await LibraryHarness.run { env in
            let item = try await addManga(env, stubManga(env, "Vagabond"))
            _ = try await env.send(.patch, "/v1/library/items/\(item)", json: ["status": "in_progress"])
            _ = try await env.send(.patch, "/v1/library/items/\(item)", json: ["status": "finished"])
            let journal = try await env.send(.get, "/v1/actions?limit=10").json()
            let summaries = (journal["items"] as? [[String: Any]])?.compactMap { $0["summary"] as? String }
            #expect(summaries == [
                "Moved Vagabond to Read",
                "Moved Vagabond to Reading",
                "Added Vagabond to Plan to read",
            ])
            let manga = try await env.send(.get, "/v1/library/items?type=manga").json()
            #expect((manga["items"] as? [[String: Any]])?.compactMap { $0["id"] as? String } == [item])
        }
    }

    @Test("An anime and a manga with the same MyAnimeList number are two titles")
    func malIDsArePerList() async throws {
        try await LibraryHarness.run { env in
            let mal = String(Int.random(in: 1_000_000 ... 9_999_999))
            env.fake.stubTitle(CatalogTitle(
                hit: CatalogHit(
                    type: .show, title: "Some Anime", originalTitle: nil, year: 2001, posterURL: nil, overview: nil,
                    byline: nil, ids: ExternalIDs(anilist: uniqueID("al"), mal: mal), isAnime: true
                ),
                status: .ended, runtimeMinutes: 24
            ))
            _ = stubManga(env, "Some Manga", mal: mal)
            let anime = try await env.send(.post, "/v1/library/items", json: [
                "mediaRef": ["type": "show", "ids": ["mal": mal]],
            ]).json()
            let manga = try await env.send(.post, "/v1/library/items", json: [
                "mediaRef": ["type": "manga", "ids": ["mal": mal]],
            ]).json()
            let animeTitle = try #require(anime["title"] as? [String: Any])
            let mangaTitle = try #require(manga["title"] as? [String: Any])
            #expect(animeTitle["title"] as? String == "Some Anime")
            #expect(mangaTitle["title"] as? String == "Some Manga")
            #expect(animeTitle["id"] as? String != mangaTitle["id"] as? String)
        }
    }

    @Test("Manga search goes to AniList alone, and says so when AniList is down")
    func search() async throws {
        try await LibraryHarness.run { env in
            _ = stubManga(env, "Berserk")
            env.fake.stubSearch("berserk", [CatalogHit(
                type: .manga, title: "Berserk", originalTitle: nil, year: 1989, posterURL: nil, overview: nil,
                byline: "Kentarou Miura", ids: ExternalIDs(anilist: uniqueID("al")), isAnime: false
            )])
            let found = try await env.send(.get, "/v1/search?q=berserk&type=manga").json()
            #expect((found["items"] as? [[String: Any]])?.compactMap { $0["type"] as? String } == ["manga"])
            #expect(found["incomplete"] as? Bool == false)

            env.fake.fail(with: ProviderError(provider: "anilist", kind: .unavailable))
            let down = try await env.send(.get, "/v1/search?q=berserk&type=manga").json()
            #expect((down["items"] as? [[String: Any]])?.isEmpty == true)
            #expect(down["incomplete"] as? Bool == true)
            #expect(down["notice"] as? String == CatalogSearchResult.mangaDown)
        }
    }
}
