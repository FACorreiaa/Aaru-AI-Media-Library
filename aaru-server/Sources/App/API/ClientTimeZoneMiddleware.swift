import Foundation
import HTTPTypes
import Hummingbird

/// The caller's time zone for this request, from `X-Timezone` (GAM-003). Points and streak days
/// are dated in it; without the header the user's stored zone applies, then UTC.
enum ClientTimeZone {
    @TaskLocal static var current: TimeZone?

    /// An IANA identifier Foundation knows; anything else is ignored rather than trusted.
    static func parse(_ value: String?) -> TimeZone? {
        guard let value, !value.isEmpty, value.count <= 64 else { return nil }
        return TimeZone(identifier: value)
    }
}

struct ClientTimeZoneMiddleware<Context: RequestContext>: RouterMiddleware {
    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        guard let zone = ClientTimeZone.parse(request.headers[.xTimezone]) else {
            return try await next(request, context)
        }
        return try await ClientTimeZone.$current.withValue(zone) {
            try await next(request, context)
        }
    }
}

extension HTTPField.Name {
    // swiftlint:disable:next force_unwrapping
    static let xTimezone = Self("X-Timezone")!
}
