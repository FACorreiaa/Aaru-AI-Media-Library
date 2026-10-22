import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Sends the device's time zone as `X-Timezone` on every request, so points and streak days are
/// dated on the user's local calendar (GAM-003). Read per request: travelling moves it.
public struct TimeZoneMiddleware: ClientMiddleware {
    private let zone: @Sendable () -> TimeZone

    public init(zone: @escaping @Sendable () -> TimeZone = { TimeZone.current }) {
        self.zone = zone
    }

    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID _: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        request.headerFields[.xTimezone] = zone().identifier
        return try await next(request, body, baseURL)
    }
}

extension HTTPField.Name {
    // swiftlint:disable:next force_unwrapping
    static let xTimezone = Self("X-Timezone")!
}
