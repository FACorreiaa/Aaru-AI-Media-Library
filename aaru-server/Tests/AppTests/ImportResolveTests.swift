import AaruCore
import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
@testable import aaru

/// IMP-011: an unmatched row is matched by hand, before or after the plan is approved.
@Suite("Import row triage", .serialized)
struct ImportResolveTests {
    let flow = ImportFlowTests()

    /// A Goodreads file whose second row matches nothing, with a book stubbed that it meant.
    func upload(_ env: LibraryHarness) async throws -> (id: String, isbn: String) {
        let (known, meant) = try (flow.isbn13(), flow.isbn13())
        env.fake.stubTitle(flow.book("Dune", isbn: known, year: 1965))
        env.fake.stubTitle(flow.book("The Book It Meant", isbn: meant, year: 1999))
        let csv = #"""
        Book Id,Title,Author,ISBN13,My Rating,Exclusive Shelf,Bookshelves,Original Publication Year
        1,Dune,Frank Herbert,"=""\#(known)""",4,read,read,1965
        2,A Book Nobody Has,Nobody,"=""""",5,read,read,1999
        """#
        let id = try #require(try await flow.upload(env, csv, source: "goodreads").json()["id"] as? String)
        let planned = try await flow.plan(env, id)
        let outcomes = (planned["rows"] as? [[String: Any]])?.compactMap { $0["outcome"] as? String }
        #expect(outcomes == ["create", "unmatched"])
        return (id, meant)
    }

    func resolve(_ env: LibraryHarness, _ id: String, row: Int, isbn: String) async throws -> LibraryHarness.Reply {
        try await env.send(.post, "/v1/imports/\(id)/rows/\(row)/resolve", json: [
            "mediaRef": ["type": "book", "ids": ["isbn": isbn]],
        ])
    }

    func libraryItem(_ env: LibraryHarness, titled name: String) async throws -> [String: Any]? {
        try (await env.send(.get, "/v1/library/sync").json()["items"] as? [[String: Any]])?
            .first { ($0["title"] as? [String: Any])?["title"] as? String == name }
    }

    @Test("After approval, a resolved row is written at once with the source's status and rating")
    func afterApproval() async throws {
        try await LibraryHarness.run { env in
            let (id, isbn) = try await upload(env)
            let applied = try await env.send(.post, "/v1/imports/\(id)/apply").json()
            #expect(applied["state"] as? String == "partial")

            let reply = try await resolve(env, id, row: 1, isbn: isbn)
            #expect(reply.status == .ok)
            let body = try reply.json()
            let job = try #require(body["job"] as? [String: Any])
            #expect(job["state"] as? String == "succeeded", "nothing is left unmatched")
            #expect((job["stats"] as? [String: Int])?["unmatched"] == 0)
            #expect((job["stats"] as? [String: Int])?["created"] == 2)
            #expect((body["row"] as? [String: Any])?["outcome"] as? String == "create")

            let item = try #require(try await libraryItem(env, titled: "The Book It Meant"))
            #expect(item["status"] as? String == "finished")
            #expect(item["rating"] as? Double == 10)

            #expect(try await resolve(env, id, row: 1, isbn: isbn).status == .conflict, "matches once")
            #expect(try await resolve(env, id, row: 7, isbn: isbn).status == .notFound)

            let actions = try await env.send(.get, "/v1/actions?limit=1").json()
            let action = try #require((actions["items"] as? [[String: Any]])?.first)
            #expect((action["summary"] as? String)?.contains("by hand") == true)
            #expect(try await env.send(.post, "/v1/actions/\(action["id"] as? String ?? "")/undo").status == .ok)
            #expect(try await libraryItem(env, titled: "The Book It Meant") == nil, "the pick undoes on its own")
            #expect(try await libraryItem(env, titled: "Dune") != nil, "the rest of the import stays")
        }
    }

    @Test("Before approval, a resolved row joins the plan and is written with it")
    func beforeApproval() async throws {
        try await LibraryHarness.run { env in
            let (id, isbn) = try await upload(env)
            let body = try await resolve(env, id, row: 1, isbn: isbn).json()
            let job = try #require(body["job"] as? [String: Any])
            #expect(job["state"] as? String == "planned")
            #expect((job["stats"] as? [String: Int])?["unmatched"] == 0)
            #expect((body["row"] as? [String: Any])?["outcome"] as? String == "create")
            #expect(
                try await libraryItem(env, titled: "The Book It Meant") == nil,
                "nothing is written before approval"
            )

            let applied = try await env.send(.post, "/v1/imports/\(id)/apply").json()
            #expect(applied["state"] as? String == "succeeded")
            #expect((applied["stats"] as? [String: Int])?["created"] == 2)
            let item = try #require(try await libraryItem(env, titled: "The Book It Meant"))
            #expect(item["status"] as? String == "finished")
        }
    }

    @Test("A pick that is already on the shelf merges into it instead of adding a second item")
    func mergesIntoExisting() async throws {
        try await LibraryHarness.run { env in
            let (id, isbn) = try await upload(env)
            _ = try await env.send(.post, "/v1/library/items", json: [
                "mediaRef": ["type": "book", "ids": ["isbn": isbn]], "status": "wishlist",
            ])
            _ = try await env.send(.post, "/v1/imports/\(id)/apply")
            let body = try await resolve(env, id, row: 1, isbn: isbn).json()
            #expect((body["row"] as? [String: Any])?["outcome"] as? String == "update")
            let items = try await env.send(.get, "/v1/library/sync").json()["items"] as? [[String: Any]]
            #expect(items?.count { ($0["title"] as? [String: Any])?["title"] as? String == "The Book It Meant" } == 1)
            let item = try #require(try await libraryItem(env, titled: "The Book It Meant"))
            #expect(item["status"] as? String == "finished", "moved forward from plan to read")
            #expect(item["rating"] as? Double == 10)
        }
    }
}
