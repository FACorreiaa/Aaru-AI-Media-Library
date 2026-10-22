import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
@testable import aaru

/// `GET /metrics` on the internal port: what Alloy scrapes into Grafana Cloud.
@Suite("Prometheus metrics")
struct MetricsTests {
    @Test("counters, the in-flight gauge and the histogram render in the text format")
    func render() {
        let metrics = Metrics()
        metrics.increment(.imports, ["source": "trakt", "result": "planned"])
        metrics.increment(.imports, ["source": "trakt", "result": "planned"])
        metrics.requestStarted()
        metrics.requestFinished(method: "GET", route: "/v1/library", status: 200, duration: .milliseconds(30))
        let text = metrics.render()
        #expect(text.contains("# TYPE aaru_imports_total counter\n"))
        #expect(text.contains("aaru_imports_total{source=\"trakt\",result=\"planned\"} 2\n"))
        #expect(text.contains("aaru_http_requests_total{method=\"GET\",route=\"/v1/library\",code=\"200\"} 1\n"))
        #expect(text.contains("aaru_http_in_flight 0\n"))
        #expect(text.contains("aaru_http_request_duration_seconds_bucket{group=\"library\",le=\"0.025\"} 0\n"))
        #expect(text.contains("aaru_http_request_duration_seconds_bucket{group=\"library\",le=\"0.05\"} 1\n"))
        #expect(text.contains("aaru_http_request_duration_seconds_bucket{group=\"library\",le=\"+Inf\"} 1\n"))
        #expect(text.contains("aaru_http_request_duration_seconds_count{group=\"library\"} 1\n"))
    }

    @Test("a label value cannot break out of its quotes")
    func escaping() {
        let metrics = Metrics()
        metrics.increment(.scrobbles, ["source": "a\"b\\c\nd"])
        #expect(metrics.render().contains("aaru_scrobbles_total{source=\"a\\\"b\\\\c\\nd\"} 1\n"))
    }

    @Test("routes group by their first segment after /v1", arguments: [
        ("/v1/titles/{id}", "titles"), ("/v1/library", "library"), ("/stremio/{token}/manifest.json", "stremio"),
        ("/", "root"), ("unmatched", "unmatched"),
    ])
    func group(route: String, group: String) {
        #expect(Metrics.group(route) == group)
    }

    @Test("the route label is the matched template, never the path with its id")
    func routeTemplate() async throws {
        let metrics = Metrics()
        let router = Router()
        router.addMiddleware { HTTPMetricsMiddleware(metrics: metrics) }
        router.get("/v1/titles/:id") { _, _ in "ok" }
        router.get("/v1/fails") { _, _ -> String in throw HTTPError(.badRequest) }
        try await Application(router: router).test(.router) { client in
            try await client.execute(uri: "/v1/titles/0b6a2f63-secret-id", method: .get) { #expect($0.status == .ok) }
            try await client.execute(uri: "/v1/fails", method: .get) { #expect($0.status == .badRequest) }
            try await client.execute(uri: "/nowhere/abc", method: .get) { #expect($0.status == .notFound) }
        }
        let text = metrics.render()
        #expect(!text.contains("0b6a2f63"))
        #expect(!text.contains("nowhere"))
        #expect(text.contains("route=\"/v1/titles/{id}\",code=\"200\"} 1\n"))
        #expect(text.contains("route=\"/v1/fails\",code=\"400\"} 1\n"))
        #expect(text.contains("route=\"unmatched\",code=\"404\"} 1\n"))
        #expect(text.contains("aaru_http_in_flight 0\n"))
    }

    @Test("the metrics listener serves the text format")
    func listener() async throws {
        let metrics = Metrics()
        metrics.increment(.push, ["channel": "apns", "result": "sent"])
        try await Application(router: metricsRouter(metrics)).test(.router) { client in
            try await client.execute(uri: "/metrics", method: .get) { response in
                #expect(response.status == .ok)
                #expect(response.headers[.contentType] == "text/plain; version=0.0.4; charset=utf-8")
                #expect(String(buffer: response.body).contains("aaru_push_total{channel=\"apns\",result=\"sent\"} 1\n"))
            }
        }
    }

    @Test("port 0 turns the listener off")
    func off() {
        #expect(metricsServices(port: 0, logger: .init(label: "test")).isEmpty)
        #expect(metricsServices(port: 9090, logger: .init(label: "test")).count == 1)
    }

    @Test("the API port has no /metrics: it is reachable from the internet")
    func notOnTheAPI() async throws {
        try await withMigratedStores { stores in
            let auth = AuthService(stores: stores, apple: UntouchedAppleVerifier(), magicLinks: nil)
            let services = Services.make(stores: stores, catalogs: FakeCatalog.providers(FakeCatalog()), auth: auth)
            try await Application(router: buildRouter(stores: stores, services: services)).test(.router) { client in
                try await client.execute(uri: "/metrics", method: .get) { #expect($0.status == .notFound) }
            }
        }
    }
}
