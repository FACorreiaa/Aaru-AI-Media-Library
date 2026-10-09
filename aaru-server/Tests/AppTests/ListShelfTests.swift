import AaruCore
import Foundation
import Testing
@testable import aaru

@Suite("Lists and shelves (M6)", .serialized)
struct ListShelfTests {
    func titleIDs(_ reply: LibraryHarness.Reply) throws -> [String] {
        try (reply.json()["titles"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
    }

    @Test("LST-001: every list route is user-scoped; visibility can only be private")
    func listsAreScoped() async throws {
        try await LibraryHarness.run { env in
            let created = try await env.send(.post, "/v1/lists", json: ["name": "Noir"])
            let id = try #require(try created.json()["id"] as? String)
            #expect(try await env.send(.post, "/v1/lists", json: ["name": "  "]).status == .unprocessableContent)

            let (_, other) = try await signedInUser(env.stores)
            #expect(try await env.send(.get, "/v1/lists/\(id)", token: other).status == .notFound)
            #expect(try await env.send(.patch, "/v1/lists/\(id)", json: ["name": "Mine"], token: other)
                .status == .notFound)
            #expect(try await env.send(.delete, "/v1/lists/\(id)", token: other).status == .notFound)
            let otherLists = try await env.send(.get, "/v1/lists", token: other).json()
            #expect((otherLists["items"] as? [Any])?.isEmpty == true)

            // The database itself refuses anything but private.
            await #expect(throws: (any Error).self) {
                try await withSQL { sql in
                    try await sql
                        .raw(
                            "UPDATE lists SET visibility = 'public' WHERE id = \(bind: #require(UUID(uuidString: id)))"
                        )
                        .run()
                }
            }
        }
    }

    @Test("LST-002: a list holds titles outside the library; order survives a round trip; undo works")
    func membership() async throws {
        try await LibraryHarness.run { env in
            let id = try #require(try await env.send(.post, "/v1/lists", json: ["name": "Watch with Ana"])
                .json()["id"] as? String)
            let first = env.stubMovie("Chinatown")
            let second = env.stubMovie("Vertigo")
            for tmdb in [first, second, first] {
                _ = try await env.send(
                    .post,
                    "/v1/lists/\(id)/items",
                    json: ["mediaRef": ["type": "movie", "ids": ["tmdb": tmdb]]]
                )
            }
            let detail = try await env.send(.get, "/v1/lists/\(id)")
            let ids = try titleIDs(detail)
            #expect(ids.count == 2, "adding a member again changes nothing")

            let library = try await env.send(.get, "/v1/library/items").json()
            #expect((library["items"] as? [Any])?.isEmpty == true, "no library item was created")

            let reordered = try await env.send(.put, "/v1/lists/\(id)/order", json: ["titleIds": Array(ids.reversed())])
            #expect(try titleIDs(reordered) == Array(ids.reversed()))
            #expect(try titleIDs(await env.send(.get, "/v1/lists/\(id)")) == Array(ids.reversed()))
            #expect(try await env.send(.put, "/v1/lists/\(id)/order", json: ["titleIds": [ids[0]]]).status
                == .unprocessableContent)

            // Removing a member is journaled and undoable.
            _ = try await env.send(.delete, "/v1/lists/\(id)/items/\(ids[0])")
            #expect(try titleIDs(await env.send(.get, "/v1/lists/\(id)")) == [ids[1]])
            let action = try #require(
                try (await env.send(.get, "/v1/actions?limit=1").json()["items"] as? [[String: Any]])?
                    .first?["id"] as? String
            )
            _ = try await env.send(.post, "/v1/actions/\(action)/undo")
            #expect(try Set(titleIDs(await env.send(.get, "/v1/lists/\(id)"))) == Set(ids))
        }
    }

    @Test("SHF-001: a shelf is a query — a new matching title appears without writing the shelf")
    func shelfIsAQuery() async throws {
        try await LibraryHarness.run { env in
            let shelf = try await env.send(.post, "/v1/shelves", json: [
                "name": "Unwatched films", "filter": ["type": "movie", "status": "wishlist"],
            ]).json()
            let shelfID = try #require(shelf["id"] as? String)
            for name in ["One", "Two"] {
                _ = try await env.add("movie", tmdb: env.stubMovie(name))
            }
            let count = { () async throws -> Int in
                try (await env.send(.get, "/v1/shelves/\(shelfID)/items").json()["items"] as? [Any])?.count ?? -1
            }
            #expect(try await count() == 2)
            _ = try await env.add("movie", tmdb: env.stubMovie("Three"))
            #expect(try await count() == 3)
            _ = try await env.add("show", tmdb: env.stubShow("Not a movie", status: .ended))
            #expect(try await count() == 3)

            let (_, other) = try await signedInUser(env.stores)
            #expect(try await env.send(.get, "/v1/shelves/\(shelfID)/items", token: other).status == .notFound)
        }
    }

    @Test("SHF-002: a shelf and its equivalent filter return identical payloads")
    func shelfMatchesFilter() async throws {
        try await LibraryHarness.run { env in
            let listID = try #require(try await env.send(.post, "/v1/lists", json: ["name": "Picks"])
                .json()["id"] as? String)
            for name in ["A", "B", "C"] {
                let tmdb = env.stubMovie(name)
                _ = try await env.add("movie", tmdb: tmdb)
                if name != "B" {
                    _ = try await env.send(
                        .post,
                        "/v1/lists/\(listID)/items",
                        json: ["mediaRef": ["type": "movie", "ids": ["tmdb": tmdb]]]
                    )
                }
            }
            let shelfID = try #require(try await env.send(.post, "/v1/shelves", json: [
                "name": "Picks I own nothing of", "filter": ["type": "movie", "owned": false, "list": listID],
            ]).json()["id"] as? String)
            let viaShelf = try await env.send(.get, "/v1/shelves/\(shelfID)/items?limit=10")
            let viaFilter = try await env.send(.get, "/v1/library/items?type=movie&owned=false&list=\(listID)&limit=10")
            #expect(viaShelf.status == .ok)
            #expect(viaShelf.body == viaFilter.body)
            #expect(try (viaShelf.json()["items"] as? [Any])?.count == 2)
        }
    }
}
