import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
@testable import AaruAPI

/// Answers every request with one status and records what it was sent. No network.
private final class StubTransport: ClientTransport, @unchecked Sendable {
    // @unchecked: test-only; `lock` guards `requests`.
    private let lock = NSLock()
    private var requests: [HTTPRequest] = []
    let status: HTTPResponse.Status
    let body: String

    init(status: HTTPResponse.Status, body: String = "{}") {
        self.status = status
        self.body = body
    }

    var sent: [HTTPRequest] {
        lock.withLock { requests }
    }

    func send(
        _ request: HTTPRequest,
        body _: HTTPBody?,
        baseURL _: URL,
        operationID _: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        lock.withLock { requests.append(request) }
        var response = HTTPResponse(status: status)
        response.headerFields[.contentType] = "application/json"
        return (response, HTTPBody(body))
    }
}

/// Counts sign-out routings.
private actor Counter {
    private(set) var value = 0
    func increment() {
        value += 1
    }
}

private actor TokenBox {
    var token: String?
    init(_ token: String?) {
        self.token = token
    }

    func set(_ token: String?) {
        self.token = token
    }
}

private let baseURL = URL(string: "https://api.aaru.test")!
private let unauthorized = #"{"error":{"code":"unauthorized","message":"Sign in again."}}"#

@Suite("APP-001: API client session handling")
struct SessionMiddlewareTests {
    @Test("A signed-in request carries the bearer token")
    func attachesToken() async throws {
        let transport = StubTransport(status: .ok, body: #"{"status":"ok"}"#)
        let client = Client.aaru(
            baseURL: baseURL,
            session: SessionMiddleware(token: { "abc" }, onUnauthorized: {}),
            transport: transport
        )
        _ = try await client.getHealth()
        #expect(transport.sent.first?.headerFields[.authorization] == "Bearer abc")
        #expect(transport.sent.first?.path == "/v1/health")
    }

    @Test("Signed out, no Authorization header is sent")
    func noTokenNoHeader() async throws {
        let transport = StubTransport(status: .ok, body: #"{"status":"ok"}"#)
        let client = Client.aaru(
            baseURL: baseURL,
            session: SessionMiddleware(token: { nil }, onUnauthorized: {}),
            transport: transport
        )
        _ = try await client.getHealth()
        #expect(transport.sent.first?.headerFields[.authorization] == nil)
    }

    @Test("Many concurrent 401s for one token route to sign-in exactly once, with no retries")
    func unauthorizedOnce() async {
        let transport = StubTransport(status: .unauthorized, body: unauthorized)
        let counter = Counter()
        let client = Client.aaru(
            baseURL: baseURL,
            session: SessionMiddleware(token: { "stale" }, onUnauthorized: { await counter.increment() }),
            transport: transport
        )
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 12 {
                group.addTask { _ = try? await client.getMe() }
            }
        }
        #expect(await counter.value == 1)
        #expect(transport.sent.count == 12, "one request each, nothing retried")
    }

    @Test("A new session that is rejected later routes to sign-in again")
    func newTokenRoutesAgain() async {
        let transport = StubTransport(status: .unauthorized, body: unauthorized)
        let counter = Counter()
        let box = TokenBox("first")
        let client = Client.aaru(
            baseURL: baseURL,
            session: SessionMiddleware(token: { await box.token }, onUnauthorized: { await counter.increment() }),
            transport: transport
        )
        _ = try? await client.getMe()
        await box.set("second")
        _ = try? await client.getMe()
        #expect(await counter.value == 2)
    }

    @Test("A 401 with no session (a failed sign-in) does not route anywhere")
    func signInFailureIsNotASignOut() async {
        let transport = StubTransport(status: .unauthorized, body: unauthorized)
        let counter = Counter()
        let client = Client.aaru(
            baseURL: baseURL,
            session: SessionMiddleware(token: { nil }, onUnauthorized: { await counter.increment() }),
            transport: transport
        )
        _ = try? await client.signInWithApple(body: .json(.init(identityToken: "x", nonce: "n")))
        #expect(await counter.value == 0)
    }
}
