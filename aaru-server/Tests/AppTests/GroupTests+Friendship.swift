import Foundation
import Testing
@testable import aaru

extension GroupTests {
    @Test("GRP-013: unfriending or blocking drops the pair's group invites; accept re-checks friendship")
    func invitesEndWithFriendship() async throws {
        try await LibraryHarness.run { env in
            let mine = try await claimHandle(env)
            let (group, _) = try await createGroup(env)
            func inbox(_ person: Person) async throws -> [[String: Any]] {
                try await env.send(.get, "/v1/me/group-invites", token: person.token)
                    .json()["items"] as? [[String: Any]] ?? []
            }

            // Unfriend: the invite goes, and becoming friends again allows a fresh one.
            let ana = try await friend(env, of: mine)
            _ = try await env.send(.post, "/v1/groups/\(group)/invites", json: ["userId": ana.id])
            let stale = try #require(try await inbox(ana).first?["id"] as? String)
            #expect(try await env.send(.delete, "/v1/social/friends/\(ana.id)").status == .noContent)
            #expect(try await inbox(ana).isEmpty)
            #expect(try await env.send(.post, "/v1/group-invites/\(stale)/accept", token: ana.token).status
                == .notFound)
            _ = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": ana.handle])
            _ = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": mine], token: ana.token)
            try await join(env, ana, group: group)

            // Block: the blocked pair's invite goes, but a third member's invite to them stays.
            let bob = try await friend(env, of: mine)
            let cy = try await friend(env, of: mine)
            try await join(env, cy, group: group)
            _ = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": bob.handle], token: cy.token)
            _ = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": cy.handle], token: bob.token)
            _ = try await env.send(.post, "/v1/groups/\(group)/invites", json: ["userId": bob.id])
            #expect(try await inbox(bob).count == 1)
            _ = try await env.send(.put, "/v1/social/blocks/\(env.userID)", token: bob.token)
            #expect(try await inbox(bob).isEmpty)
            _ = try await env.send(.post, "/v1/groups/\(group)/invites", json: ["userId": bob.id], token: cy.token)
            #expect(try await inbox(bob).count == 1)

            // A friendship gone behind the store's back: accept answers like a missing invite and removes it.
            let dee = try await friend(env, of: mine)
            _ = try await env.send(.post, "/v1/groups/\(group)/invites", json: ["userId": dee.id])
            let orphan = try #require(try await inbox(dee).first?["id"] as? String)
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
            #expect(try await inbox(dee).isEmpty)
        }
    }
}
