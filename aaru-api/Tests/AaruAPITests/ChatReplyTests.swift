import Testing
@testable import AaruAPI

private func title(_ id: String) -> Components.Schemas.TitleSummary {
    Components.Schemas.TitleSummary(id: id, _type: .movie, title: "Title \(id)", isAnime: false, ids: .init())
}

@Suite("ASK-009: the assistant's reply state")
struct ChatReplyTests {
    @Test func deltasAppendAndClearTheStatus() {
        var reply = ChatReply()
        reply.apply(.status("Thinking"))
        #expect(reply.status == "Thinking")
        reply.apply(.delta("Hi "))
        reply.apply(.delta("there"))
        #expect(reply.text == "Hi there")
        #expect(reply.status == nil)
        #expect(reply.state == .working)
    }

    @Test func aLaterStatusShowsAgain() {
        var reply = ChatReply()
        reply.apply(.delta("Hi"))
        reply.apply(.status("Checking your library"))
        #expect(reply.status == "Checking your library")
        #expect(reply.text == "Hi")
    }

    @Test func doneAnswers() {
        var reply = ChatReply()
        reply.apply(.status("Thinking"))
        reply.apply(.done(turnID: "t1"))
        #expect(reply.state == .answered)
        #expect(reply.status == nil)
        #expect(reply.problem == nil)
    }

    @Test func errorStopsWithItsMessage() {
        var reply = ChatReply()
        reply.apply(.status("Thinking"))
        reply.apply(.error(code: .resting, message: "Aaru is resting"))
        #expect(reply.state == .stopped)
        #expect(reply.problem == "Aaru is resting")
        #expect(reply.status == nil)
    }

    @Test func aStreamThatEndsWithoutAnEndIsCutOff() {
        var reply = ChatReply()
        reply.apply(.delta("Half an ans"))
        reply.streamEnded()
        #expect(reply.state == .cutOff)
        #expect(reply.text == "Half an ans")
        #expect(reply.problem == "That answer was cut off. Ask again.")
    }

    @Test func streamEndedAfterDoneChangesNothing() {
        var reply = ChatReply()
        reply.apply(.delta("All of it"))
        reply.apply(.done(turnID: "t1"))
        reply.streamEnded()
        #expect(reply.state == .answered)
        #expect(reply.problem == nil)
    }

    @Test func streamEndedAfterAnErrorChangesNothing() {
        var reply = ChatReply()
        reply.apply(.error(code: .tryAgain, message: "Try again"))
        reply.streamEnded()
        #expect(reply.state == .stopped)
        #expect(reply.problem == "Try again")
    }

    @Test func componentsMerge() {
        var reply = ChatReply()
        reply.apply(.components(.init(titles: [title("a"), title("b")])))
        reply.apply(.components(.init(
            titles: [title("b"), title("c")],
            actionId: "act1",
            actionSummary: "Added Title a"
        )))
        #expect(reply.titles.map(\.id) == ["a", "b", "c"])
        #expect(reply.actionID == "act1")
        #expect(reply.actionSummary == "Added Title a")
        reply.apply(.components(.init(titles: [title("a")])))
        #expect(reply.titles.map(\.id) == ["a", "b", "c"])
        #expect(reply.actionID == "act1")
    }

    @Test func importIsKept() {
        var reply = ChatReply()
        reply.apply(.components(.init(importId: "imp1")))
        reply.apply(.components(.init(titles: [title("a")])))
        #expect(reply.importID == "imp1")
        #expect(reply.actionID == nil)
    }

    @Test func cancelledKeepsWhatWasWritten() {
        var reply = ChatReply()
        reply.apply(.delta("So far"))
        reply.apply(.status("Checking"))
        reply.cancel()
        #expect(reply.state == .cancelled)
        #expect(reply.text == "So far")
        #expect(reply.problem == nil)
        #expect(reply.status == nil)
    }

    @Test func failedCarriesItsProblem() {
        var reply = ChatReply()
        reply.apply(.delta("So far"))
        reply.fail("Aaru could not reach the server.")
        #expect(reply.state == .failed)
        #expect(reply.problem == "Aaru could not reach the server.")
        #expect(reply.text == "So far")
    }

    @Test func framesAfterTheEndAreIgnored() {
        var reply = ChatReply()
        reply.cancel()
        reply.apply(.delta("late"))
        reply.apply(.done(turnID: "t"))
        #expect(reply.text.isEmpty)
        #expect(reply.state == .cancelled)
    }
}
