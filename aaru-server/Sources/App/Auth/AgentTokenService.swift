import AaruCore
import Foundation

/// A request made with an agent token: whose library, through which token, allowed to do what.
struct AgentCaller: Sendable, Equatable {
    var userID: UserID
    var token: AgentToken

    func has(_ scope: AgentScope) -> Bool {
        token.scopes.contains(scope)
    }
}

/// A freshly minted token: the only time its secret exists outside the caller's hands.
struct MintedAgentToken: Sendable {
    var token: AgentToken
    var secret: String
    /// The addon's manifest over HTTPS, and the same link for the Stremio app and Stremio Web.
    var manifestURL: URL
    var installURL: URL
    var webInstallURL: URL
}

/// OUT-001 (minimal): per-user tokens for outside callers, today only the Stremio addon.
/// The secret is `aaru_st_` + 32 random bytes; Postgres keeps only its SHA-256.
struct AgentTokenService: Sendable {
    static let secretPrefix = "aaru_st_"
    /// `last_used_at` is written at most this often, so a busy addon does not write per request.
    static let touchInterval: TimeInterval = 60 * 60
    /// Requests per token per minute. Stremio asks for a few catalogs per screen.
    static let requestsPerMinute = 120

    let stores: Stores
    /// Where this API is reachable from outside, for install links.
    let publicBaseURL: URL
    let limiter = FixedWindowRateLimiter(limit: requestsPerMinute, window: 60)
    var now: @Sendable () -> Date = { Date() }

    func create(userID: UserID, kind: AgentTokenKind, name: String?, allowLibraryWrites: Bool) async throws
        -> MintedAgentToken
    {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.count <= 80 else {
            throw AppError(
                status: .unprocessableContent, code: "validation_failed",
                message: "Names are at most 80 characters.", details: ["name": "At most 80 characters."]
            )
        }
        var scopes: Set<AgentScope> = [.libraryRead, .scrobbleWrite]
        if allowLibraryWrites {
            scopes.insert(.libraryWrite)
        }
        let token = AgentToken(
            id: UUID(), name: trimmed.isEmpty ? "Stremio" : trimmed, kind: kind, scopes: scopes,
            createdAt: now(), lastUsedAt: nil
        )
        let secret = Self.secretPrefix + OpaqueToken.generate()
        try await stores.agentTokens.create(token, tokenHash: OpaqueToken.hash(secret), userID: userID)
        return minted(token, secret: secret)
    }

    func tokens(userID: UserID) async throws -> [AgentToken] {
        try await stores.agentTokens.tokens(userID: userID)
    }

    func revoke(id: UUID, userID: UserID) async throws {
        guard try await stores.agentTokens.revoke(id: id, userID: userID, now: now()) else {
            throw AppError.notFound()
        }
    }

    /// The live token for a presented secret, or nil. Records use at most hourly.
    func authenticate(_ secret: String) async throws -> AgentCaller? {
        guard secret.hasPrefix(Self.secretPrefix), secret.count < 200 else { return nil }
        let now = now()
        guard let (token, userID) = try await stores.agentTokens.token(forHash: OpaqueToken.hash(secret), now: now)
        else { return nil }
        if token.lastUsedAt.map({ now.timeIntervalSince($0) >= Self.touchInterval }) ?? true {
            try? await stores.agentTokens.touch(id: token.id, at: now)
        }
        return AgentCaller(userID: userID, token: token)
    }

    /// Whether this token is inside its request budget.
    func allow(_ caller: AgentCaller) async -> Bool {
        await limiter.allow(caller.token.id.uuidString, now: now())
    }

    private func minted(_ token: AgentToken, secret: String) -> MintedAgentToken {
        let manifest = publicBaseURL.appendingPathComponent("stremio").appendingPathComponent(secret)
            .appendingPathComponent("manifest.json")
        var install = URLComponents(url: manifest, resolvingAgainstBaseURL: false)
        install?.scheme = "stremio"
        var web = URLComponents(string: "https://web.stremio.com/")
        // Stremio Web reads the addon from its hash route.
        web?.percentEncodedFragment = "/addons?addon=" + (manifest.absoluteString
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~"))) ?? "")
        return MintedAgentToken(
            token: token, secret: secret, manifestURL: manifest,
            installURL: install?.url ?? manifest, webInstallURL: web?.url ?? manifest
        )
    }
}
