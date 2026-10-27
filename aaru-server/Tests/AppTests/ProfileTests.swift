import AaruCore
import Foundation
import Hummingbird
import Testing
@testable import aaru

@Suite("Profile: names, avatar and email (SOC-001b)", .serialized)
struct ProfileTests {
    let signedOut = "signed-out"
    /// The smallest bytes the server takes for a JPEG: its magic number.
    let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4])

    func upload(_ env: LibraryHarness, _ bytes: Data, type: String = "image/jpeg", token: String? = nil)
        async throws -> LibraryHarness.Reply
    {
        try await env.client.execute(
            uri: "/v1/me/avatar", method: .put,
            headers: [.authorization: "Bearer \(token ?? env.token)", .contentType: type],
            body: ByteBuffer(bytes: bytes)
        ) { LibraryHarness.Reply(status: $0.status, body: Data(buffer: $0.body), headers: $0.headers) }
    }

    func me(_ env: LibraryHarness, token: String? = nil) async throws -> [String: Any] {
        try await env.send(.get, "/v1/me", token: token).json()
    }

    /// A signed-in user whose only sign-in has this email.
    func user(_ env: LibraryHarness, provider: AuthIdentity.Provider, email: String) async throws -> String {
        let user = try await env.stores.users.createUser(
            with: AuthIdentity(provider: provider, subject: UUID().uuidString, email: email), displayName: nil
        )
        let token = OpaqueToken.generate()
        try await env.stores.sessions.create(
            userID: user, tokenHash: OpaqueToken.hash(token), expiresAt: Date().addingTimeInterval(3600)
        )
        return token
    }

    @Test("a name splits at the first space, and saved names come back in both shapes")
    func split() {
        #expect(PersonName(splitting: "  Ana  ") == PersonName(first: "Ana", last: nil))
        #expect(PersonName(splitting: "Fernando Pereira Correia") == PersonName(
            first: "Fernando",
            last: "Pereira Correia"
        ))
        #expect(PersonName(splitting: "") == PersonName(first: nil, last: nil))
        #expect(PersonName(first: nil, last: "Lopes").displayName == "Lopes")
        #expect(PersonName(first: nil, last: nil).displayName == nil)
    }

    @Test("first and last name are saved, joined for others, and a field left out keeps its value")
    func names() async throws {
        try await LibraryHarness.run { env in
            // No handle needed for a name.
            let saved = try await env.send(.put, "/v1/me/profile", json: ["firstName": " Ana ", "lastName": "Lopes"])
            #expect(saved.status == .ok)
            #expect(try saved.json()["displayName"] as? String == "Ana Lopes")
            #expect(try saved.json()["handle"] == nil)

            _ = try await env.send(.put, "/v1/me/profile", json: ["lastName": "Silva"])
            var account = try await me(env)
            #expect(account["firstName"] as? String == "Ana")
            #expect(account["lastName"] as? String == "Silva")

            _ = try await env.send(.put, "/v1/me/profile", json: ["firstName": ""])
            account = try await me(env)
            #expect(account["firstName"] == nil)
            #expect(account["displayName"] as? String == "Silva")

            let tooLong = String(repeating: "a", count: SocialService.maxDisplayNameLength + 1)
            let refused = try await env.send(.put, "/v1/me/profile", json: ["lastName": tooLong])
            #expect(refused.status == .unprocessableContent)
            #expect(try (refused.json()["details"] as? [String: Any])?["lastName"] != nil)
        }
    }

    @Test("an older app's display name is no change when it matches, and splits when it does not")
    func olderApps() async throws {
        try await LibraryHarness.run { env in
            let handle = freshHandle()
            _ = try await env.send(
                .put, "/v1/me/profile", json: ["handle": handle, "firstName": "Mary Ann", "lastName": "Smith"]
            )
            // An old app saving only its handle still sends the name it read.
            let renamed = freshHandle()
            _ = try await env.send(.put, "/v1/me/profile", json: ["handle": renamed, "displayName": "Mary Ann Smith"])
            var account = try await me(env)
            #expect(account["handle"] as? String == renamed)
            #expect(account["firstName"] as? String == "Mary Ann")
            #expect(account["lastName"] as? String == "Smith")

            _ = try await env.send(.put, "/v1/me/profile", json: ["handle": renamed, "displayName": "Ana Lopes"])
            account = try await me(env)
            #expect(account["firstName"] as? String == "Ana")
            #expect(account["lastName"] as? String == "Lopes")

            _ = try await env.send(.put, "/v1/me/profile", json: ["handle": renamed, "displayName": ""])
            account = try await me(env)
            #expect(account["firstName"] == nil)
            #expect(account["displayName"] == nil)
        }
    }

    @Test("an avatar is a JPEG under 1 MB; anything else is refused and removing it brings back nothing")
    func avatarUpload() async throws {
        try await LibraryHarness.run { env in
            let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
            #expect(try await upload(env, png).status == .unsupportedMediaType)
            #expect(try await upload(env, png, type: "image/png").status == .unsupportedMediaType)
            let huge = jpeg + Data(count: SocialService.maxAvatarBytes)
            #expect(try await upload(env, huge).status == .contentTooLarge)
            #expect(try await me(env)["avatarUrl"] == nil)

            let saved = try await upload(env, jpeg)
            #expect(saved.status == .ok)
            let path = try #require(saved.json()["avatarUrl"] as? String)
            #expect(path.hasPrefix("/v1/users/\(env.userID.description)/avatar?v="))

            let image = try await env.send(.get, path)
            #expect(image.status == .ok)
            #expect(image.body == jpeg)
            #expect(image.headers[.contentType] == "image/jpeg")
            #expect(image.headers[.cacheControl] == "private, max-age=604800")

            // A new photo is a new URL, so no cache serves the old one.
            let again = try await upload(env, jpeg + Data([5]))
            #expect(try again.json()["avatarUrl"] as? String != path)

            let removed = try await env.send(.delete, "/v1/me/avatar")
            #expect(removed.status == .ok)
            #expect(try removed.json()["avatarUrl"] == nil)
            #expect(try await env.send(.get, path).status == .notFound)
        }
    }

    @Test("anyone signed in sees an avatar where the name shows; signed out, blocked or the invite preview never")
    func avatarReach() async throws {
        try await LibraryHarness.run { env in
            let mine = try await claimHandle(env)
            let path = try #require(try await upload(env, jpeg).json()["avatarUrl"] as? String)
            let ana = try await friend(env, of: mine)

            #expect(try await env.send(.get, path, token: ana.token).status == .ok)
            let (_, stranger) = try await signedInUser(env.stores)
            #expect(try await env.send(.get, path, token: stranger).status == .ok)
            #expect(try await env.send(.get, path, token: signedOut).status == .unauthorized)

            let friends = try await env.send(.get, "/v1/social/friends", token: ana.token).json()
            let listed = try #require((friends["items"] as? [[String: Any]])?.first)
            #expect(listed["avatarUrl"] as? String == path)

            let created = try await env.send(.post, "/v1/groups", json: ["name": "Film club"]).json()
            let group = try #require((created["group"] as? [String: Any])?["id"] as? String)
            let members = try await env.send(.get, "/v1/groups/\(group)").json()["members"] as? [[String: Any]]
            #expect((members?.first?["user"] as? [String: Any])?["avatarUrl"] as? String == path)

            let code = try #require(
                try await env.send(.post, "/v1/social/invites", json: [:] as [String: Any]).json()["code"] as? String
            )
            let preview = try await env.send(.get, "/v1/invites/\(code)", token: signedOut).json()
            let inviter = try #require(preview["inviter"] as? [String: Any])
            #expect(inviter["handle"] as? String == mine)
            #expect(inviter["avatarUrl"] == nil)

            // A block either way is the same 404 as no avatar.
            #expect(try await env.send(.put, "/v1/social/blocks/\(ana.id)").status == .noContent)
            #expect(try await env.send(.get, path, token: ana.token).status == .notFound)
            #expect(try await env.send(.get, "/v1/users/\(UUID())/avatar").status == .notFound)
        }
    }

    @Test("friends see the email only while it is shared, and never an Apple relay address")
    func email() async throws {
        try await LibraryHarness.run { env in
            let mine = try await claimHandle(env)
            let address = "\(UUID().uuidString.lowercased())@example.com"
            let token = try await user(env, provider: .email, email: address)
            let theirs = freshHandle()
            _ = try await env.send(.put, "/v1/me/profile", json: ["handle": theirs], token: token)
            _ = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": theirs])
            _ = try await env.send(.post, "/v1/social/friend-requests", json: ["handle": mine], token: token)
            let id = try #require(try await me(env, token: token)["userId"] as? String)

            let account = try await me(env, token: token)
            #expect(account["email"] as? String == address)
            #expect(account["emailShareable"] as? Bool == true)

            let profilePath = "/v1/social/friends/\(id)/profile"
            #expect(try await env.send(.get, profilePath).json()["email"] == nil)
            let settings = try await env.send(.get, "/v1/me/social-settings", token: token).json()
            #expect(settings["shareEmailWithFriends"] as? Bool == false)

            // A partial PUT, as older apps send, keeps the other switches.
            _ = try await env.send(
                .put, "/v1/me/social-settings",
                json: ["shareLibraryWithFriends": false, "shareEmailWithFriends": true], token: token
            )
            #expect(try await env.send(.get, profilePath).json()["email"] as? String == address)
            _ = try await env.send(
                .put,
                "/v1/me/social-settings",
                json: ["shareLibraryWithFriends": true],
                token: token
            )
            #expect(try await env.send(.get, "/v1/me/social-settings", token: token).json()["shareEmailWithFriends"]
                as? Bool == true)

            let relay = try await user(env, provider: .apple, email: "abc@privaterelay.appleid.com")
            let hidden = try await me(env, token: relay)
            #expect(hidden["email"] as? String == "abc@privaterelay.appleid.com")
            #expect(hidden["emailShareable"] as? Bool == false)
        }
    }

    @Test("the export carries the names and the avatar; deleting the account takes the avatar with it")
    func exportAndDelete() async throws {
        try await LibraryHarness.run { env in
            _ = try await env.send(.put, "/v1/me/profile", json: ["firstName": "Ana", "lastName": "Lopes"])
            _ = try await upload(env, jpeg)
            let export = try await env.send(.get, "/v1/me/export").json()
            let account = try #require(export["account"] as? [String: Any])
            #expect(account["firstName"] as? String == "Ana")
            #expect(account["lastName"] as? String == "Lopes")
            #expect(export["avatarJpeg"] as? String == jpeg.base64EncodedString())

            #expect(try await env.send(.delete, "/v1/me").status == .noContent)
            #expect(try await env.stores.social.avatar(env.userID) == nil)
        }
    }
}
