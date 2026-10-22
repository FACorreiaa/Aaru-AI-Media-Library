import AaruCore
import Foundation
import Testing
@testable import aaru

@Suite("Board posts over HTTP (BRD-001)", .serialized)
struct BoardTests {
    private func createPost(
        _ env: LibraryHarness, _ body: String, token: String? = nil
    ) async throws -> String {
        let reply = try await env.send(.post, "/v1/board/posts", json: ["body": body], token: token)
        #expect(reply.status == .created, "\(reply.text)")
        return try #require(reply.json()["id"] as? String)
    }

    private func ids(_ reply: LibraryHarness.Reply) throws -> [String] {
        try (reply.json()["items"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
    }

    @Test("BRD-001: friends see posts, strangers and ex-friends get the missing 404")
    func visibility() async throws {
        try await LibraryHarness.run { env in
            let mine = try await claimHandle(env)
            let ana = try await friend(env, of: mine)
            let post = try await createPost(env, "hello", token: ana.token)

            let feed = try await env.send(.get, "/v1/board")
            #expect(feed.status == .ok)
            #expect(try ids(feed).contains(post))

            let (_, stranger) = try await signedInUser(env.stores)
            let hidden = try await env.send(.get, "/v1/board/posts/\(post)", token: stranger)
            let missing = try await env.send(.get, "/v1/board/posts/\(UUID())", token: stranger)
            #expect(hidden.status == .notFound)
            #expect(hidden.text == missing.text)
            let malformed = try await env.send(.get, "/v1/board/posts/nope", token: stranger)
            #expect(malformed.status == .notFound)

            #expect(try await env.send(.get, "/v1/board/posts/\(post)").status == .ok)
            #expect(try await env.send(.delete, "/v1/social/friends/\(ana.id)").status == .noContent)
            #expect(try await env.send(.get, "/v1/board/posts/\(post)").status == .notFound)
            #expect(try await !ids(env.send(.get, "/v1/board")).contains(post))
        }
    }

    @Test("BRD-001: a blocked author's posts vanish")
    func blocked() async throws {
        try await LibraryHarness.run { env in
            let mine = try await claimHandle(env)
            let ana = try await friend(env, of: mine)
            let post = try await createPost(env, "hello", token: ana.token)
            #expect(try await env.send(.put, "/v1/social/blocks/\(ana.id)").status.code < 300)
            #expect(try await env.send(.get, "/v1/board/posts/\(post)").status == .notFound)
            #expect(try await !ids(env.send(.get, "/v1/board")).contains(post))
        }
    }

    @Test("BRD-001: post validation")
    func validation() async throws {
        try await LibraryHarness.run { env in
            let noHandle = try await env.send(.post, "/v1/board/posts", json: ["body": "hi"])
            #expect(noHandle.status == .unprocessableContent)
            #expect(try noHandle.json()["code"] as? String == "handle_required")

            _ = try await claimHandle(env)
            let blank = try await env.send(.post, "/v1/board/posts", json: ["body": "   "])
            #expect(blank.status == .unprocessableContent)
            let long = try await env.send(.post, "/v1/board/posts", json: ["body": String(repeating: "a", count: 4001)])
            #expect(long.status == .unprocessableContent)
            let lonely = try await env.send(.post, "/v1/board/posts", json: ["body": "hi", "rating": 8])
            #expect(lonely.status == .unprocessableContent)
            let details = try #require(lonely.json()["details"] as? [String: Any])
            #expect(details["rating"] != nil)

            let created = try await env.send(.post, "/v1/board/posts", json: ["body": " fine "])
            #expect(created.status == .created)
            let json = try created.json()
            #expect(json["body"] as? String == "fine")
            #expect(json["mine"] as? Bool == true)
            #expect(json["upvotes"] as? Int == 0)
            #expect(json["veiled"] as? Bool == false)
        }
    }

    @Test("BRD-001: only the author edits or deletes")
    func authorOnly() async throws {
        try await LibraryHarness.run { env in
            let mine = try await claimHandle(env)
            let ana = try await friend(env, of: mine)
            let post = try await createPost(env, "mine")

            let forbidden = try await env.send(
                .patch, "/v1/board/posts/\(post)", json: ["body": "hijack"], token: ana.token
            )
            #expect(forbidden.status == .forbidden)
            #expect(try await env.send(.delete, "/v1/board/posts/\(post)", token: ana.token).status == .forbidden)

            let edited = try await env.send(.patch, "/v1/board/posts/\(post)", json: ["body": "better"])
            #expect(edited.status == .ok)
            let json = try edited.json()
            #expect(json["body"] as? String == "better")
            #expect(json["editedAt"] != nil)

            #expect(try await env.send(.delete, "/v1/board/posts/\(post)").status == .noContent)
            #expect(try await env.send(.get, "/v1/board/posts/\(post)").status == .notFound)
            #expect(try await env.send(.delete, "/v1/board/posts/\(post)", token: ana.token).status == .notFound)
        }
    }

    @Test("BRD-001: top this week")
    func top() async throws {
        try await LibraryHarness.run { env in
            let mine = try await claimHandle(env)
            let ana = try await friend(env, of: mine)
            let quiet = try await createPost(env, "quiet")
            let loud = try await createPost(env, "loud", token: ana.token)
            let mid = try await createPost(env, "mid")
            let anaID = try #require(UserID(uuidString: ana.id))
            try await env.stores.boards.setUpvote(post: #require(UUID(uuidString: loud)), user: env.userID, on: true)
            try await env.stores.boards.setUpvote(post: #require(UUID(uuidString: loud)), user: anaID, on: true)
            try await env.stores.boards.setUpvote(post: #require(UUID(uuidString: mid)), user: anaID, on: true)

            let reply = try await env.send(.get, "/v1/board?sort=top")
            #expect(reply.status == .ok)
            #expect(try ids(reply) == [loud, mid, quiet])
            let first = try #require(reply.json()["items"] as? [[String: Any]]).first
            #expect(first?["upvotes"] as? Int == 2)
            #expect(first?["upvotedByMe"] as? Bool == true)

            let paged = try await env.send(.get, "/v1/board?limit=2")
            #expect(try ids(paged) == [mid, loud])
        }
    }
}
