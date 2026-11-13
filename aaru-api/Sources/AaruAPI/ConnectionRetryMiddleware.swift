import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Sends a read again, once, when the connection it went out on turns out to be dead.
///
/// URLSession reuses a pooled connection, and one the server or the network dropped while it
/// sat idle (a Mac waking from sleep, an ingress closing an idle connection) fails the next
/// request with `URLError.networkConnectionLost` (-1005) before it reaches the server. Apple's
/// guidance is to retry an idempotent request once on that error: the retry opens a fresh
/// connection. Only GET and HEAD are retried, only on that one transport error, and never a
/// request whose body can be read only once. Anything else, an HTTP status included, passes
/// through untouched.
public struct ConnectionRetryMiddleware: ClientMiddleware {
    public init() {}

    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID _: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        do {
            return try await next(request, body, baseURL)
        } catch {
            guard Self.isRetryable(request, body: body, after: error), !Task.isCancelled else { throw error }
            return try await next(request, body, baseURL)
        }
    }

    static func isRetryable(_ request: HTTPRequest, body: HTTPBody?, after error: any Error) -> Bool {
        guard request.method == .get || request.method == .head else { return false }
        if let body, body.iterationBehavior == .single {
            return false
        }
        return transportCode(of: error) == .networkConnectionLost
    }

    /// The URLError under the runtime's wrapping: a transport failure reaches a middleware as a
    /// `ClientError` whose `underlyingError` is what URLSession threw.
    private static func transportCode(of error: any Error) -> URLError.Code? {
        if let urlError = error as? URLError {
            return urlError.code
        }
        if let clientError = error as? ClientError {
            return (clientError.underlyingError as? URLError)?.code
        }
        return nil
    }
}
