import AaruCore
import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
@testable import aaru

/// Sign-in flows end to end over HTTP, against Postgres, with stubbed Apple and email.
@Suite("Auth flows (M2)", .serialized)
struct AuthFlowTests {
    struct FixedApple: AppleIdentityVerifying {
        let subject: String
        func verify(identityToken: String, rawNonce _: String) async throws -> AppleIdentity {
            guard identityToken == "good" else { throw AppleSignInError.invalidToken }
            return AppleIdentity(subject: subject, email: "x@privaterelay.appleid.com", isPrivateRelay: true)
        }
    }

    /// Captures the links the server "emails".
    final class Outbox: MagicLinkSending, @unchecked Sendable {
        // @unchecked: test-only; `lock` guards `links`.
        private let lock = NSLock()
        private var links: [URL] = []
        var last: URL? {
            lock.withLock { links.last }
        }

        func send(to _: String, link: URL) async throws {
            lock.withLock { links.append(link) }
        }
    }

    struct SessionBody: Decodable {
        let token: String
        let userId: String
    }

    func withApp(
        appleSubject: String = UUID().uuidString,
        outbox: Outbox = Outbox(),
        _ body: @escaping @Sendable (any TestClientProtocol, Stores) async throws -> Void
    ) async throws {
        try await withMigratedStores { stores in
            let auth = AuthService(
                stores: stores,
                apple: FixedApple(subject: appleSubject),
                magicLinks: (
                    outbox,
                    URL(string: "https://aaru.test/auth/verify")!
                )
            )
            let app = try Application(router: buildRouter(stores: stores, auth: auth))
            try await app.test(.router) { client in try await body(client, stores) }
        }
    }

    func json(_ object: [String: String]) throws -> ByteBuffer {
        try ByteBuffer(bytes: JSONSerialization.data(withJSONObject: object))
    }

    func signInApple(_ client: any TestClientProtocol, name: String? = nil) async throws -> SessionBody {
        var body = ["identityToken": "good", "nonce": "n"]
        body["displayName"] = name
        return try await client.execute(
            uri: "/v1/auth/apple", method: .post, headers: [.contentType: "application/json"], body: json(body)
        ) { response in
            #expect(response.status == .ok)
            return try JSONDecoder().decode(SessionBody.self, from: Data(buffer: response.body))
        }
    }

    @Test("AUTH-002: signing in twice with Apple yields one user, and keeps the first name")
    func appleIsIdempotent() async throws {
        try await withApp { client, _ in
            let first = try await signInApple(client, name: "Ana")
            let second = try await signInApple(client)
            #expect(first.userId == second.userId)
            #expect(first.token != second.token)
            try await client
                .execute(uri: "/v1/me", method: .get, headers: [.authorization: "Bearer \(second.token)"]) { response in
                    #expect(response.status == .ok)
                    #expect(String(buffer: response.body).contains("Ana"))
                }
        }
    }

    @Test("AUTH-002: a token Apple's keys do not verify is 401")
    func appleBadToken() async throws {
        try await withApp { client, _ in
            try await client.execute(
                uri: "/v1/auth/apple", method: .post, headers: [.contentType: "application/json"],
                body: json(["identityToken": "forged", "nonce": "n"])
            ) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test("AUTH-003: a magic link signs in once, then is dead")
    func magicLinkSingleUse() async throws {
        let outbox = Outbox()
        try await withApp(outbox: outbox) { client, _ in
            let email = "\(UUID().uuidString)@Example.com"
            try await client.execute(
                uri: "/v1/auth/email/link", method: .post, headers: [.contentType: "application/json"],
                body: json(["email": email])
            ) { response in
                #expect(response.status == .accepted)
            }
            let link = try #require(outbox.last)
            let token = try #require(URLComponents(url: link, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "token" }?.value)
            for expected in [HTTPResponse.Status.ok, .unauthorized] {
                try await client.execute(
                    uri: "/v1/auth/email/verify", method: .post, headers: [.contentType: "application/json"],
                    body: json(["token": token])
                ) { response in
                    #expect(response.status == expected)
                }
            }
        }
    }

    @Test("AUTH-003: an expired link is refused and the token is never stored in clear")
    func magicLinkExpiry() async throws {
        try await withMigratedStores { stores in
            let token = OpaqueToken.generate()
            try await stores.magicLinks.create(
                email: "e@x.test",
                tokenHash: OpaqueToken.hash(token),
                expiresAt: Date().addingTimeInterval(-1)
            )
            #expect(try await stores.magicLinks.consume(tokenHash: OpaqueToken.hash(token), now: Date()) == nil)
            #expect(try await stores.magicLinks.consume(tokenHash: token, now: Date()) == nil)
        }
    }

    @Test("AUTH-003: sign-in emails are rate-limited per address")
    func magicLinkRateLimit() async throws {
        try await withApp { client, _ in
            let email = "\(UUID().uuidString)@example.com"
            var statuses: [HTTPResponse.Status] = []
            for _ in 0 ..< 6 {
                try await client.execute(
                    uri: "/v1/auth/email/link", method: .post, headers: [.contentType: "application/json"],
                    body: json(["email": email])
                ) { response in statuses.append(response.status) }
            }
            #expect(statuses.prefix(5).allSatisfy { $0 == .accepted })
            #expect(statuses.last == .tooManyRequests)
        }
    }

    @Test("AUTH-003: an invalid email is 422 naming the field")
    func invalidEmail() async throws {
        try await withApp { client, _ in
            try await client.execute(
                uri: "/v1/auth/email/link", method: .post, headers: [.contentType: "application/json"],
                body: json(["email": "not-an-email"])
            ) { response in
                #expect(response.status == .unprocessableContent)
                #expect(String(buffer: response.body).contains("email"))
            }
        }
    }

    @Test("AUTH-004: signing out kills that session only")
    func signOut() async throws {
        try await withApp { client, _ in
            let keep = try await signInApple(client)
            let drop = try await signInApple(client)
            try await client.execute(
                uri: "/v1/auth/session",
                method: .delete,
                headers: [.authorization: "Bearer \(drop.token)"]
            ) { response in
                #expect(response.status == .noContent)
            }
            try await client
                .execute(uri: "/v1/me", method: .get, headers: [.authorization: "Bearer \(drop.token)"]) { response in
                    #expect(response.status == .unauthorized)
                }
            try await client
                .execute(uri: "/v1/me", method: .get, headers: [.authorization: "Bearer \(keep.token)"]) { response in
                    #expect(response.status == .ok)
                }
        }
    }

    @Test("AUTH-004: after account delete no row anywhere references the user")
    func accountDeleteLeavesNothing() async throws {
        let outbox = Outbox()
        try await withApp(outbox: outbox) { client, stores in
            let session = try await signInApple(client)
            let userID = try #require(UserID(uuidString: session.userId))
            // Give the user rows in every user-owned table that exists today.
            let title = Title(type: .movie, title: "Dune")
            try await stores.titles.insert(title)
            try await stores.library.insert(LibraryItem(userID: userID, titleID: title.id, status: .wishlist))
            try await stores.lists.create(AaruList(userID: userID, name: "L", titleIDs: [title.id]))
            try await stores.importJobs.insert(ImportJob(userID: userID, source: .trakt))

            try await client.execute(
                uri: "/v1/me",
                method: .delete,
                headers: [.authorization: "Bearer \(session.token)"]
            ) { response in
                #expect(response.status == .noContent)
            }
            #expect(try await rowsReferencing(userID) == [:])
            try await client
                .execute(
                    uri: "/v1/me",
                    method: .get,
                    headers: [.authorization: "Bearer \(session.token)"]
                ) { response in
                    #expect(response.status == .unauthorized)
                }
        }
    }
}
