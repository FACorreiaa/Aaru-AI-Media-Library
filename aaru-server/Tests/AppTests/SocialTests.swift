import AaruCore
import Foundation
import Testing
@testable import aaru

@Suite("Handles, friends and blocks (SOC-001 / SOC-002 minimal)", .serialized)
struct SocialTests {
    /// A handle no earlier run of the shared test database has used.
    func freshHandle() -> String {
        "t" + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(15)
    }

    struct Person {
        let id: String
        let token: String
        let handle: String
    }

    /// A second signed-in user with a claimed handle.
    func friendlyUser(_ env: LibraryHarness) async throws -> Person {
        let (id, token) = try await signedInUser(env.stores)
        let handle = freshHandle()
        let reply = try await env.send(.put, "/v1/me/profile", json: ["handle": handle], token: token)
        #expect(reply.status == .ok)
        return Person(id: id.description, token: token, handle: handle)
    }

    func relationship(_ reply: LibraryHarness.Reply) throws -> String? {
        try reply.json()["relationship"] as? String
    }

    func handles(_ reply: LibraryHarness.Reply, _ key: String = "items") throws -> [String] {
        try (reply.json()[key] as? [[String: Any]] ?? []).compactMap { $0["handle"] as? String }
    }

    @Test("SOC-001: a handle is validated, lowercased, unique, and shows on /v1/me")
    func handles() async throws {
        try await LibraryHarness.run { env in
            for bad in ["ab", "has space", "way_too_long_for_a_handle", "émile", "aaru", "AARU"] {
                #expect(
                    try await env.send(.put, "/v1/me/profile", json: ["handle": bad]).status
                        == .unprocessableContent,
                    "\(bad)"
                )
            }
            let handle = freshHandle()
            let saved = try await env.send(
                .put, "/v1/me/profile", json: ["handle": handle.uppercased(), "displayName": " Ana "]
            ).json()
            #expect(saved["handle"] as? String == handle)
            #expect(saved["displayName"] as? String == "Ana")

            let account = try await env.send(.get, "/v1/me").json()
            #expect(account["handle"] as? String == handle)

            // Absent leaves the name; empty clears it.
            _ = try await env.send(.put, "/v1/me/profile", json: ["handle": handle])
            #expect(try await env.send(.get, "/v1/me").json()["displayName"] as? String == "Ana")
            _ = try await env.send(.put, "/v1/me/profile", json: ["handle": handle, "displayName": ""])
            #expect(try await env.send(.get, "/v1/me").json()["displayName"] == nil)

            let (_, other) = try await signedInUser(env.stores)
            #expect(try await env.send(.put, "/v1/me/profile", json: ["handle": handle], token: other).status
                == .conflict)
        }
    }

    @Test("SOC-002: request, accept, unfriend; asking each other accepts; withdrawing is either side's")
    func friendFlow() async throws {
        try await LibraryHarness.run { env in
            let ana = try await friendlyUser(env)
            // No handle, no social acts: the other side must see who is asking.
            let anonymous = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": ana.handle])
            #expect(anonymous.status == .unprocessableContent)
            #expect(try anonymous.json()["code"] as? String == "handle_required")

            let mine = freshHandle()
            _ = try await env.send(.put, "/v1/me/profile", json: ["handle": mine])
            #expect(try await env.send(.post, "/v1/social/friend-requests", json: ["handle": mine]).status
                == .unprocessableContent)

            let sent = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": ana.handle])
            #expect(try relationship(sent) == "outgoing")
            // Asking twice changes nothing.
            #expect(try await relationship(env.send(.post, "/v1/social/friend-requests", json: ["handle": ana.handle]))
                == "outgoing")
            #expect(try await relationship(env.send(.get, "/v1/social/users/\(mine)", token: ana.token)) == "incoming")

            let inbox = try await env.send(.get, "/v1/social/friend-requests", token: ana.token).json()
            let incoming = try #require(inbox["incoming"] as? [[String: Any]])
            #expect(incoming.count == 1)
            let requestID = try #require(incoming.first?["id"] as? String)
            #expect((incoming.first?["user"] as? [String: Any])?["handle"] as? String == mine)

            // Only the recipient accepts.
            #expect(try await env.send(.post, "/v1/social/friend-requests/\(requestID)/accept").status == .notFound)
            let accepted = try await env.send(.post, "/v1/social/friend-requests/\(requestID)/accept", token: ana.token)
            #expect(try accepted.json()["handle"] as? String == mine)
            #expect(try await handles(env.send(.get, "/v1/social/friends")) == [ana.handle])
            #expect(try await handles(env.send(.get, "/v1/social/friends", token: ana.token)) == [mine])
            #expect(try await relationship(env.send(.post, "/v1/social/friend-requests", json: ["handle": ana.handle]))
                == "friend")

            #expect(try await env.send(.delete, "/v1/social/friends/\(ana.id)").status == .noContent)
            #expect(try await env.send(.delete, "/v1/social/friends/\(ana.id)").status == .notFound)
            #expect(try await handles(env.send(.get, "/v1/social/friends", token: ana.token)).isEmpty)

            // Both ask: the second ask is an acceptance.
            _ = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": ana.handle])
            let mutual = try await env.send(
                .post,
                "/v1/social/friend-requests",
                json: ["handle": mine],
                token: ana.token
            )
            #expect(try relationship(mutual) == "friend")
            let after = try await env.send(.get, "/v1/social/friend-requests").json()
            #expect((after["outgoing"] as? [Any])?.isEmpty == true)

            // Withdrawing: the sender cancels, a second time is a 404.
            let kai = try await friendlyUser(env)
            _ = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": kai.handle])
            let outgoing = try await env.send(.get, "/v1/social/friend-requests").json()["outgoing"] as? [[String: Any]]
            let pending = try #require(outgoing?.first?["id"] as? String)
            #expect(try await env.send(.delete, "/v1/social/friend-requests/\(pending)").status == .noContent)
            #expect(try await env.send(.delete, "/v1/social/friend-requests/\(pending)").status == .notFound)
            #expect(try await env.send(.get, "/v1/social/users/nobody_has_this").status == .notFound)
        }
    }

    @Test("SOC-002: a block ends the friendship and makes each side a 404 to the other")
    func blocks() async throws {
        try await LibraryHarness.run { env in
            let mine = freshHandle()
            _ = try await env.send(.put, "/v1/me/profile", json: ["handle": mine])
            let ana = try await friendlyUser(env)
            _ = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": ana.handle])
            _ = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": mine], token: ana.token)
            #expect(try await handles(env.send(.get, "/v1/social/friends")) == [ana.handle])

            #expect(try await env.send(.put, "/v1/social/blocks/\(ana.id)").status == .noContent)
            #expect(try await env.send(.put, "/v1/social/blocks/\(ana.id)").status == .noContent)
            #expect(try await handles(env.send(.get, "/v1/social/friends")).isEmpty)
            #expect(try await handles(env.send(.get, "/v1/social/blocks")) == [ana.handle])

            // Both directions look exactly like nobody being there.
            let fromAna = try await env.send(.get, "/v1/social/users/\(mine)", token: ana.token)
            let unknown = try await env.send(.get, "/v1/social/users/nobody_has_this", token: ana.token)
            #expect(fromAna.status == .notFound)
            #expect(fromAna.text == unknown.text)
            #expect(try await env.send(.get, "/v1/social/users/\(ana.handle)").status == .notFound)
            #expect(try await env.send(.post, "/v1/social/friend-requests", json: ["handle": mine], token: ana.token)
                .status == .notFound)

            #expect(try await env.send(.delete, "/v1/social/blocks/\(ana.id)").status == .noContent)
            #expect(try await env.send(.delete, "/v1/social/blocks/\(ana.id)").status == .notFound)
            #expect(try await relationship(env.send(.get, "/v1/social/users/\(ana.handle)")) == "none")

            #expect(try await env.send(.put, "/v1/social/blocks/\(env.userID)").status == .unprocessableContent)
            #expect(try await env.send(.put, "/v1/social/blocks/\(UUID())").status == .notFound)
        }
    }

    @Test("SOC-002: reports are accepted for real users only; account delete removes the social graph")
    func reportsAndDelete() async throws {
        try await LibraryHarness.run { env in
            let mine = freshHandle()
            _ = try await env.send(.put, "/v1/me/profile", json: ["handle": mine])
            let ana = try await friendlyUser(env)
            #expect(try await env.send(.post, "/v1/social/reports", json: ["userId": ana.id, "reason": "spam"]).status
                == .noContent)
            #expect(try await env.send(.post, "/v1/social/reports", json: ["userId": "\(UUID())", "reason": "spam"])
                .status == .notFound)

            _ = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": mine], token: ana.token)
            _ = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": ana.handle])
            #expect(try await handles(env.send(.get, "/v1/social/friends")) == [ana.handle])
            // The account export carries the social graph too.
            #expect(try await handles(env.send(.get, "/v1/me/export"), "friends") == [ana.handle])
            #expect(try await env.send(.delete, "/v1/me", token: ana.token).status == .noContent)
            #expect(try await handles(env.send(.get, "/v1/social/friends")).isEmpty)
            #expect(try await env.send(.get, "/v1/social/users/\(ana.handle)").status == .notFound)
        }
    }

    @Test("SOC-008: lookups and requests are limited per hour, separately")
    func rateLimits() async throws {
        try await LibraryHarness.run { env in
            _ = try await env.send(.put, "/v1/me/profile", json: ["handle": freshHandle()])
            let ana = try await friendlyUser(env)
            for _ in 0 ..< SocialService.lookupsPerHour {
                #expect(try await env.send(.get, "/v1/social/users/\(freshHandle())").status == .notFound)
            }
            let over = try await env.send(.get, "/v1/social/users/\(ana.handle)")
            #expect(over.status == .tooManyRequests)
            #expect(try over.json()["code"] as? String == "rate_limited")
            // A spent lookup budget leaves requests alone.
            #expect(try await env.send(.post, "/v1/social/friend-requests", json: ["handle": ana.handle]).status
                == .ok)
            for _ in 1 ..< SocialService.requestsPerHour {
                _ = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": freshHandle()])
            }
            #expect(try await env.send(.post, "/v1/social/friend-requests", json: ["handle": ana.handle]).status
                == .tooManyRequests)
            // Another user is unaffected.
            #expect(try await env.send(.get, "/v1/social/users/\(ana.handle)", token: ana.token).status == .ok)
        }
    }

    @Test("SOC-008: a friend or yourself costs no lookup; spent requests leave lookups alone")
    func rateLimitsSpareFriends() async throws {
        try await LibraryHarness.run { env in
            let mine = freshHandle()
            _ = try await env.send(.put, "/v1/me/profile", json: ["handle": mine])
            let ana = try await friendlyUser(env)
            _ = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": ana.handle])
            _ = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": mine], token: ana.token)
            for _ in 1 ..< SocialService.requestsPerHour {
                _ = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": freshHandle()])
            }
            #expect(try await env.send(.post, "/v1/social/friend-requests", json: ["handle": freshHandle()]).status
                == .tooManyRequests)
            // A spent request budget leaves lookups alone.
            let bob = try await friendlyUser(env)
            #expect(try await env.send(.get, "/v1/social/users/\(bob.handle)").status == .ok)
            for _ in 1 ..< SocialService.lookupsPerHour {
                _ = try await env.send(.get, "/v1/social/users/\(freshHandle())")
            }
            #expect(try await env.send(.get, "/v1/social/users/\(freshHandle())").status == .tooManyRequests)
            #expect(try await env.send(.get, "/v1/social/users/\(bob.handle)").status == .tooManyRequests)
            // Profiles of friends open through this lookup on every hover: those, and yourself, are free.
            let friend = try await env.send(.get, "/v1/social/users/\(ana.handle)")
            #expect(friend.status == .ok)
            #expect(try relationship(friend) == "friend")
            #expect(try await env.send(.get, "/v1/social/users/\(mine)").status == .ok)
        }
    }

    @Test("SOC-008: handle changes are limited per hour; probing a taken one counts; resaving is free")
    func handleChangeLimit() async throws {
        try await LibraryHarness.run { env in
            let taken = try await friendlyUser(env).handle
            for _ in 0 ..< SocialService.handleChangesPerHour {
                #expect(try await env.send(.put, "/v1/me/profile", json: ["handle": freshHandle()]).status == .ok)
            }
            // "That handle is taken" would say who is on Aaru, so a taken one costs like any change.
            let probe = try await env.send(.put, "/v1/me/profile", json: ["handle": taken])
            #expect(probe.status == .tooManyRequests)
            let current = try #require(try await env.send(.get, "/v1/me").json()["handle"] as? String)
            #expect(try await env.send(.put, "/v1/me/profile", json: ["handle": current, "displayName": "Ana"]).status
                == .ok)
        }
    }
}
