import AsyncHTTPClient
import Foundation
import NIOCore
import NIOHTTP1
import ServiceLifecycle

/// One outbound HTTP call. Providers (Apple JWKS, Resend, TMDB, …) talk through
/// `HTTPTransport` so tests can swap in a stub — tests never reach a real service
/// or use a real key.
struct OutboundRequest: Sendable {
    var method: String = "GET"
    var url: URL
    var headers: [(String, String)] = []
    var body: Data?
    var timeout: Duration = .seconds(10)
}

struct OutboundResponse: Sendable {
    var status: Int
    var body: Data
    var headers: [(String, String)] = []

    /// The first header with this name, ignoring case.
    func header(_ name: String) -> String? {
        headers.first { $0.0.caseInsensitiveCompare(name) == .orderedSame }?.1
    }
}

protocol HTTPTransport: Sendable {
    func send(_ request: OutboundRequest) async throws -> OutboundResponse
}

/// The production transport over AsyncHTTPClient. Cancellation of the calling
/// task cancels the request.
struct AsyncHTTPTransport: HTTPTransport {
    let client: HTTPClient
    /// Responses larger than this are refused rather than buffered.
    var maxBodyBytes = 8 * 1024 * 1024

    func send(_ request: OutboundRequest) async throws -> OutboundResponse {
        var outbound = HTTPClientRequest(url: request.url.absoluteString)
        outbound.method = HTTPMethod(rawValue: request.method)
        for (name, value) in request.headers {
            outbound.headers.add(name: name, value: value)
        }
        if let body = request.body {
            outbound.body = .bytes(ByteBuffer(bytes: body))
        }
        // AsyncHTTPClient's deadline stops at the response head; a server trickling the body would
        // outlive it. The race bounds the whole call, body included, by `timeout`.
        let (client, limit, timeout, prepared) = (client, maxBodyBytes, request.timeout, outbound)
        return try await withThrowingTaskGroup(of: OutboundResponse.self) { group in
            group.addTask {
                let response = try await client.execute(prepared, timeout: TimeAmount(timeout))
                let buffer = try await response.body.collect(upTo: limit)
                return OutboundResponse(
                    status: Int(response.status.code), body: Data(buffer: buffer),
                    headers: response.headers.map { ($0.name, $0.value) }
                )
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw HTTPClientError.deadlineExceeded
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw CancellationError() }
            return first
        }
    }
}

extension TimeAmount {
    /// The whole duration in nanoseconds (it used to be truncated to whole seconds, so 1.5 s was
    /// 1 s and anything under a second an instant timeout), and never zero.
    init(_ duration: Duration) {
        let (seconds, attoseconds) = duration.components
        self = .nanoseconds(max(1, seconds * 1_000_000_000 + attoseconds / 1_000_000_000))
    }
}

/// The one outbound client (TMDB, AniList, TVmaze, Open Library, Trakt, Anthropic, …). The
/// shared singleton waits 90 s to connect and 90 s between reads; a provider that is down should
/// fail in seconds, and each call's own `timeout` bounds the rest.
func makeHTTPClient() -> HTTPClient {
    // Read is a backstop for a stalled socket; it stays above the longest per-call timeout (120 s).
    let configuration = HTTPClient.Configuration(
        redirectConfiguration: .follow(max: 5, allowCycles: false),
        timeout: .init(connect: .seconds(5), read: .seconds(120)),
        connectionPool: .init(idleTimeout: .seconds(60))
    )
    return HTTPClient(eventLoopGroupProvider: .singleton, configuration: configuration)
}

/// Shuts the outbound client down on graceful shutdown, after the services that use it.
struct HTTPClientService: Service {
    let client: HTTPClient

    func run() async throws {
        try? await gracefulShutdown()
        try await client.shutdown()
    }
}
