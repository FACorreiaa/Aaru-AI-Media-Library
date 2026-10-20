import AaruCore
import Foundation
import HTTPTypes
import Hummingbird
import Logging

/// OUT-004 · `POST /v1/mcp`, MCP over streamable HTTP. Stateless: no session id, no server
/// stream, one JSON answer per request. Hand-written like the Stremio routes because it
/// authenticates itself: only an MCP agent token gets in, never a session or a Stremio link,
/// and the token is looked up once per request.
///
/// This folder is a transport over `AgentTools`. Deleting it and its line in `buildRouter`
/// leaves every feature reachable through `/v1`.
struct MCPRoutes: Sendable {
    static let path = "/v1/mcp"
    static let maxBody = 1 << 20

    let tools: AgentTools
    let tokens: AgentTokenService
    /// Browser origins allowed to call (`MCP_ALLOWED_ORIGINS`). Real MCP clients send none.
    var allowedOrigins: Set<String> = []
    var logger = Logger(label: "aaru-mcp")

    func register(on router: Router<AppRequestContext>) {
        router.post(RouterPath(Self.path)) { request, _ in
            await respond(to: request)
        }
        // No server-initiated stream and no sessions to end.
        for method in [HTTPRequest.Method.get, .delete] {
            router.on(RouterPath(Self.path), method: method) { _, _ in
                Response(status: .methodNotAllowed, headers: [.allow: "POST"])
            }
        }
    }

    func respond(to request: Request) async -> Response {
        if let origin = request.headers[.origin], !origin.isEmpty, !allowedOrigins.contains(origin.lowercased()) {
            return Self.plain(.forbidden, "This origin may not call Aaru's MCP endpoint.")
        }
        if let version = request.headers[.mcpProtocolVersion], !MCPProtocol.versions.contains(version) {
            return Self.plain(.badRequest, "Unsupported MCP-Protocol-Version \(version).")
        }
        do {
            guard let secret = AuthMiddleware.bearerToken(request),
                  let caller = try await tokens.authenticate(secret, for: .mcp)
            else { return Self.unauthorized() }
            guard await tokens.allow(caller) else {
                return Self.plain(.tooManyRequests, "Too many requests. Wait a minute.")
            }
            let body: ByteBuffer
            do {
                body = try await request.body.collect(upTo: Self.maxBody)
            } catch {
                return Self.plain(.contentTooLarge, "Requests are at most 1 MiB.")
            }
            return try await handle(Data(buffer: body), caller: caller)
        } catch {
            logger.error("MCP request failed", metadata: ["error": "\(error)"])
            return Self.plain(.internalServerError, "Something went wrong.")
        }
    }

    private func handle(_ body: Data, caller: AgentCaller) async throws -> Response {
        let rpc: MCPRequest
        do {
            rpc = try JSONDecoder().decode(MCPRequest.self, from: body)
        } catch {
            // A JSON-RPC batch (an array) lands here too: removed from the spec in 2025-06-18.
            return try Self.json(.failure(id: nil, .parseError("The body is not one JSON-RPC request.")))
        }
        // Notifications and client responses get 202 and no body.
        guard let id = rpc.id else { return Response(status: .accepted) }
        do {
            return try await Self.json(.success(id: id, dispatch(rpc, caller: caller)))
        } catch let error as MCPError {
            return try Self.json(.failure(id: id, error))
        }
    }

    private func dispatch(_ rpc: MCPRequest, caller: AgentCaller) async throws -> JSONValue {
        switch rpc.method {
        case "initialize":
            let requested = rpc.params?.objectValue?["protocolVersion"]?.stringValue
            return .object([
                "protocolVersion": .string(MCPProtocol.negotiate(requested)),
                "capabilities": .object(["tools": .object(["listChanged": .bool(false)])]),
                "serverInfo": .object([
                    "name": .string(MCPProtocol.serverName),
                    "title": .string(MCPProtocol.serverTitle),
                    "version": .string(MCPProtocol.serverVersion),
                ]),
                "instructions": .string(MCPProtocol.instructions),
            ])
        case "ping":
            return .object([:])
        case "tools/list":
            return .object(["tools": MCPToolCatalog.listing])
        case "tools/call":
            return try await call(rpc.params, caller: caller)
        default:
            throw MCPError.methodNotFound("Aaru does not support \(rpc.method).")
        }
    }

    private func call(_ params: JSONValue?, caller: AgentCaller) async throws -> JSONValue {
        guard let params = params?.objectValue, let name = params["name"]?.stringValue else {
            throw MCPError.invalidParams("tools/call needs a name.")
        }
        guard let tool = MCPToolCatalog.tool(named: name) else {
            throw MCPError.invalidParams("Aaru has no tool named \(name).")
        }
        let arguments = params["arguments"]?.objectValue ?? [:]
        if let unknown = tool.unknownArgument(in: arguments) {
            return Self.toolError("\(name) has no argument \(unknown).")
        }
        do {
            let result = try await tool.run(tools, .object(arguments), caller)
            return try Self.toolResult(JSONValue.encoding(result))
        } catch let error as AgentToolError {
            return Self.toolError(error.message)
        } catch let error as AppError where error.status.code < 500 {
            return Self.toolError(error.message)
        } catch let error as ValidationError {
            return Self.toolError(error.description)
        } catch is DecodingError {
            return Self.toolError("The arguments for \(name) do not match its input schema.")
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Never hand an agent an internal message it would repeat to the user.
            logger.error("MCP tool failed", metadata: ["tool": "\(name)", "error": "\(error)"])
            return Self.toolError("Aaru could not finish \(name). Try again later.")
        }
    }

    // MARK: Responses

    /// MCP wants structured content plus a text rendering; clients differ in which they show.
    private static func toolResult(_ value: JSONValue) throws -> JSONValue {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        let text = try String(bytes: encoder.encode(value), encoding: .utf8) ?? "{}"
        return .object([
            "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
            "structuredContent": value,
            "isError": .bool(false),
        ])
    }

    private static func toolError(_ message: String) -> JSONValue {
        .object([
            "content": .array([.object(["type": .string("text"), "text": .string(message)])]),
            "isError": .bool(true),
        ])
    }

    private static func json(_ response: MCPResponse) throws -> Response {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return try Response(
            status: .ok,
            headers: [.contentType: "application/json", .cacheControl: "no-store"],
            body: .init(byteBuffer: ByteBuffer(bytes: encoder.encode(response)))
        )
    }

    private static func plain(_ status: HTTPResponse.Status, _ message: String) -> Response {
        Response(
            status: status,
            headers: [.contentType: "text/plain; charset=utf-8", .cacheControl: "no-store"],
            body: .init(byteBuffer: ByteBuffer(string: message))
        )
    }

    private static func unauthorized() -> Response {
        var response = plain(.unauthorized, "Connect this client in Aaru → Settings → Connections.")
        response.headers[.wwwAuthenticate] = #"Bearer realm="aaru""#
        return response
    }
}

extension HTTPField.Name {
    // swiftlint:disable:next force_unwrapping
    static let mcpProtocolVersion = Self("MCP-Protocol-Version")!
}
