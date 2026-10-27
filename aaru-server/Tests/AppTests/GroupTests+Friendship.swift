import Foundation
import Testing
@testable import aaru

extension GroupTests {
    @Test("GRP-013: unfriending drops the pair's group invite; friends again, a fresh one works")
    func invitesEndWithFriendship() async throws {
        try await LibraryHarness.run { env in
            let mine = try await claimHandle(env)
            let (group, _) = try await createGroup(env)
            let ana = try await friend(env, of: mine)
            _ = try await env.send(.post, "/v1/groups/\(group)/invites", json: ["userId": ana.id])
            let stale = try #require(try await groupInbox(env, ana).first?["id"] as? String)
            #expect(try await env.send(.delete, "/v1/social/friends/\(ana.id)").status == .noContent)
            #expect(try await groupInbox(env, ana).isEmpty)
            #expect(try await env.send(.post, "/v1/group-invites/\(stale)/accept", token: ana.token).status
                == .notFound)
            _ = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": ana.handle])
            _ = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": mine], token: ana.token)
            try await join(env, ana, group: group)
        }
    }

    @Test("GRP-013: a block drops the pair's invite; a third person's waiting invite stays")
    func blockDropsOnlyThePairsInvites() async throws {
        try await LibraryHarness.run { env in
            let mine = try await claimHandle(env)
            let (group, _) = try await createGroup(env)
            let bob = try await friend(env, of: mine)
            let cara = try await friend(env, of: mine)
            _ = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": bob.handle], token: cara.token)
            _ = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": cara.handle], token: bob.token)
            let caras = try await env.send(.post, "/v1/groups", json: ["name": "Cara's"], token: cara.token)
            let carasGroup = try #require(try (caras.json()["group"] as? [String: Any])?["id"] as? String)
            _ = try await env.send(
                .post,
                "/v1/groups/\(carasGroup)/invites",
                json: ["userId": bob.id],
                token: cara.token
            )
            _ = try await env.send(.post, "/v1/groups/\(group)/invites", json: ["userId": bob.id])
            #expect(try await groupInbox(env, bob).count == 2)
            _ = try await env.send(.put, "/v1/social/blocks/\(env.userID)", token: bob.token)
            let left = try await groupInbox(env, bob)
            #expect(left.compactMap { $0["groupId"] as? String } == [carasGroup])
            #expect(left.compactMap { ($0["inviter"] as? [String: Any])?["handle"] as? String } == [cara.handle])
        }
    }

    @Test("GRP-013: accept re-checks the friendship; a lapsed invite reads as missing and goes")
    func acceptRechecksFriendship() async throws {
        try await LibraryHarness.run { env in
            let mine = try await claimHandle(env)
            let (group, _) = try await createGroup(env)
            let dee = try await friend(env, of: mine)
            _ = try await env.send(.post, "/v1/groups/\(group)/invites", json: ["userId": dee.id])
            let orphan = try #require(try await groupInbox(env, dee).first?["id"] as? String)
            // The friendship goes behind the store's back, as a race with a block could leave it.
            let deeID = try #require(UUID(uuidString: dee.id))
            try await withSQL { sql in
                try await sql.raw("""
                DELETE FROM social_friendships
                WHERE user_low = LEAST(\(bind: env.userID.rawValue), \(bind: deeID))
                  AND user_high = GREATEST(\(bind: env.userID.rawValue), \(bind: deeID))
                """).run()
            }
            let refused = try await env.send(.post, "/v1/group-invites/\(orphan)/accept", token: dee.token)
            let missing = try await env.send(.post, "/v1/group-invites/\(UUID())/accept", token: dee.token)
            #expect(refused.status == .notFound)
            #expect(refused.text == missing.text)
            #expect(try await groupInbox(env, dee).isEmpty)
        }
    }

    func groupInbox(_ env: LibraryHarness, _ person: Person) async throws -> [[String: Any]] {
        try await env.send(.get, "/v1/me/group-invites", token: person.token).json()["items"] as? [[String: Any]] ?? []
    }
}
