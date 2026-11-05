import Foundation
import HTTPTypes
import OpenAPIRuntime

/// One scripted answer: a status, a body that arrives in chunks, and optionally a failure
/// either instead of the answer or part-way through its body.
struct ScriptedResponse: Sendable {
    var status: HTTPResponse.Status
    var contentType: String
    var chunks: [Data]
    /// Thrown by `send` itself: the request never gets an answer.
    var sendFailure: (any Error)?
    /// Thrown from the body after all `chunks`: the stream drops part-way.
    var streamFailure: (any Error)?
    /// Keeps the body open after the chunks until the request is cancelled.
    var hangsAfterChunks = false

    init(
        status: HTTPResponse.Status = .ok,
        contentType: String = "application/json",
        chunks: [Data] = [],
        streamFailure: (any Error)? = nil,
        hangsAfterChunks: Bool = false
    ) {
        self.status = status
        self.contentType = contentType
        self.chunks = chunks
        self.streamFailure = streamFailure
        self.hangsAfterChunks = hangsAfterChunks
    }

    init(status: HTTPResponse.Status = .ok, json: String) {
        self.init(status: status, chunks: [Data(json.utf8)])
    }

    init(stream chunks: [String], status: HTTPResponse.Status = .ok, streamFailure: (any Error)? = nil) {
        self.init(
            status: status,
            contentType: "text/event-stream",
            chunks: chunks.map { Data($0.utf8) },
            streamFailure: streamFailure
        )
    }

    static func failing(_ error: any Error) -> ScriptedResponse {
        var response = ScriptedResponse()
        response.sendFailure = error
        return response
    }
}

/// Answers requests from a queue, in order; the last answer repeats once the queue is down to
/// one. Records every request and the bytes of its body. No network.
final class ScriptedTransport: ClientTransport, @unchecked Sendable {
    // @unchecked: test-only; `lock` guards `queue`, `requests` and `bodies`.
    private let lock = NSLock()
    private var queue: [ScriptedResponse]
    private var requests: [HTTPRequest] = []
    private var bodies: [Data] = []

    init(_ responses: [ScriptedResponse]) {
        queue = responses
    }

    convenience init(_ response: ScriptedResponse = ScriptedResponse(json: "{}")) {
        self.init([response])
    }

    var sent: [HTTPRequest] {
        lock.withLock { requests }
    }

    var sentBodies: [Data] {
        lock.withLock { bodies }
    }

    func send(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL _: URL,
        operationID _: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var sentBody = Data()
        if let body {
            for try await chunk in body {
                sentBody.append(contentsOf: chunk)
            }
        }
        let scripted: ScriptedResponse = lock.withLock {
            requests.append(request)
            bodies.append(sentBody)
            return queue.count > 1 ? queue.removeFirst() : (queue.first ?? ScriptedResponse(json: "{}"))
        }
        if let failure = scripted.sendFailure {
            throw failure
        }
        var response = HTTPResponse(status: scripted.status)
        response.headerFields[.contentType] = scripted.contentType
        let stream = AsyncThrowingStream<ArraySlice<UInt8>, any Error> { continuation in
            for chunk in scripted.chunks {
                continuation.yield(ArraySlice(chunk))
            }
            if let failure = scripted.streamFailure {
                continuation.finish(throwing: failure)
            } else if !scripted.hangsAfterChunks {
                continuation.finish()
            }
        }
        return (response, HTTPBody(stream, length: .unknown, iterationBehavior: .single))
    }
}
