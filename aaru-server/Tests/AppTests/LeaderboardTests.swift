import AaruCore
import Foundation
import Testing
@testable import aaru

@Suite("Friends board and what friends see (GAM-005)", .serialized)
struct LeaderboardTests {
    let friendTests = FriendTests()

    func board(_ env: LibraryHarness, token: String? = nil) async throws -> (optedIn: Bool, handles: [String]) {
        let json = try await env.send(.get, "/v1/social/leaderboard", token: token).json()
        let entries = json["entries"] as? [[String: Any]] ?? []
        return (
            json["optedIn"] as? Bool ?? false,
            entries.compactMap { ($0["user"] as? [String: Any])?["handle"] as? String }
        )
    }

    func join(_ env: LibraryHarness, token: String? = nil, _ joined: Bool = true) async throws {
        let reply = try await env.send(
            .put, "/v1/me/social-settings", json: ["shareLibraryWithFriends": true, "leaderboardOptIn": joined],
            token: token
        )
        #expect(reply.status == .ok)
    }

    @Test("Nobody appears until they join, friends' boards included; blocks hide both ways")
    func optInAndBlocks() async throws {
        try await LibraryHarness.run { env in
            let ana = try await friendTests.friends(env)
            let mine = try #require(try await env.send(.get, "/v1/me").json()["handle"] as? String)

            #expect(try await board(env) == (false, []))
            try await join(env)
            #expect(try await board(env) == (true, [mine]), "a friend who has not joined never appears")
            #expect(try await board(env, token: ana.token).handles.isEmpty, "nor does anyone, to someone not joined")

            try await join(env, token: ana.token)
            #expect(try await Set(board(env).handles) == [mine, ana.handle])

            #expect(try await env.send(.put, "/v1/social/blocks/\(ana.id)").status == .noContent)
            #expect(try await board(env).handles == [mine])
            #expect(try await board(env, token: ana.token).handles == [ana.handle])
        }
    }

    @Test("Friend and first-import points stay off the board; ranks follow the week's points")
    func boardPoints() async throws {
        try await LibraryHarness.run { env in
            let ana = try await friendTests.friends(env)
            try await join(env)
            try await join(env, token: ana.token)
            _ = try await env.add("movie", tmdb: env.stubMovie("Alien"), status: "finished")
            let json = try await env.send(.get, "/v1/social/leaderboard").json()
            let entries = json["entries"] as? [[String: Any]] ?? []
            #expect(entries.first?["you"] as? Bool == true)
            #expect(entries.first?["points"] as? Int == 25, "the friend award does not count")
            #expect(entries.first?["rank"] as? Int == 1)
            #expect(entries.last?["points"] as? Int == 0)
            #expect(try await env.send(.get, "/v1/me/progress").json()["weekPoints"] as? Int == 25)
            #expect(try await env.send(.get, "/v1/social/leaderboard?week=bad").status == .badRequest)
        }
    }

    @Test("An older app's settings PUT leaves the new switches alone")
    func partialSettings() async throws {
        try await LibraryHarness.run { env in
            try await join(env)
            let reply = try await env.send(.put, "/v1/me/social-settings", json: ["shareLibraryWithFriends": false])
            let json = try reply.json()
            #expect(json["leaderboardOptIn"] as? Bool == true)
            #expect(json["showAchievementsToFriends"] as? Bool == true)
            #expect(json["shareLibraryWithFriends"] as? Bool == false)
        }
    }

    @Test("Friends see level and badges unless switched off; never private ones")
    func friendAchievements() async throws {
        try await LibraryHarness.run { env in
            let ana = try await friendTests.friends(env)
            let item = try await env.add("movie", tmdb: env.stubMovie("Ran"), status: "finished")
            for _ in 0 ..< 10 {
                _ = try await env.add("movie", tmdb: env.stubMovie("Owned \(UUID())"), status: "wishlist")
            }
            _ = item
            try await withSQL { sql in
                try await sql
                    .raw("UPDATE library_items SET is_owned = true WHERE user_id = \(bind: env.userID.rawValue)").run()
            }
            _ = try await env.stores.gamification.insertBadges(
                [("collector", 1)], userID: env.userID, origin: .live, actionID: nil, now: Date()
            )
            let profile = try await env.send(.get, "/v1/social/friends/\(env.userID)/profile", token: ana.token).json()
            let achievements = try #require(profile["achievements"] as? [String: Any])
            let badges = (achievements["badges"] as? [[String: Any]] ?? []).compactMap { $0["badge"] as? String }
            #expect(badges.contains("first_film"))
            #expect(!badges.contains("collector"), "owned items are never shown to friends")
            #expect(achievements["level"] as? Int == 1)

            _ = try await env.send(
                .put, "/v1/me/social-settings",
                json: ["shareLibraryWithFriends": true, "showAchievementsToFriends": false]
            )
            let hidden = try await env.send(.get, "/v1/social/friends/\(env.userID)/profile", token: ana.token).json()
            #expect(hidden["achievements"] == nil)
        }
    }
}
