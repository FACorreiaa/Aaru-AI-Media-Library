import Hummingbird
import Logging

/// Logs each request like Hummingbird's `LogRequestsMiddleware`, but never a secret in the URL:
/// the Stremio addon's token is a path segment, and Trakt's callback carries `code` and `state`.
struct RedactedLogRequestsMiddleware<Context: RequestContext>: RouterMiddleware {
    let logLevel: Logger.Level

    init(_ logLevel: Logger.Level) {
        self.logLevel = logLevel
    }

    func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws
        -> Response
    {
        context.logger.log(
            level: logLevel,
            "Request",
            metadata: [
                "hb.request.path": .string(Self.redacted(request.uri.path, query: request.uri.query)),
                "hb.request.method": .string(request.method.rawValue),
            ]
        )
        return try await next(request, context)
    }

    /// `/stremio/<secret>/…` becomes `/stremio/[token]/…`; the Trakt callback and the concert
    /// city search (a place the user typed) lose their query. Any other path keeps its query.
    static func redacted(_ path: String, query: String?) -> String {
        var path = path
        if path.hasPrefix("/stremio/") {
            let rest = path.dropFirst("/stremio/".count)
            let tail = rest.firstIndex(of: "/").map { String(rest[$0...]) } ?? ""
            path = "/stremio/[token]" + tail
            return path
        }
        if path == "/v1/imports/trakt/callback" || path == "/v1/concerts/places" {
            return path
        }
        guard let query, !query.isEmpty else { return path }
        return path + "?" + query
    }
}
