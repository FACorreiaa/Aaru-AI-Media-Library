import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Puts the session's bearer token on every request and reports a rejected token once.
///
/// A 401 for a token calls `onUnauthorized` the first time only, however many requests were
/// in flight with that token, so the app routes to sign-in once instead of once per request.
/// Nothing is retried: a rejected session stays rejected until the user signs in again.
public struct SessionMiddleware: ClientMiddleware {
    private let token: @Sendable () async -> String?
    private let onUnauthorized: @Sendable () async -> Void
    private let gate = RejectionGate()

    public init(
        token: @escaping @Sendable () async -> String?,
        onUnauthorized: @escaping @Sendable () async -> Void
    ) {
        self.token = token
        self.onUnauthorized = onUnauthorized
    }

    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID _: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        let current = await token()
        if let current {
            request.headerFields[.authorization] = "Bearer \(current)"
        }
        let (response, responseBody) = try await next(request, body, baseURL)
        if response.status == .unauthorized, let current, await gate.isFirstRejection(of: current) {
            await onUnauthorized()
        }
        return (response, responseBody)
    }
}

/// Remembers the last token the server rejected.
private actor RejectionGate {
    private var lastRejected: String?

    func isFirstRejection(of token: String) -> Bool {
        guard token != lastRejected else { return false }
        lastRejected = token
        return true
    }
}
