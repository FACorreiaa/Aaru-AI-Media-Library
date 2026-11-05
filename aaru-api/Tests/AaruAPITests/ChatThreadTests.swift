import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
@testable import AaruAPI
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

private let baseURL = URL(string: "https://api.aaru.test")!

private func makeClient(_ transport: ScriptedTransport) -> Client {
    Client.aaru(
        baseURL: baseURL,
        session: SessionMiddleware(token: { "abc" }, onUnauthorized: {}),
        transport: transport
    )
}

private let created = ScriptedResponse(status: .created, json: #"{"id":"c1"}"#)

private func frames(_ lines: String...) -> ScriptedResponse {
    ScriptedResponse(stream: lines)
}

private let answered = frames(
    "event: delta\ndata: {\"text\":\"Hi\"}\n\n",
    "event: done\ndata: {\"turnId\":\"t1\"}\n\n"
)

private final class Clock: @unchecked Sendable {
    // @unchecked: test-only; `lock` guards `date`.
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_000_000)

    var now: Date {
        lock.withLock { date }
    }

    func advance(_ seconds: TimeInterval) {
        lock.withLock { date = date.addingTimeInterval(seconds) }
    }
}

private actor Updates {
    private(set) var seen: [ChatReply] = []

    func add(_ reply: ChatReply) {
        seen.append(reply)
    }
}

private func paths(_ transport: ScriptedTransport) -> [String] {
    transport.sent.map { "\($0.method.rawValue) \($0.path ?? "")" }
}

private func thread(_ transport: ScriptedTransport, clock: Clock = Clock()) -> ChatThread {
    ChatThread(client: makeClient(transport), busyRetryDelay: .zero, now: { clock.now })
}

private func plain(_ reply: ChatReply) async {}

@Suite("ASK-009: one chat thread")
struct ChatThreadTests {
    @Test func createsAChatOnceAndReusesIt() async {
        let transport = ScriptedTransport([created, answered])
        let chat = thread(transport)
        _ = await chat.send("one", hint: nil, onUpdate: plain)
        _ = await chat.send("two", hint: nil, onUpdate: plain)
        #expect(paths(transport) == ["POST /v1/chats", "POST /v1/chats/c1/turns", "POST /v1/chats/c1/turns"])
    }

    @Test func sendsTheBodyAndHint() async throws {
        let transport = ScriptedTransport([created, answered])
        _ = await thread(transport).send(
            "what is this",
            hint: .init(screen: "title", titleId: "tmdb:1"),
            onUpdate: plain
        )
        let json = try #require(JSONSerialization.jsonObject(with: transport.sentBodies[1]) as? [String: Any])
        #expect(json["body"] as? String == "what is this")
        let hint = try #require(json["hint"] as? [String: Any])
        #expect(hint["screen"] as? String == "title")
        #expect(hint["titleId"] as? String == "tmdb:1")
    }

    @Test func deliversUpdatesInOrder() async {
        let transport = ScriptedTransport([
            created,
            frames(
                "event: status\ndata: {\"text\":\"Looking\"}\n\n",
                "event: delta\ndata: {\"text\":\"Hel\"}\n\n",
                "event: delta\ndata: {\"text\":\"lo\"}\n\n",
                "event: done\ndata: {\"turnId\":\"t1\"}\n\n"
            ),
        ])
        let updates = Updates()
        let final = await thread(transport).send("hi", hint: nil) { await updates.add($0) }
        let seen = await updates.seen
        #expect(seen.map(\.status) == ["Looking", nil, nil, nil])
        #expect(seen.map(\.text) == ["", "Hel", "Hello", "Hello"])
        #expect(seen.map(\.state) == [.working, .working, .working, .answered])
        #expect(final.state == .answered)
        #expect(final.text == "Hello")
    }

    @Test func continuesWithin15MinutesAndNotAfter() async {
        let transport = ScriptedTransport([created, answered])
        let clock = Clock()
        let chat = thread(transport, clock: clock)
        #expect(await chat.reopen())
        _ = await chat.send("one", hint: nil, onUpdate: plain)
        clock.advance(14 * 60 + 59)
        #expect(await chat.reopen())
        _ = await chat.send("two", hint: nil, onUpdate: plain)
        #expect(paths(transport).filter { $0 == "POST /v1/chats" }.count == 1)
        clock.advance(15 * 60 + 1)
        #expect(await chat.reopen() == false)
        _ = await chat.send("three", hint: nil, onUpdate: plain)
        #expect(paths(transport).filter { $0 == "POST /v1/chats" }.count == 2)
    }

    @Test func aChatTheServerNoLongerHasStartsANewOneOnce() async {
        let transport = ScriptedTransport([
            created,
            ScriptedResponse(status: .notFound, json: #"{"code":"not_found","message":"gone"}"#),
            created,
            answered,
        ])
        let final = await thread(transport).send("hi", hint: nil, onUpdate: plain)
        #expect(final.state == .answered)
        #expect(paths(transport) == [
            "POST /v1/chats", "POST /v1/chats/c1/turns", "POST /v1/chats", "POST /v1/chats/c1/turns",
        ])
        #expect(transport.sentBodies[1] == transport.sentBodies[3])
    }

    @Test func stopsAfterOne404Retry() async {
        let gone = ScriptedResponse(status: .notFound, json: #"{"code":"not_found","message":"gone"}"#)
        let transport = ScriptedTransport([created, gone, created, gone])
        let final = await thread(transport).send("hi", hint: nil, onUpdate: plain)
        #expect(final.state == .failed)
        #expect(paths(transport).filter { $0.hasSuffix("/turns") }.count == 2)
    }

    @Test func waitsOutABusyChat() async {
        let busy = ScriptedResponse(status: .conflict, json: #"{"code":"busy","message":"busy"}"#)
        let transport = ScriptedTransport([created, busy, busy, answered])
        let final = await thread(transport).send("hi", hint: nil, onUpdate: plain)
        #expect(final.state == .answered)
        #expect(paths(transport).filter { $0.hasSuffix("/turns") }.count == 3)
    }

    @Test func givesUpOnABusyChatAfterThreeTries() async {
        let transport = ScriptedTransport([
            created,
            ScriptedResponse(status: .conflict, json: #"{"code":"busy","message":"busy"}"#),
        ])
        let final = await thread(transport).send("hi", hint: nil, onUpdate: plain)
        #expect(final.state == .failed)
        #expect(final.problem == "Aaru is still finishing the last answer. Try again in a moment.")
        #expect(paths(transport).filter { $0.hasSuffix("/turns") }.count == 3)
    }

    @Test func reportsAnUnavailableAssistant() async {
        let transport = ScriptedTransport([
            created,
            ScriptedResponse(
                status: .serviceUnavailable,
                json: #"{"code":"unavailable","message":"Aaru is resting."}"#
            ),
        ])
        let final = await thread(transport).send("hi", hint: nil, onUpdate: plain)
        #expect(final.state == .failed)
        #expect(final.problem == "Aaru is resting.")
    }

    @Test func aCreateFailureFails() async {
        let transport = ScriptedTransport(.failing(URLError(.notConnectedToInternet)))
        let final = await thread(transport).send("hi", hint: nil, onUpdate: plain)
        #expect(final.state == .failed)
        #expect(final.problem == "Aaru could not reach the server.")
    }

    @Test func aDroppedStreamIsCutOff() async {
        let transport = ScriptedTransport([
            created,
            ScriptedResponse(
                stream: ["event: delta\ndata: {\"text\":\"Par\"}\n\n"],
                streamFailure: URLError(.networkConnectionLost)
            ),
        ])
        let final = await thread(transport).send("hi", hint: nil, onUpdate: plain)
        #expect(final.state == .cutOff)
        #expect(final.text == "Par")
    }

    @Test func cancellingTheTaskCancelsTheReply() async {
        var hanging = ScriptedResponse(
            stream: ["event: delta\ndata: {\"text\":\"Par\"}\n\n"]
        )
        hanging.hangsAfterChunks = true
        let transport = ScriptedTransport([created, hanging])
        let chat = thread(transport)
        let updates = Updates()
        let task = Task {
            await chat.send("hi", hint: nil) { await updates.add($0) }
        }
        while await updates.seen.isEmpty {
            await Task.yield()
        }
        task.cancel()
        let final = await task.value
        #expect(final.state == .cancelled)
        #expect(final.problem == nil)
        #expect(final.text == "Par")
    }

    @Test func cancellingBeforeTheChatExistsCancelsTheReply() async {
        let transport = ScriptedTransport(.failing(URLError(.cancelled)))
        let chat = thread(transport)
        let task = Task {
            await chat.send("hi", hint: nil, onUpdate: plain)
        }
        task.cancel()
        let final = await task.value
        #expect(final.state == .cancelled)
        #expect(final.problem == nil)
    }

    @Test func cancellingDuringTheBusyWaitCancelsTheReply() async {
        let busy = ScriptedResponse(status: .conflict, json: #"{"code":"busy","message":"busy"}"#)
        let transport = ScriptedTransport([created, busy])
        let chat = ChatThread(client: makeClient(transport), busyRetryDelay: .seconds(60), now: { Date() })
        let task = Task {
            await chat.send("hi", hint: nil, onUpdate: plain)
        }
        while transport.sent.count < 2 {
            await Task.yield()
        }
        task.cancel()
        let final = await task.value
        #expect(final.state == .cancelled)
        #expect(final.problem == nil)
        #expect(transport.sent.count == 2)
    }

    @Test func resetForgetsTheChat() async {
        let transport = ScriptedTransport([created, answered])
        let chat = thread(transport)
        _ = await chat.send("one", hint: nil, onUpdate: plain)
        await chat.reset()
        _ = await chat.send("two", hint: nil, onUpdate: plain)
        #expect(paths(transport).filter { $0 == "POST /v1/chats" }.count == 2)
    }
}
