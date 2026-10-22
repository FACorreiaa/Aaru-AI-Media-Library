import AaruCore
import Foundation
import Testing
@testable import aaru

/// A model that answers from a script and records what it was asked. Never a network call.
actor ScriptedModel: ModelProviding {
    nonisolated let model = "scripted"
    private var script: [Result<ModelResponse, ModelProviderError>]
    private(set) var requests: [ModelRequest] = []

    init(_ script: [Result<ModelResponse, ModelProviderError>]) {
        self.script = script
    }

    func complete(_ request: ModelRequest) async throws -> ModelResponse {
        requests.append(request)
        guard !script.isEmpty else { throw ModelProviderError(status: 500, outOfCredit: false) }
        return try script.removeFirst().get()
    }

    /// Everything the model was shown, as one string, for "never saw X" checks.
    var everythingSeen: String {
        requests.map { request in
            let turns = (try? JSONEncoder().encode(request.turns.map { ModelJSON.array($0.content) }))
                .flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
            return request.system + turns
        }.joined()
    }

    static func tool(_ name: String, _ input: [String: ModelJSON] = [:], id: String = "call") -> ModelResponse {
        ModelResponse(
            content: [.object([
                "type": .string("tool_use"), "id": .string(id), "name": .string(name), "input": .object(input),
            ])],
            stop: .toolUse, inputTokens: 100, outputTokens: 10
        )
    }

    static func text(_ text: String) -> ModelResponse {
        ModelResponse(
            content: [.object(["type": .string("text"), "text": .string(text)])], stop: .done, inputTokens: 200,
            outputTokens: 30
        )
    }
}

@Suite("@aaru in groups (GRP-010 / GRP-011)", .serialized)
struct AgentTests {
    let groups = GroupTests()

    /// The queue is shared by every test run on this database: settle anything left behind so a
    /// test claims only its own mentions.
    func clearQueue() async throws {
        // On a fresh database this can run before any test migrated it.
        try await TestMigrations.shared.ensureMigrated()
        try await withSQL { sql in
            try await sql.raw("UPDATE agent_replies SET state = 'skipped' WHERE state IN ('queued', 'running')").run()
        }
    }

    @Test("GRP-010: the Messages API body has no sampling fields or prefill, and replies parse")
    func wireBody() async throws {
        let transport = StubTransport { _ in
            OutboundResponse(status: 200, body: Data("""
            {"content":[{"type":"thinking","thinking":"","signature":"s"},{"type":"text","text":"Hi"}],
             "stop_reason":"end_turn","usage":{"input_tokens":12,"output_tokens":3}}
            """.utf8))
        }
        let provider = try AnthropicMessagesProvider(
            transport: transport, apiKey: "test-key", model: "claude-haiku-5-5",
            baseURL: #require(URL(string: "http://stub.test"))
        )
        let response = try await provider.complete(ModelRequest(
            system: "sys", turns: [.user("hello")], tools: GroupAgentTools.definitions, maxTokens: 2048
        ))
        #expect(response.text == "Hi")
        #expect(response.stop == .done)
        #expect(response.inputTokens == 12)
        // Thinking blocks are kept to replay unchanged.
        #expect(response.content.first?["type"]?.string == "thinking")

        let request = try #require(transport.requests.first)
        #expect(request.url.absoluteString == "http://stub.test/v1/messages")
        #expect(request.headers.contains { $0 == ("x-api-key", "test-key") })
        #expect(request.headers.contains { $0 == ("anthropic-version", "2023-06-01") })
        #expect(!request.headers.contains { $0.0 == "anthropic-workspace-id" })
        let body = try #require(request.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        for banned in ["temperature", "top_p", "top_k"] {
            #expect(body[banned] == nil)
        }
        #expect(body["max_tokens"] as? Int == 2048)
        #expect((body["output_config"] as? [String: Any])?["effort"] as? String == "low")
        #expect((body["messages"] as? [[String: Any]])?.last?["role"] as? String == "user")

        transport.respond { _ in
            OutboundResponse(
                status: 400,
                body: Data(#"{"error":{"message":"You have reached your usage limit"}}"#.utf8)
            )
        }
        await #expect(throws: ModelProviderError(status: 400, outOfCredit: true)) {
            _ = try await provider.complete(ModelRequest(system: "s", turns: [.user("x")], tools: [], maxTokens: 10))
        }
    }

    @Test("GRP-010: a key not scoped to a workspace sends the workspace id")
    func workspaceHeader() async throws {
        let transport = StubTransport { _ in
            OutboundResponse(status: 200, body: Data(#"{"content":[],"stop_reason":"end_turn"}"#.utf8))
        }
        let provider = try AnthropicMessagesProvider(
            transport: transport, apiKey: "test-key", model: "claude-haiku-5-5",
            baseURL: #require(URL(string: "http://stub.test")), workspaceID: "wrkspc_test"
        )
        _ = try await provider.complete(ModelRequest(system: "s", turns: [.user("x")], tools: [], maxTokens: 10))
        let request = try #require(transport.requests.first)
        #expect(request.headers.contains { $0 == ("anthropic-workspace-id", "wrkspc_test") })
    }

    @Test("GRP-010: every agent tool reads; none writes")
    func toolsRead() {
        #expect(Set(GroupAgentTools.definitions.map(\.name))
            == ["search_titles", "title_details", "list_airs", "read_my_library", "show_titles"])
    }

    @Test("GRP-011: a tagged question gets one reply, built only from the tagger's own library")
    func reply() async throws {
        let model = ScriptedModel([
            .success(ScriptedModel.tool("read_my_library", id: "a")),
            .success(ScriptedModel.tool("show_titles", ["refs": .array([.string("r1")])], id: "b")),
            .success(ScriptedModel.text("Heat is waiting on your list.")),
        ])
        try await clearQueue()
        try await LibraryHarness.run(model: model) { env in
            let mine = try await claimHandle(env)
            let ana = try await friend(env, of: mine)
            let (group, general) = try await groups.createGroup(env)
            try await groups.join(env, ana, group: group)
            #expect(try await env.send(.get, "/v1/groups/\(group)").json()["agent"] as? Bool == true)
            // The owner's library holds Arrival; Ana's holds Heat.
            _ = try await env.add("movie", tmdb: env.stubMovie("Arrival"))
            let heat = env.stubMovie("Heat")
            _ = try await env.send(
                .post, "/v1/library/items", json: ["mediaRef": ["type": "movie", "ids": ["tmdb": heat]]],
                token: ana.token
            )
            let channel = "/v1/groups/\(group)/channels/\(general)"
            _ = try await groups.post(env, channel, "I loved Arrival")
            let mention = try await groups.post(env, channel, "@aaru what should I watch tonight?", token: ana.token)
            #expect(mention["mentionsAgent"] as? Bool == true)

            let replies = try #require(env.services.agentReplies)
            #expect(try await replies.runNext())
            #expect(try await !replies.runNext())

            let items = try await env.send(.get, "\(channel)/messages").json()["items"] as? [[String: Any]] ?? []
            let reply = try #require(items.last)
            #expect(reply["fromAgent"] as? Bool == true)
            #expect(reply["author"] == nil)
            #expect(reply["replyTo"] as? String == mention["id"] as? String)
            #expect(reply["body"] as? String == "Heat is waiting on your list.")
            let card = (reply["components"] as? [[String: Any]])?.first?["title"] as? [String: Any]
            #expect(card?["title"] as? String == "Heat")
            #expect(items.count(where: { $0["fromAgent"] as? Bool == true }) == 1)

            // The model saw the chat (where the owner named Arrival) but never the owner's library.
            let seen = await model.everythingSeen
            #expect(seen.contains("Heat"))
            #expect(seen.contains("I loved Arrival"))
            #expect(!seen.contains("Arrival (2001)"))
            #expect(await model.requests.first?.system.contains("@\(ana.handle)") == true)

            // Three calls metered to the tagger, none to anyone else.
            let anaID = try #require(UUID(uuidString: ana.id)).asUser
            let usage = try await env.stores.agent.usage(anaID, day: Date())
            #expect(usage == AgentUsage(requests: 3, inputTokens: 400, outputTokens: 50))
            #expect(try await env.stores.agent.usage(env.userID, day: Date()).requests == 0)
        }
    }

    @Test("GRP-011: over the group's hourly cap Aaru says once that it is resting, with no model call")
    func caps() async throws {
        let model = ScriptedModel([])
        try await LibraryHarness.run(model: model) { env in
            _ = try await claimHandle(env)
            let (group, general) = try await groups.createGroup(env)
            let channel = "/v1/groups/\(group)/channels/\(general)"
            for number in 1 ... GroupService.agentHourlyCapPerGroup + 2 {
                _ = try await groups.post(env, channel, "@aaru question \(number)")
            }
            let items = try await env.send(.get, "\(channel)/messages").json()["items"] as? [[String: Any]] ?? []
            let agent = items.filter { $0["fromAgent"] as? Bool == true }
            #expect(agent.count == 1)
            #expect(agent.first?["body"] as? String == GroupService.restingNote)
            #expect(await model.requests.isEmpty)
        }
    }

    @Test("GRP-011: a refusal gets a short reply; repeated failures end in one apology")
    func refusalAndFailure() async throws {
        let refusing = ScriptedModel([
            .success(ModelResponse(content: [], stop: .refusal, inputTokens: 5, outputTokens: 0)),
        ])
        try await clearQueue()
        try await LibraryHarness.run(model: refusing) { env in
            _ = try await claimHandle(env)
            let (group, general) = try await groups.createGroup(env)
            let channel = "/v1/groups/\(group)/channels/\(general)"
            _ = try await groups.post(env, channel, "@aaru something odd")
            #expect(try await env.services.agentReplies?.runNext() == true)
            let items = try await env.send(.get, "\(channel)/messages").json()["items"] as? [[String: Any]] ?? []
            #expect(items.last?["body"] as? String == AgentReplyService.refusalReply)
        }

        let failing = ScriptedModel([])
        try await clearQueue()
        try await LibraryHarness.run(model: failing) { env in
            _ = try await claimHandle(env)
            let (group, general) = try await groups.createGroup(env)
            let channel = "/v1/groups/\(group)/channels/\(general)"
            _ = try await groups.post(env, channel, "@aaru hello?")
            var replies = try #require(env.services.agentReplies)
            // Each retry waits; a clock that jumps ahead lets the next attempt claim it.
            let clock = TestClock(Date())
            replies.now = { clock.now }
            for _ in 1 ... AgentReplyService.maxAttempts {
                #expect(try await replies.runNext())
                clock.advance(by: 600)
            }
            #expect(try await !replies.runNext())
            let items = try await env.send(.get, "\(channel)/messages").json()["items"] as? [[String: Any]] ?? []
            #expect(items.filter { $0["fromAgent"] as? Bool == true }.map { $0["body"] as? String }
                == [AgentReplyService.failureReply])
            #expect(await failing.requests.count == AgentReplyService.maxAttempts)
        }
    }

    @Test("GRP-010: with no model configured, groups say so and mentions queue nothing")
    func disabled() async throws {
        try await LibraryHarness.run { env in
            _ = try await claimHandle(env)
            let (group, general) = try await groups.createGroup(env)
            #expect(try await env.send(.get, "/v1/groups/\(group)").json()["agent"] as? Bool == false)
            _ = try await groups.post(env, "/v1/groups/\(group)/channels/\(general)", "@aaru hi")
            #expect(env.services.agentReplies == nil)
            let groupID = try #require(UUID(uuidString: group))
            let load = try await env.stores.agent.load(
                tagger: env.userID, group: groupID, dayStart: .distantPast, hourStart: .distantPast
            )
            #expect(load.groupHour == 0)
        }
    }
}
