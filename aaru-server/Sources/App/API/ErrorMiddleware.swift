import aaruAPI
import AaruCore
import Foundation
import Hummingbird
import OpenAPIRuntime

/// Turns every thrown error into the shared `ErrorResponse` JSON shape.
///
/// Sits outside the OpenAPI handlers so unknown routes, framework errors, and
/// handler errors all leave the server in one shape. Unknown errors become an
/// opaque 500 and are logged; their text never reaches the client.
struct ErrorMiddleware<Context: RequestContext>: RouterMiddleware {
    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        do {
            return try await next(request, context)
        } catch {
            let appError = Self.appError(for: error)
            if appError.status.code >= 500 {
                context.logger.error("Unhandled error", metadata: ["error": "\(String(reflecting: error))"])
            }
            return Self.response(for: appError)
        }
    }

    static func appError(for error: any Error) -> AppError {
        switch error {
        case let error as AppError:
            return error
        case let error as ValidationError:
            return AppError(error)
        case let error as HTTPError:
            return AppError(error)
        case let error as ServerError:
            // OpenAPI wraps handler errors; prefer the handler's own meaning.
            let underlying = appError(for: error.underlyingError)
            if underlying.status.code < 500 {
                return underlying
            }
            if (400 ..< 500).contains(error.httpStatus.code) {
                return AppError(
                    status: error.httpStatus,
                    code: AppError.code(for: error.httpStatus),
                    message: "The request could not be read."
                )
            }
            return underlying
        default:
            return AppError(status: .internalServerError, code: "internal", message: "Something went wrong.")
        }
    }

    static func response(for error: AppError) -> Response {
        let body = Components.Schemas.ErrorResponse(
            code: error.code,
            message: error.message,
            details: error.details.map { .init(additionalProperties: $0) }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(body)) ?? Data(#"{"code":"internal","message":"Something went wrong."}"#.utf8)
        return Response(
            status: error.status,
            headers: [.contentType: "application/json; charset=utf-8"],
            body: .init(byteBuffer: ByteBuffer(bytes: data))
        )
    }
}
