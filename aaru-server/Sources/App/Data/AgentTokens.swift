import AaruCore
import Foundation

// Agent tokens (OUT-001, OUT-004): the scoped, revocable credentials the Stremio addon and MCP
// clients use. Part of the data layer boundary in Stores.swift.

/// What an agent token may do (OUT-001). A token never has more than a signed-in session.
enum AgentScope: String, Codable, Sendable, CaseIterable {
    case libraryRead = "library:read"
    case libraryWrite = "library:write"
    case scrobbleWrite = "scrobble:write"
    /// Queue an import for the user to review (`plan_import`). Never an apply.
    case importsWrite = "imports:write"
}

/// Which outside caller a token is for: the Stremio addon, an MCP client (OUT-004), or Aaru's
/// browser extension (SCR-007). The MCP kinds differ only in the setup Settings shows; they reach
/// the same tools.
enum AgentTokenKind: String, Codable, Sendable, CaseIterable {
    case stremio
    case claudeCode = "claude_code"
    case codex
    case hermes
    case gemini
    case other
    /// Claude (claude.ai, Desktop, mobile) through its custom connector, over OAuth.
    case claude
    /// Aaru's browser extension: scrobbles plays on streaming sites, nothing else (SCR-007).
    case browser

    /// Which surface a token opens. A token for one never authenticates on the other.
    enum Group: String, Sendable {
        case stremio, mcp, scrobble
    }

    var group: Group {
        switch self {
        case .stremio: .stremio
        case .browser: .scrobble
        case .claudeCode, .codex, .hermes, .gemini, .other, .claude: .mcp
        }
    }

    /// The default token name, and the client's name in Settings.
    var label: String {
        switch self {
        case .stremio: "Stremio"
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .hermes: "Hermes"
        case .gemini: "Gemini CLI"
        case .other: "MCP client"
        case .claude: "Claude"
        case .browser: "Browser extension"
        }
    }
}

/// One agent token as its owner sees it. The secret is never stored, only its SHA-256.
struct AgentToken: Sendable, Equatable {
    var id: UUID
    var name: String
    var kind: AgentTokenKind
    var scopes: Set<AgentScope>
    var createdAt: Date
    var lastUsedAt: Date?
}

protocol AgentTokenStore: Sendable {
    func create(_ token: AgentToken, tokenHash: String, userID: UserID) async throws
    /// Tokens not revoked, newest first.
    func tokens(userID: UserID) async throws -> [AgentToken]
    /// True when the user's token existed and was live.
    func revoke(id: UUID, userID: UserID, now: Date) async throws -> Bool
    /// The live token with this hash and its owner; nil when unknown, revoked or expired.
    func token(forHash hash: String, now: Date) async throws -> (token: AgentToken, userID: UserID)?
    func touch(id: UUID, at date: Date) async throws
}
