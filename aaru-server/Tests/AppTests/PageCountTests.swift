import AaruCore
import Foundation
import Testing
@testable import aaru

@Suite("Book page counts (APP-017)", .serialized)
struct PageCountTests {
    func book(_ name: String, isbn: String, pages: Int?) -> CatalogTitle {
        CatalogTitle(
            hit: CatalogHit(
                type: .book, title: name, originalTitle: nil, year: 1965, posterURL: nil, overview: nil,
                byline: "Frank Herbert", ids: ExternalIDs(isbn: isbn), isAnime: false, pageCount: pages
            ),
            status: nil, runtimeMinutes: nil
        )
    }

    @Test("A book added carries its page count; one stored without it is filled by the refresher")
    func pageCounts() async throws {
        try await LibraryHarness.run { env in
            let dune = "97804411\(Int.random(in: 10000 ... 99999))"
            env.fake.stubTitle(book("Dune", isbn: dune, pages: 412))
            let added = try await env.send(.post, "/v1/library/items", json: [
                "mediaRef": ["type": "book", "ids": ["isbn": dune]], "status": "in_progress",
            ]).json()
            #expect((added["title"] as? [String: Any])?["pageCount"] as? Int == 412)

            let emma = "97801414\(Int.random(in: 10000 ... 99999))"
            env.fake.stubTitle(book("Emma", isbn: emma, pages: nil))
            let reply = try await env.send(.post, "/v1/library/items", json: [
                "mediaRef": ["type": "book", "ids": ["isbn": emma]], "status": "in_progress",
            ]).json()
            let id = try #require(reply["id"] as? String)
            #expect((reply["title"] as? [String: Any])?["pageCount"] == nil)

            let later = FakeCatalog()
            later.stubTitle(book("Emma", isbn: emma, pages: 474))
            var refresher = CatalogRefresher(
                stores: env.stores,
                catalog: CatalogService(stores: env.stores, catalogs: FakeCatalog.providers(later))
            )
            refresher.pageCountLimit = 100_000
            #expect(try await refresher.fillPageCounts() >= 1)
            let item = try await env.send(.get, "/v1/library/items/\(id)").json()
            #expect((item["title"] as? [String: Any])?["pageCount"] as? Int == 474)

            let again = try await env.stores.titles.booksMissingPageCount(retryAfter: Date(), limit: 100_000)
            #expect(!again.contains { $0.ids.isbn == emma }, "filled, so never asked again")
        }
    }
}
