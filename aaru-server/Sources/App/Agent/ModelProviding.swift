import Foundation

/// Any JSON value. Model content blocks travel as this so a block the adapter does not know
/// (thinking, and whatever the API adds later) is replayed unchanged.
enum ModelJSON: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([ModelJSON])
    case object([String: ModelJSON])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([ModelJSON].self) {
            self = .array(value)
        } else {
            self = try .object(container.decode([String: ModelJSON].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }

    subscript(key: String) -> ModelJSON? {
        if case let .object(object) = self {
            return object[key]
        }
        return nil
    }

    var string: String? {
        if case let .string(value) = self {
            return value
        }
        return nil
    }
}

/// A tool the model may call. Every agent tool is a read; none writes (X-009).
struct ModelTool: Sendable, Equatable {
    var name: String
    var description: String
    /// JSON Schema for the input.
    var inputSchema: ModelJSON
}

/// One turn of the transcript. Content is raw blocks so replies round-trip unchanged.
struct ModelTurn: Sendable, Equatable {
    enum Role: String, Sendable { case user, assistant }
    var role: Role
    var content: [ModelJSON]

    static func user(_ text: String) -> ModelTurn {
        ModelTurn(role: .user, content: [.object(["type": .string("text"), "text": .string(text)])])
    }

    /// One image (base64) and the words about it, in that order.
    static func user(image: Data, mediaType: String, _ text: String) -> ModelTurn {
        ModelTurn(role: .user, content: [
            .object([
                "type": .string("image"),
                "source": .object([
                    "type": .string("base64"), "media_type": .string(mediaType),
                    "data": .string(image.base64EncodedString()),
                ]),
            ]),
            .object(["type": .string("text"), "text": .string(text)]),
        ])
    }
}

struct ModelRequest: Sendable, Equatable {
    var system: String
    var turns: [ModelTurn]
    var tools: [ModelTool]
    var maxTokens: Int
    /// A tool the model must call, by name; nil lets it choose. Claude Haiku 5.5 accepts a forced
    /// call (and skips thinking for it); Opus 5.5, Sonnet 5.5 and Fable 5.1 answer it with a 400.
    var toolChoice: String?
}

struct ModelResponse: Sendable, Equatable {
    enum Stop: Sendable, Equatable {
        case done
        case toolUse
        case maxTokens
        case refusal
        case other(String)
    }

    /// The assistant's blocks, to append to the transcript as they are.
    var content: [ModelJSON]
    var stop: Stop
    var inputTokens: Int
    var outputTokens: Int

    /// The concatenated text blocks.
    var text: String {
        content.compactMap { block in block["type"]?.string == "text" ? block["text"]?.string : nil }
            .joined(separator: "\n")
    }

    struct ToolCall: Sendable, Equatable {
        var id: String
        var name: String
        var input: ModelJSON
    }

    /// The `tool_use` blocks.
    var toolCalls: [ToolCall] {
        content.compactMap { block in
            guard block["type"]?.string == "tool_use", let id = block["id"]?.string,
                  let name = block["name"]?.string
            else { return nil }
            return ToolCall(id: id, name: name, input: block["input"] ?? .object([:]))
        }
    }
}

/// The agent's model (AG-007, minimal for GRP-010). One adapter per wire format; no provider
/// name appears outside its adapter.
protocol ModelProviding: Sendable {
    var model: String { get }
    /// What a call costs, for `agent_usage`. Free unless the provider says otherwise.
    var pricing: ModelPricing { get }
    func complete(_ request: ModelRequest) async throws -> ModelResponse
}

extension ModelProviding {
    var pricing: ModelPricing {
        .free
    }
}

/// Dollars per million tokens, which is the same number as millionths of a dollar per token.
struct ModelPricing: Sendable, Equatable {
    var inputPerMTok: Double
    var outputPerMTok: Double

    static let free = ModelPricing(inputPerMTok: 0, outputPerMTok: 0)

    /// One response's cost in millionths of a dollar, rounded up.
    func micros(_ response: ModelResponse) -> Int {
        Int((Double(response.inputTokens) * inputPerMTok + Double(response.outputTokens) * outputPerMTok)
            .rounded(.up))
    }
}

/// A provider that answered with an error status, or nothing usable.
struct ModelProviderError: Error, Equatable {
    var status: Int
    var outOfCredit: Bool
}
