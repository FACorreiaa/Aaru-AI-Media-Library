import Hummingbird
import HummingbirdCore
import Logging
import NIOCore
import ServiceLifecycle

/// Counts each request by method, route template and status, and times it by route group.
/// The route is the template Hummingbird matched (`/v1/titles/{id}`), never the raw path.
struct HTTPMetricsMiddleware<Context: RequestContext>: RouterMiddleware {
    var metrics: Metrics = .shared

    func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws
        -> Response
    {
        metrics.requestStarted()
        let started = ContinuousClock.now
        do {
            let response = try await next(request, context)
            finish(request, status: response.status.code, since: started, context: context)
            return response
        } catch {
            let status = (error as? any HTTPResponseError)?.status.code ?? 500
            finish(request, status: status, since: started, context: context)
            throw error
        }
    }

    private func finish(_ request: Request, status: Int, since started: ContinuousClock.Instant, context: Context) {
        // Read after `next`: the router fills the template in while routing.
        metrics.requestFinished(
            method: request.method.rawValue, route: context.endpointPath, status: status,
            duration: ContinuousClock.now - started
        )
    }
}

/// `GET /metrics` on its own listener (`METRICS_PORT`), outside the Service and the Ingress, so
/// only the cluster's Alloy reaches it on the pod IP. Nothing when the port is 0.
func metricsServices(port: Int, metrics: Metrics = .shared, logger: Logger) -> [any Service] {
    guard port > 0 else { return [] }
    return [
        Application(
            router: metricsRouter(metrics),
            configuration: .init(address: .hostname("0.0.0.0", port: port), serverName: nil),
            logger: logger
        ),
    ]
}

func metricsRouter(_ metrics: Metrics) -> Router<BasicRequestContext> {
    let router = Router()
    router.get("/metrics") { _, _ in
        Response(
            status: .ok,
            headers: [.contentType: "text/plain; version=0.0.4; charset=utf-8"],
            body: .init(byteBuffer: ByteBuffer(string: metrics.render()))
        )
    }
    return router
}
