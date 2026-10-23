import AaruCore
import Foundation
import Testing
@testable import aaru

@Suite("Board posts on a title (BOARD-001)", .serialized)
struct BoardTitleTests {
    @Test("BOARD-001: a title page lists friends' posts about it, newest first")
    func titlePosts() async throws {
        try await LibraryHarness.run { env in
            let mine = try await claimHandle(env)
            let ana = try await friend(env, of: mine)
            let (_, stranger) = try await signedInUser(env.stores)
            _ = try await env.send(.put, "/v1/me/profile", json: ["handle": freshHandle()], token: stranger)
            let tmdb = env.stubMovie("Dune")
            let ref: [String: Any] = ["type": "movie", "ids": ["tmdb": tmdb]]

            func post(_ body: String, about: Bool, token: String?) async throws -> String {
                var json: [String: Any] = ["body": body]
                if about {
                    json["title"] = ref
                }
                let reply = try await env.send(.post, "/v1/board/posts", json: json, token: token)
                #expect(reply.status == .created, "\(reply.text)")
                return try #require(reply.json()["id"] as? String)
            }
            let anasFree = try await post("free", about: false, token: ana.token)
            _ = try await post("stranger", about: true, token: stranger)
            let first = try await post("ana on dune", about: true, token: ana.token)
            let second = try await post("my dune", about: true, token: nil)

            let detail = try await env.send(.get, "/v1/board/posts/\(first)").json()
            let titleID = try #require((detail["title"] as? [String: Any])?["id"] as? String)

            let reply = try await env.send(.get, "/v1/titles/\(titleID)/posts")
            #expect(reply.status == .ok, "\(reply.text)")
            let ids = try (reply.json()["items"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
            #expect(ids == [second, first])
            #expect(!ids.contains(anasFree))

            let one = try await env.send(.get, "/v1/titles/\(titleID)/posts?limit=1")
            #expect(try (one.json()["items"] as? [Any])?.count == 1)
        }
    }
}
