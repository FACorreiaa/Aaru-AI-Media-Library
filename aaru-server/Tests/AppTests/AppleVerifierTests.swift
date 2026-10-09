import Foundation
import JWTKit
import Testing
@testable import aaru

/// Sign in with Apple verification against a stub JWKS. Never reaches Apple.
@Suite("Sign in with Apple (AUTH-002)")
struct AppleVerifierTests {
    struct Claims: JWTPayload {
        var sub: SubjectClaim
        var aud: AudienceClaim
        var iss: IssuerClaim
        var exp: ExpirationClaim
        var nonce: String?
        var email: String?
        // swiftlint:disable:next identifier_name
        var is_private_email: String?

        func verify(using _: some JWTAlgorithm) async throws {}
    }

    static let audience = "com.fernandocorreia.aaru.beta"
    static let rawNonce = "raw-nonce-123"

    let key = ES256PrivateKey()

    static func jwksJSON(kid: String, parameters: ECDSAParameters) -> Data {
        let jwk: [String: String] = [
            "kty": "EC", "crv": "P-256", "alg": "ES256", "use": "sig",
            "kid": kid, "x": parameters.x, "y": parameters.y,
        ]
        // swiftlint:disable:next force_try
        return try! JSONSerialization.data(withJSONObject: ["keys": [jwk]])
    }

    let kid = "test-kid"

    func jwks(kid: String) throws -> Data {
        let parameters = try #require(key.publicKey.parameters)
        return Self.jwksJSON(kid: kid, parameters: parameters)
    }

    func token(
        kid: String? = nil,
        signingKey: ES256PrivateKey? = nil,
        audience: String = audience,
        nonce: String? = sha256Hex(rawNonce),
        expires: Date = Date().addingTimeInterval(600)
    ) async throws -> String {
        let keys = JWTKeyCollection()
        await keys.add(ecdsa: signingKey ?? key, kid: JWKIdentifier(string: kid ?? self.kid))
        return try await keys.sign(Claims(
            sub: "001234.apple-user",
            aud: AudienceClaim(value: [audience]),
            iss: IssuerClaim(value: AppleIdentityVerifier.issuer),
            exp: ExpirationClaim(value: expires),
            nonce: nonce,
            email: "Relay@PrivateRelay.AppleID.com",
            is_private_email: "true"
        ), kid: JWKIdentifier(string: kid ?? self.kid))
    }

    func verifier(jwksKid: String? = nil) throws -> (AppleIdentityVerifier, StubTransport) {
        let body = try jwks(kid: jwksKid ?? kid)
        let transport = StubTransport { _ in OutboundResponse(status: 200, body: body) }
        let cache = AppleJWKSCache(transport: transport, url: AppleIdentityVerifier.keysURL, minimumRefreshInterval: 0)
        return (AppleIdentityVerifier(audiences: [Self.audience], jwks: cache), transport)
    }

    @Test("A valid token yields the subject, a lowercased email, and the relay flag")
    func validToken() async throws {
        let (verifier, _) = try verifier()
        let identity = try await verifier.verify(identityToken: token(), rawNonce: Self.rawNonce)
        #expect(identity == AppleIdentity(
            subject: "001234.apple-user",
            email: "relay@privaterelay.appleid.com",
            isPrivateRelay: true
        ))
    }

    @Test("An expired token is rejected")
    func expired() async throws {
        let (verifier, _) = try verifier()
        let stale = try await token(expires: Date().addingTimeInterval(-60))
        await #expect(throws: AppleSignInError.invalidToken) {
            try await verifier.verify(identityToken: stale, rawNonce: Self.rawNonce)
        }
    }

    @Test("A rotated key published after the cache was filled is picked up by one refresh")
    func rotatedKeyRefresh() async throws {
        let rotated = ES256PrivateKey()
        let parameters = try #require(rotated.publicKey.parameters)
        let rotatedSet = Self.jwksJSON(kid: "new-kid", parameters: parameters)
        // First fetch returns the old set; the refresh returns the rotated one.
        let original = try jwks(kid: kid)
        let transport = StubTransport { _ in OutboundResponse(status: 200, body: original) }
        let cache = AppleJWKSCache(
            transport: transport,
            url: AppleIdentityVerifier.keysURL,
            minimumRefreshInterval: 0
        )
        _ = try await cache.keys(for: kid) // fills the cache with the old set
        #expect(transport.requests.count == 1)
        transport.respond { _ in OutboundResponse(status: 200, body: rotatedSet) }
        let verifier = AppleIdentityVerifier(audiences: [Self.audience], jwks: cache)
        let token = try await token(kid: "new-kid", signingKey: rotated)
        let identity = try await verifier.verify(identityToken: token, rawNonce: Self.rawNonce)
        #expect(identity.subject == "001234.apple-user")
        #expect(transport.requests.count == 2, "one refresh for the new kid")
    }

    @Test("A token for another audience or with the wrong nonce is rejected")
    func audienceAndNonce() async throws {
        let (verifier, _) = try verifier()
        let otherApp = try await token(audience: "com.example.other")
        await #expect(throws: AppleSignInError.invalidToken) {
            try await verifier.verify(identityToken: otherApp, rawNonce: Self.rawNonce)
        }
        let good = try await token()
        await #expect(throws: AppleSignInError.invalidToken) {
            try await verifier.verify(identityToken: good, rawNonce: "a-different-nonce")
        }
        let noNonce = try await token(nonce: nil)
        await #expect(throws: AppleSignInError.invalidToken) {
            try await verifier.verify(identityToken: noNonce, rawNonce: Self.rawNonce)
        }
    }

    @Test("An unknown kid triggers exactly one JWKS refresh, then fails closed")
    func unknownKid() async throws {
        let (verifier, transport) = try verifier(jwksKid: "published-kid")
        // Apple rotated: the token is signed by a key the cached set does not hold.
        let unknown = try await token(kid: "rotated-kid", signingKey: ES256PrivateKey())
        await #expect(throws: AppleSignInError.invalidToken) {
            try await verifier.verify(identityToken: unknown, rawNonce: Self.rawNonce)
        }
        #expect(transport.requests.count == 2, "initial fetch + one refresh")
    }
}
