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
    static let maxCodeAttempts = 5

    let stores: Stores
    let apple: any AppleIdentityVerifying
    /// Nil when email sign-in is not configured (no RESEND_API_KEY).
    let magicLinks: (sender: any MagicLinkSending, linkBaseURL: URL)?
    /// Nil when Google sign-in is not configured (no GOOGLE_CLIENT_IDS).
    var google: (any GoogleIdentityVerifying)?
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

    // MARK: Google (AUTH-005)

    func signInWithGoogle(idToken: String, nonce: String?) async throws -> NewSession {
        let identity = try await verifyGoogle(idToken: idToken, nonce: nonce)
        let userID = try await findOrCreateUser(
            AuthIdentity(provider: .google, subject: identity.subject, email: identity.email),
            displayName: identity.name
        )
        return try await issueSession(for: userID)
    }

    /// Adds Google to the signed-in account, so one person signing in with Apple and with Google
    /// has one library. A Google account already on another Aaru account is refused, never merged.
    func linkGoogle(userID: UserID, idToken: String, nonce: String?) async throws {
        let identity = try await verifyGoogle(idToken: idToken, nonce: nonce)
        if let owner = try await stores.users.user(for: .google, subject: identity.subject) {
            guard owner != userID else { return }
            throw AppError(
                status: .conflict, code: "identity_taken",
                message: "That Google account already signs in to a different Aaru account."
            )
        }
        try await stores.users.addIdentity(
            AuthIdentity(provider: .google, subject: identity.subject, email: identity.email), to: userID
        )
    }

    private func verifyGoogle(idToken: String, nonce: String?) async throws -> GoogleIdentity {
        guard let google else {
            throw AppError(
                status: .serviceUnavailable, code: "google_unavailable",
                message: "Sign in with Google is not available yet."
            )
        }
        do {
            return try await google.verify(idToken: idToken, nonce: nonce)
        } catch GoogleSignInError.invalidToken {
            throw AppError.unauthorized("The Google sign-in could not be verified.")
        }
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
        let code = EmailCode.generate()
        try await stores.magicLinks.create(
            email: email,
            tokenHash: OpaqueToken.hash(token),
            codeHash: EmailCode.hash(code, email: email),
            expiresAt: now().addingTimeInterval(Self.magicLinkLifetime)
        )
        var components = URLComponents(url: config.linkBaseURL, resolvingAgainstBaseURL: false)
        let queryItems = (components?.queryItems ?? []) + [URLQueryItem(name: "token", value: token)]
        components?.queryItems = queryItems
        guard let link = components?.url else {
            throw AppError(status: .internalServerError, code: "internal", message: "Something went wrong.")
        }
        try await config.sender.send(to: email, link: link, code: code)
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

    /// The app's path while the link cannot open it (APP-002): the email plus its 6-digit code.
    func verifyEmailCode(email rawEmail: String, code rawCode: String) async throws -> NewSession {
        let email = try Self.normalizedEmail(rawEmail)
        guard let code = EmailCode.normalized(rawCode) else {
            throw AppError(
                status: .unprocessableContent,
                code: "validation_failed",
                message: "The code is six digits.",
                details: ["code": "Six digits."]
            )
        }
        let consumed = try await stores.magicLinks.consume(
            email: email,
            codeHash: EmailCode.hash(code, email: email),
            maxAttempts: Self.maxCodeAttempts,
            now: now()
        )
        guard consumed else {
            throw AppError.unauthorized("This code is wrong, expired, or already used.")
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
            let userID = try await stores.users.createUser(with: identity, displayName: displayName?.nilIfBlank)
            ProductEvents.capture(.accountCreated, userID: userID, ["provider": identity.provider.rawValue])
            return userID
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
