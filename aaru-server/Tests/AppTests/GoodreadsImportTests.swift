import AaruCore
import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
@testable import aaru

/// IMP-020: a Goodreads export matches more books, and brings its reviews, owned copies and
/// "did not finish" shelves. Stub catalog, real Postgres.
@Suite("Goodreads import", .serialized)
struct GoodreadsImportTests {
    let flow = ImportFlowTests()

    /// A book Open Library knows by its work id only (no ISBN), found by a title + author search.
    func stubBook(_ env: LibraryHarness, _ title: String, year: Int, byline: String, query: String) -> CatalogHit {
        let hit = CatalogHit(
            type: .book, title: title, originalTitle: nil, year: year, posterURL: nil, overview: nil,
            byline: byline, ids: ExternalIDs(openLibrary: uniqueID("OL")), isAnime: false
        )
        env.fake.stubTitle(CatalogTitle(hit: hit, status: nil, runtimeMinutes: nil))
        env.fake.stubSearch(query, [hit])
        return hit
    }

    func items(_ env: LibraryHarness) async throws -> [String: [String: Any]] {
        let items = try #require(try await env.send(.get, "/v1/library/sync").json()["items"] as? [[String: Any]])
        return Dictionary(items.map { (($0["title"] as? [String: Any])?["title"] as? String ?? "", $0) }) { first, _ in
            first
        }
    }

    func outcomes(_ planned: [String: Any]) -> [String]? {
        (planned["rows"] as? [[String: Any]])?.compactMap { $0["outcome"] as? String }
    }

    @Test("An ISBN Open Library does not know falls back to title + author, without the series suffix")
    func unknownISBNFallsBackToTitleAndAuthor() async throws {
        try await LibraryHarness.run { env in
            let isbn = try flow.isbn13()
            _ = stubBook(
                env,
                "Leviathan Wakes",
                year: 2011,
                byline: "James S. A. Corey",
                query: "Leviathan Wakes James S.A. Corey"
            )
            let csv = #"""
            Book Id,Title,Author,ISBN13,My Rating,Exclusive Shelf,Bookshelves,Original Publication Year
            1,"Leviathan Wakes (The Expanse, #1)",James S.A. Corey,"=""\#(isbn)""",5,read,read,2011
            """#
            let id = try #require(try await flow.upload(env, csv, source: "goodreads").json()["id"] as? String)
            let planned = try await flow.plan(env, id)
            #expect(outcomes(planned) == ["create"])
            _ = try await env.send(.post, "/v1/imports/\(id)/apply")
            let item = try #require(try await items(env)["Leviathan Wakes"])
            #expect(item["status"] as? String == "finished")
            #expect(item["rating"] as? Double == 10)
        }
    }

    @Test("A book one year off matches only with its author, and only when one hit qualifies")
    func yearToleranceNeedsTheAuthor() async throws {
        try await LibraryHarness.run { env in
            let near = uniqueID("Near")
            _ = stubBook(env, near, year: 2012, byline: "Ann Leckie", query: "\(near) Ann Leckie")
            let stranger = uniqueID("Stranger")
            _ = stubBook(env, stranger, year: 2012, byline: "Ann Leckie", query: "\(stranger) Someone Else")
            let far = uniqueID("Far")
            _ = stubBook(env, far, year: 2013, byline: "Ann Leckie", query: "\(far) Ann Leckie")
            let twice = uniqueID("Twice")
            let editions = [2010, 2012].map { year in
                CatalogHit(
                    type: .book, title: twice, originalTitle: nil, year: year, posterURL: nil, overview: nil,
                    byline: "Ann Leckie", ids: ExternalIDs(openLibrary: uniqueID("OL")), isAnime: false
                )
            }
            env.fake.stubSearch("\(twice) Ann Leckie", editions)
            let csv = """
            Title,Author,Exclusive Shelf,Original Publication Year
            \(near),Ann Leckie,read,2011
            \(stranger),Someone Else,read,2011
            \(far),Ann Leckie,read,2011
            \(twice),Ann Leckie,read,2011
            """
            let id = try #require(try await flow.upload(env, csv, source: "goodreads").json()["id"] as? String)
            let planned = try await flow.plan(env, id)
            #expect(outcomes(planned) == ["create", "unmatched", "unmatched", "unmatched"])
            let reasons = (planned["rows"] as? [[String: Any]])?.map { $0["reason"] as? String }
            #expect(reasons?[3]?.contains("More than one") == true, "two hits one year off are never a guess")
        }
    }

    @Test("A did-not-finish shelf is dropped, and the shelf still becomes a list")
    func didNotFinishIsDropped() async throws {
        try await LibraryHarness.run { env in
            let isbn = try flow.isbn13()
            let title = uniqueID("Gave Up")
            env.fake.stubTitle(flow.book(title, isbn: isbn, year: 2001))
            let csv = #"""
            Title,Author,ISBN13,Exclusive Shelf,Bookshelves
            \#(title),An Author,"=""\#(isbn)""",DNF,dnf
            """#
            let id = try #require(try await flow.upload(env, csv, source: "goodreads").json()["id"] as? String)
            #expect(try outcomes(await flow.plan(env, id)) == ["create"])
            _ = try await env.send(.post, "/v1/imports/\(id)/apply")
            #expect(try await items(env)[title]?["status"] as? String == "dropped")
            let lists = try await env.send(.get, "/v1/lists").json()
            #expect((lists["items"] as? [[String: Any]])?.contains { $0["name"] as? String == "dnf" } == true)
        }
    }

    @Test("The review becomes notes and an owned copy marks it owned, filling only what is empty")
    func reviewAndOwnedFillEmptyOnly() async throws {
        try await LibraryHarness.run { env in
            let (fresh, noted, bare) = try (flow.isbn13(), flow.isbn13(), flow.isbn13())
            let names = (uniqueID("Fresh"), uniqueID("Noted"), uniqueID("Bare"))
            env.fake.stubTitle(flow.book(names.0, isbn: fresh, year: 2001))
            env.fake.stubTitle(flow.book(names.1, isbn: noted, year: 2002))
            env.fake.stubTitle(flow.book(names.2, isbn: bare, year: 2003))
            for isbn in [noted, bare] {
                _ = try await env.send(.post, "/v1/library/items", json: [
                    "mediaRef": ["type": "book", "ids": ["isbn": isbn]], "status": "finished",
                ])
            }
            let notedID = try #require(try await items(env)[names.1]?["id"] as? String)
            _ = try await env.send(.patch, "/v1/library/items/\(notedID)", json: ["notes": "Mine"])

            let csv = #"""
            Title,Author,ISBN13,Exclusive Shelf,My Review,Private Notes,Owned Copies
            \#(names.0),A,"=""\#(fresh)""",read,"Loved it.<br/><br/>Tom &amp; Jerry",,1
            \#(names.1),A,"=""\#(noted)""",read,Theirs,,0
            \#(names.2),A,"=""\#(bare)""",read,,Only private,2
            """#
            let id = try #require(try await flow.upload(env, csv, source: "goodreads").json()["id"] as? String)
            #expect(try outcomes(await flow.plan(env, id)) == ["create", "skip", "update"])
            _ = try await env.send(.post, "/v1/imports/\(id)/apply")
            let library = try await items(env)
            #expect(library[names.0]?["notes"] as? String == "Loved it.\n\nTom & Jerry")
            #expect(library[names.0]?["isOwned"] as? Bool == true)
            #expect(library[names.1]?["notes"] as? String == "Mine", "notes the library has stay")
            #expect(library[names.1]?["isOwned"] as? Bool != true, "0 owned copies sets nothing")
            #expect(library[names.2]?["notes"] as? String == "Only private", "private notes when there is no review")
            #expect(library[names.2]?["isOwned"] as? Bool == true)
        }
    }

    @Test("Re-importing without owned copies never clears the owned mark")
    func ownedIsNeverCleared() {
        let row = ImportRow(type: .book, title: "Owned", ids: ExternalIDs(), status: .finished, lists: [])
        let state = ImportItemState(
            itemID: LibraryItemID(),
            fields: ItemFields(
                status: .finished, rating: nil, notes: nil, isOwned: true,
                finishedAt: nil, bookPage: nil, bookPercent: nil
            ),
            statusByHand: false, watched: []
        )
        let decision = ImportService.decide(row, item: state)
        #expect(decision.outcome == .skip)
        #expect(decision.fields == nil)
    }
}
