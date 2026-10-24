import AaruCore
import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
@testable import aaru

/// MNG-002: MyAnimeList's manga XML. AniList's manga list is read in `AnimeListImportTests`.
@Suite("Manga list imports (MNG-002)", .serialized)
struct MangaImportTests {
    static let malMangaExport = #"""
    <?xml version="1.0" encoding="UTF-8" ?>
    <myanimelist>
      <myinfo><user_name>someone</user_name><user_export_type>2</user_export_type></myinfo>
      <manga>
        <manga_mangadb_id>2</manga_mangadb_id>
        <manga_title><![CDATA[Berserk]]></manga_title>
        <manga_volumes>0</manga_volumes>
        <manga_chapters>0</manga_chapters>
        <my_read_volumes>12</my_read_volumes>
        <my_read_chapters>112</my_read_chapters>
        <my_score>10</my_score>
        <my_status>Reading</my_status>
        <my_finish_date>0000-00-00</my_finish_date>
      </manga>
      <manga>
        <manga_mangadb_id>656</manga_mangadb_id>
        <manga_title><![CDATA[Vagabond]]></manga_title>
        <manga_volumes>37</manga_volumes>
        <manga_chapters>327</manga_chapters>
        <my_read_volumes>0</my_read_volumes>
        <my_read_chapters>0</my_read_chapters>
        <my_score>0</my_score>
        <my_status>Completed</my_status>
        <my_finish_date>2019-08-02</my_finish_date>
      </manga>
      <manga>
        <manga_mangadb_id>1706</manga_mangadb_id>
        <manga_title>JoJo no Kimyou na Bouken</manga_title>
        <manga_volumes>0</manga_volumes>
        <manga_chapters>0</manga_chapters>
        <my_read_volumes>0</my_read_volumes>
        <my_read_chapters>0</my_read_chapters>
        <my_score>0</my_score>
        <my_status>Plan to Read</my_status>
      </manga>
    </myanimelist>
    """#

    @Test("MAL manga XML (MNG-002): manga rows with chapters and volumes; completed with 0 read means all")
    func malMangaParser() throws {
        let rows = try MALListParser.parse(Self.malMangaExport)
        #expect(rows.map(\.type) == [.manga, .manga, .manga])
        #expect(rows.map(\.ids.mal) == ["2", "656", "1706"])
        #expect(rows.map(\.sourceKey) == ["mal-manga:2", "mal-manga:656", "mal-manga:1706"])
        #expect(rows.map(\.status) == [.inProgress, .finished, .wishlist])
        #expect(rows[0].mangaChapter == 112 && rows[0].mangaVolume == 12 && rows[0].rating == 10)
        #expect(rows[1].mangaChapter == 327 && rows[1].mangaVolume == 37)
        #expect(rows[1].finishedAt == Date.catalogDay("2019-08-02"))
        #expect(rows[2].mangaChapter == nil && rows[2].mangaVolume == nil)
        #expect(rows.allSatisfy { $0.watched == nil })

        let both = AnimeListImportTests.malExport.replacingOccurrences(
            of: "</myanimelist>",
            with: "<manga><manga_mangadb_id>2</manga_mangadb_id><manga_title>Berserk</manga_title></manga>"
                + "</myanimelist>"
        )
        let mixed = try MALListParser.parse(both)
        #expect(mixed.map(\.type) == [.show, .show, .movie, .manga], "one file may hold both lists")
    }

    @Test("A MAL manga upload resolves through AniList's manga, never an anime with the same MAL number")
    func malMangaFlow() async throws {
        try await LibraryHarness.run { env in
            let mal = String(Int.random(in: 100_000 ..< 999_999))
            env.fake.stubTitle(CatalogTitle(
                hit: CatalogHit(
                    type: .show, title: "Same Number Anime", originalTitle: nil, year: 2001, posterURL: nil,
                    overview: nil, byline: nil, ids: ExternalIDs(anilist: uniqueID("al"), mal: mal), isAnime: true
                ),
                status: .ended, runtimeMinutes: 24
            ))
            env.fake.stubTitle(CatalogTitle(
                hit: CatalogHit(
                    type: .manga, title: "Berserk", originalTitle: nil, year: 1989, posterURL: nil, overview: nil,
                    byline: "Kentarou Miura", ids: ExternalIDs(anilist: uniqueID("al"), mal: mal), isAnime: false
                ),
                status: .returning, runtimeMinutes: nil
            ))
            let xml = Self.malMangaExport.replacingOccurrences(
                of: "<manga_mangadb_id>2</manga_mangadb_id>", with: "<manga_mangadb_id>\(mal)</manga_mangadb_id>"
            )
            let created = try await env.client.execute(
                uri: "/v1/imports/csv?source=auto&filename=mangalist.xml",
                method: .post,
                headers: [.authorization: "Bearer \(env.token)", .contentType: "application/xml"],
                body: ByteBuffer(string: xml)
            ) { LibraryHarness.Reply(status: $0.status, body: Data(buffer: $0.body)) }
            #expect(created.status == .accepted)
            let id = try #require(try created.json()["id"] as? String)
            let service = ImportService(
                stores: env.stores,
                resolver: TitleResolver(stores: env.stores, catalogs: FakeCatalog.providers(env.fake))
            )
            for _ in 0 ..< 50 {
                let state = try await (env.send(.get, "/v1/imports/\(id)").json()["job"] as? [String: Any])?["state"]
                if state as? String != "queued", state as? String != "running" {
                    break
                }
                guard try await service.runNext(for: env.userID) else { break }
            }
            _ = try await env.send(.post, "/v1/imports/\(id)/apply")
            let manga = try await env.send(.get, "/v1/library/items?type=manga").json()
            let items = try #require(manga["items"] as? [[String: Any]])
            let berserk = try #require(items.first {
                ($0["title"] as? [String: Any])?["title"] as? String == "Berserk"
            })
            #expect(berserk["status"] as? String == "in_progress")
            #expect((berserk["mangaProgress"] as? [String: Any])?["chapter"] as? Int == 112)
            #expect((berserk["mangaProgress"] as? [String: Any])?["volume"] as? Int == 12)
            let shows = try await env.send(.get, "/v1/library/items?type=show").json()
            #expect((shows["items"] as? [[String: Any]])?.isEmpty == true, "the anime with that MAL number stays out")
        }
    }

    @Test("A manga import moves the chapter forward, never back")
    func mangaProgressOnlyMovesForward() {
        let row = ImportRow(
            type: .manga, title: "Berserk", ids: ExternalIDs(mal: "2"), status: .inProgress, lists: [],
            mangaChapter: 100, mangaVolume: 15
        )
        let item = ImportItemState(
            itemID: LibraryItemID(),
            fields: ItemFields(status: .inProgress, isOwned: false, mangaChapter: 120, mangaVolume: 12),
            statusByHand: false, watched: []
        )
        let decision = ImportService.decide(row, item: item)
        #expect(decision.fields?.mangaChapter == 120, "chapter 100 is behind 120")
        #expect(decision.fields?.mangaVolume == 15)
        #expect(decision.reason == "Adds the volume 15.")
    }
}
