import AaruCore
import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
@testable import aaru

@Suite("MCP endpoint (OUT-004)", .serialized)
struct MCPTests {
    /// Mints an MCP token through the route, as Settings does.
    private func connect(_ env: LibraryHarness, writes: Bool = false) async throws -> String {
        let body = try await env.send(.post, "/v1/agent/tokens", json: [
            "kind": "claude_code", "allowLibraryWrites": writes,
        ]).json()
        return try #require(body["secret"] as? String)
    }

    private func rpc(
        _ env: LibraryHarness,
        _ method: String,
        _ params: [String: Any] = [:],
        token: String
    ) async throws -> [String: Any] {
        let reply = try await env.send(.post, MCPRoutes.path, json: [
            "jsonrpc": "2.0", "id": 1, "method": method, "params": params,
        ], token: token)
        #expect(reply.status == .ok)
        return try reply.json()
    }

    private func call(
        _ env: LibraryHarness,
        _ tool: String,
        _ arguments: [String: Any],
        token: String
    ) async throws -> [String: Any] {
        let reply = try await rpc(env, "tools/call", ["name": tool, "arguments": arguments], token: token)
        return try #require(reply["result"] as? [String: Any])
    }

    private func raw(
        _ env: LibraryHarness,
        _ method: HTTPRequest.Method,
        headers: HTTPFields,
        body: String? = nil
    ) async throws -> (status: HTTPResponse.Status, headers: HTTPFields) {
        try await env.client.execute(
            uri: MCPRoutes.path, method: method, headers: headers, body: body.map { ByteBuffer(string: $0) }
        ) { ($0.status, $0.headers) }
    }

    @Test("initialize negotiates the version; tools/list is exactly the agent tools")
    func handshake() async throws {
        try await LibraryHarness.run { env in
            let token = try await connect(env)
            let reply = try await rpc(env, "initialize", [
                "protocolVersion": "2025-06-18", "capabilities": [:],
                "clientInfo": ["name": "test", "version": "0"],
            ], token: token)
            let result = try #require(reply["result"] as? [String: Any])
            #expect(result["protocolVersion"] as? String == "2025-06-18")
            #expect((result["serverInfo"] as? [String: Any])?["name"] as? String == "aaru")
            let newer = try await rpc(env, "initialize", ["protocolVersion": "1999-01-01"], token: token)
            #expect((newer["result"] as? [String: Any])?["protocolVersion"] as? String == MCPProtocol.versions[0])

            let listed = try await rpc(env, "tools/list", token: token)
            let tools = try #require((listed["result"] as? [String: Any])?["tools"] as? [[String: Any]])
            #expect(tools.compactMap { $0["name"] as? String }
                == ["search_titles", "read_library", "list_airs", "apply_library_patch", "plan_import"])
            let unknown = try await rpc(env, "resources/list", token: token)
            #expect((unknown["error"] as? [String: Any])?["code"] as? Int == -32601)
        }
    }

    @Test("Only a live MCP token gets in: not a session, not a Stremio link, not a browser")
    func authentication() async throws {
        try await LibraryHarness.run { env in
            let json: HTTPFields = [.contentType: "application/json"]
            let ping = #"{"jsonrpc":"2.0","id":1,"method":"ping"}"#
            let anonymous = try await raw(env, .post, headers: json, body: ping)
            #expect(anonymous.status == .unauthorized)
            #expect(anonymous.headers[.wwwAuthenticate]?.hasPrefix("Bearer") == true)

            var session = json
            session[.authorization] = "Bearer \(env.token)"
            #expect(try await raw(env, .post, headers: session, body: ping).status == .unauthorized)

            let stremio = try #require(try await env.send(.post, "/v1/agent/tokens", json: ["kind": "stremio"])
                .json()["secret"] as? String)
            var stremioHeaders = json
            stremioHeaders[.authorization] = "Bearer \(stremio)"
            #expect(try await raw(env, .post, headers: stremioHeaders, body: ping).status == .unauthorized)

            let token = try await connect(env)
            var good = json
            good[.authorization] = "Bearer \(token)"
            #expect(try await raw(env, .post, headers: good, body: ping).status == .ok)
            #expect(try await raw(env, .get, headers: good).status == .methodNotAllowed)
            let notification = #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#
            #expect(try await raw(env, .post, headers: good, body: notification).status == .accepted)

            var browser = good
            browser[.origin] = "https://evil.example"
            #expect(try await raw(env, .post, headers: browser, body: ping).status == .forbidden)

            let listed = try await env.send(.get, "/v1/agent/tokens?for=mcp").json()["items"] as? [[String: Any]]
            let id = try #require(listed?.first?["id"] as? String)
            #expect(try await env.send(.delete, "/v1/agent/tokens/\(id)").status == .noContent)
            #expect(try await raw(env, .post, headers: good, body: ping).status == .unauthorized, "revoked")
        }
    }

    @Test("Reads: search, library and airs come back as /v1 DTOs")
    func reads() async throws {
        try await LibraryHarness.run { env in
            let tmdb = env.stubShow("Andor", status: .ended)
            env.fake.stubSearch("Andor", [CatalogHit(
                type: .show, title: "Andor", originalTitle: nil, year: 2022, posterURL: nil, overview: nil,
                byline: nil, ids: ExternalIDs(tmdb: tmdb), isAnime: false
            )])
            let itemID = try await env.add("show", tmdb: tmdb)
            let token = try await connect(env)

            let search = try await call(env, "search_titles", ["query": "Andor", "type": "show"], token: token)
            #expect(search["isError"] as? Bool == false)
            let hits = (search["structuredContent"] as? [String: Any])?["items"] as? [[String: Any]]
            #expect(hits?.first?["title"] as? String == "Andor")

            let library = try await call(env, "read_library", ["status": "wishlist"], token: token)
            let items = (library["structuredContent"] as? [String: Any])?["items"] as? [[String: Any]]
            #expect(items?.compactMap { $0["id"] as? String } == [itemID])

            let one = try await call(env, "read_library", ["libraryItemId": itemID], token: token)
            #expect((one["structuredContent"] as? [String: Any])?["watchedEpisodes"] is [Any])

            let airs = try await call(env, "list_airs", ["view": "up_next"], token: token)
            #expect((airs["structuredContent"] as? [String: Any])?["counts"] != nil)
            let calendar = try await call(env, "list_airs", ["from": "2026-01-01", "to": "2026-03-01"], token: token)
            #expect(calendar["isError"] as? Bool == true, "more than 42 days")

            let typo = try await call(env, "read_library", ["stauts": "wishlist"], token: token)
            #expect(typo["isError"] as? Bool == true)
            let content = (typo["content"] as? [[String: Any]])?.first?["text"] as? String
            #expect(content == "read_library has no argument stauts.")
        }
    }

    @Test("A tap-sized write applies as the token and is undoable; bigger ones wait; read-only tokens never write")
    func writes() async throws {
        try await LibraryHarness.run { env in
            let itemID = try await env.add("show", tmdb: env.stubShow("Severance", status: .ended))
            let readOnly = try await connect(env)
            let tick: [String: Any] = ["changes": [[
                "op": "episodes", "libraryItemId": itemID, "watched": true,
                "episodes": [["season": 1, "episode": 1]],
            ]]]
            let before = try await env.actionCount()
            let refused = try await call(env, "apply_library_patch", tick, token: readOnly)
            #expect(refused["isError"] as? Bool == true)
            #expect(try await env.actionCount() == before)

            let writer = try await connect(env, writes: true)
            let applied = try await call(env, "apply_library_patch", tick, token: writer)
            #expect(applied["isError"] as? Bool == false)
            let structured = applied["structuredContent"] as? [String: Any]
            #expect(structured?["applied"] as? Bool == true)
            #expect(try await env.actionCount() == before + 1)

            let actions = try #require(try await env.send(.get, "/v1/actions?limit=1").json()["items"]
                as? [[String: Any]])
            #expect(actions.first?["actor"] as? String == "external_agent")
            #expect(actions.first?["summary"] as? String == "Claude Code: marked S01E01 of Severance watched")
            let actionID = try #require(actions.first?["id"] as? String)
            #expect(try await env.send(.post, "/v1/actions/\(actionID)/undo").status == .ok)

            let many: [String: Any] = ["changes": [[
                "op": "episodes", "libraryItemId": itemID, "watched": true,
                "episodes": [["season": 1, "episode": 1], ["season": 1, "episode": 2]],
            ]]]
            let big = try await call(env, "apply_library_patch", many, token: writer)
            let proposed = big["structuredContent"] as? [String: Any]
            #expect(proposed?["applied"] as? Bool == false)
            #expect(proposed?["planId"] is String, "bigger than a tap: a plan, not a write")
            #expect(try await env.actionCount() == before + 2, "the tick and its undo only")
        }
    }

    @Test("plan_import queues an import for review and never writes; it needs the imports scope")
    func planImport() async throws {
        try await LibraryHarness.run { env in
            let csv = "Title,Year\nArrival,2016\nDune,2021\n"
            let plain = try await connect(env, writes: true)
            let refused = try await call(env, "plan_import", ["text": csv, "source": "csv"], token: plain)
            #expect(refused["isError"] as? Bool == true)

            let body = try await env.send(.post, "/v1/agent/tokens", json: [
                "kind": "codex", "allowImports": true,
            ]).json()
            #expect((body["token"] as? [String: Any])?["scopes"] as? [String] == ["imports:write", "library:read"])
            let importer = try #require(body["secret"] as? String)
            let before = try await env.actionCount()
            let queued = try await call(env, "plan_import", ["text": csv, "source": "csv"], token: importer)
            let structured = try #require(queued["structuredContent"] as? [String: Any])
            #expect(structured["applied"] as? Bool == false)
            let importID = try #require(structured["importId"] as? String)
            let jobs = try await env.send(.get, "/v1/imports").json()["items"] as? [[String: Any]]
            #expect(jobs?.contains { $0["id"] as? String == importID } == true)
            #expect(try await env.actionCount() == before, "nothing lands before the user approves the import")
        }
    }
}
