import Foundation

/// One question and its answer in a stored chat (ASK-011).
public struct ChatExchange: Sendable {
    public let question: String
    public let reply: ChatReply

    /// A stored chat's turns as question-and-answer pairs, oldest first. A question whose answer
    /// was never stored still shows, with a reply that says nothing.
    public static func pairs(_ turns: [Components.Schemas.ChatTurn]) -> [ChatExchange] {
        var out: [ChatExchange] = []
        var question: String?
        for turn in turns {
            switch turn.role {
            case .user:
                if let asked = question {
                    out.append(ChatExchange(question: asked, reply: .unanswered))
                }
                question = turn.body
            case .agent:
                out.append(ChatExchange(question: question ?? "", reply: ChatReply(stored: turn)))
                question = nil
            }
        }
        if let asked = question {
            out.append(ChatExchange(question: asked, reply: .unanswered))
        }
        return out
    }
}

/// A read of the chat history: what came back, or why it did not.
public enum ChatHistoryResult<Value: Sendable>: Sendable {
    case loaded(Value)
    case failed(String)
}

/// One page of the caller's chats, latest first.
public struct ChatHistoryPage: Sendable {
    public let chats: [Components.Schemas.ChatSummary]
    /// The cursor of the next page; nil on the last.
    public let next: String?
}

/// A stored chat, ready to show and continue.
public struct StoredChat: Sendable {
    public let id: String
    public let title: String?
    public let exchanges: [ChatExchange]
}

public extension Client {
    private static var unreachable: String {
        "Aaru could not reach the server."
    }

    /// One page of the caller's chats with Aaru (ASK-011). Never throws.
    func chatHistory(after cursor: String? = nil) async -> ChatHistoryResult<ChatHistoryPage> {
        do {
            switch try await listChats(query: .init(cursor: cursor)) {
            case let .ok(response):
                let list = try response.body.json
                return .loaded(ChatHistoryPage(chats: list.items, next: list.page.nextCursor))
            case let .default(_, error):
                return .failed((try? error.body.json.message) ?? "Your chats could not be loaded.")
            }
        } catch {
            return .failed("Your chats could not be loaded. \(Self.unreachable)")
        }
    }

    /// One chat with its turns, to read again and continue (ASK-011). Never throws.
    func storedChat(_ id: String) async -> ChatHistoryResult<StoredChat> {
        do {
            switch try await getChat(path: .init(id: id)) {
            case let .ok(response):
                let chat = try response.body.json
                return .loaded(StoredChat(id: chat.id, title: chat.title, exchanges: ChatExchange.pairs(chat.turns)))
            case let .default(status, error):
                return .failed(status == 404
                    ? "That chat is no longer here."
                    : (try? error.body.json.message) ?? "That chat could not be opened.")
            }
        } catch {
            return .failed("That chat could not be opened. \(Self.unreachable)")
        }
    }

    /// Deletes one chat (ASK-011). Nil once deleted, or what went wrong. Never throws.
    func removeChat(_ id: String) async -> String? {
        do {
            switch try await deleteChat(path: .init(id: id)) {
            case .noContent:
                return nil
            case let .default(_, error):
                return (try? error.body.json.message) ?? "That chat was not deleted."
            }
        } catch {
            return "That chat was not deleted. \(Self.unreachable)"
        }
    }
}
