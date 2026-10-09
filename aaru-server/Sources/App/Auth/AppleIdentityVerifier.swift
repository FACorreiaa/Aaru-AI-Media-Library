import Foundation
import JWTKit

/// What a verified Sign in with Apple identity token says.
struct AppleIdentity: Sendable, Equatable {
    /// Apple's stable user id (`sub`). The only thing an account is keyed on —
    /// the email can be a private relay address and can change.
    var subject: String
    var email: String?
    var isPrivateRelay: Bool
}

enum AppleSignInError: Error, Equatable {
    /// Signature, issuer, audience, expiry, or nonce check failed.
    case invalidToken
}

protocol AppleIdentityVerifying: Sendable {
    func verify(identityToken: String, rawNonce: String) async throws -> AppleIdentity
}

private struct AppleIDClaims: JWTPayload {
    let sub: SubjectClaim
    let aud: AudienceClaim
    let iss: IssuerClaim
    let exp: ExpirationClaim
    let nonce: String?
    let email: String?
    let isPrivateEmail: BoolOrString?

    enum CodingKeys: String, CodingKey {
        case sub, aud, iss, exp, nonce, email
        case isPrivateEmail = "is_private_email"
    }

    func verify(using _: some JWTAlgorithm) async throws {
        try exp.verifyNotExpired()
    }
}

/// Apple sends some booleans as `true` and some as `"true"`.
private struct BoolOrString: Codable {
    let value: Bool

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = (try? container.decode(String.self))?.lowercased() == "true"
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

/// Apple's signing keys, cached. An unknown `kid` refreshes the set at most once
/// per `minimumRefreshInterval` and then fails closed.
///
/// The `kid` check is ours, not jwt-kit's: given a `kid` it does not hold, jwt-kit
/// falls back to its default key. After Apple rotates keys that would fail every
/// sign-in until the cache expired, instead of refreshing once.
private struct JWKSKeyIDs: Decodable {
    struct Key: Decodable { let kid: String? }
    let keys: [Key]
}

actor AppleJWKSCache {
    private let transport: any HTTPTransport
    private let url: URL
    private let ttl: TimeInterval
    private let minimumRefreshInterval: TimeInterval
    private var keys: JWTKeyCollection?
    private var kids: Set<String> = []
    private var fetchedAt: Date?

    init(
        transport: any HTTPTransport,
        url: URL,
        ttl: TimeInterval = 12 * 60 * 60,
        minimumRefreshInterval: TimeInterval = 60
    ) {
        self.transport = transport
        self.url = url
        self.ttl = ttl
        self.minimumRefreshInterval = minimumRefreshInterval
    }

    /// Keys that hold `kid`, refreshing once if it is unknown. Nil means fail closed.
    func keys(for kid: String, now: Date = .now) async throws -> JWTKeyCollection? {
        if keys == nil || fetchedAt.map({ now.timeIntervalSince($0) >= ttl }) ?? true {
            try await fetch(now: now)
        }
        if kids.contains(kid) {
            return keys
        }
        // Unknown kid: refresh at most once per interval, so a flood of bad kids
        // cannot hammer Apple.
        if let fetchedAt, now.timeIntervalSince(fetchedAt) < minimumRefreshInterval {
            return nil
        }
        try await fetch(now: now)
        return kids.contains(kid) ? keys : nil
    }

    private func fetch(now: Date) async throws {
        let response = try await transport.send(OutboundRequest(url: url))
        guard response.status == 200 else {
            throw AppError(
                status: .badGateway,
                code: "provider_unavailable",
                message: "Sign in with Apple is unavailable."
            )
        }
        let collection = JWTKeyCollection()
        try await collection.add(jwksJSON: String(bytes: response.body, encoding: .utf8) ?? "")
        keys = collection
        kids = try Set(JSONDecoder().decode(JWKSKeyIDs.self, from: response.body).keys.compactMap(\.kid))
        fetchedAt = now
    }
}

/// Verifies Sign in with Apple identity tokens: signature against Apple's JWKS,
/// issuer, audience (app bundle ids + web Services ID), expiry, and nonce.
struct AppleIdentityVerifier: AppleIdentityVerifying {
    static let issuer = "https://appleid.apple.com"
    static let keysURL = URL(string: "https://appleid.apple.com/auth/keys")!

    let audiences: Set<String>
    let jwks: AppleJWKSCache

    func verify(identityToken: String, rawNonce: String) async throws -> AppleIdentity {
        let claims = try await verifiedClaims(identityToken)
        guard claims.iss.value == Self.issuer,
              claims.aud.value.contains(where: audiences.contains)
        else { throw AppleSignInError.invalidToken }
        // The client sends Apple sha256(rawNonce) and sends us rawNonce, so a token
        // lifted from another sign-in cannot be replayed here.
        guard !rawNonce.isEmpty, claims.nonce == sha256Hex(rawNonce) else {
            throw AppleSignInError.invalidToken
        }
        return AppleIdentity(
            subject: claims.sub.value,
            email: claims.email.map { $0.lowercased() },
            isPrivateRelay: claims.isPrivateEmail?.value ?? false
        )
    }

    private func verifiedClaims(_ token: String) async throws -> AppleIDClaims {
        guard let kid = Self.keyID(of: token), let keys = try await jwks.keys(for: kid) else {
            throw AppleSignInError.invalidToken
        }
        do {
            return try await keys.verify(token, as: AppleIDClaims.self)
        } catch {
            throw AppleSignInError.invalidToken
        }
    }

    /// The `kid` from the token's (unverified) header. Used only to pick a key.
    static func keyID(of token: String) -> String? {
        struct Header: Decodable { let kid: String? }
        guard let part = token.split(separator: ".").first else { return nil }
        var base64 = part.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64) else { return nil }
        return (try? JSONDecoder().decode(Header.self, from: data))?.kid
    }
}
