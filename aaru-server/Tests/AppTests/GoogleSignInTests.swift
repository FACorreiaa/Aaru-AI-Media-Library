import Foundation
import Hummingbird
import HummingbirdTesting
import JWTKit
import Testing
@testable import aaru

/// AUTH-005: Google ID tokens against a stub JWKS, then sign-in and linking over HTTP. Never reaches Google.
@Suite("Sign in with Google (AUTH-005)", .serialized)
struct GoogleSignInTests {
    struct Claims: JWTPayload {
        var sub: SubjectClaim
        var aud: AudienceClaim
        var iss: IssuerClaim
        var exp: ExpirationClaim
        var nonce: String?
        var email: String?
        // swiftlint:disable:next identifier_name
        var email_verified: Bool?
        var name: String?

        func verify(using _: some JWTAlgorithm) async throws {}
    }

    static let audience = "1234-ios.apps.googleusercontent.com"
    let key = ES256PrivateKey()
    let kid = "google-kid"

    func token(
        subject: String = "google-sub-1",
        audience: String = audience,
        issuer: String = "https://accounts.google.com",
        nonce: String? = "n-1",
        verified: Bool = true,
        expires: Date = Date().addingTimeInterval(600)
    ) async throws -> String {
        let keys = JWTKeyCollection()
        await keys.add(ecdsa: key, kid: JWKIdentifier(string: kid))
        return try await keys.sign(Claims(
            sub: SubjectClaim(value: subject),
            aud: AudienceClaim(value: [audience]),
            iss: IssuerClaim(value: issuer),
            exp: ExpirationClaim(value: expires),
            nonce: nonce,
            email: "Ana@Example.com",
            email_verified: verified,
            name: "Ana"
        ), kid: JWKIdentifier(string: kid))
    }

    func verifier() throws -> GoogleIdentityVerifier {
        let parameters = try #require(key.publicKey.parameters)
        let body = AppleVerifierTests.jwksJSON(kid: kid, parameters: parameters)
        let transport = StubTransport { _ in OutboundResponse(status: 200, body: body) }
        let cache = AppleJWKSCache(transport: transport, url: GoogleIdentityVerifier.keysURL, minimumRefreshInterval: 0)
        return GoogleIdentityVerifier(audiences: [Self.audience], jwks: cache)
    }

    @Test("A valid token yields the subject, the name, and the email only when Google verified it")
    func validToken() async throws {
        let verifier = try verifier()
        let identity = try await verifier.verify(idToken: token(), nonce: "n-1")
        #expect(identity == GoogleIdentity(subject: "google-sub-1", email: "ana@example.com", name: "Ana"))
        let unverified = try await verifier.verify(idToken: token(verified: false), nonce: nil)
        #expect(unverified.email == nil)
        let bareIssuer = try await verifier.verify(idToken: token(issuer: "accounts.google.com"), nonce: nil)
        #expect(bareIssuer.subject == "google-sub-1")
    }

    @Test("Wrong audience, issuer, nonce, or an expired token is rejected")
    func rejections() async throws {
        let verifier = try verifier()
        for bad in try await [
            token(audience: "someone-else.apps.googleusercontent.com"),
            token(issuer: "https://evil.example.com"),
            token(expires: Date().addingTimeInterval(-60)),
        ] {
            await #expect(throws: GoogleSignInError.invalidToken) {
                try await verifier.verify(idToken: bad, nonce: nil)
            }
        }
        await #expect(throws: GoogleSignInError.invalidToken) {
            try await verifier.verify(idToken: token(), nonce: "a-different-nonce")
        }
    }

    // MARK: Over HTTP

    struct FixedGoogle: GoogleIdentityVerifying {
        let subject: String
        func verify(idToken: String, nonce _: String?) async throws -> GoogleIdentity {
            guard idToken == "good" else { throw GoogleSignInError.invalidToken }
            return GoogleIdentity(subject: subject, email: "g@example.com", name: "Gee")
        }
    }

    struct FixedApple: AppleIdentityVerifying {
        let subject: String
        func verify(identityToken _: String, rawNonce _: String) async throws -> AppleIdentity {
            AppleIdentity(subject: subject, email: nil, isPrivateRelay: false)
        }
    }

    struct SessionBody: Decodable {
        let token: String
        let userId: String
    }

    func withApp(
        google: (any GoogleIdentityVerifying)?,
        _ body: @escaping @Sendable (any TestClientProtocol) async throws -> Void
    ) async throws {
        try await withMigratedStores { stores in
            var auth = AuthService(stores: stores, apple: FixedApple(subject: UUID().uuidString), magicLinks: nil)
            auth.google = google
            let services = Services.make(stores: stores, catalogs: FakeCatalog.providers(FakeCatalog()), auth: auth)
            let app = try Application(router: buildRouter(stores: stores, services: services))
            try await app.test(.router) { client in try await body(client) }
        }
    }

    func post(
        _ client: any TestClientProtocol,
        _ uri: String,
        _ object: [String: String],
        token: String? = nil
    ) async throws -> (HTTPResponse.Status, Data) {
        var headers: HTTPFields = [.contentType: "application/json"]
        if let token {
            headers[.authorization] = "Bearer \(token)"
        }
        let body = try ByteBuffer(bytes: JSONSerialization.data(withJSONObject: object))
        return try await client.execute(uri: uri, method: .post, headers: headers, body: body) {
            ($0.status, Data(buffer: $0.body))
        }
    }

    @Test("Signing in twice with Google is one user; a forged token is 401")
    func signIn() async throws {
        try await withApp(google: FixedGoogle(subject: UUID().uuidString)) { client in
            let (status, data) = try await post(client, "/v1/auth/google", ["idToken": "good"])
            #expect(status == .ok)
            let first = try JSONDecoder().decode(SessionBody.self, from: data)
            let second = try await JSONDecoder().decode(
                SessionBody.self, from: post(client, "/v1/auth/google", ["idToken": "good"]).1
            )
            #expect(first.userId == second.userId)
            #expect(try await post(client, "/v1/auth/google", ["idToken": "forged"]).0 == .unauthorized)
        }
    }

    @Test("Without GOOGLE_CLIENT_IDS the route answers 503")
    func unconfigured() async throws {
        try await withApp(google: nil) { client in
            let (status, _) = try await post(client, "/v1/auth/google", ["idToken": "good"])
            #expect(status == .serviceUnavailable)
        }
    }

    @Test("Linking adds Google to the Apple account; the same Google on another account is refused")
    func linking() async throws {
        try await withApp(google: FixedGoogle(subject: UUID().uuidString)) { client in
            let apple = try await JSONDecoder().decode(
                SessionBody.self,
                from: post(client, "/v1/auth/apple", ["identityToken": "t", "nonce": "n"]).1
            )
            let (status, data) = try await post(
                client, "/v1/me/identities/google", ["idToken": "good"], token: apple.token
            )
            #expect(status == .ok)
            let providers = try (JSONSerialization.jsonObject(with: data) as? [String: Any])?["providers"] as? [String]
            #expect(Set(providers ?? []) == ["apple", "google"])
            let (again, _) = try await post(client, "/v1/me/identities/google", ["idToken": "good"], token: apple.token)
            #expect(again == .ok, "linking again is a no-op")

            let viaGoogle = try await JSONDecoder().decode(
                SessionBody.self, from: post(client, "/v1/auth/google", ["idToken": "good"]).1
            )
            #expect(viaGoogle.userId == apple.userId, "Google now signs in to the Apple account")
        }
    }

    @Test("A Google account already on another user is a 409, never a merge")
    func conflict() async throws {
        try await withApp(google: FixedGoogle(subject: UUID().uuidString)) { client in
            _ = try await post(client, "/v1/auth/google", ["idToken": "good"])
            let apple = try await JSONDecoder().decode(
                SessionBody.self,
                from: post(client, "/v1/auth/apple", ["identityToken": "t", "nonce": "n"]).1
            )
            #expect(try await post(
                client, "/v1/me/identities/google", ["idToken": "good"], token: apple.token
            ).0 == .conflict)
        }
    }
}
