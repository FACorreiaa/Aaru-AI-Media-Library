import AaruCore
import FluentSQL
import Foundation
import Testing
@testable import aaru

@Suite("Friend profiles and activity (SOC-001 / SOC-003)", .serialized)
struct FriendTests {
    let social = SocialTests()

    /// The harness user and a second user, both with handles, made friends by an invite.
    func friends(_ env: LibraryHarness) async throws -> SocialTests.Person {
        _ = try await env.send(.put, "/v1/me/profile", json: ["handle": social.freshHandle()])
        let ana = try await social.friendlyUser(env)
        let code = try #require(
            try await env.send(.post, "/v1/social/invites", json: [:] as [String: Any]).json()["code"] as? String
        )
        #expect(try await env.send(
            .post, "/v1/social/invites/\(code)/redeem", json: ["addTitle": false], token: ana.token
        ).status == .ok)
        return ana
    }

    /// Adds a title to someone's library and returns the item id.
    func add(
        _ env: LibraryHarness, _ type: String, _ tmdb: String, _ status: String, token: String? = nil
    ) async throws -> String {
        let reply = try await env.send(
            .post, "/v1/library/items", json: ["mediaRef": ["type": type, "ids": ["tmdb": tmdb]], "status": status],
            token: token
        )
        return try #require(reply.json()["id"] as? String)
    }

    func titles(_ value: Any?) -> [String] {
        (value as? [[String: Any]] ?? []).compactMap { ($0["title"] as? [String: Any])?["title"] as? String }
    }

    func names(_ value: Any?) -> [String] {
        (value as? [[String: Any]] ?? []).compactMap { $0["title"] as? String }
    }

    @Test("a friend's profile shows their shelves and what you share, never their notes")
    func profile() async throws {
        try await LibraryHarness.run { env in
            let ana = try await friends(env)
            let (arrival, dune, heat) = (env.stubMovie("Arrival"), env.stubMovie("Dune"), env.stubMovie("Heat"))
            let show = try await add(
                env,
                "show",
                env.stubShow("Severance", status: .returning),
                "in_progress",
                token: ana.token
            )
            _ = try await env.send(
                .put,
                "/v1/library/items/\(show)/episodes/1/2",
                json: ["watched": true],
                token: ana.token
            )
            let anaArrival = try await add(env, "movie", arrival, "finished", token: ana.token)
            _ = try await env.send(
                .patch,
                "/v1/library/items/\(anaArrival)",
                json: ["rating": 9, "notes": "secret note"],
                token: ana.token
            )
            let anaHeat = try await add(env, "movie", heat, "finished", token: ana.token)
            _ = try await env.send(.patch, "/v1/library/items/\(anaHeat)", json: ["rating": 8.5], token: ana.token)
            _ = try await add(env, "movie", dune, "wishlist", token: ana.token)
            _ = try await add(env, "movie", dune, "wishlist")
            _ = try await add(env, "movie", arrival, "finished")

            let reply = try await env.send(.get, "/v1/social/friends/\(ana.id)/profile")
            #expect(reply.status == .ok)
            #expect(!reply.text.contains("secret note"))
            let profile = try reply.json()
            #expect(profile["sharing"] as? Bool == true)
            #expect((profile["user"] as? [String: Any])?["handle"] as? String == ana.handle)
            let watching = try #require(profile["watching"] as? [[String: Any]])
            #expect(titles(watching) == ["Severance"])
            #expect(watching.first?["lastSeason"] as? Int == 1)
            #expect(watching.first?["lastEpisode"] as? Int == 2)
            #expect(Set(titles(profile["recentlyFinished"])) == ["Arrival", "Heat"])
            let counts = try #require(profile["counts"] as? [String: Any])
            #expect(counts["movie"] as? Int == 3)
            #expect(counts["show"] as? Int == 1)
            let compare = try #require(profile["compare"] as? [String: Any])
            #expect(names(compare["bothWant"]) == ["Dune"])
            #expect(compare["bothFinished"] as? Int == 1)
            // Arrival is loved too, but you already have it.
            #expect(names(compare["theyLoved"]) == ["Heat"])
        }
    }

    @Test("only friends see a profile; hiding the library leaves only the name")
    func privacy() async throws {
        try await LibraryHarness.run { env in
            let ana = try await friends(env)
            let kai = try await social.friendlyUser(env)
            let stranger = try await env.send(.get, "/v1/social/friends/\(ana.id)/profile", token: kai.token)
            let nobody = try await env.send(.get, "/v1/social/friends/\(UUID())/profile", token: kai.token)
            #expect(stranger.status == .notFound)
            #expect(stranger.text == nobody.text)
            #expect(try await env.send(.get, "/v1/social/friends/\(env.userID)/profile").status == .notFound)

            #expect(try await env.send(.get, "/v1/me/social-settings", token: ana.token)
                .json()["shareLibraryWithFriends"] as? Bool == true)
            _ = try await add(env, "movie", env.stubMovie("Heat"), "finished", token: ana.token)
            #expect(try await env.send(
                .put, "/v1/me/social-settings", json: ["shareLibraryWithFriends": false], token: ana.token
            ).status == .ok)
            let hidden = try await env.send(.get, "/v1/social/friends/\(ana.id)/profile").json()
            #expect(hidden["sharing"] as? Bool == false)
            #expect(hidden["watching"] == nil)
            #expect(hidden["compare"] == nil)
            #expect(try (await env.send(.get, "/v1/activity").json()["items"] as? [Any])?.isEmpty == true)

            // A block ends the friendship and the profile with it.
            _ = try await env.send(
                .put,
                "/v1/me/social-settings",
                json: ["shareLibraryWithFriends": true],
                token: ana.token
            )
            #expect(try await env.send(.put, "/v1/social/blocks/\(ana.id)").status == .noContent)
            #expect(try await env.send(.get, "/v1/social/friends/\(ana.id)/profile").status == .notFound)
        }
    }

    @Test("activity is friends' dated ticks and finishes, one row per title and day; imports never show")
    func activity() async throws {
        try await LibraryHarness.run { env in
            let ana = try await friends(env)
            let show = try await add(
                env,
                "show",
                env.stubShow("Andor", status: .returning),
                "in_progress",
                token: ana.token
            )
            for episode in 1 ... 3 {
                _ = try await env.send(
                    .put,
                    "/v1/library/items/\(show)/episodes/1/\(episode)",
                    json: ["watched": true],
                    token: ana.token
                )
            }
            _ = try await add(env, "movie", env.stubMovie("Heat"), "finished", token: ana.token)
            // Your own activity is not in your friends' feed.
            _ = try await add(env, "movie", env.stubMovie("Arrival"), "finished")

            let items = try #require(try await env.send(.get, "/v1/activity").json()["items"] as? [[String: Any]])
            #expect(Set(titles(items)) == ["Andor", "Heat"])
            let andor = try #require(items.first { ($0["title"] as? [String: Any])?["title"] as? String == "Andor" })
            #expect(andor["episodes"] as? Int == 3)
            #expect(andor["lastEpisode"] as? Int == 3)
            #expect(andor["finished"] as? Bool == false)
            #expect((andor["user"] as? [String: Any])?["handle"] as? String == ana.handle)
            #expect(try await env.send(.get, "/v1/activity", token: ana.token).json()["items"]
                .map { titles($0) } == ["Arrival"])

            // A tick without a known date (an import, a restore) is not activity.
            let showID = try #require(UUID(uuidString: show))
            try await withSQL { sql in
                try await sql.raw("""
                UPDATE episode_progress SET watched_at_known = false WHERE library_item_id = \(bind: showID)
                """).run()
            }
            let after = try #require(try await env.send(.get, "/v1/activity").json()["items"] as? [[String: Any]])
            #expect(titles(after) == ["Heat"])
        }
    }
}
