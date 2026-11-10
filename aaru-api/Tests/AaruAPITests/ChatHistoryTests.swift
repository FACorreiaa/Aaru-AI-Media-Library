import Foundation
import OpenAPIRuntime
import Testing
@testable import AaruAPI

private let baseURL = URL(string: "https://api.test")!

private func makeClient(_ transport: some ClientTransport) -> Client {
    Client.aaru(
        baseURL: baseURL,
        session: SessionMiddleware(token: { "abc" }, onUnauthorized: {}),
        transport: transport
    )
}

private let stamp = "2026-11-10T10:00:00Z"

private func turnJSON(_ role: String, _ body: String, state: String = "done", components: String? = nil) -> String {
    let extra = components.map { #","components":\#($0)"# } ?? ""
    let head = #"{"id":"t","role":"\#(role)","body":"\#(body)","state":"\#(state)""#
    return head + #","createdAt":"\#(stamp)"\#(extra)}"#
}

private func chatJSON(_ turns: String...) -> String {
    let head = #"{"id":"C1","title":"what is on?","createdAt":"\#(stamp)","updatedAt":"\#(stamp)""#
    return head + #","turns":[\#(turns.joined(separator: ","))]}"#
}

private let roadmap = """
{"importId":"I1","roadmap":{"listName":"Before Secret Wars","steps":[{"heading":"The Multiverse","note":"Start here.",\
"items":[{"title":"Loki","type":"show","year":2021,"note":"Both seasons"},\
{"title":"What If...?","type":"show","optional":true}]}]}}
"""

private func plain(_: ChatReply) async {}

@Suite("ASK-011: chat history and the roadmap a reply carries")
struct ChatHistoryTests {
    @Test func aComponentsFrameCarriesTheRoadmapBesideItsImport() throws {
        var parser = ChatFrameParser()
        var reply = ChatReply()
        for frame in parser.consume(Array("event: components\ndata: \(roadmap)\n\n".utf8)) {
            reply.apply(frame)
        }
        #expect(reply.importID == "I1")
        let steps = try #require(reply.roadmap?.steps)
        #expect(reply.roadmap?.listName == "Before Secret Wars")
        #expect(steps.count == 1)
        #expect(steps[0].heading == "The Multiverse")
        #expect(steps[0].items.map(\.title) == ["Loki", "What If...?"])
        #expect(steps[0].items[0].year == 2021)
        #expect(steps[0].items[1].optional == true)
    }

    @Test func aStoredChatReadsBackAsQuestionsAndAnswers() async {
        let transport = ScriptedTransport([ScriptedResponse(json: chatJSON(
            turnJSON("user", "what do I watch before Secret Wars?"),
            turnJSON("agent", "Two titles, waiting for your review.", components: roadmap),
            turnJSON("user", "and after?"),
            turnJSON("agent", "First, ", state: "stopped"),
            turnJSON("user", "never answered")
        ))])
        guard case let .loaded(chat) = await makeClient(transport).storedChat("C1") else {
            Issue.record("the chat did not load")
            return
        }
        #expect(transport.sent.map { $0.path ?? "" } == ["/v1/chats/C1"])
        #expect(chat.id == "C1")
        #expect(chat.exchanges.map(\.question) == [
            "what do I watch before Secret Wars?", "and after?", "never answered",
        ])
        let first = chat.exchanges[0].reply
        #expect(first.state == .answered)
        #expect(first.text == "Two titles, waiting for your review.")
        #expect(first.importID == "I1")
        #expect(first.roadmap?.steps.count == 1)
        #expect(first.problem == nil)
        let second = chat.exchanges[1].reply
        #expect(second.state == .cancelled)
        #expect(second.text == "First, ")
        #expect(second.problem == ChatReply.stoppedEarly)
        #expect(chat.exchanges[2].reply.state == .cancelled)
        #expect(chat.exchanges[2].reply.text.isEmpty)
    }

    @Test func aFailedStoredAnswerSaysSo() {
        let turn = Components.Schemas.ChatTurn(
            id: "t", role: .agent, body: "", state: .failed, createdAt: Date(timeIntervalSince1970: 0)
        )
        let reply = ChatReply(stored: turn)
        #expect(reply.state == .failed)
        #expect(reply.problem == ChatReply.didNotFinish)
    }

    @Test func aChatThatIsGoneSaysSo() async {
        let transport = ScriptedTransport([
            ScriptedResponse(status: .notFound, json: #"{"code":"not_found","message":"That chat doesn't exist."}"#),
        ])
        guard case let .failed(problem) = await makeClient(transport).storedChat("C9") else {
            Issue.record("a missing chat loaded")
            return
        }
        #expect(problem == "That chat is no longer here.")
    }

    @Test func historyPagesWithItsCursor() async {
        let first = #"{"id":"C1","title":"first","createdAt":"\#(stamp)","updatedAt":"\#(stamp)"}"#
        let page = #"{"items":[\#(first)],"page":{"nextCursor":"abc"}}"#
        let last = #"{"items":[{"id":"C2","createdAt":"\#(stamp)","updatedAt":"\#(stamp)"}],"page":{}}"#
        let transport = ScriptedTransport([ScriptedResponse(json: page), ScriptedResponse(json: last)])
        let client = makeClient(transport)
        guard case let .loaded(opening) = await client.chatHistory() else {
            Issue.record("the first page did not load")
            return
        }
        #expect(opening.chats.map(\.id) == ["C1"])
        #expect(opening.next == "abc")
        guard case let .loaded(second) = await client.chatHistory(after: opening.next) else {
            Issue.record("the second page did not load")
            return
        }
        #expect(second.chats.map(\.title) == [nil])
        #expect(second.next == nil)
        #expect(transport.sent.map { $0.path ?? "" } == ["/v1/chats", "/v1/chats?cursor=abc"])
    }

    @Test func deletingOneChatAnswersNothingOrWhy() async {
        let transport = ScriptedTransport([
            ScriptedResponse(status: .noContent),
            ScriptedResponse(status: .internalServerError, json: #"{"code":"internal","message":"Try again."}"#),
        ])
        let client = makeClient(transport)
        #expect(await client.removeChat("C1") == nil)
        #expect(await client.removeChat("C1") == "Try again.")
        #expect(transport.sent.map { "\($0.method.rawValue) \($0.path ?? "")" } == [
            "DELETE /v1/chats/C1", "DELETE /v1/chats/C1",
        ])
    }

    @Test func anAdoptedChatIsContinuedAndItsClockStartsAgain() async {
        let answered = ScriptedResponse(stream: [
            "event: delta\ndata: {\"text\":\"Hi\"}\n\n", "event: done\ndata: {\"turnId\":\"t1\"}\n\n",
        ])
        let transport = ScriptedTransport([answered])
        let thread = ChatThread(client: makeClient(transport), busyRetryDelay: .zero)
        await thread.adopt("OLD")
        #expect(await thread.current() == "OLD")
        #expect(await thread.reopen())
        let reply = await thread.send("and then?", hint: nil, onUpdate: plain)
        #expect(reply.state == .answered)
        #expect(transport.sent.map { "\($0.method.rawValue) \($0.path ?? "")" } == ["POST /v1/chats/OLD/turns"])
    }

    @Test func aNewChatForgetsTheOneBefore() async {
        let created = ScriptedResponse(status: .created, json: #"{"id":"c1"}"#)
        let transport = ScriptedTransport([created])
        let thread = ChatThread(client: makeClient(transport), busyRetryDelay: .zero)
        await thread.adopt("OLD")
        await thread.reset()
        #expect(await thread.current() == nil)
    }
}
