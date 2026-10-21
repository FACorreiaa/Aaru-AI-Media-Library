import AaruCore
import Foundation
import Testing
@testable import aaru

@Suite("Title genres (CAT-018)", .serialized)
struct GenreTests {
    func catalogTitle(
        _ type: MediaType, _ name: String, ids: ExternalIDs, anime: Bool = false, genres: [String]
    ) -> CatalogTitle {
        CatalogTitle(
            hit: CatalogHit(
                type: type, title: name, originalTitle: nil, year: 2020, posterURL: nil, overview: nil,
                byline: nil, ids: ids, isAnime: anime
            ),
            status: nil, runtimeMinutes: nil, genres: genres
        )
    }

    @Test("CAT-018: a hydrated movie, show and anime each carry their provider's genres")
    func storedAtHydration() async throws {
        try await withMigratedStores { stores in
            let fake = FakeCatalog()
            let movie = ExternalIDs(tmdb: uniqueID("tmdb"))
            let show = ExternalIDs(tmdb: uniqueID("tmdb"))
            let anime = ExternalIDs(anilist: uniqueID("al"))
            fake.stubTitle(catalogTitle(.movie, "Arrival", ids: movie, genres: ["Drama", "Science Fiction"]))
            fake.stubTitle(catalogTitle(.show, "Severance", ids: show, genres: ["Drama", "Mystery"]))
            fake.stubTitle(catalogTitle(.show, "Frieren", ids: anime, anime: true, genres: ["Adventure", "Fantasy"]))
            let resolver = TitleResolver(stores: stores, catalogs: FakeCatalog.providers(fake))

            let stored = try await [
                resolver.resolve(MediaRef(type: .movie, ids: movie)),
                resolver.resolve(MediaRef(type: .show, ids: show)),
                resolver.resolve(MediaRef(type: .show, ids: anime)),
            ]
            var genres: [[String]] = []
            for title in stored {
                try await genres.append(stores.titles.genres(title.id))
            }
            #expect(genres == [["Drama", "Science Fiction"], ["Drama", "Mystery"], ["Adventure", "Fantasy"]])
        }
    }

    @Test("CAT-018: the backfill fills tracked titles once, skips books, never overwrites, and backs off")
    func backfill() async throws {
        try await LibraryHarness.run { env in
            // Added before genres were stored: the harness's stubs carry none.
            let heatTMDB = env.stubMovie("Heat")
            let heat = try await env.add("movie", tmdb: heatTMDB)
            let silentTMDB = env.stubMovie("Silent")
            let silent = try await env.add("movie", tmdb: silentTMDB)
            let isbn = uniqueID("978")
            env.fake.stubTitle(catalogTitle(.book, "Emma", ids: ExternalIDs(isbn: isbn), genres: []))
            let bookReply = try await env.send(.post, "/v1/library/items", json: [
                "mediaRef": ["type": "book", "ids": ["isbn": isbn]],
            ])
            let book = try #require(try bookReply.json()["id"] as? String)

            // The provider now lists Heat's genres; it still has none for Silent.
            let later = FakeCatalog()
            later.stubTitle(catalogTitle(.movie, "Heat", ids: ExternalIDs(tmdb: heatTMDB), genres: ["Crime"]))
            later.stubTitle(catalogTitle(.movie, "Silent", ids: ExternalIDs(tmdb: silentTMDB), genres: []))
            let now = Date()
            var refresher = CatalogRefresher(
                stores: env.stores,
                catalog: CatalogService(stores: env.stores, catalogs: FakeCatalog.providers(later))
            )
            refresher.now = { now }
            refresher.genreLimit = 100_000
            _ = try await refresher.fillGenres()

            let heatID = try await titleID(env, item: heat)
            let silentID = try await titleID(env, item: silent)
            #expect(try await env.stores.titles.genres(heatID) == ["Crime"])
            #expect(try await env.stores.titles.genres(silentID).isEmpty)

            let retry = now.addingTimeInterval(-CatalogRefresher.genresRetryAfter)
            let due = try await env.stores.titles.titlesMissingGenres(retryAfter: retry, limit: 100_000)
            #expect(!due.contains { $0.id == heatID || $0.id == silentID }, "stamped: not asked again this week")
            let nextWeek = try await env.stores.titles.titlesMissingGenres(
                retryAfter: now.addingTimeInterval(1), limit: 100_000
            )
            #expect(nextWeek.contains { $0.id == silentID } && !nextWeek.contains { $0.id == heatID })

            try await env.stores.titles.fillGenres(heatID, ["Drama"], attemptedAt: now)
            #expect(try await env.stores.titles.genres(heatID) == ["Crime"], "fill-empty-only")

            let bookID = try await titleID(env, item: book)
            #expect(!nextWeek.contains { $0.id == bookID }, "books have no genres to fill")
        }
    }

    private func titleID(_ env: LibraryHarness, item: String) async throws -> TitleID {
        let reply = try await env.send(.get, "/v1/library/items/\(item)")
        let title = try #require(try reply.json()["title"] as? [String: Any])
        let id = try #require(title["id"] as? String)
        return try #require(TitleID(uuidString: id))
    }
}
