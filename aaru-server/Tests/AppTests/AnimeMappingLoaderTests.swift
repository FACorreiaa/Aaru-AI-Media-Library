import AaruCore
import Foundation
import Testing
@testable import aaru

@Suite("Anime mapping load (CAT-010)", .serialized)
struct AnimeMappingLoaderTests {
    /// Fribb rows: a mapped TV cour, a film (TMDB *movie* id, as a list), a row with no AniList
    /// id, and a TV entry whose TMDB id is a list.
    func fixture(_ anilist: [String], tmdb: String, mal: String = "290", anidb: String = "1", tvdb: String = "72025")
        -> Data
    {
        Data("""
        [
          {"type":"TV","anilist_id":\(anilist[0]),"mal_id":\(mal),"anidb_id":\(anidb),"tvdb_id":\(tvdb),
           "themoviedb_id":{"tv":\(tmdb)},"season":{"tvdb":2,"tmdb":2}},
          {"type":"MOVIE","anilist_id":\(anilist[1]),"mal_id":291,"themoviedb_id":{"movie":[1390599]},
           "season":{"tvdb":0}},
          {"type":"SPECIAL","mal_id":292},
          {"type":"TV","anilist_id":\(anilist[2]),"themoviedb_id":{"tv":[\(tmdb),999]},"season":{"tmdb":3}}
        ]
        """.utf8)
    }

    @Test("Fribb rows parse; a film's TMDB movie id is never kept; rows without AniList are skipped")
    func parse() throws {
        let mappings = try AnimeMappingLoader.parse(fixture(["10", "11", "12"], tmdb: "26209"))
        #expect(mappings.map(\.anilist) == ["10", "11", "12"])
        #expect(mappings[0] == AnimeMapping(
            anilist: "10", mal: "290", anidb: "1", tvdb: "72025", tmdb: "26209", tmdbSeason: 2
        ))
        #expect(mappings[1].tmdb == nil && mappings[1].tmdbSeason == nil, "a film is not a TMDB show")
        #expect(mappings[1].mal == "291")
        #expect(mappings[2].tmdb == "26209" && mappings[2].tmdbSeason == 3)
    }

    @Test("Loading twice is idempotent and the mapped AniList id resolves to its TMDB show")
    func loadAndResolve() async throws {
        try await withMigratedStores { stores in
            let tmdb = String(Int.random(in: 10_000_000 ... 99_999_999))
            let ids = (0 ..< 3).map { _ in String(Int.random(in: 10_000_000 ... 99_999_999)) }
            // Global ids are unique across titles, so a fixed MAL id would find an earlier run's title.
            let random = { String(Int.random(in: 10_000_000 ... 99_999_999)) }
            let mappings = try AnimeMappingLoader.parse(fixture(
                ids, tmdb: tmdb, mal: random(), anidb: random(), tvdb: random()
            ))
            try await stores.animeMappings.upsertMany(mappings)
            try await stores.animeMappings.upsertMany(mappings)
            #expect(try await stores.animeMappings.mapping(anilist: ids[0]) == mappings[0])
            #expect(try await stores.animeMappings.mapping(anilist: ids[1])?.tmdb == nil)

            let fake = FakeCatalog()
            fake.stubTitle(CatalogTitle(
                hit: CatalogHit(
                    type: .show, title: "Mapped Anime", originalTitle: nil, year: 1999, posterURL: nil,
                    overview: nil, byline: nil, ids: ExternalIDs(tmdb: tmdb), isAnime: false
                ),
                status: .ended, runtimeMinutes: 24
            ))
            let resolver = TitleResolver(stores: stores, catalogs: FakeCatalog.providers(fake))
            let title = try await resolver.resolve(MediaRef(type: .show, ids: ExternalIDs(anilist: ids[0])))
            #expect(title.ids.tmdb == tmdb)
            #expect(title.isAnime)
        }
    }
}
