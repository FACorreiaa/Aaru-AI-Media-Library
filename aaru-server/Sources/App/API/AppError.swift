import AaruCore
import Hummingbird

/// An error a route means to return. Carries the shared `ErrorResponse` fields.
///
/// Throw this (or an `AaruCore.ValidationError`) from handlers; `ErrorMiddleware`
/// turns it into the one error shape. Anything else becomes an opaque 500.
struct AppError: Error, Sendable {
    var status: HTTPResponse.Status
    var code: String
    var message: String
    var details: [String: String]?

    static func notFound(_ message: String = "Not found.") -> AppError {
        AppError(status: .notFound, code: "not_found", message: message)
    }

    static func conflict(_ message: String) -> AppError {
        AppError(status: .conflict, code: "conflict", message: message)
    }

    static func badRequest(_ message: String = "The request could not be read.") -> AppError {
        AppError(status: .badRequest, code: "bad_request", message: message)
    }

    static func unauthorized(_ message: String = "Sign in to continue.") -> AppError {
        AppError(status: .unauthorized, code: "unauthorized", message: message)
    }
}

extension AppError {
    /// Maps a shared validation failure to 422, naming the offending field.
    init(_ validation: ValidationError) {
        self.init(
            status: .unprocessableContent,
            code: "validation_failed",
            message: validation.description,
            details: [validation.field: validation.description]
        )
    }

    /// Maps a framework `HTTPError` (unknown route, bad method, oversize body) to the shared codes.
    init(_ http: HTTPError) {
        self.init(
            status: http.status,
            code: Self.code(for: http.status),
            message: http.body ?? Self.message(for: http.status)
        )
    }

    private static let codes: [Int: String] = [
        400: "bad_request",
        401: "unauthorized",
        403: "forbidden",
        404: "not_found",
        405: "method_not_allowed",
        409: "conflict",
        413: "payload_too_large",
        422: "validation_failed",
        429: "rate_limited",
    ]

    static func code(for status: HTTPResponse.Status) -> String {
        codes[status.code] ?? ((400 ..< 500).contains(status.code) ? "client_error" : "internal")
    }

    private static func message(for status: HTTPResponse.Status) -> String {
        status.code >= 500 ? "Something went wrong." : status.reasonPhrase
    }
}

extension ValidationError {
    /// The request field a validation failure belongs to, for `ErrorResponse.details`.
    var field: String {
        switch self {
        case .emptyTitle: "title"
        case .invalidYear: "year"
        case .ratingOutOfRange, .ratingNotInHalfSteps: "rating"
        case .emptyListName: "name"
        case .invalidEpisodeNumber: "episode"
        case .invalidBookProgress: "progress"
        case .unresolvableMediaRef: "mediaRef"
        }
    }
}
