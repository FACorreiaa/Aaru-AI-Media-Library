import Foundation
import Testing
@testable import aaru

@Suite("Board upvotes (BRD-001)", .serialized)
struct BoardUpvoteTests {
    private func createPost(_ env: LibraryHarness, _ body: String, token: String? = nil) async throws -> String {
        let reply = try await env.send(.post, "/v1/board/posts", json: ["body": body], token: token)
        #expect(reply.status == .created, "\(reply.text)")
        return try #require(reply.json()["id"] as? String)
    }

    private func upvotes(_ env: LibraryHarness, _ post: String) async throws -> Int {
        try await env.send(.get, "/v1/board/posts/\(post)").json()["upvotes"] as? Int ?? -1
    }

    @Test("BRD-001: upvote twice counts once; removing twice is fine")
    func idempotent() async throws {
        try await LibraryHarness.run { env in
            let mine = try await claimHandle(env)
            let ana = try await friend(env, of: mine)
            let post = try await createPost(env, "hello", token: ana.token)
            let path = "/v1/board/posts/\(post)/upvote"

            #expect(try await env.send(.put, path).status == .noContent)
            #expect(try await env.send(.put, path).status == .noContent)
            #expect(try await upvotes(env, post) == 1)
            let seen = try await env.send(.get, "/v1/board/posts/\(post)").json()
            #expect(seen["upvotedByMe"] as? Bool == true)

            #expect(try await env.send(.delete, path).status == .noContent)
            #expect(try await env.send(.delete, path).status == .noContent)
            #expect(try await upvotes(env, post) == 0)
        }
    }

    @Test("BRD-001: upvoting a hidden or deleted post is the missing 404")
    func hidden() async throws {
        try await LibraryHarness.run { env in
            let mine = try await claimHandle(env)
            let ana = try await friend(env, of: mine)
            let post = try await createPost(env, "hello", token: ana.token)
            let (_, stranger) = try await signedInUser(env.stores)
            let path = "/v1/board/posts/\(post)/upvote"

            let hidden = try await env.send(.put, path, token: stranger)
            let missing = try await env.send(.put, "/v1/board/posts/\(UUID())/upvote", token: stranger)
            #expect(hidden.status == .notFound)
            #expect(hidden.text == missing.text)
            #expect(try await env.send(.delete, path, token: stranger).status == .notFound)
            #expect(try await env.send(.get, "/v1/board/posts/\(post)/upvotes", token: stranger).status == .notFound)

            #expect(try await env.send(.delete, "/v1/board/posts/\(post)", token: ana.token).status == .noContent)
            #expect(try await env.send(.put, path).status == .notFound)
            #expect(try await env.send(.put, "/v1/board/posts/nope/upvote").status == .notFound)
        }
    }

    @Test("BRD-001: upvoters list hides blocked people")
    func upvotersHideBlocked() async throws {
        try await LibraryHarness.run { env in
            let mine = try await claimHandle(env)
            let ana = try await friend(env, of: mine)
            let bob = try await friend(env, of: mine)
            let cara = try await friend(env, of: mine)
            let post = try await createPost(env, "mine")
            for who in [ana, bob, cara] {
                let reply = try await env.send(.put, "/v1/board/posts/\(post)/upvote", token: who.token)
                #expect(reply.status == .noContent)
            }
            func handles() async throws -> Set<String> {
                let reply = try await env.send(.get, "/v1/board/posts/\(post)/upvotes")
                #expect(reply.status == .ok, "\(reply.text)")
                let items = try reply.json()["items"] as? [[String: Any]] ?? []
                return Set(items.compactMap { $0["handle"] as? String })
            }
            #expect(try await handles() == [ana.handle, bob.handle, cara.handle])

            // I blocked ana; cara blocked me.
            #expect(try await env.send(.put, "/v1/social/blocks/\(ana.id)").status.code < 300)
            #expect(try await env.send(.put, "/v1/social/blocks/\(env.userID)", token: cara.token).status.code < 300)
            #expect(try await handles() == [bob.handle])
        }
    }
}
