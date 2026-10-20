import Foundation

/// OUT-004 · MCP over streamable HTTP, hand-rolled rather than from an SDK: the wire format is
/// small, and the part an SDK would own (transport and auth) is exactly what must stay ours,
/// because every call is one user's library through one revocable token.
enum MCPProtocol {
    /// Spec revisions this server speaks, newest first. `initialize` echoes the client's when
    /// it is one of these, else offers the newest.
    static let versions = ["2025-11-25", "2025-06-18", "2025-03-26"]
    static let serverName = "aaru"
    static let serverTitle = "Aaru"
    /// The MCP surface's version, not the server's. Bump when a tool or schema changes.
    static let serverVersion = "1.0.0"

    static func negotiate(_ requested: String?) -> String {
        requested.flatMap { versions.contains($0) ? $0 : nil } ?? versions[0]
    }

    static let instructions = """
    Aaru is one person's private media library: movies, shows, anime and books, with what they plan \
    to watch or read, what they are in the middle of, and what they finished.

    Read with read_library (their items, by status, type or list), list_airs (episodes of shows they \
    track airing soon, or their Up Next) and search_titles (the public catalog). Search before \
    adding, and add by the mediaRef a search hit gives you.

    apply_library_patch changes the library only if the user allowed changes for this connection. \
    One item at a time applies at once, like a tap in the app, and the user can undo it there. \
    Anything larger needs the user's approval inside Aaru. Never tell the user something changed \
    unless the tool answered applied: true.
    """
}

// MARK: - JSON-RPC

struct MCPRequest: Decodable, Sendable {
    let jsonrpc: String?
    /// Absent for notifications, which get no answer.
    let id: JSONValue?
    let method: String
    let params: JSONValue?
}

struct MCPResponse: Encodable, Sendable {
    let jsonrpc = "2.0"
    let id: JSONValue?
    var result: JSONValue?
    var error: MCPErrorBody?

    static func success(id: JSONValue?, _ result: JSONValue) -> MCPResponse {
        MCPResponse(id: id, result: result, error: nil)
    }

    static func failure(id: JSONValue?, _ error: MCPError) -> MCPResponse {
        MCPResponse(id: id, result: nil, error: error.body)
    }
}

struct MCPErrorBody: Encodable, Sendable {
    let code: Int
    let message: String
}

/// Protocol failures. A tool that cannot do what was asked answers a normal result with
/// `isError: true` instead, so the agent can react.
enum MCPError: Error, Sendable {
    case parseError(String)
    case invalidRequest(String)
    case methodNotFound(String)
    case invalidParams(String)
    case internalError(String)

    var body: MCPErrorBody {
        switch self {
        case let .parseError(message): MCPErrorBody(code: -32700, message: message)
        case let .invalidRequest(message): MCPErrorBody(code: -32600, message: message)
        case let .methodNotFound(message): MCPErrorBody(code: -32601, message: message)
        case let .invalidParams(message): MCPErrorBody(code: -32602, message: message)
        case let .internalError(message): MCPErrorBody(code: -32603, message: message)
        }
    }
}
