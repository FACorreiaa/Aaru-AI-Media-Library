import AaruCore
import Foundation
import Testing
@testable import aaru

@Suite("Groups, channels and messages (GRP-001…GRP-003)", .serialized)
struct GroupTests {
    @Test("GRP-001: creating a group needs a handle and starts it with #general; outsiders get 404")
    func createAndHide() async throws {
        try await LibraryHarness.run { env in
            let noHandle = try await env.send(.post, "/v1/groups", json: ["name": "Film club"])
            #expect(try noHandle.json()["code"] as? String == "handle_required")
            _ = try await claimHandle(env)
            #expect(try await env.send(.post, "/v1/groups", json: ["name": "  "]).status == .unprocessableContent)

            let (group, general) = try await createGroup(env)
            let detail = try await env.send(.get, "/v1/groups/\(group)").json()
            let channels = try #require(detail["channels"] as? [[String: Any]])
            #expect(channels.map { $0["name"] as? String } == ["general"])
            #expect(channels.first?["id"] as? String == general)
            #expect(channels.first?["isDefault"] as? Bool == true)
            #expect((detail["group"] as? [String: Any])?["role"] as? String == "owner")
            let listed = try await env.send(.get, "/v1/groups").json()["items"] as? [[String: Any]]
            #expect(listed?.contains { $0["id"] as? String == group } == true)

            // A stranger sees exactly what a group that does not exist shows.
            let (_, stranger) = try await signedInUser(env.stores)
            let hidden = try await env.send(.get, "/v1/groups/\(group)", token: stranger)
            let missing = try await env.send(.get, "/v1/groups/\(UUID())", token: stranger)
            #expect(hidden.status == .notFound)
            #expect(hidden.text == missing.text)
            #expect(try await env.send(.get, "/v1/groups/\(group)/channels/\(general)/messages", token: stranger)
                .status == .notFound)
        }
    }

    @Test("GRP-002: only friends can be invited; invites are accepted, declined or cancelled")
    func invites() async throws {
        try await LibraryHarness.run { env in
            let mine = try await claimHandle(env)
            let (group, _) = try await createGroup(env)
            let (strangerID, _) = try await signedInUser(env.stores)
            let notFriend = try await env.send(.post, "/v1/groups/\(group)/invites", json: ["userId": "\(strangerID)"])
            #expect(notFriend.status == .unprocessableContent)
            // Someone who blocked you looks exactly like someone who is not your friend.
            let blocker = try await friend(env, of: mine)
            _ = try await env.send(.put, "/v1/social/blocks/\(env.userID)", token: blocker.token)
            let blocked = try await env.send(.post, "/v1/groups/\(group)/invites", json: ["userId": blocker.id])
            #expect(blocked.status == .unprocessableContent)
            #expect(blocked.text == notFriend.text.replacingOccurrences(of: "\(strangerID)", with: blocker.id))

            let ana = try await friend(env, of: mine)
            #expect(try await env.send(.post, "/v1/groups/\(group)/invites", json: ["userId": ana.id]).status
                == .noContent)
            let pending = try await env.send(.get, "/v1/groups/\(group)").json()["invited"] as? [[String: Any]]
            #expect(pending?.compactMap { $0["handle"] as? String } == [ana.handle])
            // Declining removes it; a non-member still sees nothing.
            let inbox = try await env.send(.get, "/v1/me/group-invites", token: ana.token).json()
            let invite = try #require((inbox["items"] as? [[String: Any]])?.first)
            #expect((invite["inviter"] as? [String: Any])?["handle"] as? String == mine)
            let inviteID = try #require(invite["id"] as? String)
            #expect(try await env.send(.delete, "/v1/group-invites/\(inviteID)", token: ana.token).status == .noContent)
            #expect(try await env.send(.post, "/v1/group-invites/\(inviteID)/accept", token: ana.token).status
                == .notFound)
            #expect(try await env.send(.get, "/v1/groups/\(group)", token: ana.token).status == .notFound)

            try await join(env, ana, group: group)
            let members = try await env.send(.get, "/v1/groups/\(group)", token: ana.token).json()["members"]
            #expect((members as? [[String: Any]])?.count == 2)
            // Inviting someone already in changes nothing.
            #expect(try await env.send(.post, "/v1/groups/\(group)/invites", json: ["userId": ana.id]).status
                == .noContent)
            #expect(try (await env.send(.get, "/v1/groups/\(group)").json()["invited"] as? [Any])?.isEmpty == true)
        }
    }

    @Test("GRP-003: messages page by cursor, retries are idempotent, mentions are parsed, unread counts move")
    func messages() async throws {
        try await LibraryHarness.run { env in
            let mine = try await claimHandle(env)
            let ana = try await friend(env, of: mine)
            let (group, general) = try await createGroup(env)
            try await join(env, ana, group: group)
            let channel = "/v1/groups/\(group)/channels/\(general)"

            let first = try await env.send(
                .post, "\(channel)/messages", json: ["body": " hi ", "clientNonce": "n-1"]
            ).json()
            let retry = try await env.send(
                .post, "\(channel)/messages", json: ["body": "hi", "clientNonce": "n-1"]
            ).json()
            #expect(first["id"] as? String == retry["id"] as? String)
            #expect(first["body"] as? String == "hi")
            #expect(try await env.send(.post, "\(channel)/messages", json: ["body": "   "]).status
                == .unprocessableContent)
            #expect(try await env.send(
                .post, "\(channel)/messages", json: ["body": String(repeating: "a", count: 4001)]
            ).status == .unprocessableContent)

            let tagged = try await post(env, channel, "@\(ana.handle.uppercased()) and @aaru, not a@\(ana.handle)")
            #expect(tagged["mentions"] as? [String] == [ana.id])
            #expect(tagged["mentionsAgent"] as? Bool == true)
            // A friend who is not in the group is not mentioned.
            let outsider = try await friend(env, of: mine)
            #expect(try await post(env, channel, "hi @\(outsider.handle)")["mentions"] as? [String] == [])
            for number in 1 ... 5 {
                _ = try await post(env, channel, "m\(number)")
            }

            // Ana sees her unread and mention counts, then reads.
            let summary = try await env.send(.get, "/v1/groups", token: ana.token).json()["items"] as? [[String: Any]]
            let row = try #require(summary?.first { $0["id"] as? String == group })
            #expect(row["unread"] as? Int == 8)
            #expect(row["mentions"] as? Int == 1)

            let latest = try await env.send(.get, "\(channel)/messages?limit=3", token: ana.token)
            #expect(try bodies(latest) == ["m3", "m4", "m5"])
            let oldest = try #require(try (latest.json()["items"] as? [[String: Any]])?.first?["id"] as? String)
            let older = try await env.send(.get, "\(channel)/messages?before=\(oldest)&limit=3", token: ana.token)
            #expect(try bodies(older).count == 3)
            #expect(try bodies(older).last == "m2")
            let newer = try await env.send(.get, "\(channel)/messages?after=\(oldest)", token: ana.token)
            #expect(try bodies(newer) == ["m4", "m5"])

            let last = try #require(try (latest.json()["items"] as? [[String: Any]])?.last?["id"] as? String)
            #expect(try await env.send(.post, "\(channel)/read", json: ["messageId": last], token: ana.token).status
                == .noContent)
            let read = try await env.send(.get, "/v1/groups/\(group)", token: ana.token).json()
            let readChannel = (read["channels"] as? [[String: Any]])?.first
            #expect(readChannel?["unread"] as? Int == 0)
            #expect(readChannel?["mentions"] as? Int == 0)
            // The read point never moves back.
            _ = try await env.send(.post, "\(channel)/read", json: ["messageId": oldest], token: ana.token)
            let still = try await env.send(.get, "/v1/groups/\(group)", token: ana.token).json()
            #expect(((still["channels"] as? [[String: Any]])?.first?["unread"] as? Int) == 0)
        }
    }

    @Test("GRP-003: only the author edits; authors and admins delete; a blocked author arrives flagged")
    func editDeleteBlock() async throws {
        try await LibraryHarness.run { env in
            let mine = try await claimHandle(env)
            let ana = try await friend(env, of: mine)
            let (group, general) = try await createGroup(env)
            try await join(env, ana, group: group)
            let channel = "/v1/groups/\(group)/channels/\(general)"

            let hers = try #require(try await post(env, channel, "from ana", token: ana.token)["id"] as? String)
            let mineID = try #require(try await post(env, channel, "from me")["id"] as? String)
            #expect(try await env.send(.patch, "\(channel)/messages/\(hers)", json: ["body": "edited"]).status
                == .forbidden)
            let edited = try await env.send(
                .patch, "\(channel)/messages/\(hers)", json: ["body": "edited"], token: ana.token
            ).json()
            #expect(edited["body"] as? String == "edited")
            #expect(edited["editedAt"] != nil)
            #expect(try await env.send(.delete, "\(channel)/messages/\(mineID)", token: ana.token).status
                == .forbidden)
            // The owner deletes anyone's message; the row stays, empty.
            #expect(try await env.send(.delete, "\(channel)/messages/\(hers)").status == .noContent)
            let after = try await env.send(.get, "\(channel)/messages").json()["items"] as? [[String: Any]]
            let deleted = try #require(after?.first { $0["id"] as? String == hers })
            #expect(deleted["deleted"] as? Bool == true)
            #expect(deleted["body"] as? String == "")

            _ = try await post(env, channel, "still here", token: ana.token)
            #expect(try await env.send(.put, "/v1/social/blocks/\(ana.id)").status == .noContent)
            let flagged = try await env.send(.get, "\(channel)/messages").json()["items"] as? [[String: Any]]
            #expect(flagged?.last?["fromBlocked"] as? Bool == true)
            #expect(flagged?.last?["body"] as? String == "still here")
        }
    }

    @Test("GRP-001: roles gate channels and members; #general stays; the owner transfers before leaving")
    func rolesAndChannels() async throws {
        try await LibraryHarness.run { env in
            let mine = try await claimHandle(env)
            let ana = try await friend(env, of: mine)
            let kai = try await friend(env, of: mine)
            let (group, general) = try await createGroup(env)
            try await join(env, ana, group: group)
            try await join(env, kai, group: group)
            let base = "/v1/groups/\(group)"

            #expect(try await env.send(.post, "\(base)/channels", json: ["name": "x"], token: ana.token).status
                == .forbidden)
            #expect(try await env.send(.patch, "\(base)/members/\(ana.id)", json: ["role": "admin"], token: kai.token)
                .status == .forbidden)
            #expect(try await env.send(.patch, "\(base)/members/\(ana.id)", json: ["role": "admin"]).status
                == .noContent)

            let created = try await env.send(
                .post,
                "\(base)/channels",
                json: ["name": " Movie  Night! "],
                token: ana.token
            )
            #expect(try created.json()["name"] as? String == "movie-night")
            let channelID = try #require(try created.json()["id"] as? String)
            #expect(try await env.send(.post, "\(base)/channels", json: ["name": "movie night"]).status == .conflict)
            let renamed = try await env.send(
                .patch, "\(base)/channels/\(channelID)", json: ["topic": "Fridays"], token: ana.token
            ).json()
            #expect(renamed["topic"] as? String == "Fridays")
            #expect(renamed["name"] as? String == "movie-night")
            #expect(try await env.send(.delete, "\(base)/channels/\(general)").status == .unprocessableContent)
            #expect(try await env.send(.delete, "\(base)/channels/\(channelID)", token: ana.token).status
                == .noContent)
            for number in 1 ... 19 {
                _ = try await env.send(.post, "\(base)/channels", json: ["name": "c\(number)"])
            }
            #expect(try await env.send(.post, "\(base)/channels", json: ["name": "one-too-many"]).status
                == .unprocessableContent)

            // An admin removes members, not the owner or another admin.
            #expect(try await env.send(.delete, "\(base)/members/\(env.userID)", token: ana.token).status
                == .forbidden)
            #expect(try await env.send(.delete, "\(base)/members/\(kai.id)", token: ana.token).status == .noContent)
            #expect(try await env.send(.get, base, token: kai.token).status == .notFound)

            #expect(try await env.send(.delete, "\(base)/members/\(env.userID)").status == .unprocessableContent)
            #expect(try await env.send(.post, "\(base)/transfer", json: ["userId": ana.id]).status == .noContent)
            #expect(try await env.send(.delete, base).status == .forbidden)
            #expect(try await env.send(.delete, "\(base)/members/\(env.userID)").status == .noContent)
            #expect(try await env.send(.get, base).status == .notFound)
            let hers = try await env.send(.get, base, token: ana.token).json()["group"] as? [String: Any]
            #expect(hers?["role"] as? String == "owner")
            #expect(try await env.send(.delete, base, token: ana.token).status == .noContent)
            #expect(try await env.send(.get, base, token: ana.token).status == .notFound)
        }
    }

    @Test("GRP-003: deleting an account empties its messages and hands its groups on; export carries them")
    func accountDelete() async throws {
        try await LibraryHarness.run { env in
            let mine = try await claimHandle(env)
            let (anaID, anaToken) = try await signedInUser(env.stores)
            let anaHandle = freshHandle()
            _ = try await env.send(.put, "/v1/me/profile", json: ["handle": anaHandle], token: anaToken)
            _ = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": mine], token: anaToken)
            _ = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": anaHandle])
            // Ana owns one group with the harness user in it and one alone.
            let shared = try await env.send(.post, "/v1/groups", json: ["name": "Shared"], token: anaToken).json()
            let sharedGroup = try #require((shared["group"] as? [String: Any])?["id"] as? String)
            let general = try #require((shared["group"] as? [String: Any])?["defaultChannelId"] as? String)
            let alone = try await env.send(.post, "/v1/groups", json: ["name": "Alone"], token: anaToken).json()
            let aloneGroup = try #require((alone["group"] as? [String: Any])?["id"] as? String)
            #expect(try await env.send(
                .post, "/v1/groups/\(sharedGroup)/invites", json: ["userId": "\(env.userID)"], token: anaToken
            ).status == .noContent)
            let invite = try #require(
                try (await env.send(.get, "/v1/me/group-invites").json()["items"] as? [[String: Any]])?.first
            )
            _ = try await env.send(.post, "/v1/group-invites/\(invite["id"] as? String ?? "")/accept")
            let channel = "/v1/groups/\(sharedGroup)/channels/\(general)"
            _ = try await post(env, channel, "secret plans", token: anaToken)
            _ = try await post(env, channel, "mine stays")

            let export = try await env.send(.get, "/v1/me/export", token: anaToken).json()
            let exported = export["groupMessages"] as? [[String: Any]]
            #expect(exported?.compactMap { $0["body"] as? String } == ["secret plans"])
            #expect((export["groups"] as? [Any])?.count == 2)

            #expect(try await env.send(.delete, "/v1/me", token: anaToken).status == .noContent)
            let detail = try await env.send(.get, "/v1/groups/\(sharedGroup)").json()
            #expect((detail["group"] as? [String: Any])?["role"] as? String == "owner")
            let messages = try await env.send(.get, "\(channel)/messages").json()["items"] as? [[String: Any]]
            #expect(messages?.map { $0["body"] as? String } == ["", "mine stays"])
            #expect(messages?.first?["author"] == nil)
            let remaining = try await withMigratedStores { stores in
                try await stores.groups.groups(for: anaID)
            }
            #expect(remaining.isEmpty)
            #expect(!aloneGroup.isEmpty)
            let (_, other) = try await signedInUser(env.stores)
            #expect(try await env.send(.get, "/v1/groups/\(aloneGroup)", token: other).status == .notFound)
        }
    }
}

extension GroupTests {
    @Test("GRP-003: walking back page by page returns every message exactly once")
    func pagination() async throws {
        try await LibraryHarness.run { env in
            _ = try await claimHandle(env)
            let (group, general) = try await createGroup(env)
            let channel = "/v1/groups/\(group)/channels/\(general)"
            for number in 1 ... 7 {
                _ = try await post(env, channel, "p\(number)")
            }
            var seen: [String] = []
            var cursor = ""
            while true {
                let page = try await env.send(.get, "\(channel)/messages?limit=2\(cursor)")
                let items = try page.json()["items"] as? [[String: Any]] ?? []
                guard let first = items.first?["id"] as? String else { break }
                seen.insert(contentsOf: items.compactMap { $0["body"] as? String }, at: 0)
                cursor = "&before=\(first)"
            }
            #expect(seen == (1 ... 7).map { "p\($0)" })
        }
    }

    @Test("Mentions skip emails and words, dedupe, and tag the agent")
    func mentionParsing() throws {
        let ana = GroupMember(
            user: SocialUser(id: UserID(UUID()), handle: "ana", displayName: nil),
            role: .member,
            joinedAt: Date()
        )
        let (users, agent) = GroupService.mentions(in: "@ana @ANA mail@ana x@aaru @anax", members: [ana])
        #expect(users == [ana.user.id])
        #expect(!agent)
        #expect(GroupService.mentions(in: "hey @aaru!", members: []).agent)
        #expect(try GroupService.channelName("Séries  e Filmes") == "séries-e-filmes")
        #expect(throws: AppError.self) { try GroupService.channelName("!!!") }
    }

    struct Person {
        let id: String
        let token: String
        let handle: String
    }

    func freshHandle() -> String {
        "g" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(15)
    }

    /// Gives the harness user a handle and returns it.
    func claimHandle(_ env: LibraryHarness) async throws -> String {
        let handle = freshHandle()
        #expect(try await env.send(.put, "/v1/me/profile", json: ["handle": handle]).status == .ok)
        return handle
    }

    /// A second user with a handle, friends with the harness user.
    func friend(_ env: LibraryHarness, of handle: String) async throws -> Person {
        let (id, token) = try await signedInUser(env.stores)
        let theirs = freshHandle()
        _ = try await env.send(.put, "/v1/me/profile", json: ["handle": theirs], token: token)
        _ = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": theirs])
        let accepted = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": handle], token: token)
        #expect(try accepted.json()["relationship"] as? String == "friend")
        return Person(id: id.description, token: token, handle: theirs)
    }

    func createGroup(
        _ env: LibraryHarness,
        _ name: String = "Film club"
    ) async throws -> (id: String, general: String) {
        let created = try await env.send(.post, "/v1/groups", json: ["name": name])
        #expect(created.status == .ok)
        let group = try #require(created.json()["group"] as? [String: Any])
        return try (#require(group["id"] as? String), #require(group["defaultChannelId"] as? String))
    }

    /// Invites a friend and accepts for them.
    func join(_ env: LibraryHarness, _ person: Person, group: String) async throws {
        #expect(try await env.send(.post, "/v1/groups/\(group)/invites", json: ["userId": person.id]).status
            == .noContent)
        let invites = try await env.send(.get, "/v1/me/group-invites", token: person.token).json()
        let invite = try #require((invites["items"] as? [[String: Any]])?.first { $0["groupId"] as? String == group })
        let id = try #require(invite["id"] as? String)
        #expect(try await env.send(.post, "/v1/group-invites/\(id)/accept", token: person.token).status == .ok)
    }

    func bodies(_ reply: LibraryHarness.Reply) throws -> [String] {
        try (reply.json()["items"] as? [[String: Any]] ?? []).compactMap { $0["body"] as? String }
    }

    func post(
        _ env: LibraryHarness, _ path: String, _ body: String, token: String? = nil
    ) async throws -> [String: Any] {
        let reply = try await env.send(.post, "\(path)/messages", json: ["body": body], token: token)
        #expect(reply.status == .ok, "\(reply.text)")
        return try reply.json()
    }
}
