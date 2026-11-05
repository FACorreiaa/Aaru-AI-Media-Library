import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
@testable import AaruAPI

private let baseURL = URL(string: "https://api.aaru.test")!

private func makeClient(_ transport: ScriptedTransport) -> Client {
    Client.aaru(
        baseURL: baseURL,
        session: SessionMiddleware(token: { "abc" }, onUnauthorized: {}),
        transport: transport
    )
}

@Suite("ASK-009: the spoken question call")
struct ChatVoiceTests {
    @Test func sendsAudioMP4NotTheWildcard() async {
        let transport = ScriptedTransport(ScriptedResponse(json: #"{"text":"hi","language":"en"}"#))
        let audio = Data([1, 2, 3, 4])
        _ = await makeClient(transport).transcribeQuestion(audio, seconds: 3)
        #expect(transport.sent.first?.path == "/v1/chats/transcribe")
        #expect(transport.sent.first?.headerFields[.contentType] == "audio/mp4")
        #expect(transport.sentBodies.first == audio)
    }

    @Test func leavesOtherRequestsAlone() async throws {
        let transport = ScriptedTransport(ScriptedResponse(stream: ["event: done\ndata: {\"turnId\":\"t\"}\n\n"]))
        let client = makeClient(transport)
        _ = try await client.createChatTurn(
            path: .init(id: "c1"),
            body: .json(.init(body: "hello"))
        )
        #expect(transport.sent.first?.headerFields[.contentType]?.hasPrefix("application/json") == true)
    }

    @Test func clampsTheSecondsHeaderTo60() async throws {
        let transport = ScriptedTransport(ScriptedResponse(json: #"{"text":"hi","language":"en"}"#))
        _ = await makeClient(transport).transcribeQuestion(Data([1]), seconds: 60.04)
        let name = try #require(HTTPField.Name("X-Audio-Seconds"))
        let value = try #require(transport.sent.first?.headerFields[name])
        let seconds = try #require(Double(value))
        #expect(seconds <= 60)
    }

    @Test func returnsTextAndLanguage() async {
        let transport = ScriptedTransport(ScriptedResponse(json: #"{"text":"olá","language":"pt"}"#))
        let result = await makeClient(transport).transcribeQuestion(Data([1]), seconds: 2)
        #expect(result == .text("olá", language: "pt"))
    }

    @Test func mapsStatuses() async {
        func result(_ status: HTTPResponse.Status, _ code: String, _ message: String) async -> ChatVoiceResult {
            let body = #"{"code":"\#(code)","message":"\#(message)"}"#
            let transport = ScriptedTransport(ScriptedResponse(status: status, json: body))
            return await makeClient(transport).transcribeQuestion(Data([1]), seconds: 2)
        }
        #expect(await result(.unprocessableContent, "transcription_empty", "No words") == .notHeard)
        #expect(await result(.contentTooLarge, "audio_too_long", "Too long") == .tooLong)
        #expect(await result(.tooManyRequests, "rate_limited", "Slow down") == .tooMany)
        #expect(await result(.serviceUnavailable, "transcription_unavailable", "Voice is off") == .off)
        #expect(await result(.internalServerError, "internal", "Something broke") == .failed("Something broke"))
    }

    @Test func aThrownTransportErrorFails() async {
        let transport = ScriptedTransport(.failing(URLError(.notConnectedToInternet)))
        let result = await makeClient(transport).transcribeQuestion(Data([1]), seconds: 2)
        #expect(result == .failed("Aaru could not reach the server."))
    }
}
