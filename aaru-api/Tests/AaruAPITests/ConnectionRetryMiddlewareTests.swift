import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
@testable import AaruAPI

private let baseURL = URL(string: "https://api.aaru.test")!
private let healthy = ScriptedResponse(json: #"{"status":"ok"}"#)

private func makeClient(_ transport: ScriptedTransport) -> Client {
    Client.aaru(
        baseURL: baseURL,
        session: SessionMiddleware(token: { "abc" }, onUnauthorized: {}),
        transport: transport
    )
}

@Suite("API client: a read on a dropped connection is sent again once")
struct ConnectionRetryMiddlewareTests {
    @Test("A GET that fails with networkConnectionLost is resent once and succeeds")
    func retriesALostRead() async throws {
        let transport = ScriptedTransport([.failing(URLError(.networkConnectionLost)), healthy])
        let output = try await makeClient(transport).getHealth()

        guard case .ok = output else {
            Issue.record("expected ok, got \(output)")
            return
        }
        #expect(transport.sent.count == 2)
        #expect(transport.sent.allSatisfy { $0.headerFields[.authorization] == "Bearer abc" })
    }

    @Test("A GET that loses the connection twice fails with the URLError, after one retry")
    func retriesOnlyOnce() async {
        let transport = ScriptedTransport([.failing(URLError(.networkConnectionLost))])
        await #expect(throws: ClientError.self) { _ = try await makeClient(transport).getHealth() }
        #expect(transport.sent.count == 2)
    }

    @Test("A POST is never resent: it may have reached the server")
    func neverRetriesAWrite() async {
        let transport = ScriptedTransport([.failing(URLError(.networkConnectionLost)), healthy])
        await #expect(throws: ClientError.self) { _ = try await makeClient(transport).signOut() }
        #expect(transport.sent.count == 1)
    }

    @Test("Other transport errors are not retried", arguments: [
        URLError.Code.notConnectedToInternet, .timedOut, .cancelled, .cannotFindHost,
    ])
    func otherErrorsPassThrough(code: URLError.Code) async {
        let transport = ScriptedTransport([.failing(URLError(code)), healthy])
        await #expect(throws: ClientError.self) { _ = try await makeClient(transport).getHealth() }
        #expect(transport.sent.count == 1)
    }

    @Test("A HEAD is retryable; a GET with a one-shot body is not")
    func methodAndBodyRules() {
        let lost = URLError(.networkConnectionLost)
        let head = HTTPRequest(method: .head, scheme: "https", authority: "api.aaru.test", path: "/v1/health")
        let get = HTTPRequest(method: .get, scheme: "https", authority: "api.aaru.test", path: "/v1/health")
        let oneShot = HTTPBody(
            AsyncStream<ArraySlice<UInt8>> { $0.finish() },
            length: .unknown,
            iterationBehavior: .single
        )

        #expect(ConnectionRetryMiddleware.isRetryable(head, body: nil, after: lost))
        #expect(ConnectionRetryMiddleware.isRetryable(get, body: HTTPBody("x"), after: lost))
        #expect(!ConnectionRetryMiddleware.isRetryable(get, body: oneShot, after: lost))
        #expect(!ConnectionRetryMiddleware.isRetryable(get, body: nil, after: CancellationError()))
    }
}
