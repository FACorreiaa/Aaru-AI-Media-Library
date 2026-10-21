import AaruCore
import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
@testable import aaru

/// CAT-019: the All scope over separate TMDB, AniList and Open Library fakes.
@Suite("All-kinds search (CAT-019)", .serialized)
struct CatalogSearchAllTests {
    struct Fakes {
        let tmdb = FakeCatalog()
        let anilist = FakeCatalog()
        let openLibrary = FakeCatalog()

        var providers: CatalogProviders {
            CatalogProviders(tmdb: tmdb, anilist: anilist, openLibrary: openLibrary)
        }
    }

    func hit(_ title: String, _ type: AaruCore.MediaType, ids: ExternalIDs, anime: Bool = false) -> CatalogHit {
        CatalogHit(
            type: type, title: title, originalTitle: nil, year: 2025, posterURL: nil, overview: nil, byline: nil,
            ids: ids, isAnime: anime
        )
    }

    @Test("CAT-019: films, shows and anime together, exact title first; Open Library is never called")
    func mixed() async throws {
        try await withMigratedStores { stores in
            let fakes = Fakes()
            let mobland = hit("MobLand", .show, ids: ExternalIDs(tmdb: uniqueID("tmdb")))
            fakes.tmdb.stubSearch("Mobland", [
                hit("Mob Land Stories", .movie, ids: ExternalIDs(tmdb: uniqueID("tmdb"))),
                mobland,
            ])
            fakes.anilist.stubSearch("Mobland", [
                hit("Mobland Gakuen", .show, ids: ExternalIDs(anilist: uniqueID("al")), anime: true),
            ])
            fakes.openLibrary.stubSearch("Mobland", [hit("Mobland", .book, ids: ExternalIDs(isbn: "1"))])
            let service = CatalogService(stores: stores, catalogs: fakes.providers)

            let result = try await service.search(query: "Mobland", scope: .all)
            #expect(result.hits.first == mobland, "the exact title leads")
            #expect(result.hits.map(\.title) == ["MobLand", "Mob Land Stories", "Mobland Gakuen"])
            #expect(!result.incomplete)
            #expect(fakes.openLibrary.callCount("search") == 0)
            #expect(fakes.tmdb.callCount("searchMulti") == 1 && fakes.tmdb.callCount("search") == 0)
        }
    }

    @Test("CAT-019: a mapped anime appears once, with the TMDB id; same-named titles with no shared id both stay")
    func mappingDedupe() async throws {
        try await withMigratedStores { stores in
            let fakes = Fakes()
            let (tmdb, anilist) = (uniqueID("tmdb"), uniqueID("al"))
            try await stores.animeMappings.upsert(AnimeMapping(anilist: anilist, tmdb: tmdb, tmdbSeason: 1))
            let sameName = ExternalIDs(tmdb: uniqueID("tmdb"))
            fakes.tmdb.stubSearch("frieren", [
                hit("Frieren", .show, ids: ExternalIDs(tmdb: tmdb), anime: true),
                // Same name, no shared id: a different work as far as Aaru knows.
                hit("Frieren", .movie, ids: sameName),
            ])
            fakes.anilist.stubSearch("frieren", [
                hit("Frieren", .show, ids: ExternalIDs(anilist: anilist), anime: true),
                hit("Frieren", .show, ids: ExternalIDs(anilist: uniqueID("al")), anime: true),
            ])
            let service = CatalogService(stores: stores, catalogs: fakes.providers)

            let hits = try await service.search(query: "frieren", scope: .all).hits
            #expect(hits.count == 3)
            #expect(hits.filter { $0.ids.tmdb == tmdb }.map(\.ids.anilist) == [anilist], "kept once, as AniList")
            #expect(hits.contains { $0.ids == sameName })
            #expect(hits.count { $0.ids.anilist != nil } == 2)
        }
    }

    @Test("CAT-021: while AniList is down, anime search is TMDB's anime, incomplete, with a notice")
    func animeStandIn() async throws {
        try await withMigratedStores { stores in
            let fakes = Fakes()
            fakes.tmdb.stubSearch("frieren", [
                hit("Frieren", .show, ids: ExternalIDs(tmdb: uniqueID("tmdb")), anime: true),
                hit("Frieren: The Documentary", .movie, ids: ExternalIDs(tmdb: uniqueID("tmdb"))),
            ])
            fakes.anilist.fail(with: ProviderError(provider: "anilist", kind: .unavailable))
            let service = CatalogService(stores: stores, catalogs: fakes.providers)
            let result = try await service.search(query: "frieren", scope: .anime)
            #expect(result.hits.map(\.title) == ["Frieren"], "anime only")
            #expect(result.incomplete && result.notice == CatalogSearchResult.aniListDown)

            let all = try await service.search(query: "frieren", scope: .all)
            #expect(all.notice == CatalogSearchResult.aniListDown)
        }
    }

    @Test("CAT-019: one provider failing or too slow answers the other's hits, marked incomplete")
    func partial() async throws {
        try await withMigratedStores { stores in
            let fakes = Fakes()
            fakes.tmdb.stubSearch("dune", [hit("Dune", .movie, ids: ExternalIDs(tmdb: uniqueID("tmdb")))])
            fakes.anilist.stubSearch("dune", [hit("Dune Gakuen", .show, ids: ExternalIDs(anilist: "1"), anime: true)])
            var service = CatalogService(stores: stores, catalogs: fakes.providers)
            service.anilistDeadline = .milliseconds(50)

            fakes.anilist.fail(with: ProviderError(provider: "anilist", kind: .unavailable))
            var result = try await service.search(query: "dune", scope: .all)
            #expect(result.incomplete && result.hits.map(\.title) == ["Dune"])

            fakes.anilist.fail(with: nil)
            fakes.anilist.delay(.seconds(5))
            let clock = ContinuousClock()
            let started = clock.now
            result = try await service.search(query: "dune", scope: .all)
            #expect(result.incomplete && result.hits.map(\.title) == ["Dune"])
            #expect(started.duration(to: clock.now) < .seconds(2), "AniList's deadline, not its latency")

            fakes.anilist.delay(nil)
            fakes.tmdb.fail(with: ProviderError(provider: "tmdb", kind: .unavailable))
            result = try await service.search(query: "dune", scope: .all)
            #expect(result.incomplete && result.hits.map(\.title) == ["Dune Gakuen"])

            fakes.anilist.fail(with: ProviderError(provider: "anilist", kind: .unavailable))
            await #expect(throws: ProviderError(provider: "tmdb", kind: .unavailable)) {
                _ = try await service.search(query: "dune", scope: .all)
            }
        }
    }

    @Test("CAT-019: ranking alternates providers after exact matches and stops at 40")
    func ranking() {
        let video = (0 ..< 30).map { hit("Video \($0)", .movie, ids: ExternalIDs(tmdb: "\($0)")) }
        let anime = (0 ..< 30).map { hit("Anime \($0)", .show, ids: ExternalIDs(anilist: "\($0)"), anime: true) }
        let exact = hit("The Exact One", .show, ids: ExternalIDs(anilist: "x"), anime: true)
        let ranked = CatalogService.ranked(video, anime + [exact], query: "exact one")
        #expect(ranked.count == CatalogService.allLimit)
        #expect(ranked.first == exact, "a leading article and case do not matter")
        #expect(ranked.dropFirst().prefix(4).map(\.title) == ["Video 0", "Anime 0", "Video 1", "Anime 1"])
    }

    @Test("CAT-019: the route takes type=all and says whether the answer is complete")
    func route() async throws {
        try await withMigratedStores { stores in
            let fakes = Fakes()
            fakes.tmdb.stubSearch("severance", [
                hit("Severance", .show, ids: ExternalIDs(tmdb: uniqueID("tmdb"))),
            ])
            fakes.anilist.fail(with: ProviderError(provider: "anilist", kind: .unavailable))
            let (_, token) = try await signedInUser(stores)
            let auth = AuthService(stores: stores, apple: UntouchedAppleVerifier(), magicLinks: nil)
            let app = try Application(router: buildRouter(
                stores: stores, services: Services.make(stores: stores, catalogs: fakes.providers, auth: auth)
            ))
            try await app.test(.router) { client in
                let headers: HTTPFields = [.authorization: "Bearer \(token)"]
                try await client.execute(uri: "/v1/search?q=severance&type=all", method: .get, headers: headers) {
                    #expect($0.status == .ok)
                    let body = try JSONSerialization.jsonObject(with: Data(buffer: $0.body)) as? [String: Any]
                    #expect(body?["incomplete"] as? Bool == true)
                    #expect((body?["items"] as? [[String: Any]])?.first?["type"] as? String == "show")
                }
                try await client.execute(uri: "/v1/search?q=severance&type=show", method: .get, headers: headers) {
                    let body = try JSONSerialization.jsonObject(with: Data(buffer: $0.body)) as? [String: Any]
                    #expect(body?["incomplete"] as? Bool == false)
                }
            }
        }
    }
}
