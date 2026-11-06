import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
@testable import AaruAPI

private let baseURL = URL(string: "https://api.aaru.test")!

private func thread(_ transport: ScriptedTransport) -> ChatThread {
    let client = Client.aaru(
        baseURL: baseURL,
        session: SessionMiddleware(token: { "abc" }, onUnauthorized: {}),
        transport: transport
    )
    return ChatThread(client: client, busyRetryDelay: .zero)
}

private func paths(_ transport: ScriptedTransport) -> [String] {
    transport.sent.map { "\($0.method.rawValue) \($0.path ?? "")" }
}

private let created = ScriptedResponse(status: .created, json: #"{"id":"c1"}"#)

private let answered = ScriptedResponse(stream: [
    "event: delta\ndata: {\"text\":\"Hi\"}\n\n",
    "event: done\ndata: {\"turnId\":\"t1\"}\n\n",
])

private let plain: @Sendable (ChatReply) async -> Void = { _ in }

private let attached = ScriptedResponse(
    status: .created,
    json: #"{"id":"f1","kind":"export","name":"watched.csv","size":20,"source":"letterboxd_csv","rows":1,"#
        + #""summary":"a Letterboxd export of 1 rows"}"#
)

@Suite("ASK-010: files in a chat")
struct ChatFileTests {
    @Test func attachesIntoTheChatTheTurnThenGoesTo() async throws {
        let transport = ScriptedTransport([created, attached, answered])
        let chat = thread(transport)
        let result = await chat.attach(Data("Name,Year\n".utf8), name: "watched.csv")
        let file = ChatFile(id: "f1", kind: .export, name: "watched.csv", summary: "a Letterboxd export of 1 rows")
        #expect(result == .attached(chat: "c1", file: file))
        _ = await chat.send("", hint: nil, attachments: ["f1"], onUpdate: plain)
        #expect(paths(transport) == [
            "POST /v1/chats", "POST /v1/chats/c1/attachments?filename=watched.csv", "POST /v1/chats/c1/turns",
        ])
        #expect(transport.sentBodies[1] == Data("Name,Year\n".utf8))
        let json = try #require(JSONSerialization.jsonObject(with: transport.sentBodies[2]) as? [String: Any])
        #expect(json["attachments"] as? [String] == ["f1"])
        #expect(json["body"] as? String == "")
    }

    @Test func saysWhyAFileIsRefused() async {
        let refused = ScriptedResponse(
            status: .unprocessableContent, json: #"{"code":"validation_failed","message":"That file is a program."}"#
        )
        let transport = ScriptedTransport([created, refused])
        let result = await thread(transport).attach(Data("MZ".utf8), name: "list.csv")
        #expect(result == .refused("That file is a program."))
    }

    @Test func aTurnWhoseFilesAreGoneStartsNoNewChat() async {
        let gone = ScriptedResponse(status: .notFound, json: #"{"code":"not_found","message":"gone"}"#)
        let transport = ScriptedTransport([created, attached, gone])
        let chat = thread(transport)
        _ = await chat.attach(Data("x".utf8), name: "a.txt")
        let reply = await chat.send("import it", hint: nil, attachments: ["f1"], onUpdate: plain)
        #expect(reply.problem == "Those files are no longer here. Attach them again.")
        #expect(paths(transport).count == 3)
    }

    @Test func sendsNoAttachmentsKeyWithoutFiles() async throws {
        let transport = ScriptedTransport([created, answered])
        _ = await thread(transport).send("hi", hint: nil, onUpdate: plain)
        let json = try #require(JSONSerialization.jsonObject(with: transport.sentBodies[1]) as? [String: Any])
        #expect(json["attachments"] == nil)
    }
}
