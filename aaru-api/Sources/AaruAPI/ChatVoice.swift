import Foundation
import HTTPTypes
import OpenAPIRuntime

/// How a spoken question went (ASK-009).
public enum ChatVoiceResult: Sendable, Equatable {
    case text(String, language: String)
    /// 422: no words were heard.
    case notHeard
    /// 413: over 60 seconds, or over the size limit.
    case tooLong
    /// 429: past the hourly limit.
    case tooMany
    /// 503: voice is off on the server.
    case off
    case failed(String)
}

/// The generated client sends the wildcard `audio/*` for the audio body, and the server names
/// the file from it. The Apple apps record `.m4a` only, so say `audio/mp4`.
public struct ChatAudioContentTypeMiddleware: ClientMiddleware {
    public init() {}

    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        if operationID == Operations.TranscribeChatAudio.id {
            request.headerFields[.contentType] = "audio/mp4"
        }
        return try await next(request, body, baseURL)
    }
}

public extension Client {
    /// Turns a recorded question into text. Never throws: every outcome is a `ChatVoiceResult`.
    /// `seconds` is clamped to 60 so a full recording whose timer ran a hair over is not refused.
    func transcribeQuestion(_ audio: Data, seconds: Double) async -> ChatVoiceResult {
        let output: Operations.TranscribeChatAudio.Output
        do {
            output = try await transcribeChatAudio(
                headers: .init(xAudioSeconds: min(seconds, 60)),
                body: .audio_Ast_(HTTPBody(audio))
            )
        } catch {
            return .failed("Aaru could not reach the server.")
        }
        switch output {
        case let .ok(ok):
            guard let transcript = try? ok.body.json else {
                return .failed("Aaru could not read that.")
            }
            return .text(transcript.text, language: transcript.language)
        case let .default(status, response):
            switch status {
            case 422: return .notHeard
            case 413: return .tooLong
            case 429: return .tooMany
            case 503: return .off
            default: return .failed((try? response.body.json.message) ?? "Aaru could not read that.")
            }
        }
    }
}
