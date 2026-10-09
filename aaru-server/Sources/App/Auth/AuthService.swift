import AaruCore
import Foundation

/// A freshly issued session. `token` is returned to the client once and never stored.
struct NewSession: Sendable {
    var token: String
    var userID: UserID
    var expiresAt: Date
}

struct EmailSettings: Sendable {
    var resendAPIKey: String
    var from: String
    /// Where the emailed link points; the token is appended as `?token=`.
    var linkBaseURL: URL
}

/// Sign-in, sign-out, and account deletion (M2). Handlers call this; it owns the rules.
struct AuthService: Sendable {
    static let sessionLifetime: TimeInterval = 90 * 24 * 60 * 60
    static let magicLinkLifetime: TimeInterval = 15 * 60

    let stores: Stores
    let apple: any AppleIdentityVerifying
    /// Nil when email sign-in is not configured (no RESEND_API_KEY).
    let magicLinks: (sender: any MagicLinkSending, linkBaseURL: URL)?
    let perEmailLimiter = FixedWindowRateLimiter(limit: 5, window: 60 * 60)
    let perClientLimiter = FixedWindowRateLimiter(limit: 20, window: 60 * 60)
    var now: @Sendable () -> Date = { Date() }

    // MARK: Apple (AUTH-002)

    func signInWithApple(identityToken: String, rawNonce: String, displayName: String?) async throws -> NewSession {
        let identity: AppleIdentity
        do {
            identity = try await apple.verify(identityToken: identityToken, rawNonce: rawNonce)
        } catch AppleSignInError.invalidToken {
            throw AppError.unauthorized("The Apple sign-in could not be verified.")
        }
        // Keyed on `sub`, never on email: relay addresses and changed emails must not
        // fork an account. The name arrives only on the first authorization.
        let userID = try await findOrCreateUser(
            AuthIdentity(provider: .apple, subject: identity.subject, email: identity.email),
            displayName: displayName
        )
        return try await issueSession(for: userID)
    }

    // MARK: Email magic link (AUTH-003)

    /// Sends a sign-in link. The response is the same whether or not the address has
    /// an account: verifying the link is what creates one.
    func requestMagicLink(email rawEmail: String, clientAddress: String) async throws {
        guard let config = magicLinks else {
            throw AppError(
                status: .serviceUnavailable,
                code: "email_unavailable",
                message: "Email sign-in is not available yet."
            )
        }
        let email = try Self.normalizedEmail(rawEmail)
        guard await perClientLimiter.allow(clientAddress, now: now()),
              await perEmailLimiter.allow(email, now: now())
        else {
            throw AppError(
                status: .tooManyRequests,
                code: "rate_limited",
                message: "Too many sign-in emails. Try again later."
            )
        }
        let token = OpaqueToken.generate()
        try await stores.magicLinks.create(
            email: email,
            tokenHash: OpaqueToken.hash(token),
            expiresAt: now().addingTimeInterval(Self.magicLinkLifetime)
        )
        var components = URLComponents(url: config.linkBaseURL, resolvingAgainstBaseURL: false)
        let queryItems = (components?.queryItems ?? []) + [URLQueryItem(name: "token", value: token)]
        components?.queryItems = queryItems
        guard let link = components?.url else {
            throw AppError(status: .internalServerError, code: "internal", message: "Something went wrong.")
        }
        try await config.sender.send(to: email, link: link)
    }

    func verifyMagicLink(token: String) async throws -> NewSession {
        guard let email = try await stores.magicLinks.consume(tokenHash: OpaqueToken.hash(token), now: now()) else {
            throw AppError.unauthorized("This sign-in link is invalid, expired, or already used.")
        }
        let userID = try await findOrCreateUser(
            AuthIdentity(provider: .email, subject: email, email: email),
            displayName: nil
        )
        return try await issueSession(for: userID)
    }

    // MARK: Sign-out and delete (AUTH-004)

    func signOut(tokenHash: String) async throws {
        try await stores.sessions.delete(tokenHash: tokenHash)
    }

    func deleteAccount(_ userID: UserID) async throws {
        try await stores.users.deleteUser(userID)
    }

    // MARK: Helpers

    private func findOrCreateUser(_ identity: AuthIdentity, displayName: String?) async throws -> UserID {
        if let existing = try await stores.users.user(for: identity.provider, subject: identity.subject) {
            return existing
        }
        do {
            return try await stores.users.createUser(with: identity, displayName: displayName?.nilIfBlank)
        } catch is StoreConflict {
            // A concurrent sign-in created it first.
            guard let existing = try await stores.users.user(for: identity.provider, subject: identity.subject) else {
                throw AppError(status: .internalServerError, code: "internal", message: "Something went wrong.")
            }
            return existing
        }
    }

    private func issueSession(for userID: UserID) async throws -> NewSession {
        let token = OpaqueToken.generate()
        let expiresAt = now().addingTimeInterval(Self.sessionLifetime)
        try await stores.sessions.create(userID: userID, tokenHash: OpaqueToken.hash(token), expiresAt: expiresAt)
        return NewSession(token: token, userID: userID, expiresAt: expiresAt)
    }

    static func normalizedEmail(_ raw: String) throws -> String {
        let email = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard email.count <= 254, parts.count == 2, !parts[0].isEmpty, parts[1].contains("."),
              !email.contains(where: \.isWhitespace)
        else {
            throw AppError(
                status: .unprocessableContent,
                code: "validation_failed",
                message: "That email address is not valid.",
                details: ["email": "Not a valid email address."]
            )
        }
        return email
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
