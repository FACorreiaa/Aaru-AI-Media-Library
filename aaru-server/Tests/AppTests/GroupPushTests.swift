import AaruCore
import Foundation
import Testing
@testable import aaru

/// Mention and invite alerts against a fake APNs (GRP-012). No real key, no network.
@Suite("Group push (GRP-012)", .serialized)
struct GroupPushTests {
    let groups = GroupTests()

    /// Registers a device for whoever `token` signs in, and returns its APNs token.
    func device(_ env: LibraryHarness, token: String? = nil) async throws -> String {
        let device = PushTests.token()
        let reply = try await env.send(.put, "/v1/devices", json: [
            "token": device, "environment": "production", "bundleId": "com.fernandocorreia.aaru",
        ], token: token)
        #expect(reply.status == .noContent)
        return device
    }

    func settings(_ env: LibraryHarness, _ json: [String: Bool], token: String? = nil) async throws -> [String: Any] {
        let reply = try await env.send(.put, "/v1/me/notifications", json: json, token: token)
        #expect(reply.status == .ok, "\(reply.text)")
        return try reply.json()
    }

    @Test("Notification switches start off, and a PUT changes only the ones it sends")
    func switches() async throws {
        try await LibraryHarness.run { env in
            let initial = try await env.send(.get, "/v1/me/notifications").json()
            #expect(initial["airing"] as? Bool == false)
            #expect(initial["groupMentions"] as? Bool == false)
            #expect(initial["groupInvites"] as? Bool == false)
            let mentions = try await settings(env, ["groupMentions": true])
            #expect(mentions["groupMentions"] as? Bool == true)
            #expect(mentions["airing"] as? Bool == false)
            let airing = try await settings(env, ["airing": true])
            #expect(airing["airing"] as? Bool == true)
            #expect(airing["groupMentions"] as? Bool == true)
            #expect(airing["groupInvites"] as? Bool == false)
        }
    }

    @Test("A mention alerts the tagged member once, with the channel's link and none of the message")
    func mentions() async throws {
        let sender = PushTests.FakeSender()
        try await LibraryHarness.run(push: sender) { env in
            let mine = try await groups.claimHandle(env)
            let (group, general) = try await groups.createGroup(env)
            let ana = try await groups.friend(env, of: mine)
            let ben = try await groups.friend(env, of: mine)
            let cai = try await groups.friend(env, of: mine)
            let dan = try await groups.friend(env, of: mine)
            for person in [ana, ben, cai, dan] {
                try await groups.join(env, person, group: group)
            }
            let anaDevice = try await device(env, token: ana.token)
            var names = [anaDevice: "ana"]
            try names[await device(env)] = "me"
            for (name, person) in [("ben", ben), ("dan", dan)] {
                try names[await device(env, token: person.token)] = name
            }
            for person in [ana, ben, dan] {
                _ = try await settings(env, ["groupMentions": true], token: person.token)
            }
            try names[await device(env, token: cai.token)] = "cai"
            _ = try await settings(env, ["groupMentions": true])
            // Ben muted the group, Cai never turned mention alerts on, Dan blocked the author.
            let muted = try await env.send(.put, "/v1/groups/\(group)/me", json: ["muted": true], token: ben.token)
            #expect(try muted.json()["muted"] as? Bool == true)
            #expect(try muted.json()["shareProgress"] as? Bool == false)
            _ = try await env.send(.put, "/v1/social/blocks/\(env.userID)", token: dan.token)

            let path = "/v1/groups/\(group)/channels/\(general)"
            let body = "@\(ana.handle) @\(ben.handle) @\(cai.handle) @\(dan.handle) @\(mine) the twist is the dog"
            let json: [String: Any] = ["body": body, "clientNonce": "n-1"]
            #expect(try await env.send(.post, "\(path)/messages", json: json).status == .ok)
            // A retry returns the first message and alerts nobody again.
            #expect(try await env.send(.post, "\(path)/messages", json: json).status == .ok)

            let sent = sender.messages
            #expect(sent.map { names[$0.1.token] } == ["ana"])
            let alert = try #require(sent.first?.0)
            #expect(alert.title == "Film club")
            #expect(alert.body == "@\(mine) mentioned you in #general")
            #expect(alert.payload["url"] == "aaru://group/\(group)/channel/\(general)")
            #expect(alert.payload["groupId"] == group)
            #expect(alert.payload["channelId"] == general)
            #expect(!"\(alert)".contains("twist"))
        }
    }

    @Test("An invite alerts the friend once, only when they turned invite alerts on")
    func invites() async throws {
        let sender = PushTests.FakeSender()
        try await LibraryHarness.run(push: sender) { env in
            let mine = try await groups.claimHandle(env)
            let (group, _) = try await groups.createGroup(env, "Anime night")
            let ana = try await groups.friend(env, of: mine)
            let ben = try await groups.friend(env, of: mine)
            let anaDevice = try await device(env, token: ana.token)
            _ = try await device(env, token: ben.token)
            _ = try await settings(env, ["groupInvites": true], token: ana.token)

            for person in [ana, ben, ana] {
                let reply = try await env.send(.post, "/v1/groups/\(group)/invites", json: ["userId": person.id])
                #expect(reply.status == .noContent)
            }
            let sent = sender.messages
            #expect(sent.map(\.1.token) == [anaDevice])
            #expect(sent.first?.0.body == "@\(mine) invited you to Anime night")
            #expect(sent.first?.0.payload["url"] == "aaru://groups")
        }
    }

    @Test("Web alerts open the channel, or the groups page for an invite")
    func webPaths() {
        let channel = GroupService.mentionAlert(
            by: SocialUser(id: UserID(UUID()), handle: "ana", displayName: "  "),
            group: "Film club",
            channel: GroupChannel(
                id: UUID(), groupID: UUID(), name: "general", topic: nil, position: 0, isDefault: true,
                createdAt: Date()
            )
        )
        #expect(channel.body == "@ana mentioned you in #general")
        let (group, general) = (channel.payload["groupId"] ?? "", channel.payload["channelId"] ?? "")
        #expect(WebPushSender.path(channel.payload) == "/app/groups/\(group)/\(general)")
        let invite = GroupService.inviteAlert(
            by: SocialUser(id: UserID(UUID()), handle: "ana", displayName: "Ana"), group: "Film club"
        )
        #expect(invite.body == "Ana invited you to Film club")
        #expect(WebPushSender.path(invite.payload) == "/app/groups")
    }
}
