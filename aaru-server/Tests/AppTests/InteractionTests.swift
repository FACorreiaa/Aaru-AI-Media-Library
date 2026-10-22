import AaruCore
import Foundation
import Testing
@testable import aaru

@Suite("Reactions and recommendations (SOC-007 / SOC-006)", .serialized)
struct InteractionTests {
    let friends = FriendTests()
    let social = SocialTests()

    func rows(_ reply: LibraryHarness.Reply) throws -> [[String: Any]] {
        try reply.json()["items"] as? [[String: Any]] ?? []
    }

    @Test("a friend reacts to a row once, can change or clear it, and you see it on yours")
    func reactions() async throws {
        try await LibraryHarness.run { env in
            let ana = try await friends.friends(env)
            _ = try await friends.add(env, "movie", env.stubMovie("Heat"), "finished")
            let mine = try #require(try await rows(env.send(.get, "/v1/activity")).first)
            let id = try #require(mine["id"] as? String)

            #expect(try await env.send(.put, "/v1/activity/\(id)/reaction", json: ["emoji": "🔥"], token: ana.token)
                .status == .noContent)
            #expect(try await env.send(.put, "/v1/activity/\(id)/reaction", json: ["emoji": "❤️"], token: ana.token)
                .status == .noContent)
            let row = try #require(try await rows(env.send(.get, "/v1/activity")).first)
            let counts = try #require(row["reactions"] as? [[String: Any]])
            #expect(counts.count == 1)
            #expect(counts.first?["emoji"] as? String == "❤️")
            #expect(counts.first?["count"] as? Int == 1)
            #expect(row["myReaction"] == nil)
            let theirs = try #require(try await rows(env.send(.get, "/v1/activity", token: ana.token)).first)
            #expect(theirs["myReaction"] as? String == "❤️")

            // Only the six, never on your own row, never on a stranger's.
            #expect(try await env.send(.put, "/v1/activity/\(id)/reaction", json: ["emoji": "👍"], token: ana.token)
                .status == .badRequest)
            #expect(try await env.send(.put, "/v1/activity/\(id)/reaction", json: ["emoji": "❤️"]).status
                == .notFound)
            let kai = try await social.friendlyUser(env)
            #expect(try await env.send(.put, "/v1/activity/\(id)/reaction", json: ["emoji": "❤️"], token: kai.token)
                .status == .notFound)
            #expect(try await env.send(.put, "/v1/activity/nonsense/reaction", json: ["emoji": "❤️"], token: ana.token)
                .status == .notFound)

            #expect(try await env.send(.delete, "/v1/activity/\(id)/reaction", token: ana.token).status == .noContent)
            #expect(try rows(await env.send(.get, "/v1/activity")).first?["reactions"] == nil)
        }
    }

    @Test("a recommendation reaches friends only, and adding it is one Plan to watch write")
    func recommendations() async throws {
        try await LibraryHarness.run { env in
            let ana = try await friends.friends(env)
            let kai = try await social.friendlyUser(env)
            let tmdb = env.stubMovie("Arrival")
            let title: [String: Any] = ["type": "movie", "ids": ["tmdb": tmdb]]

            // A stranger anywhere in the list sends nothing.
            #expect(try await env.send(
                .post, "/v1/social/recommendations", json: ["to": [ana.id, kai.id], "title": title]
            ).status == .notFound)
            #expect(try rows(await env.send(.get, "/v1/me/recommendations", token: ana.token)).isEmpty)
            #expect(try await env.send(
                .post, "/v1/social/recommendations",
                json: ["to": [ana.id], "title": title, "note": String(repeating: "a", count: 141)]
            ).status == .unprocessableContent)

            let sent = try await env.send(
                .post, "/v1/social/recommendations", json: ["to": [ana.id], "title": title, "note": " You'll love it "]
            )
            #expect(sent.status == .noContent)
            // Sending it again while it waits changes nothing.
            _ = try await env.send(.post, "/v1/social/recommendations", json: ["to": [ana.id], "title": title])
            let inbox = try rows(await env.send(.get, "/v1/me/recommendations", token: ana.token))
            #expect(inbox.count == 1)
            #expect(inbox.first?["note"] as? String == "You'll love it")
            #expect((inbox.first?["title"] as? [String: Any])?["title"] as? String == "Arrival")
            let id = try #require(inbox.first?["id"] as? String)

            #expect(try await env.send(.post, "/v1/me/recommendations/\(id)/add").status == .notFound)
            #expect(try await env.send(.post, "/v1/me/recommendations/\(id)/add", token: ana.token).status
                == .noContent)
            let library = try rows(await env.send(.get, "/v1/library/items", token: ana.token))
            #expect(library.count == 1)
            #expect(library.first?["status"] as? String == "wishlist")
            #expect(try rows(await env.send(.get, "/v1/me/recommendations", token: ana.token)).isEmpty)
            #expect(try await env.send(.post, "/v1/me/recommendations/\(id)/add", token: ana.token).status
                == .notFound)

            // Unfriending hides what is still waiting; dismissing removes it.
            _ = try await env.send(.post, "/v1/social/recommendations", json: ["to": [ana.id], "title": [
                "type": "movie", "ids": ["tmdb": env.stubMovie("Heat")],
            ]])
            let waiting = try #require(try await rows(env.send(.get, "/v1/me/recommendations", token: ana.token)).first)
            #expect(try await env.send(
                .delete,
                "/v1/me/recommendations/\(#require(waiting["id"] as? String))",
                token: ana.token
            ).status == .noContent)
            #expect(try rows(await env.send(.get, "/v1/me/recommendations", token: ana.token)).isEmpty)
        }
    }
}
