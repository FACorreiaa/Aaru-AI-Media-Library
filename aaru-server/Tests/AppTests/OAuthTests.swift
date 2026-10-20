import AaruCore
import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
@testable import aaru

@Suite("OAuth front door for Claude's connector (OUT-004)", .serialized)
struct OAuthTests {
    static let callback = "https://claude.ai/api/mcp/auth_callback"
    static let resource = "https://api.aaruapp.com/v1/mcp"

    private struct Raw {
        let status: HTTPResponse.Status
        let headers: HTTPFields
        let body: Data

        func json() throws -> [String: Any] {
            try (JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
        }
    }

    private func raw(
        _ env: LibraryHarness,
        _ method: HTTPRequest.Method,
        _ uri: String,
        headers: HTTPFields = [:],
        body: String? = nil
    ) async throws -> Raw {
        try await env.client.execute(
            uri: uri, method: method, headers: headers, body: body.map { ByteBuffer(string: $0) }
        ) { Raw(status: $0.status, headers: $0.headers, body: Data(buffer: $0.body)) }
    }

    private func form(_ env: LibraryHarness, _ path: String, _ fields: [String: String]) async throws -> Raw {
        let body = fields.map { name, value in
            "\(name)=\(value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value)"
        }.joined(separator: "&")
        return try await raw(env, .post, path, headers: [.contentType: "application/x-www-form-urlencoded"], body: body)
    }

    private func register(_ env: LibraryHarness, name: String = "Claude") async throws -> String {
        let reply = try await raw(
            env, .post, "/oauth/register", headers: [.contentType: "application/json"],
            body: #"{"client_name":"\#(name)","redirect_uris":["\#(Self.callback)"]}"#
        )
        #expect(reply.status == .created)
        return try #require(reply.json()["client_id"] as? String)
    }

    /// Authorize, then approve as the signed-in user; returns the code and the verifier.
    private func authorize(
        _ env: LibraryHarness,
        clientID: String,
        allowWrites: Bool = false
    ) async throws -> (code: String, verifier: String) {
        let verifier = OpaqueToken.generate() + OpaqueToken.generate()
        var query = try #require(URLComponents(string: "/oauth/authorize"))
        query.queryItems = [
            .init(name: "client_id", value: clientID), .init(name: "redirect_uri", value: Self.callback),
            .init(name: "response_type", value: "code"), .init(name: "state", value: "xyz"),
            .init(name: "code_challenge", value: OAuthService.challenge(for: verifier)),
            .init(name: "code_challenge_method", value: "S256"), .init(name: "resource", value: Self.resource),
        ]
        let started = try await raw(env, .get, #require(query.string))
        #expect(started.status == .found)
        let consent = try #require(started.headers[.location].flatMap(URLComponents.init(string:)))
        #expect(consent.host == "aaruapp.com" && consent.path == "/oauth/consent")
        let requestID = try #require(consent.queryItems?.first { $0.name == "request" }?.value)
        let cookie = try #require(started.headers[.setCookie])
        #expect(cookie.contains("HttpOnly") && cookie.contains("Domain=aaruapp.com"))
        let binding = try #require(cookie.split(separator: ";").first?.split(separator: "=").last.map(String.init))

        let shown = try await env.send(.get, "/v1/oauth/requests/\(requestID)").json()
        #expect(shown["redirectHost"] as? String == "claude.ai")
        #expect(
            try await env.send(.post, "/v1/oauth/requests/\(requestID)/approve", json: ["binding": "stolen"])
                .status == .forbidden,
            "another browser cannot answer"
        )

        let approved = try await env.send(.post, "/v1/oauth/requests/\(requestID)/approve", json: [
            "binding": binding, "allowLibraryWrites": allowWrites,
        ]).json()
        let back = try #require((approved["redirectTo"] as? String).flatMap(URLComponents.init(string:)))
        #expect(back.host == "claude.ai")
        #expect(back.queryItems?.first { $0.name == "state" }?.value == "xyz")
        let code = try #require(back.queryItems?.first { $0.name == "code" }?.value)
        return (code, verifier)
    }

    private func exchange(_ env: LibraryHarness, clientID: String, code: String, verifier: String) async throws
        -> Raw
    {
        try await form(env, "/oauth/token", [
            "grant_type": "authorization_code", "code": code, "client_id": clientID, "code_verifier": verifier,
            "redirect_uri": Self.callback, "resource": Self.resource,
        ])
    }

    private func mcpPing(_ env: LibraryHarness, _ token: String) async throws -> HTTPResponse.Status {
        try await raw(
            env, .post, MCPRoutes.path,
            headers: [.contentType: "application/json", .authorization: "Bearer \(token)"],
            body: #"{"jsonrpc":"2.0","id":1,"method":"ping"}"#
        ).status
    }

    @Test("Discovery: an unauthenticated MCP call points at metadata naming Aaru's endpoints")
    func discovery() async throws {
        try await LibraryHarness.run { env in
            let challenge = try await raw(env, .post, MCPRoutes.path, body: "{}")
            #expect(challenge.status == .unauthorized)
            #expect(challenge.headers[.wwwAuthenticate]?.contains(
                #"resource_metadata="https://api.aaruapp.com/.well-known/oauth-protected-resource/v1/mcp""#
            ) == true)
            let resource = try await raw(env, .get, "/.well-known/oauth-protected-resource/v1/mcp").json()
            #expect(resource["resource"] as? String == Self.resource)
            let server = try await raw(env, .get, "/.well-known/oauth-authorization-server")
            #expect(server.headers[.accessControlAllowOrigin] == "*")
            let metadata = try server.json()
            #expect(metadata["registration_endpoint"] as? String == "https://api.aaruapp.com/oauth/register")
            #expect(metadata["code_challenge_methods_supported"] as? [String] == ["S256"])
        }
    }

    @Test("Registration takes https or loopback redirects only; authorize never redirects to an unregistered one")
    func registration() async throws {
        try await LibraryHarness.run { env in
            let bad = try await raw(
                env, .post, "/oauth/register", headers: [.contentType: "application/json"],
                body: #"{"client_name":"x","redirect_uris":["http://evil.example/cb"]}"#
            )
            #expect(try bad.json()["error"] as? String == "invalid_redirect_uri")
            let loopback = try await raw(
                env, .post, "/oauth/register", headers: [.contentType: "application/json"],
                body: #"{"client_name":"Claude Code","redirect_uris":["http://localhost:4567/callback"]}"#
            )
            #expect(loopback.status == .created)

            let clientID = try await register(env)
            let hijack = try await raw(
                env, .get, "/oauth/authorize?client_id=\(clientID)&redirect_uri=https://evil.example/cb"
                    + "&response_type=code&code_challenge=\(String(repeating: "a", count: 43))"
                    + "&code_challenge_method=S256"
            )
            #expect(hijack.status == .badRequest)
            #expect(hijack.headers[.location] == nil)
            let plain = try await raw(
                env, .get, "/oauth/authorize?client_id=\(clientID)&redirect_uri=\(Self.callback)"
                    + "&response_type=code&code_challenge=abc&code_challenge_method=plain&state=s"
            )
            #expect(plain.headers[.location]?.contains("error=invalid_request") == true, "S256 only")
        }
    }

    @Test("The full flow: consent, PKCE, a token that opens MCP only, refresh rotation and reuse detection")
    func flow() async throws {
        try await LibraryHarness.run { env in
            let clientID = try await register(env)
            let (code, verifier) = try await authorize(env, clientID: clientID, allowWrites: true)
            let wrong = try await exchange(env, clientID: clientID, code: code, verifier: verifier + "x")
            #expect(try wrong.json()["error"] as? String == "invalid_grant", "PKCE mismatch, and the code is spent")

            let (fresh, freshVerifier) = try await authorize(env, clientID: clientID, allowWrites: true)
            let tokens = try await exchange(env, clientID: clientID, code: fresh, verifier: freshVerifier).json()
            let access = try #require(tokens["access_token"] as? String)
            let refresh = try #require(tokens["refresh_token"] as? String)
            #expect(access.hasPrefix("aaru_oat_"))
            #expect(tokens["scope"] as? String == "library:read library:write")
            #expect(try await mcpPing(env, access) == .ok)
            #expect(try await env.send(.get, "/v1/library/items", token: access).status == .unauthorized)

            let listed = try await env.send(.get, "/v1/agent/tokens?for=mcp").json()["items"] as? [[String: Any]]
            #expect(listed?.first?["kind"] as? String == "claude")
            #expect(listed?.first?["name"] as? String == "Claude")

            let rotated = try await form(env, "/oauth/token", [
                "grant_type": "refresh_token", "refresh_token": refresh, "client_id": clientID,
            ]).json()
            let newAccess = try #require(rotated["access_token"] as? String)
            #expect(try await mcpPing(env, access) == .unauthorized, "the old access token is replaced")
            #expect(try await mcpPing(env, newAccess) == .ok)

            let replay = try await form(env, "/oauth/token", [
                "grant_type": "refresh_token", "refresh_token": refresh, "client_id": clientID,
            ])
            #expect(try replay.json()["error"] as? String == "invalid_grant")
            #expect(try await mcpPing(env, newAccess) == .unauthorized, "a replayed refresh revokes the connection")
        }
    }

    @Test("A reused code revokes what it issued; revoking in Settings stops refresh")
    func revocation() async throws {
        try await LibraryHarness.run { env in
            let clientID = try await register(env)
            let (code, verifier) = try await authorize(env, clientID: clientID)
            let first = try await exchange(env, clientID: clientID, code: code, verifier: verifier).json()
            let access = try #require(first["access_token"] as? String)
            #expect(first["scope"] as? String == "library:read")
            let again = try await exchange(env, clientID: clientID, code: code, verifier: verifier)
            #expect(try again.json()["error"] as? String == "invalid_grant")
            #expect(try await mcpPing(env, access) == .unauthorized)

            let (second, secondVerifier) = try await authorize(env, clientID: clientID)
            let tokens = try await exchange(env, clientID: clientID, code: second, verifier: secondVerifier).json()
            let refresh = try #require(tokens["refresh_token"] as? String)
            let listed = try await env.send(.get, "/v1/agent/tokens?for=mcp").json()["items"] as? [[String: Any]]
            let id = try #require(listed?.first?["id"] as? String)
            #expect(try await env.send(.delete, "/v1/agent/tokens/\(id)").status == .noContent)
            let refused = try await form(env, "/oauth/token", [
                "grant_type": "refresh_token", "refresh_token": refresh, "client_id": clientID,
            ])
            #expect(try refused.json()["error"] as? String == "invalid_grant")
            #expect(
                try await env.send(.post, "/v1/agent/tokens", json: ["kind": "claude"]).status
                    == .unprocessableContent,
                "Claude connects over OAuth, never with a pasted token"
            )
        }
    }
}
