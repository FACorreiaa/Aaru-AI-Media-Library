import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
@testable import aaru

@Suite("A title page for any title (LIB-006)")
struct TitlePreviewTests {
    @Test("Resolving a hit not in the library returns its page and adds nothing")
    func notInLibrary() async throws {
        try await LibraryHarness.run { env in
            let tmdb = env.stubMovie("Dune")
            let reply = try await env.send(.post, "/v1/titles/resolve", json: [
                "type": "movie", "ids": ["tmdb": tmdb],
            ])
            #expect(reply.status == .ok)
            let body = try reply.json()
            let title = try #require(body["title"] as? [String: Any])
            #expect(title["title"] as? String == "Dune")
            #expect(body["libraryItemId"] == nil)

            let library = try await env.send(.get, "/v1/library/items").json()
            #expect((library["items"] as? [[String: Any]])?.isEmpty == true, "resolving is not adding")
            let journal = try await env.send(.get, "/v1/actions?limit=5").json()
            #expect((journal["items"] as? [[String: Any]])?.isEmpty == true, "nothing journaled")
        }
    }

    @Test("A title in the library answers with its item, so the client opens that page")
    func inLibrary() async throws {
        try await LibraryHarness.run { env in
            let tmdb = env.stubMovie("Arrival")
            let itemID = try await env.add("movie", tmdb: tmdb)
            let body = try await env.send(.post, "/v1/titles/resolve", json: [
                "type": "movie", "ids": ["tmdb": tmdb],
            ]).json()
            #expect(body["libraryItemId"] as? String == itemID)
        }
    }

    @Test("A ref no provider knows is a 422, as an add of it is")
    func unknown() async throws {
        try await LibraryHarness.run { env in
            let reply = try await env.send(.post, "/v1/titles/resolve", json: [
                "type": "movie", "ids": ["tmdb": "999999999"],
            ])
            #expect(reply.status == .unprocessableContent)
        }
    }
}
