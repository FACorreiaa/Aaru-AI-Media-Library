import AaruCore
import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
@testable import aaru

@Suite("Catalog resolution and detail (CAT-004…009)", .serialized)
struct CatalogResolutionTests {
    func movie(_ title: String, year: Int, ids: ExternalIDs) -> CatalogTitle {
        CatalogTitle(
            hit: CatalogHit(
                type: .movie, title: title, originalTitle: nil, year: year, posterURL: nil,
                overview: nil, byline: nil, ids: ids, isAnime: false
            ),
            status: nil,
            runtimeMinutes: 120
        )
    }

    @Test("CAT-005: concurrent resolutions of one MediaRef produce exactly one titles row")
    func concurrentResolution() async throws {
        try await withMigratedStores { stores in
            let fake = FakeCatalog()
            let tmdb = uniqueID("tmdb")
            fake.stubTitle(movie("Dune", year: 2021, ids: ExternalIDs(tmdb: tmdb, imdb: uniqueID("tt"))))
            let resolver = TitleResolver(stores: stores, catalogs: FakeCatalog.providers(fake))
            let ref = MediaRef(type: .movie, ids: ExternalIDs(tmdb: tmdb))
            let ids = try await withThrowingTaskGroup(of: TitleID.self) { group in
                for _ in 0 ..< 8 {
                    group.addTask { try await resolver.resolve(ref).id }
                }
                return try await group.reduce(into: Set<TitleID>()) { $0.insert($1) }
            }
            #expect(ids.count == 1)
            let rows = try await withSQL { sql in
                try await sql.raw("SELECT count(*)::int AS count FROM titles WHERE tmdb = \(bind: tmdb)")
                    .first(decoding: CountRow.self)?.count
            }
            #expect(rows == 1)
        }
    }

    @Test("CAT-005: a title known by its ids is found without asking the provider again")
    func existingByIDs() async throws {
        try await withMigratedStores { stores in
            let fake = FakeCatalog()
            let imdb = uniqueID("tt")
            fake.stubTitle(movie("Arrival", year: 2016, ids: ExternalIDs(tmdb: uniqueID("tmdb"), imdb: imdb)))
            let resolver = TitleResolver(stores: stores, catalogs: FakeCatalog.providers(fake))
            let first = try await resolver.resolve(MediaRef(type: .movie, ids: ExternalIDs(imdb: imdb)))
            let second = try await resolver.resolve(MediaRef(type: .movie, ids: ExternalIDs(imdb: imdb)))
            #expect(first.id == second.id)
            #expect(fake.callCount("hydrate") == 1)
        }
    }

    @Test("CAT-005: title + year resolves only an unambiguous match; never merges on name alone")
    func titleAndYear() async throws {
        try await withMigratedStores { stores in
            let fake = FakeCatalog()
            let solo = movie("Heat", year: 1995, ids: ExternalIDs(tmdb: uniqueID("tmdb")))
            fake.stubSearch("Heat", [solo.hit])
            fake.stubTitle(solo)
            let twins = [
                movie("Crash", year: 2004, ids: ExternalIDs(tmdb: uniqueID("tmdb"))).hit,
                movie("Crash", year: 2004, ids: ExternalIDs(tmdb: uniqueID("tmdb"))).hit,
            ]
            fake.stubSearch("Crash", twins)
            let resolver = TitleResolver(stores: stores, catalogs: FakeCatalog.providers(fake))

            let heat = try await resolver.resolve(MediaRef(type: .movie, title: "Heat", year: 1995))
            #expect(heat.ids.tmdb == solo.hit.ids.tmdb)
            await #expect(throws: ResolutionError.ambiguous) {
                _ = try await resolver.resolve(MediaRef(type: .movie, title: "Crash", year: 2004))
            }
            await #expect(throws: ResolutionError.notFound) {
                _ = try await resolver.resolve(MediaRef(type: .movie, title: "Heat", year: 1986))
            }
        }
    }

    @Test("CAT-003: an ISBN-10 and its ISBN-13 resolve to the same title")
    func isbnForms() async throws {
        try await withMigratedStores { stores in
            // A synthetic ISBN-13 per run, so runs never collide on the unique index.
            let digits = String(format: "%09d", Int.random(in: 0 ..< 1_000_000_000))
            let isbn10 = digits + isbn10Check(digits)
            let isbn13 = try #require(ISBN.normalize(isbn10))
            let fake = FakeCatalog()
            fake.stubTitle(CatalogTitle(
                hit: CatalogHit(
                    type: .book, title: "A Book", originalTitle: nil, year: 1965, posterURL: nil, overview: nil,
                    byline: nil, ids: ExternalIDs(isbn: isbn13, openLibrary: uniqueID("OL")), isAnime: false
                ),
                status: nil, runtimeMinutes: nil
            ))
            let resolver = TitleResolver(stores: stores, catalogs: FakeCatalog.providers(fake))
            let viaThirteen = try await resolver.resolve(MediaRef(type: .book, ids: ExternalIDs(isbn: isbn13)))
            let viaTen = try await resolver.resolve(MediaRef(
                type: .book,
                ids: ExternalIDs(isbn: ISBN.normalize(isbn10))
            ))
            #expect(viaThirteen.id == viaTen.id)
        }
    }

    @Test("CAT-009: mapped anime cours resolve to one TMDB show; unmapped stays separate")
    func animeMapping() async throws {
        try await withMigratedStores { stores in
            let fake = FakeCatalog()
            let tmdb = uniqueID("tmdb")
            let (cour1, cour2, unmapped) = (uniqueID("al"), uniqueID("al"), uniqueID("al"))
            fake.stubTitle(CatalogTitle(
                hit: CatalogHit(
                    type: .show, title: "Long Anime", originalTitle: nil, year: 2013, posterURL: nil,
                    overview: nil, byline: nil, ids: ExternalIDs(tmdb: tmdb), isAnime: false
                ),
                status: .ended, runtimeMinutes: 24
            ))
            fake.stubTitle(CatalogTitle(
                hit: CatalogHit(
                    type: .show, title: "Long Anime: Part 2 (AniList only)", originalTitle: nil, year: 2014,
                    posterURL: nil, overview: nil, byline: nil, ids: ExternalIDs(anilist: unmapped), isAnime: true
                ),
                status: .ended, runtimeMinutes: 24
            ))
            try await stores.animeMappings.upsert(AnimeMapping(anilist: cour1, tmdb: tmdb, tmdbSeason: 1))
            try await stores.animeMappings.upsert(AnimeMapping(anilist: cour2, tmdb: tmdb, tmdbSeason: 2))
            let resolver = TitleResolver(stores: stores, catalogs: FakeCatalog.providers(fake))

            let first = try await resolver.resolve(MediaRef(type: .show, ids: ExternalIDs(anilist: cour1)))
            let second = try await resolver.resolve(MediaRef(type: .show, ids: ExternalIDs(anilist: cour2)))
            let separate = try await resolver.resolve(MediaRef(type: .show, ids: ExternalIDs(anilist: unmapped)))
            #expect(first.id == second.id)
            #expect(first.isAnime)
            #expect(separate.id != first.id)
        }
    }

    @Test("CAT-006: a show's episodes hydrate once, serve from Postgres, and refresh after the window")
    func episodeHydration() async throws {
        try await withMigratedStores { stores in
            let fake = FakeCatalog()
            let tmdb = uniqueID("tmdb")
            let show = Title(type: .show, title: "Dormant Show", year: 2010, ids: ExternalIDs(tmdb: tmdb))
            try await stores.titles.insert(show, status: .ended, runtimeMinutes: nil)
            let longAgo = Date(timeIntervalSince1970: 1_300_000_000)
            fake.stubEpisodes(tmdb, CatalogEpisodes(status: .ended, episodes: [
                CatalogEpisode(
                    season: 1,
                    episode: 1,
                    name: "Pilot",
                    airsAt: longAgo,
                    runtimeMinutes: 50,
                    tmdbEpisodeID: nil
                ),
            ]))
            let clock = TestClock(Date())
            var service = CatalogService(stores: stores, catalogs: FakeCatalog.providers(fake))
            service.now = { clock.now }

            #expect(try await service.detail(show.id).episodes?.count == 1)
            #expect(try await service.detail(show.id).episodes?.count == 1)
            #expect(fake.callCount("episodes") == 1, "second request served from Postgres")

            fake.stubEpisodes(tmdb, CatalogEpisodes(status: .returning, episodes: [
                CatalogEpisode(
                    season: 1,
                    episode: 1,
                    name: "Pilot",
                    airsAt: longAgo,
                    runtimeMinutes: 50,
                    tmdbEpisodeID: nil
                ),
                CatalogEpisode(
                    season: 2,
                    episode: 1,
                    name: "Revival",
                    airsAt: nil,
                    runtimeMinutes: 50,
                    tmdbEpisodeID: nil
                ),
            ]))
            clock.advance(by: CatalogService.dormantStaleness + 60)
            let refreshed = try await service.detail(show.id)
            #expect(fake.callCount("episodes") == 2)
            #expect(refreshed.episodes?.map(\.season) == [1, 2])
            #expect(refreshed.status == .returning)
        }
    }

    @Test("CAT-004: search answers DTOs; a provider outage is 502, not 500; type is required")
    func searchRoute() async throws {
        try await withMigratedStores { stores in
            let fake = FakeCatalog()
            fake.stubSearch(
                "matrix",
                [movie("The Matrix", year: 1999, ids: ExternalIDs(tmdb: "603", imdb: "tt0133093")).hit]
            )
            let (_, token) = try await signedInUser(stores)
            let auth = AuthService(stores: stores, apple: UntouchedAppleVerifier(), magicLinks: nil)
            let app = try Application(router: buildRouter(
                stores: stores, auth: auth, catalog: CatalogService(
                    stores: stores,
                    catalogs: FakeCatalog.providers(fake)
                )
            ))
            try await app.test(.router) { client in
                let headers: HTTPFields = [.authorization: "Bearer \(token)"]
                try await client
                    .execute(uri: "/v1/search?q=matrix&type=movie", method: .get, headers: headers) { response in
                        #expect(response.status == .ok)
                        let body = String(buffer: response.body)
                        #expect(body.contains(#""tmdb" : "603""#) || body.contains(#""tmdb":"603""#))
                        #expect(!body.contains("poster_path") && !body.contains("release_date"))
                        #expect(!body.contains("status") && !body.contains("rating"), "no library fields on a hit")
                    }
                try await client.execute(uri: "/v1/search?q=matrix", method: .get, headers: headers) { response in
                    #expect(response.status == .badRequest)
                }
                fake.fail(with: ProviderError(provider: "tmdb", kind: .unavailable))
                try await client
                    .execute(uri: "/v1/search?q=matrix&type=movie", method: .get, headers: headers) { response in
                        #expect(response.status == .badGateway)
                        #expect(String(buffer: response.body).contains("provider_unavailable"))
                    }
            }
        }
    }
}

struct CountRow: Decodable {
    let count: Int
}

/// A clock tests move by hand.
final class TestClock: @unchecked Sendable {
    // @unchecked: test-only; `lock` guards `value`.
    private let lock = NSLock()
    private var value: Date
    init(_ start: Date) {
        value = start
    }

    var now: Date {
        lock.withLock { value }
    }

    func advance(by seconds: TimeInterval) {
        lock.withLock { value.addTimeInterval(seconds) }
    }
}

/// ISBN-10 check character for nine digits.
func isbn10Check(_ nine: String) -> String {
    let sum = nine.enumerated().reduce(0) { $0 + ($1.element.wholeNumberValue ?? 0) * (10 - $1.offset) }
    let check = (11 - sum % 11) % 11
    return check == 10 ? "X" : String(check)
}
