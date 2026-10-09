import AsyncHTTPClient
import Foundation
import NIOCore
import NIOHTTP1

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
        let seconds = Int64(request.timeout.components.seconds)
        let response = try await client.execute(outbound, timeout: .seconds(seconds))
        let buffer = try await response.body.collect(upTo: maxBodyBytes)
        return OutboundResponse(status: Int(response.status.code), body: Data(buffer: buffer))
    }
}
