import AaruCore
import Foundation

// Agent tokens (OUT-001, OUT-004): the scoped, revocable credentials the Stremio addon and MCP
// clients use. Part of the data layer boundary in Stores.swift.

/// What an agent token may do (OUT-001). A token never has more than a signed-in session.
enum AgentScope: String, Codable, Sendable, CaseIterable {
    case libraryRead = "library:read"
    case libraryWrite = "library:write"
    case scrobbleWrite = "scrobble:write"
}

/// Which outside caller a token is for: the Stremio addon, or an MCP client (OUT-004).
/// The MCP kinds differ only in the setup Settings shows; they reach the same tools.
enum AgentTokenKind: String, Codable, Sendable, CaseIterable {
    case stremio
    case claudeCode = "claude_code"
    case codex
    case hermes
    case gemini
    case other

    /// Which surface a token opens. A token for one never authenticates on the other.
    enum Group: String, Sendable {
        case stremio, mcp
    }

    var group: Group {
        self == .stremio ? .stremio : .mcp
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
