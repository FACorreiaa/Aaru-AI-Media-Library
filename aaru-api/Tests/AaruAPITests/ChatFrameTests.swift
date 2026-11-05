import Foundation
import Testing
@testable import AaruAPI

/// A comparable one-line form of a frame, since `ChatFrame` is not `Equatable`.
private func describe(_ frame: ChatFrame) -> String {
    switch frame {
    case let .status(text): "status:\(text)"
    case let .delta(text): "delta:\(text)"
    case let .components(frame):
        "components:\(frame.titles?.map(\.title) ?? []):\(frame.plan?.id ?? "-"):\(frame.actionId ?? "-"):\(frame.actionSummary ?? "-")"
    case let .done(turnID): "done:\(turnID)"
    case let .error(code, message): "error:\(code.rawValue):\(message)"
    }
}

private func parse(_ chunks: [[UInt8]]) -> [String] {
    var parser = ChatFrameParser()
    return chunks.flatMap { parser.consume($0) }.map(describe)
}

private let componentsJSON = """
{"titles":[{"id":"t1","type":"show","title":"Frieren","isAnime":true,"ids":{}}],\
"plan":{"id":"p1","status":"pending","agentName":"Aaru","summary":"Add one",\
"changes":[{"text":"Add Frieren","titleId":"t1","title":"Frieren","type":"show"}],\
"counts":{"adds":1,"updates":0,"removes":0,"episodes":0},\
"createdAt":"2026-11-05T10:00:00Z","expiresAt":"2026-11-06T10:00:00Z"},\
"actionId":"a1","actionSummary":"Added"}
"""

private let everyFrame = """
event: status
data: {"text":"Looking"}

event: delta
data: {"text":"Hello"}

event: components
data: \(componentsJSON)

event: done
data: {"turnId":"turn-1"}

event: error
data: {"code":"try_again","message":"Again please"}


"""

private let expected = [
    "status:Looking",
    "delta:Hello",
    "components:[\"Frieren\"]:p1:a1:Added",
    "done:turn-1",
    "error:try_again:Again please",
]

struct ChatFrameTests {
    @Test func parsesEveryFrameType() {
        #expect(parse([Array(everyFrame.utf8)]) == expected)
    }

    @Test func keepsAMultibyteCharacterSplitAcrossChunks() throws {
        let bytes = Array("event: delta\ndata: {\"text\":\"não\"}\n\n".utf8)
        let cut = try #require(bytes.firstIndex(of: 0xC3)) + 1
        #expect(parse([Array(bytes[..<cut]), Array(bytes[cut...])]) == ["delta:não"])
    }

    @Test func reassemblesAFrameAcrossEveryByteBoundary() {
        let chunks = everyFrame.utf8.map { [$0] }
        #expect(parse(chunks) == expected)
    }

    @Test func ignoresHeartbeatComments() {
        let text = ": keepalive\n\nevent: delta\ndata: {\"text\":\"a\"}\n\n: keepalive\n\n"
        #expect(parse([Array(text.utf8)]) == ["delta:a"])
    }

    @Test func acceptsCRLF() {
        let text = everyFrame.replacingOccurrences(of: "\n", with: "\r\n")
        #expect(parse([Array(text.utf8)]) == expected)
    }

    @Test func skipsAnUnknownEvent() {
        let text = "event: future\ndata: {\"x\":1}\n\nevent: delta\ndata: {\"text\":\"a\"}\n\n"
        #expect(parse([Array(text.utf8)]) == ["delta:a"])
    }

    @Test func skipsMalformedJSONAndKeepsGoing() {
        let text = "event: delta\ndata: {not json\n\nevent: delta\ndata: {\"text\":\"b\"}\n\n"
        #expect(parse([Array(text.utf8)]) == ["delta:b"])
    }

    @Test func joinsMultipleDataLinesWithANewline() {
        let text = "event: delta\ndata: {\"text\":\ndata: \"a\"}\n\n"
        #expect(parse([Array(text.utf8)]) == ["delta:a"])
    }

    @Test func decodesAPlanAndTitlesFromAComponentsFrame() throws {
        var parser = ChatFrameParser()
        let frames = parser.consume(Array("event: components\ndata: \(componentsJSON)\n\n".utf8))
        guard case let .components(frame) = try #require(frames.first) else {
            Issue.record("not a components frame")
            return
        }
        #expect(frame.titles?.first?.title == "Frieren")
        let plan = try #require(frame.plan)
        #expect(plan.createdAt == Date(timeIntervalSince1970: 1_793_872_800))
        #expect(plan.counts.adds == 1)
    }
}
