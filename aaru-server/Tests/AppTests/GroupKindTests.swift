import AaruCore
import Foundation
import Testing
@testable import aaru

@Suite("Title, shelf and watch channels (GRP-007…GRP-009)", .serialized)
struct GroupKindTests {
    let groups = GroupTests()

    struct Fixture {
        let ana: Person
        let group: String
        let channel: String
    }

    /// A group with the harness user as owner and Ana as a member, plus a channel of `kind`.
    func setUp(_ env: LibraryHarness, kind: String, title: [String: Any]? = nil) async throws -> Fixture {
        let mine = try await claimHandle(env)
        let ana = try await friend(env, of: mine)
        let (group, _) = try await groups.createGroup(env)
        try await groups.join(env, ana, group: group)
        var body: [String: Any] = ["kind": kind]
        if let title {
            body["title"] = title
        } else {
            body["name"] = kind
        }
        let created = try await env.send(.post, "/v1/groups/\(group)/channels", json: body)
        #expect(created.status == .ok, "\(created.text)")
        return try Fixture(ana: ana, group: group, channel: #require(created.json()["id"] as? String))
    }

    /// Adds a show to someone's library and ticks episodes; returns the item id.
    func watch(
        _ env: LibraryHarness, tmdb: String, _ episodes: [(Int, Int)], token: String? = nil
    ) async throws -> String {
        let added = try await env.send(
            .post, "/v1/library/items",
            json: ["mediaRef": ["type": "show", "ids": ["tmdb": tmdb]], "status": "in_progress"], token: token
        )
        let item = try #require(added.json()["id"] as? String)
        for (season, episode) in episodes {
            let ticked = try await env.send(
                .put, "/v1/library/items/\(item)/episodes/\(season)/\(episode)", json: ["watched": true], token: token
            )
            #expect(ticked.status == .ok, "\(ticked.text)")
        }
        return item
    }

    func messages(_ env: LibraryHarness, _ path: String, token: String? = nil) async throws -> [[String: Any]] {
        try await env.send(.get, "\(path)/messages", token: token).json()["items"] as? [[String: Any]] ?? []
    }

    @Test("GRP-007: a title channel stamps messages; readers behind the stamp see them veiled")
    func spoilerGuard() async throws {
        try await LibraryHarness.run { env in
            let tmdb = env.stubShow("Severance", status: .returning)
            let ref: [String: Any] = ["type": "show", "ids": ["tmdb": tmdb]]
            let fixture = try await setUp(env, kind: "title", title: ref)
            let (ana, group, channel) = (fixture.ana, fixture.group, fixture.channel)
            let path = "/v1/groups/\(group)/channels/\(channel)"
            let detail = try await env.send(.get, "/v1/groups/\(group)").json()
            let listed = try #require((detail["channels"] as? [[String: Any]])?
                .first { $0["id"] as? String == channel })
            #expect(listed["name"] as? String == "severance")
            #expect((listed["title"] as? [String: Any])?["title"] as? String == "Severance")

            _ = try await watch(env, tmdb: tmdb, [(1, 1), (1, 2), (1, 3)])
            let anaItem = try await watch(env, tmdb: tmdb, [(1, 1)], token: ana.token)

            // Auto-stamped where the author is: S1E3. Ana is at S1E1.
            let auto = try await groups.post(env, path, "the ending of episode 3!")
            #expect((auto["spoiler"] as? [String: Any])?["episode"] as? Int == 3)
            #expect(auto["veiled"] as? Bool == false)
            // A hand stamp, a spoiler-free message, and one about the ending.
            _ = try await env.send(
                .post, "\(path)/messages", json: ["body": "S1E5 twist", "spoiler": ["season": 1, "episode": 5]]
            )
            _ = try await env.send(.post, "\(path)/messages", json: ["body": "who's in?", "spoilerFree": true])
            _ = try await env.send(
                .post,
                "\(path)/messages",
                json: ["body": "that finale", "spoiler": ["ending": true]]
            )

            var seen = try await messages(env, path, token: ana.token).map { (
                $0["body"] as? String,
                $0["veiled"] as? Bool
            ) }
            #expect(seen.map(\.1) == [true, true, false, true])
            // Ana catches up to S2E1: everything up to there unveils, the ending does not.
            for (season, episode) in [(1, 2), (1, 3), (2, 1)] {
                _ = try await env.send(
                    .put, "/v1/library/items/\(anaItem)/episodes/\(season)/\(episode)", json: ["watched": true],
                    token: ana.token
                )
            }
            seen = try await messages(env, path, token: ana.token)
                .map { ($0["body"] as? String, $0["veiled"] as? Bool) }
            #expect(seen.map(\.1) == [false, false, false, true])
            // The author never sees their own messages veiled.
            #expect(try await messages(env, path).allSatisfy { $0["veiled"] as? Bool == false })
            // The stamp shows where its author is, so nobody else sees it.
            #expect(try await messages(env, path, token: ana.token).allSatisfy { $0["spoiler"] == nil })
        }
    }

    @Test("GRP-007: only members who share their progress appear in a title channel's header")
    func shareProgress() async throws {
        try await LibraryHarness.run { env in
            let tmdb = env.stubShow("Andor", status: .returning)
            let fixture = try await setUp(env, kind: "title", title: ["type": "show", "ids": ["tmdb": tmdb]])
            let (ana, group, channel) = (fixture.ana, fixture.group, fixture.channel)
            let path = "/v1/groups/\(group)/channels/\(channel)/progress"
            _ = try await watch(env, tmdb: tmdb, [(1, 2)])
            _ = try await watch(env, tmdb: tmdb, [(1, 1)], token: ana.token)

            var header = try await env.send(.get, path, token: ana.token).json()
            #expect((header["members"] as? [Any])?.isEmpty == true)
            #expect((header["mine"] as? [String: Any])?["episode"] as? Int == 1)

            let shared = try await env.send(.put, "/v1/groups/\(group)/me", json: ["shareProgress": true]).json()
            #expect(shared["shareProgress"] as? Bool == true)
            header = try await env.send(.get, path, token: ana.token).json()
            let members = header["members"] as? [[String: Any]]
            #expect(members?.count == 1)
            #expect(members?.first?["episode"] as? Int == 2)
            // Ana does not share, so she never appears for anyone.
            let mine = try await env.send(.get, path).json()["members"] as? [Any]
            #expect(mine?.isEmpty == true)
        }
    }

    @Test("GRP-008: members share a shelf; adding to my library is one journaled action for me only")
    func shelf() async throws {
        try await LibraryHarness.run { env in
            let fixture = try await setUp(env, kind: "shelf")
            let (ana, group, channel) = (fixture.ana, fixture.group, fixture.channel)
            let path = "/v1/groups/\(group)/channels/\(channel)/items"
            let anaSocket = Frames()
            let anaID = try #require(UUID(uuidString: ana.id)).asUser
            _ = await env.realtime.connect(anaID) { await anaSocket.append($0) }

            let tmdb = env.stubMovie("Arrival")
            let added = try await env.send(
                .post, path, json: ["title": ["type": "movie", "ids": ["tmdb": tmdb]]], token: ana.token
            ).json()
            let item = try #require((added["items"] as? [[String: Any]])?.first)
            #expect((item["addedBy"] as? [String: Any])?["handle"] as? String == ana.handle)
            #expect(item["myStatus"] == nil)
            #expect(await anaSocket.types.contains("shelf.updated"))
            // Adding it again changes nothing.
            let again = try await env.send(.post, path, json: ["title": ["type": "movie", "ids": ["tmdb": tmdb]]])
            #expect(try (again.json()["items"] as? [Any])?.count == 1)

            let titleID = try #require((item["title"] as? [String: Any])?["id"] as? String)
            let before = try await env.actionCount()
            let mine = try await env.send(
                .post,
                "/v1/library/items",
                json: ["mediaRef": ["type": "movie", "titleId": titleID]]
            )
            #expect(mine.status == .ok)
            #expect(try await env.actionCount() == before + 1)
            let shelf = try await env.send(.get, path).json()["items"] as? [[String: Any]]
            #expect(shelf?.first?["myStatus"] as? String == "wishlist")
            let hers = try await env.send(.get, path, token: ana.token).json()["items"] as? [[String: Any]]
            #expect(hers?.first?["myStatus"] == nil)

            #expect(try await env.send(.delete, "\(path)/\(titleID)").status == .noContent)
            #expect(try await env.send(.delete, "\(path)/\(titleID)").status == .notFound)
            let general = try await env.send(.get, "/v1/groups/\(group)").json()["group"] as? [String: Any]
            let text = try #require(general?["defaultChannelId"] as? String)
            #expect(try await env.send(.get, "/v1/groups/\(group)/channels/\(text)/items").status
                == .unprocessableContent)
        }
    }

    @Test("GRP-009: a watch party counts down on server time and ticks only the members who tap")
    func watchParty() async throws {
        try await LibraryHarness.run { env in
            let tmdb = env.stubShow("Shogun", status: .ended)
            let fixture = try await setUp(env, kind: "watch")
            let (ana, group, channel) = (fixture.ana, fixture.group, fixture.channel)
            let path = "/v1/groups/\(group)/channels/\(channel)/party"
            let show: [String: Any] = ["type": "show", "ids": ["tmdb": tmdb]]
            #expect(try await env.send(.get, path).json()["party"] == nil)
            #expect(try await env.send(.post, path, json: ["title": show]).status == .unprocessableContent)
            let opened = try await env.send(.post, path, json: ["title": show, "season": 1, "episode": 2]).json()
            #expect((opened["party"] as? [String: Any])?["state"] as? String == "lobby")
            #expect(opened["serverTime"] != nil)
            #expect(try await env.send(.post, path, json: ["title": show, "season": 1, "episode": 3]).status
                == .conflict)

            let ready = try await env.send(.post, "\(path)/ready", json: ["ready": true], token: ana.token).json()
            #expect(((ready["party"] as? [String: Any])?["ready"] as? [Any])?.count == 1)
            #expect(try await env.send(.post, "\(path)/watched", token: ana.token).status == .unprocessableContent)
            #expect(try await env.send(.post, "\(path)/start", json: [:], token: ana.token).status == .forbidden)
            let started = try await env.send(.post, "\(path)/start", json: ["countdownSeconds": 5]).json()
            let party = try #require(started["party"] as? [String: Any])
            #expect(party["state"] as? String == "countdown")
            let formatter = ISO8601DateFormatter()
            let startsAt = try #require((party["startsAt"] as? String).flatMap(formatter.date))
            let serverTime = try #require((started["serverTime"] as? String).flatMap(formatter.date))
            #expect(abs(startsAt.timeIntervalSince(serverTime) - 5) < 1.5)

            // Reactions reach the others; anything outside the set is dropped.
            let anaSocket = Frames()
            let anaID = try #require(UUID(uuidString: ana.id)).asUser
            _ = await env.realtime.connect(anaID) { await anaSocket.append($0) }
            let groupID = try #require(UUID(uuidString: group))
            let channelID = try #require(UUID(uuidString: channel))
            try await env.services.groups.react(groupID, channel: channelID, emoji: "🔥", viewer: env.userID)
            try await env.services.groups.react(groupID, channel: channelID, emoji: "lol", viewer: env.userID)
            #expect(await anaSocket.types == ["watch.reaction"])

            #expect(try await env.send(.post, "\(path)/end").json()["party"].map { ($0 as? [String: Any])?["state"] }
                as? String == "ended")
            // After the end, Ana ticks it for herself; nobody else's library changes.
            #expect(try await env.send(.post, "\(path)/watched", token: ana.token).status == .noContent)
            let hers = try await env.send(.get, "/v1/library/items?type=show", token: ana.token).json()
            let entry = try #require((hers["items"] as? [[String: Any]])?.first)
            #expect((entry["progress"] as? [String: Any])?["watchedCount"] as? Int == 1)
            let mine = try await env.send(.get, "/v1/library/items?type=show").json()["items"] as? [Any]
            #expect(mine?.isEmpty == true)
        }
    }
}
