import Foundation
import JWTKit

/// AUTH-005: a verified Google ID token.
struct GoogleIdentity: Sendable, Equatable {
    var subject: String
    var email: String?
    var name: String?
}

enum GoogleSignInError: Error, Equatable {
    case invalidToken
}

protocol GoogleIdentityVerifying: Sendable {
    /// `nonce`, when the client sent one with the sign-in, must come back in the token.
    func verify(idToken: String, nonce: String?) async throws -> GoogleIdentity
}

private struct GoogleIDClaims: JWTPayload {
    let sub: SubjectClaim
    let aud: AudienceClaim
    let iss: IssuerClaim
    let exp: ExpirationClaim
    let email: String?
    let emailVerified: Bool?
    let name: String?
    let nonce: String?

    enum CodingKeys: String, CodingKey {
        case sub, aud, iss, exp, email, name, nonce
        case emailVerified = "email_verified"
    }

    func verify(using _: some JWTAlgorithm) async throws {
        try exp.verifyNotExpired()
    }
}

/// Google ID tokens checked against Google's published keys (the same JWKS cache as Apple's):
/// issuer, audience (the iOS and web client ids), expiry, nonce. Keyed on `sub`, never on email.
struct GoogleIdentityVerifier: GoogleIdentityVerifying {
    static let issuers: Set<String> = ["https://accounts.google.com", "accounts.google.com"]
    static let keysURL = URL(string: "https://www.googleapis.com/oauth2/v3/certs")!

    let audiences: Set<String>
    let jwks: AppleJWKSCache

    func verify(idToken: String, nonce: String?) async throws -> GoogleIdentity {
        guard let kid = AppleIdentityVerifier.keyID(of: idToken), let keys = try await jwks.keys(for: kid) else {
            throw GoogleSignInError.invalidToken
        }
        let claims: GoogleIDClaims
        do {
            claims = try await keys.verify(idToken, as: GoogleIDClaims.self)
        } catch {
            throw GoogleSignInError.invalidToken
        }
        guard Self.issuers.contains(claims.iss.value),
              claims.aud.value.contains(where: audiences.contains),
              nonce == nil || claims.nonce == nonce
        else { throw GoogleSignInError.invalidToken }
        // An unverified Google email is not an email we may write to.
        let email = claims.emailVerified == true ? claims.email?.lowercased() : nil
        return GoogleIdentity(subject: claims.sub.value, email: email, name: claims.name)
    }
}
