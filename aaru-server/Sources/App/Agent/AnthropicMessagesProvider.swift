import Foundation

/// `ModelProviding` over Anthropic's Messages API (`POST /v1/messages`), as raw HTTP: there is
/// no official Swift SDK. Named for the wire format, so pointing `ANTHROPIC_BASE_URL` at a
/// compatible endpoint is configuration, not code.
///
/// Claude Haiku 5.5 answers any non-default `temperature`, `top_p` or `top_k`, and an assistant
/// prefill, with a 400 (`platform/infra/docs/llm-haiku-trial.md`), so the body never carries
/// them. Thinking is left to the model's adaptive default; its blocks come back in `content`
/// and are replayed unchanged on the next round of a tool loop.
struct AnthropicMessagesProvider: ModelProviding {
    let transport: any HTTPTransport
    let apiKey: String
    let model: String
    var baseURL = URL(string: "https://api.anthropic.com")!
    /// `output_config.effort`; nil leaves the model's default.
    var effort: String? = "low"
    /// `anthropic-workspace-id`, which a key not scoped to one workspace must send.
    var workspaceID: String?
    var timeout: Duration = .seconds(60)

    static let apiVersion = "2023-06-01"

    func complete(_ request: ModelRequest) async throws -> ModelResponse {
        let body = try JSONEncoder().encode(Self.body(request, model: model, effort: effort))
        var headers = [
            ("content-type", "application/json"),
            ("x-api-key", apiKey),
            ("anthropic-version", Self.apiVersion),
        ]
        if let workspaceID {
            headers.append(("anthropic-workspace-id", workspaceID))
        }
        let response = try await transport.send(OutboundRequest(
            method: "POST",
            url: baseURL.appendingPathComponent("v1/messages"),
            headers: headers,
            body: body,
            timeout: timeout
        ))
        guard (200 ..< 300).contains(response.status) else {
            let text = String(bytes: response.body, encoding: .utf8) ?? ""
            throw ModelProviderError(
                status: response.status,
                outOfCredit: text.contains("usage limit") || text.contains("credit balance")
            )
        }
        return try Self.parse(response.body)
    }

    /// The request body. Deliberately no sampling fields and no prefill.
    static func body(_ request: ModelRequest, model: String, effort: String?) -> ModelJSON {
        var body: [String: ModelJSON] = [
            "model": .string(model),
            "max_tokens": .number(Double(request.maxTokens)),
            "system": .string(request.system),
            "messages": .array(request.turns.map {
                .object(["role": .string($0.role.rawValue), "content": .array($0.content)])
            }),
        ]
        if !request.tools.isEmpty {
            body["tools"] = .array(request.tools.map {
                .object([
                    "name": .string($0.name), "description": .string($0.description), "input_schema": $0.inputSchema,
                ])
            })
        }
        if let effort {
            body["output_config"] = .object(["effort": .string(effort)])
        }
        return .object(body)
    }

    static func parse(_ data: Data) throws -> ModelResponse {
        let json = try JSONDecoder().decode(ModelJSON.self, from: data)
        guard case let .array(content)? = json["content"] else {
            throw ModelProviderError(status: 200, outOfCredit: false)
        }
        let stop: ModelResponse.Stop = switch json["stop_reason"]?.string {
        case "end_turn", "stop_sequence": .done
        case "tool_use": .toolUse
        case "max_tokens": .maxTokens
        case "refusal": .refusal
        case let other: .other(other ?? "none")
        }
        func tokens(_ key: String) -> Int {
            if case let .number(value)? = json["usage"]?[key] {
                return Int(value)
            }
            return 0
        }
        return ModelResponse(
            content: content, stop: stop, inputTokens: tokens("input_tokens"), outputTokens: tokens("output_tokens")
        )
    }
}
