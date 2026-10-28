import AaruCore
import Foundation
import Testing
@testable import aaru

@Suite("Share links (SHR-002)", .serialized)
struct ShareTests {
    let social = SocialTests()

    /// A bearer token no session holds, so the request is signed out.
    let signedOut = "signed-out"

    func code(_ reply: LibraryHarness.Reply) throws -> String {
        try #require(reply.json()["code"] as? String)
    }

    func from(_ reply: LibraryHarness.Reply) throws -> [String: Any]? {
        try reply.json()["from"] as? [String: Any]
    }

    func handle(_ from: [String: Any]?) -> String? {
        (from?["user"] as? [String: Any])?["handle"] as? String
    }

    struct Shared {
        let handle: String
        let code: String
        let tmdb: String
    }

    /// The default user with a handle, sharing Arrival with a note.
    func shareArrival(_ env: LibraryHarness, note: String? = "watch this") async throws -> Shared {
        let mine = social.freshHandle()
        _ = try await env.send(.put, "/v1/me/profile", json: ["handle": mine, "displayName": "Fern"])
        let tmdb = env.stubMovie("Arrival")
        var body: [String: Any] = ["target": ["kind": "title", "ref": ["type": "movie", "ids": ["tmdb": tmdb]]]]
        if let note {
            body["note"] = note
        }
        let created = try await env.send(.post, "/v1/shares", json: body)
        #expect(created.status == .ok)
        return try Shared(handle: mine, code: code(created), tmdb: tmdb)
    }

    /// Two people who asked each other are friends.
    func befriend(_ env: LibraryHarness, _ mine: String, _ other: SocialTests.Person) async throws {
        _ = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": other.handle])
        _ = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": mine], token: other.token)
    }

    @Test("a share makes a reusable link that shows its title signed out, with nobody's name")
    func createAndOpenSignedOut() async throws {
        try await LibraryHarness.run { env in
            let code = try await shareArrival(env).code
            #expect(code.count == ShareService.codeLength)
            let again = try await env.send(.get, "/v1/shares/\(code)", token: signedOut)
            #expect(again.status == .ok)
            let preview = try again.json()
            #expect(preview["kind"] as? String == "title")
            #expect(preview["unavailable"] as? Bool == false)
            #expect((preview["title"] as? [String: Any])?["title"] as? String == "Arrival")
            #expect(preview["from"] == nil)
            #expect(preview["libraryItemId"] == nil)
            #expect(preview["status"] == nil)
            #expect(try await env.send(.get, "/v1/shares/\(code)", token: signedOut).status == .ok, "reusable")
        }
    }

    @Test("the link's url is the web page")
    func url() async throws {
        try await LibraryHarness.run(sports: sportsWith(["42"])) { env in
            let created = try await env.send(.post, "/v1/shares", json: ["target": ["kind": "sport_event", "id": "42"]])
            let code = try code(created)
            #expect(try created.json()["url"] as? String == "https://aaruapp.com/s/\(code)")
        }
    }

    @Test("the same target and note reuse one link; another note makes another")
    func dedupeByNote() async throws {
        try await LibraryHarness.run(sports: sportsWith(["42"])) { env in
            let target: [String: Any] = ["kind": "sport_event", "id": "42"]
            let first = try await code(env.send(.post, "/v1/shares", json: ["target": target, "note": "hi"]))
            let same = try await code(env.send(.post, "/v1/shares", json: ["target": target, "note": "  hi "]))
            let other = try await code(env.send(.post, "/v1/shares", json: ["target": target, "note": "yo"]))
            let bare = try await code(env.send(.post, "/v1/shares", json: ["target": target]))
            let blank = try await code(env.send(.post, "/v1/shares", json: ["target": target, "note": "   "]))
            #expect(first == same)
            #expect(first != other)
            #expect(bare != first && bare == blank)
        }
    }

    @Test("a friend sees who sent it and the note; a stranger does not")
    func friendSeesSender() async throws {
        try await LibraryHarness.run { env in
            let shared = try await shareArrival(env)
            let (mine, code) = (shared.handle, shared.code)
            let ana = try await social.friendlyUser(env)
            try await befriend(env, mine, ana)
            let seen = try await from(env.send(.get, "/v1/shares/\(code)", token: ana.token))
            #expect(handle(seen) == mine)
            #expect(seen?["note"] as? String == "watch this")

            let kai = try await social.friendlyUser(env)
            #expect(try await from(env.send(.get, "/v1/shares/\(code)", token: kai.token)) == nil)
        }
    }

    @Test("the sender sees their own name on their link")
    func senderSeesSelf() async throws {
        try await LibraryHarness.run { env in
            let shared = try await shareArrival(env)
            let (mine, code) = (shared.handle, shared.code)
            let own = try await env.send(.get, "/v1/shares/\(code)")
            #expect(try handle(from(own)) == mine)
        }
    }

    @Test("a block either way shows the content and hides the sender")
    func blockHidesSender() async throws {
        try await LibraryHarness.run { env in
            let shared = try await shareArrival(env)
            let (mine, code) = (shared.handle, shared.code)
            let ana = try await social.friendlyUser(env)
            try await befriend(env, mine, ana)
            #expect(try await env.send(.put, "/v1/social/blocks/\(env.userID)", token: ana.token).status == .noContent)
            let blocked = try await env.send(.get, "/v1/shares/\(code)", token: ana.token)
            #expect(blocked.status == .ok)
            #expect(try (blocked.json()["title"] as? [String: Any])?["title"] as? String == "Arrival")
            #expect(try from(blocked) == nil)
        }
    }

    @Test("a signed-in opener who has the title gets their item and status")
    func viewerItem() async throws {
        try await LibraryHarness.run { env in
            let shared = try await shareArrival(env)
            let (code, tmdb) = (shared.code, shared.tmdb)
            let ana = try await social.friendlyUser(env)
            let added = try await env.send(
                .post, "/v1/library/items",
                json: ["mediaRef": ["type": "movie", "ids": ["tmdb": tmdb]], "status": "wishlist"], token: ana.token
            )
            #expect(added.status == .ok || added.status == .created)
            let preview = try await env.send(.get, "/v1/shares/\(code)", token: ana.token).json()
            #expect(preview["libraryItemId"] is String)
            #expect(preview["status"] as? String == "wishlist")
        }
    }

    @Test("a shared match shows its result to anyone")
    func sportEventResult() async throws {
        let sports = FakeSports()
        sports.events["42"] = sampleMatch(
            "42", home: "133604", away: "133615", at: "2026-10-18T14:00:00Z", homeScore: 2, awayScore: 1
        )
        try await LibraryHarness.run(sports: sports) { env in
            let code = try await code(env.send(
                .post,
                "/v1/shares",
                json: ["target": ["kind": "sport_event", "id": "42"]]
            ))
            let preview = try await env.send(.get, "/v1/shares/\(code)", token: signedOut).json()
            #expect(preview["kind"] as? String == "sport_event")
            let event = try #require(preview["sportEvent"] as? [String: Any])
            #expect((event["home"] as? [String: Any])?["score"] as? Int == 2)
            #expect((event["away"] as? [String: Any])?["score"] as? Int == 1)
            #expect(preview["unavailable"] as? Bool == false)
        }
    }

    @Test("a shared concert shows when the provider has it, and says unavailable when not")
    func concertUnavailable() async throws {
        let concerts = FakeConcerts()
        concerts.events["Z1"] = sampleConcert("Z1", "2026-11-02")
        try await LibraryHarness.run(concerts: concerts) { env in
            let first = try await code(env.send(.post, "/v1/shares", json: ["target": ["kind": "concert", "id": "Z1"]]))
            let shown = try await env.send(.get, "/v1/shares/\(first)", token: signedOut).json()
            #expect((shown["concert"] as? [String: Any])?["name"] as? String == "Show Z1")

            // A link made while the concert existed; by the time it opens, Ticketmaster has none.
            let second = InviteService.newCode()
            try await env.stores.shares.createShare(Share(
                code: second, senderID: env.userID, target: .concert("Z2"), note: nil, createdAt: Date()
            ))
            concerts.fail(true)
            let gone = try await env.send(.get, "/v1/shares/\(second)", token: signedOut)
            #expect(gone.status == .ok)
            #expect(try gone.json()["unavailable"] as? Bool == true)
            #expect(try gone.json()["concert"] == nil)
        }
    }

    @Test("bad targets and notes are refused; signed out cannot share")
    func badTargets() async throws {
        try await LibraryHarness.run(sports: sportsWith(["42"])) { env in
            let refused: [[String: Any]] = [
                ["target": ["kind": "sport_event", "id": "abc"]],
                ["target": ["kind": "concert", "id": "../x"]],
                ["target": ["kind": "title"]],
                ["target": ["kind": "sport_event"]],
                ["target": ["kind": "sport_event", "id": "42"], "note": String(repeating: "a", count: 141)],
            ]
            for body in refused {
                #expect(try await env.send(.post, "/v1/shares", json: body).status == .unprocessableContent)
            }
            let fine = ["target": ["kind": "sport_event", "id": "42"], "note": String(repeating: "a", count: 140)]
            #expect(try await env.send(.post, "/v1/shares", json: fine).status == .ok)
            let anonymous = try await env.send(
                .post, "/v1/shares", json: ["target": ["kind": "sport_event", "id": "42"]], token: signedOut
            )
            #expect(anonymous.status == .unauthorized)
        }
    }

    @Test("an unknown code is one 404")
    func unknownCode() async throws {
        try await LibraryHarness.run { env in
            let reply = try await env.send(.get, "/v1/shares/nope12345678", token: signedOut)
            #expect(reply.status == .notFound)
        }
    }

    @Test("making links is limited per user; opening them per address")
    func rateLimits() async throws {
        let concerts = FakeConcerts()
        for id in 1 ... ShareService.createsPerHour {
            concerts.events["C\(id)"] = sampleConcert("C\(id)", "2026-11-02")
        }
        try await LibraryHarness.run(concerts: concerts) { env in
            for id in 1 ... ShareService.createsPerHour {
                let reply = try await env.send(
                    .post,
                    "/v1/shares",
                    json: ["target": ["kind": "concert", "id": "C\(id)"]]
                )
                #expect(reply.status == .ok)
            }
            let over = try await env.send(.post, "/v1/shares", json: ["target": ["kind": "concert", "id": "C1"]])
            #expect(over.status == .tooManyRequests)
        }
        #expect(ShareService.createsPerHour == 60)
        #expect(ShareService.previewsPerHour == 600)
    }

    @Test("only a share's preview path is public")
    func publicPath() {
        #expect(AuthMiddleware.isPublic("/v1/shares/abc"))
        #expect(!AuthMiddleware.isPublic("/v1/shares/"))
        #expect(!AuthMiddleware.isPublic("/v1/shares"))
        #expect(!AuthMiddleware.isPublic("/v1/shares/abc/x"))
        #expect(AuthMiddleware.isPublic("/v1/invites/abc"), "invites stay public")
    }
}
