import Foundation
import HTTPTypes
import Hummingbird
import Logging

/// OUT-004 · the OAuth endpoints and discovery documents, hand-written like the MCP route:
/// their shapes are fixed by RFC 8414, 9728, 7591, 6749 and 7009, not by `openapi.yaml`.
/// claude.ai reads discovery and exchanges tokens from the browser, so these answer CORS `*`
/// without credentials. The user's own decision goes through `/v1/oauth/requests`.
struct OAuthRoutes: Sendable {
    let service: OAuthService
    var logger = Logger(label: "aaru-oauth")

    func register(on router: Router<AppRequestContext>) {
        for path in ["/.well-known/oauth-protected-resource", "/.well-known/oauth-protected-resource/v1/mcp"] {
            router.get(RouterPath(path)) { _, _ in Self.json(service.protectedResource) }
        }
        router.get("/.well-known/oauth-authorization-server") { _, _ in
            Self.json(service.authorizationServer)
        }
        router.post("/oauth/register") { request, context in
            await respond { try await registration(request, context: context) }
        }
        router.get("/oauth/authorize") { request, _ in
            await respond { try await authorize(request) }
        }
        router.post("/oauth/token") { request, _ in
            await respond { try await Self.json(service.token(Self.form(request))) }
        }
        router.post("/oauth/revoke") { request, _ in
            await respond {
                try await service.revoke(Self.form(request))
                return Self.json([:])
            }
        }
        for path in [
            "/.well-known/oauth-protected-resource", "/.well-known/oauth-protected-resource/v1/mcp",
            "/.well-known/oauth-authorization-server", "/oauth/register", "/oauth/token", "/oauth/revoke",
        ] {
            router.on(RouterPath(path), method: .options) { _, _ in
                Response(status: .noContent, headers: Self.cors)
            }
        }
    }

    private func registration(_ request: Request, context: AppRequestContext) async throws -> Response {
        let body = try await request.body.collect(upTo: 16 * 1024)
        guard let registration = try? JSONDecoder().decode(OAuthService.Registration.self, from: Data(buffer: body))
        else { throw OAuthError(error: "invalid_client_metadata", description: "The body is not JSON client metadata.")
        }
        let client = try await service.register(registration, clientAddress: context.clientAddressForRateLimit)
        return Self.json(client, status: .created)
    }

    private func authorize(_ request: Request) async throws -> Response {
        var query: [String: String] = [:]
        for (name, value) in request.uri.queryParameters {
            query[String(name)] = String(value)
        }
        switch try await service.authorize(query) {
        case let .refuse(message):
            return Response(
                status: .badRequest, headers: [.contentType: "text/plain; charset=utf-8", .cacheControl: "no-store"],
                body: .init(byteBuffer: ByteBuffer(string: message))
            )
        case let .redirect(url):
            return Response(status: .found, headers: [.location: url.absoluteString, .cacheControl: "no-store"])
        case let .consent(url, binding):
            return Response(status: .found, headers: [
                .location: url.absoluteString, .setCookie: service.bindingCookie(binding), .cacheControl: "no-store",
            ])
        }
    }

    /// Every OAuth failure as RFC 6749's JSON; anything unexpected is logged and stays vague.
    private func respond(_ body: () async throws -> Response) async -> Response {
        do {
            return try await body()
        } catch let error as OAuthError {
            return Self.json(
                ["error": .string(error.error), "error_description": .string(error.description)], status: error.status
            )
        } catch {
            logger.error("OAuth request failed", metadata: ["error": "\(error)"])
            return Self.json(
                ["error": .string("server_error"), "error_description": .string("Try again later.")],
                status: .internalServerError
            )
        }
    }

    // MARK: Encoding

    static let cors: HTTPFields = [
        .accessControlAllowOrigin: "*",
        .accessControlAllowHeaders: "Authorization, Content-Type, MCP-Protocol-Version",
        .accessControlAllowMethods: "GET, POST, OPTIONS",
        .accessControlMaxAge: "86400",
    ]

    static func json(_ body: [String: JSONValue], status: HTTPResponse.Status = .ok) -> Response {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        var headers = cors
        headers[.contentType] = "application/json"
        headers[.cacheControl] = "no-store"
        return Response(
            status: status, headers: headers,
            body: .init(byteBuffer: ByteBuffer(bytes: (try? encoder.encode(body)) ?? Data("{}".utf8)))
        )
    }

    /// An `application/x-www-form-urlencoded` body, as the token and revoke endpoints take.
    static func form(_ request: Request) async throws -> [String: String] {
        let body = try await request.body.collect(upTo: 16 * 1024)
        let text = String(buffer: body)
        var fields: [String: String] = [:]
        for pair in text.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map {
                String($0).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String($0)
            }
            if let name = parts.first, !name.isEmpty {
                fields[name] = parts.count > 1 ? parts[1] : ""
            }
        }
        return fields
    }
}
