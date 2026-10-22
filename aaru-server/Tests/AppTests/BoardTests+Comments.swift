import Foundation
import Testing
@testable import aaru

@Suite("Board comments (BRD-001)", .serialized)
struct BoardCommentTests {
    private func createPost(_ env: LibraryHarness, _ body: String, token: String? = nil) async throws -> String {
        let reply = try await env.send(.post, "/v1/board/posts", json: ["body": body], token: token)
        #expect(reply.status == .created, "\(reply.text)")
        return try #require(reply.json()["id"] as? String)
    }

    private func comment(
        _ env: LibraryHarness, _ post: String, _ body: String, replyTo: String? = nil, token: String? = nil
    ) async throws -> [String: Any] {
        var json: [String: Any] = ["body": body]
        if let replyTo {
            json["replyTo"] = replyTo
        }
        let reply = try await env.send(.post, "/v1/board/posts/\(post)/comments", json: json, token: token)
        #expect(reply.status == .created, "\(reply.text)")
        return try reply.json()
    }

    private func list(_ env: LibraryHarness, _ post: String, token: String? = nil) async throws -> [[String: Any]] {
        let reply = try await env.send(.get, "/v1/board/posts/\(post)/comments", token: token)
        #expect(reply.status == .ok, "\(reply.text)")
        return try #require(reply.json()["items"] as? [[String: Any]])
    }

    @Test("BRD-001: comments are visible to everyone who sees the post")
    func visibleToAudience() async throws {
        try await LibraryHarness.run { env in
            let mine = try await claimHandle(env)
            let ana = try await friend(env, of: mine)
            let ben = try await friend(env, of: mine)
            let post = try await createPost(env, "hello")
            _ = try await comment(env, post, "nice", token: ben.token)

            let seen = try await list(env, post, token: ana.token)
            #expect(seen.count == 1)
            let author = seen.first?["author"] as? [String: Any]
            #expect(author?["handle"] as? String == ben.handle)
        }
    }

    @Test("BRD-001: a reply to a reply hangs off the top-level comment")
    func nestingStaysOneLevel() async throws {
        try await LibraryHarness.run { env in
            _ = try await claimHandle(env)
            let post = try await createPost(env, "hello")
            let topID = try #require(try await comment(env, post, "c1")["id"] as? String)
            let second = try await comment(env, post, "r1", replyTo: topID)
            let replyID = try #require(second["id"] as? String)
            #expect(second["replyTo"] as? String == topID)
            let third = try await comment(env, post, "r2", replyTo: replyID)
            #expect(third["replyTo"] as? String == topID)

            let bad = try await env.send(
                .post, "/v1/board/posts/\(post)/comments", json: ["body": "x", "replyTo": UUID().uuidString]
            )
            #expect(bad.status.code == 422)
            #expect(bad.text.contains("replyTo"))
        }
    }

    @Test("BRD-001: blocks hide comments both ways")
    func blocksHide() async throws {
        try await LibraryHarness.run { env in
            let mine = try await claimHandle(env)
            let ana = try await friend(env, of: mine)
            let ben = try await friend(env, of: mine)
            let post = try await createPost(env, "hello")
            _ = try await comment(env, post, "from ben", token: ben.token)
            _ = try await comment(env, post, "from me")
            #expect(try await list(env, post, token: ana.token).count == 2)

            #expect(try await env.send(.put, "/v1/social/blocks/\(ben.id)", token: ana.token).status.code < 300)
            let anas = try await list(env, post, token: ana.token)
            #expect(anas.map { $0["body"] as? String } == ["from me"])
            _ = try await comment(env, post, "from ana", token: ana.token)
            let bens = try await list(env, post, token: ben.token)
            #expect(!bens.contains { $0["body"] as? String == "from ana" })
        }
    }

    @Test("BRD-001: a blocked friend of a friend is the missing 404")
    func blockedPostIs404() async throws {
        try await LibraryHarness.run { env in
            let mine = try await claimHandle(env)
            let ana = try await friend(env, of: mine)
            let anaPost = try await createPost(env, "ana's", token: ana.token)
            #expect(try await env.send(.put, "/v1/social/blocks/\(ana.id)").status.code < 300)
            #expect(try await env.send(.get, "/v1/board/posts/\(anaPost)/comments").status == .notFound)
        }
    }

    @Test("BRD-001: post author can delete any comment, others only their own")
    func deleting() async throws {
        try await LibraryHarness.run { env in
            let mine = try await claimHandle(env)
            let ana = try await friend(env, of: mine)
            let ben = try await friend(env, of: mine)
            let post = try await createPost(env, "hello")
            let byAna = try #require(try await comment(env, post, "ana", token: ana.token)["id"] as? String)
            let byBen = try #require(try await comment(env, post, "ben", token: ben.token)["id"] as? String)

            let path = "/v1/board/posts/\(post)/comments"
            #expect(try await env.send(.delete, "\(path)/\(byAna)", token: ben.token).status == .forbidden)
            #expect(try await env.send(.delete, "\(path)/\(byBen)", token: ben.token).status == .noContent)
            #expect(try await env.send(.delete, "\(path)/\(byAna)").status == .noContent)
            #expect(try await list(env, post).isEmpty)
        }
    }

    @Test("BRD-001: a deleted comment with replies stays as an empty row")
    func deletedWithReplies() async throws {
        try await LibraryHarness.run { env in
            _ = try await claimHandle(env)
            let post = try await createPost(env, "hello")
            let topID = try #require(try await comment(env, post, "top")["id"] as? String)
            _ = try await comment(env, post, "reply", replyTo: topID)
            #expect(try await env.send(.delete, "/v1/board/posts/\(post)/comments/\(topID)").status == .noContent)

            let rows = try await list(env, post)
            #expect(rows.count == 2)
            #expect(rows.first?["deleted"] as? Bool == true)
            #expect(rows.first?["body"] as? String == "")
            #expect(rows.last?["body"] as? String == "reply")
        }
    }

    @Test("BRD-001: commenting on a deleted post is the missing 404")
    func deletedPost() async throws {
        try await LibraryHarness.run { env in
            _ = try await claimHandle(env)
            let post = try await createPost(env, "hello")
            #expect(try await env.send(.delete, "/v1/board/posts/\(post)").status == .noContent)
            let path = "/v1/board/posts/\(post)/comments"
            #expect(try await env.send(.post, path, json: ["body": "late"]).status == .notFound)
            #expect(try await env.send(.get, path).status == .notFound)
        }
    }

    @Test("BRD-001: @aaru in a comment is recorded, not answered")
    func aaruRecorded() async throws {
        try await LibraryHarness.run { env in
            let mine = try await claimHandle(env)
            let ana = try await friend(env, of: mine)
            let post = try await createPost(env, "hello")
            let made = try await comment(env, post, "hey @aaru and @\(ana.handle)")
            #expect(made["mentionsAgent"] as? Bool == true)
            #expect(made["mentions"] as? [String] == [ana.id])
            let rows = try await list(env, post)
            #expect(rows.count == 1)
            #expect(rows.first?["fromAgent"] as? Bool == false)
        }
    }

    @Test("BRD-001: comment bodies are validated")
    func validation() async throws {
        try await LibraryHarness.run { env in
            _ = try await claimHandle(env)
            let post = try await createPost(env, "hello")
            let path = "/v1/board/posts/\(post)/comments"
            #expect(try await env.send(.post, path, json: ["body": "   "]).status.code == 422)
            let long = String(repeating: "a", count: 4001)
            #expect(try await env.send(.post, path, json: ["body": long]).status.code == 422)
        }
    }
}
