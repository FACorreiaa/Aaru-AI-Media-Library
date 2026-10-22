import AaruCore
import Foundation
import Testing
@testable import aaru

@Suite("Friend invite links (SOC-002)", .serialized)
struct InviteTests {
    let social = SocialTests()

    /// A bearer token no session holds, so the request is signed out.
    let signedOut = "signed-out"

    func code(_ reply: LibraryHarness.Reply) throws -> String {
        try #require(reply.json()["code"] as? String)
    }

    @Test("an invite makes a one-use link that previews signed out and befriends on redeem")
    func redeem() async throws {
        try await LibraryHarness.run { env in
            // No handle, no invite: the friend must see who sent it.
            #expect(try await env.send(.post, "/v1/social/invites", json: [:] as [String: Any]).status
                == .unprocessableContent)
            let mine = social.freshHandle()
            _ = try await env.send(.put, "/v1/me/profile", json: ["handle": mine, "displayName": "Fern"])

            let created = try await env.send(.post, "/v1/social/invites", json: [:] as [String: Any])
            #expect(created.status == .ok)
            let invite = try code(created)
            #expect(invite.count == InviteService.codeLength)
            #expect(try created.json()["url"] as? String == "https://aaruapp.com/i/\(invite)")

            let preview = try await env.send(.get, "/v1/invites/\(invite)", token: signedOut)
            #expect(preview.status == .ok)
            let inviter = try #require(preview.json()["inviter"] as? [String: Any])
            #expect(inviter["handle"] as? String == mine)
            #expect(inviter["displayName"] as? String == "Fern")
            #expect(try preview.json()["relationship"] == nil)
            #expect(try await social.relationship(env.send(.get, "/v1/invites/\(invite)")) == "self")

            // The invitee needs a handle too, and redeeming your own link is refused.
            let (_, newcomer) = try await signedInUser(env.stores)
            let noHandle = try await env.send(
                .post, "/v1/social/invites/\(invite)/redeem", json: ["addTitle": false], token: newcomer
            )
            #expect(try noHandle.json()["code"] as? String == "handle_required")
            #expect(try await env.send(.post, "/v1/social/invites/\(invite)/redeem", json: ["addTitle": false]).status
                == .conflict)

            let ana = try await social.friendlyUser(env)
            // A pending request between them is answered by the invite.
            _ = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": mine], token: ana.token)
            #expect(try await social
                .relationship(env.send(.get, "/v1/invites/\(invite)", token: ana.token)) == "outgoing")
            let redeemed = try await env.send(
                .post, "/v1/social/invites/\(invite)/redeem", json: ["addTitle": true], token: ana.token
            )
            #expect(redeemed.status == .ok)
            #expect(try (redeemed.json()["friend"] as? [String: Any])?["handle"] as? String == mine)
            #expect(try redeemed.json()["titleAdded"] as? Bool == false)
            #expect(try await social.handles(env.send(.get, "/v1/social/friends")) == [ana.handle])
            let requests = try await env.send(.get, "/v1/social/friend-requests").json()
            #expect((requests["incoming"] as? [Any])?.isEmpty == true)

            // Spent: everyone else now sees the same dead end as a code that never existed.
            let kai = try await social.friendlyUser(env)
            let spent = try await env.send(.get, "/v1/invites/\(invite)", token: kai.token)
            let unknown = try await env.send(.get, "/v1/invites/nothing_here", token: kai.token)
            #expect(spent.status == .notFound)
            #expect(spent.text == unknown.text)
            #expect(try await env.send(
                .post, "/v1/social/invites/\(invite)/redeem", json: ["addTitle": false], token: kai.token
            ).status == .notFound)
            #expect(try await env.send(.get, "/v1/social/invites").json()["items"] is [Any])
        }
    }

    @Test("an invite's title lands on Plan to watch only when asked, and never over an existing item")
    func title() async throws {
        try await LibraryHarness.run { env in
            _ = try await env.send(.put, "/v1/me/profile", json: ["handle": social.freshHandle()])
            let tmdb = env.stubMovie("Arrival")
            let created = try await env.send(
                .post, "/v1/social/invites", json: ["title": ["type": "movie", "ids": ["tmdb": tmdb]]]
            )
            #expect(created.status == .ok)
            #expect(try (created.json()["title"] as? [String: Any])?["title"] as? String == "Arrival")
            let invite = try code(created)
            let preview = try await env.send(.get, "/v1/invites/\(invite)", token: signedOut).json()
            #expect((preview["title"] as? [String: Any])?["title"] as? String == "Arrival")

            let ana = try await social.friendlyUser(env)
            let redeemed = try await env.send(
                .post, "/v1/social/invites/\(invite)/redeem", json: ["addTitle": true], token: ana.token
            ).json()
            #expect(redeemed["titleAdded"] as? Bool == true)
            let library = try await env.send(.get, "/v1/library/items", token: ana.token).json()
            let items = try #require(library["items"] as? [[String: Any]])
            #expect(items.count == 1)
            #expect(items.first?["status"] as? String == "wishlist")

            // Someone who already has it keeps their own status.
            let second = try await code(env.send(
                .post, "/v1/social/invites", json: ["title": ["type": "movie", "ids": ["tmdb": tmdb]]]
            ))
            let kai = try await social.friendlyUser(env)
            let kaiItem = try await env.send(
                .post, "/v1/library/items", json: [
                    "mediaRef": ["type": "movie", "ids": ["tmdb": tmdb]],
                    "status": "finished",
                ],
                token: kai.token
            )
            #expect(kaiItem.status == .ok)
            let kept = try await env.send(
                .post, "/v1/social/invites/\(second)/redeem", json: ["addTitle": true], token: kai.token
            ).json()
            #expect(kept["titleAdded"] as? Bool == false)
            let kaiLibrary = try await env.send(.get, "/v1/library/items", token: kai.token).json()
            #expect((kaiLibrary["items"] as? [[String: Any]])?.first?["status"] as? String == "finished")
        }
    }

    @Test("revoked, expired and blocked invites all read as invalid; already friends keeps the link")
    func deadEnds() async throws {
        try await LibraryHarness.run { env in
            let mine = social.freshHandle()
            _ = try await env.send(.put, "/v1/me/profile", json: ["handle": mine])
            let ana = try await social.friendlyUser(env)

            let revoked = try await code(env.send(.post, "/v1/social/invites", json: [:] as [String: Any]))
            #expect(try await env.send(.delete, "/v1/social/invites/\(revoked)", token: ana.token).status == .notFound)
            #expect(try await env.send(.delete, "/v1/social/invites/\(revoked)").status == .noContent)
            #expect(try await env.send(.get, "/v1/invites/\(revoked)", token: signedOut).status == .notFound)
            #expect(try await env.send(.delete, "/v1/social/invites/\(revoked)").status == .notFound)

            let now = Date()
            let expired = InviteService.newCode()
            try await env.stores.social.createInvite(FriendInvite(
                id: UUID(), code: expired, inviter: env.userID, titleID: nil,
                createdAt: now.addingTimeInterval(-InviteService.lifetime - 60), expiresAt: now.addingTimeInterval(-60)
            ))
            #expect(try await env.send(.get, "/v1/invites/\(expired)", token: signedOut).status == .notFound)
            #expect(try await env.send(
                .post, "/v1/social/invites/\(expired)/redeem", json: ["addTitle": false], token: ana.token
            ).status == .notFound)

            // A block either way hides the invite from the blocked side.
            let blocked = try await code(env.send(.post, "/v1/social/invites", json: [:] as [String: Any]))
            #expect(try await env.send(.put, "/v1/social/blocks/\(ana.id)").status == .noContent)
            #expect(try await env.send(.get, "/v1/invites/\(blocked)", token: ana.token).status == .notFound)
            #expect(try await env.send(
                .post, "/v1/social/invites/\(blocked)/redeem", json: ["addTitle": false], token: ana.token
            ).status == .notFound)
            #expect(try await env.send(.get, "/v1/invites/\(blocked)", token: signedOut).status == .ok)
            _ = try await env.send(.delete, "/v1/social/blocks/\(ana.id)")

            // Already friends: a success that leaves the link for someone else.
            _ = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": ana.handle])
            _ = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": mine], token: ana.token)
            #expect(try await env.send(
                .post, "/v1/social/invites/\(blocked)/redeem", json: ["addTitle": false], token: ana.token
            ).status == .ok)
            #expect(try await env.send(.get, "/v1/invites/\(blocked)", token: signedOut).status == .ok)
            let open = try await env.send(.get, "/v1/social/invites").json()["items"] as? [[String: Any]]
            #expect(open?.compactMap { $0["code"] as? String } == [blocked])
        }
    }

    @Test("open invites are capped")
    func cap() async throws {
        try await LibraryHarness.run { env in
            _ = try await env.send(.put, "/v1/me/profile", json: ["handle": social.freshHandle()])
            for _ in 0 ..< InviteService.maxOpenInvites {
                #expect(try await env.send(.post, "/v1/social/invites", json: [:] as [String: Any]).status == .ok)
            }
            let over = try await env.send(.post, "/v1/social/invites", json: [:] as [String: Any])
            #expect(try over.json()["code"] as? String == "too_many_invites")
        }
    }

    @Test("only a bare invite code is public")
    func publicPaths() {
        #expect(AuthMiddleware.isPublic("/v1/invites/abc123"))
        #expect(!AuthMiddleware.isPublic("/v1/invites/"))
        #expect(!AuthMiddleware.isPublic("/v1/invites/abc/redeem"))
        #expect(!AuthMiddleware.isPublic("/v1/social/invites"))
        #expect(AuthMiddleware.isPublic("/v1/health"))
    }
}
