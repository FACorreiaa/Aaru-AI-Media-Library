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
    /// The addon's manifest over HTTPS, and the same link for the Stremio app and Stremio Web.
    struct StremioLinks: Sendable {
        var manifestURL: URL
        var installURL: URL
        var webInstallURL: URL
    }

    var token: AgentToken
    var secret: String
    /// Only for a Stremio token.
    var stremio: StremioLinks?
}

/// OUT-001: per-user tokens for outside callers: the Stremio addon, MCP clients (OUT-004) and the
/// browser extension (SCR-007).
/// The secret is a per-surface prefix + 32 random bytes; Postgres keeps only its SHA-256.
struct AgentTokenService: Sendable {
    static let stremioPrefix = "aaru_st_"
    static let mcpPrefix = "aaru_mcp_"
    static let scrobblePrefix = "aaru_scr_"
    /// An access token the OAuth front door issued (one hour). Also an MCP credential.
    static let oauthPrefix = "aaru_oat_"
    /// `last_used_at` is written at most this often, so a busy addon does not write per request.
    static let touchInterval: TimeInterval = 60 * 60
    /// Requests per token per minute. Stremio asks for a few catalogs per screen.
    static let requestsPerMinute = 120

    let stores: Stores
    /// Where this API is reachable from outside, for install links.
    let publicBaseURL: URL
    let limiter = FixedWindowRateLimiter(limit: requestsPerMinute, window: 60)
    var now: @Sendable () -> Date = { Date() }

    func create(
        userID: UserID,
        kind: AgentTokenKind,
        name: String?,
        allowLibraryWrites: Bool,
        allowImports: Bool = false
    ) async throws -> MintedAgentToken {
        guard kind != .claude else {
            throw AppError(
                status: .unprocessableContent, code: "validation_failed",
                message: "Claude connects through its connector: add Aaru in Claude and approve it there.",
                details: ["kind": "Claude connects over OAuth."]
            )
        }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.count <= 80 else {
            throw AppError(
                status: .unprocessableContent, code: "validation_failed",
                message: "Names are at most 80 characters.", details: ["name": "At most 80 characters."]
            )
        }
        // An MCP client reads and, if allowed, writes the library; only a player scrobbles. The
        // browser extension only scrobbles: it never reads the library.
        var scopes: Set<AgentScope> = switch kind.group {
        case .stremio: [.libraryRead, .scrobbleWrite]
        case .mcp: [.libraryRead]
        case .scrobble: [.scrobbleWrite]
        }
        if allowLibraryWrites, kind.group != .scrobble {
            scopes.insert(.libraryWrite)
        }
        if allowImports, kind.group == .mcp {
            scopes.insert(.importsWrite)
        }
        let token = AgentToken(
            id: UUID(), name: trimmed.isEmpty ? kind.label : trimmed, kind: kind, scopes: scopes,
            createdAt: now(), lastUsedAt: nil
        )
        let secret = Self.prefix(for: kind.group) + OpaqueToken.generate()
        try await stores.agentTokens.create(token, tokenHash: OpaqueToken.hash(secret), userID: userID)
        return MintedAgentToken(
            token: token, secret: secret, stremio: kind.group == .stremio ? stremioLinks(secret) : nil
        )
    }

    /// Live tokens for one surface, newest first. Old Apple builds decode only Stremio kinds,
    /// so the list never mixes the two.
    func tokens(userID: UserID, group: AgentTokenKind.Group) async throws -> [AgentToken] {
        try await stores.agentTokens.tokens(userID: userID).filter { $0.kind.group == group }
    }

    static func prefix(for group: AgentTokenKind.Group) -> String {
        switch group {
        case .stremio: stremioPrefix
        case .mcp: mcpPrefix
        case .scrobble: scrobblePrefix
        }
    }

    func revoke(id: UUID, userID: UserID) async throws {
        guard try await stores.agentTokens.revoke(id: id, userID: userID, now: now()) else {
            throw AppError.notFound()
        }
    }

    /// The live token for a presented secret on one surface, or nil. Records use at most hourly.
    func authenticate(_ secret: String, for group: AgentTokenKind.Group) async throws -> AgentCaller? {
        let prefixes = group == .mcp ? [Self.mcpPrefix, Self.oauthPrefix] : [Self.prefix(for: group)]
        guard prefixes.contains(where: secret.hasPrefix), secret.count < 200 else { return nil }
        let now = now()
        guard let (token, userID) = try await stores.agentTokens.token(forHash: OpaqueToken.hash(secret), now: now),
              token.kind.group == group
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

    private func stremioLinks(_ secret: String) -> MintedAgentToken.StremioLinks {
        let manifest = publicBaseURL.appendingPathComponent("stremio").appendingPathComponent(secret)
            .appendingPathComponent("manifest.json")
        var install = URLComponents(url: manifest, resolvingAgainstBaseURL: false)
        install?.scheme = "stremio"
        var web = URLComponents(string: "https://web.stremio.com/")
        // Stremio Web reads the addon from its hash route.
        web?.percentEncodedFragment = "/addons?addon=" + (manifest.absoluteString
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~"))) ?? "")
        return MintedAgentToken.StremioLinks(
            manifestURL: manifest, installURL: install?.url ?? manifest, webInstallURL: web?.url ?? manifest
        )
    }
}
