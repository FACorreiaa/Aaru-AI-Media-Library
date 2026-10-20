import AaruCore
import Foundation
import Testing
@testable import aaru

@Suite("Agent tokens (OUT-001, minimal)", .serialized)
struct AgentTokenTests {
    private struct HashRow: Decodable {
        let tokenHash: String
        let scopes: [String]
    }

    @Test("Create, list and revoke; the secret is shown once and never stored")
    func lifecycle() async throws {
        try await LibraryHarness.run { env in
            let created = try await env.send(.post, "/v1/agent/tokens", json: ["kind": "stremio"])
            #expect(created.status == .created)
            let body = try created.json()
            let secret = try #require(body["secret"] as? String)
            let token = try #require(body["token"] as? [String: Any])
            let id = try #require(token["id"] as? String)
            #expect(secret.hasPrefix("aaru_st_"))
            #expect(token["name"] as? String == "Stremio")
            #expect(token["scopes"] as? [String] == ["library:read", "scrobble:write"])
            let stremio = try #require(body["stremio"] as? [String: String])
            #expect(stremio["manifestUrl"] == "https://api.aaruapp.com/stremio/\(secret)/manifest.json")
            #expect(stremio["installUrl"] == "stremio://api.aaruapp.com/stremio/\(secret)/manifest.json")
            #expect(stremio["webInstallUrl"]?
                .hasPrefix("https://web.stremio.com/#/addons?addon=https%3A%2F%2F") == true)

            let tokenID = try #require(UUID(uuidString: id))
            let stored = try await withSQL { sql in
                try await sql
                    .raw("SELECT token_hash, scopes FROM agent_tokens WHERE id = \(bind: tokenID)")
                    .first(decoding: HashRow.self, keyDecodingStrategy: .convertFromSnakeCase)
            }
            #expect(stored?.tokenHash == OpaqueToken.hash(secret))
            #expect(stored?.tokenHash.contains(secret) == false)

            let listed = try await env.send(.get, "/v1/agent/tokens").json()["items"] as? [[String: Any]]
            #expect(listed?.compactMap { $0["id"] as? String } == [id])
            #expect(listed?.first?["secret"] == nil)

            let service = AgentTokenService(stores: env.stores, publicBaseURL: URL(string: "https://api.aaruapp.com")!)
            let caller = try #require(try await service.authenticate(secret))
            #expect(caller.userID == env.userID)
            #expect(caller.has(.scrobbleWrite) && !caller.has(.libraryWrite))
            #expect(try await service.authenticate("aaru_st_wrong") == nil)
            #expect(try await service.authenticate(String(secret.dropFirst(8))) == nil, "prefix required")

            #expect(try await env.send(.delete, "/v1/agent/tokens/\(id)").status == .noContent)
            #expect(try await env.send(.delete, "/v1/agent/tokens/\(id)").status == .notFound)
            #expect(try await service.authenticate(secret) == nil, "revoked")
            #expect(try (await env.send(.get, "/v1/agent/tokens").json()["items"] as? [Any])?.isEmpty == true)
        }
    }

    @Test("Library writes are opt-in; another user cannot revoke your token")
    func scopesAndOwnership() async throws {
        try await LibraryHarness.run { env in
            let body = try await env.send(.post, "/v1/agent/tokens", json: [
                "kind": "stremio", "name": "Living room", "allowLibraryWrites": true,
            ]).json()
            let token = try #require(body["token"] as? [String: Any])
            #expect(token["name"] as? String == "Living room")
            #expect(token["scopes"] as? [String] == ["library:read", "library:write", "scrobble:write"])

            let (_, other) = try await signedInUser(env.stores)
            let id = try #require(token["id"] as? String)
            #expect(try await env.send(.delete, "/v1/agent/tokens/\(id)", token: other).status == .notFound)
            #expect(try await env.send(.post, "/v1/agent/tokens", json: [
                "kind": "stremio", "name": String(repeating: "x", count: 81),
            ]).status == .unprocessableContent)
        }
    }

    @Test("Request logs never carry a Stremio token or Trakt's callback secrets")
    func redaction() {
        typealias Log = RedactedLogRequestsMiddleware<AppRequestContext>
        #expect(Log.redacted("/stremio/aaru_st_SECRET/manifest.json", query: nil) == "/stremio/[token]/manifest.json")
        #expect(Log.redacted("/stremio/aaru_st_SECRET/catalog/series/up-next/skip=100.json", query: "x=1")
            == "/stremio/[token]/catalog/series/up-next/skip=100.json")
        #expect(Log.redacted("/stremio/aaru_st_SECRET", query: nil) == "/stremio/[token]")
        #expect(Log.redacted("/v1/imports/trakt/callback", query: "code=abc&state=def") == "/v1/imports/trakt/callback")
        #expect(Log.redacted("/v1/calendar", query: "from=a") == "/v1/calendar?from=a")
    }
}
