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
        let path = Self.redacted(request.uri.path, query: request.uri.query)
        context.logger.log(
            level: logLevel,
            "Request",
            metadata: [
                "hb.request.path": .string(path),
                "hb.request.method": .string(request.method.rawValue),
            ]
        )
        // One closing line with the status and the time spent here, so a slow route shows in the
        // log without a profiler. The request id ties it to the line above.
        let started = ContinuousClock.now
        do {
            let response = try await next(request, context)
            logDone(request, path: path, status: response.status.code, since: started, context: context)
            return response
        } catch {
            let status = (error as? any HTTPResponseError)?.status.code ?? 500
            logDone(request, path: path, status: status, since: started, context: context)
            throw error
        }
    }

    private func logDone(
        _ request: Request, path: String, status: Int, since started: ContinuousClock.Instant, context: Context
    ) {
        context.logger.log(
            level: logLevel,
            "Response",
            metadata: [
                "hb.request.path": .string(path),
                "hb.request.method": .string(request.method.rawValue),
                "hb.response.status": .stringConvertible(status),
                "hb.response.ms": .stringConvertible(Self.milliseconds(ContinuousClock.now - started)),
            ]
        )
    }

    /// Whole milliseconds, rounded down.
    static func milliseconds(_ duration: Duration) -> Int64 {
        let (seconds, attoseconds) = duration.components
        return seconds * 1000 + attoseconds / 1_000_000_000_000_000
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
