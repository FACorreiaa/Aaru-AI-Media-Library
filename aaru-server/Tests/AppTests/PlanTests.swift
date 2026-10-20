import AaruCore
import Foundation
import Testing
@testable import aaru

@Suite("Remote approval (AG-003, OUT-004)", .serialized)
struct PlanTests {
    private struct Agent {
        let secret: String
        let id: String
    }

    private func connect(_ env: LibraryHarness) async throws -> Agent {
        let body = try await env.send(.post, "/v1/agent/tokens", json: [
            "kind": "claude_code", "name": "Laptop", "allowLibraryWrites": true,
        ]).json()
        let token = try #require(body["token"] as? [String: Any])
        return try Agent(secret: #require(body["secret"] as? String), id: #require(token["id"] as? String))
    }

    /// Asks over MCP and returns the plan id the tool answered.
    private func propose(_ env: LibraryHarness, _ agent: Agent, _ changes: [[String: Any]]) async throws -> String {
        let reply = try await env.send(.post, MCPRoutes.path, json: [
            "jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": ["name": "apply_library_patch", "arguments": ["changes": changes]],
        ], token: agent.secret).json()
        let result = try #require(reply["result"] as? [String: Any])
        let structured = try #require(result["structuredContent"] as? [String: Any], "\(result)")
        #expect(structured["applied"] as? Bool == false)
        return try #require(structured["planId"] as? String)
    }

    private func episodes(_ itemID: String, _ keys: [(Int, Int)]) -> [[String: Any]] {
        [[
            "op": "episodes",
            "libraryItemId": itemID,
            "watched": true,
            "episodes": keys.map { ["season": $0.0, "episode": $0.1] },
        ]]
    }

    @Test("A plan writes nothing until approved; approval is one undoable action named after the agent")
    func approve() async throws {
        try await LibraryHarness.run { env in
            let itemID = try await env.add("show", tmdb: env.stubShow("Andor", status: .ended))
            let agent = try await connect(env)
            let before = try await env.actionCount()
            let planID = try await propose(env, agent, episodes(itemID, [(1, 1), (1, 2), (1, 3)]))
            #expect(try await env.actionCount() == before, "nothing written yet")

            let pending = try #require(try await env.send(.get, "/v1/plans").json()["items"] as? [[String: Any]])
            #expect(pending.count == 1)
            #expect(pending.first?["agentName"] as? String == "Laptop")
            #expect(pending.first?["summary"] as? String == "Marked 3 episodes of Andor watched")
            #expect((pending.first?["counts"] as? [String: Any])?["episodes"] as? Int == 3)

            let approved = try await env.send(.post, "/v1/plans/\(planID)/approve")
            #expect(approved.status == .ok)
            let action = try #require(try approved.json()["action"] as? [String: Any])
            #expect(action["actor"] as? String == "external_agent")
            #expect(action["summary"] as? String == "Laptop: marked 3 episodes of Andor watched")
            let item = try LibraryItemID(#require(UUID(uuidString: itemID)))
            #expect(try await env.stores.library.watched(itemID: item).count == 3)
            #expect(try await env.send(.post, "/v1/plans/\(planID)/approve").status == .conflict, "decided once")
            #expect(try (await env.send(.get, "/v1/plans").json()["items"] as? [Any])?.isEmpty == true)

            let actionID = try #require(action["id"] as? String)
            #expect(try await env.send(.post, "/v1/actions/\(actionID)/undo").status == .ok)
            #expect(try await env.stores.library.watched(itemID: item).isEmpty)
        }
    }

    @Test("A plan whose library moved is stale and writes nothing; a title added meanwhile also stales it")
    func stale() async throws {
        try await LibraryHarness.run { env in
            let itemID = try await env.add("show", tmdb: env.stubShow("Severance", status: .ended))
            let agent = try await connect(env)
            let planID = try await propose(env, agent, episodes(itemID, [(1, 1), (1, 2)]))
            #expect(try await env.send(.put, "/v1/library/items/\(itemID)/episodes/2/1", json: ["watched": true])
                .status == .ok)
            let reply = try await env.send(.post, "/v1/plans/\(planID)/approve")
            #expect(reply.status == .conflict)
            #expect(try reply.json()["code"] as? String == "plan_stale")
            let plan = try await env.send(.get, "/v1/plans/\(planID)").json()
            #expect(plan["status"] as? String == "stale")
            let item = try LibraryItemID(#require(UUID(uuidString: itemID)))
            #expect(try await env.stores.library.watched(itemID: item) == [EpisodeKey(season: 2, episode: 1)])

            let first = env.stubMovie("Arrival")
            let second = env.stubMovie("Dune")
            let adds = try await propose(env, agent, [first, second].map {
                ["op": "add", "mediaRef": ["type": "movie", "ids": ["tmdb": $0]]]
            })
            _ = try await env.add("movie", tmdb: second)
            #expect(try await env.send(.post, "/v1/plans/\(adds)/approve").json()["code"] as? String == "plan_stale")
        }
    }

    @Test("Deny writes nothing; expired plans and revoked tokens' plans cannot be approved")
    func denyAndExpire() async throws {
        try await LibraryHarness.run { env in
            let itemID = try await env.add("show", tmdb: env.stubShow("Dark", status: .ended))
            let agent = try await connect(env)
            let before = try await env.actionCount()

            let denied = try await propose(env, agent, [["op": "remove", "libraryItemId": itemID]])
            let reply = try await env.send(.post, "/v1/plans/\(denied)/deny")
            #expect(try reply.json()["status"] as? String == "denied")
            #expect(try await env.send(.post, "/v1/plans/\(denied)/approve").status == .conflict)
            #expect(try await env.send(.get, "/v1/library/items/\(itemID)").status == .ok, "never removed")

            let old = try await propose(env, agent, episodes(itemID, [(1, 1), (1, 2)]))
            let oldID = try #require(UUID(uuidString: old))
            try await withSQL { sql in
                try await sql
                    .raw("UPDATE agent_plans SET expires_at = now() - interval '1 minute' WHERE id = \(bind: oldID)")
                    .run()
            }
            #expect(try await env.send(.post, "/v1/plans/\(old)/approve").json()["code"] as? String == "plan_expired")

            let orphan = try await propose(env, agent, episodes(itemID, [(2, 1), (2, 2)]))
            #expect(try await env.send(.delete, "/v1/agent/tokens/\(agent.id)").status == .noContent)
            #expect(try await env.send(.get, "/v1/plans/\(orphan)").json()["status"] as? String == "expired")
            #expect(try await env.actionCount() == before, "nothing applied")
        }
    }

    @Test("Only the signed-in owner decides: an agent token gets 401, another user 404")
    func onlyTheOwner() async throws {
        try await LibraryHarness.run { env in
            let itemID = try await env.add("show", tmdb: env.stubShow("Andor", status: .ended))
            let agent = try await connect(env)
            let planID = try await propose(env, agent, episodes(itemID, [(1, 1), (1, 2)]))
            let selfApproval = try await env.send(.post, "/v1/plans/\(planID)/approve", token: agent.secret)
            #expect(selfApproval.status == .unauthorized)
            let (_, other) = try await signedInUser(env.stores)
            #expect(try await env.send(.post, "/v1/plans/\(planID)/approve", token: other).status == .notFound)
            #expect(try await env.send(.get, "/v1/plans/\(planID)", token: other).status == .notFound)
        }
    }
}
