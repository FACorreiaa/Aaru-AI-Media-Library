import Foundation
import Synchronization

/// Prometheus metrics for the cluster's Alloy, served as text on the internal port (`METRICS_PORT`).
///
/// Every label value comes from a small fixed set: a route template, a source, a result. Never a
/// path with an id in it, a user, or a title. The Grafana Cloud plan is about 10k series for every
/// app on the cluster.
final class Metrics: Sendable {
    static let shared = Metrics()

    /// A counter and the words Prometheus shows for it.
    enum Counter: String, CaseIterable, Sendable {
        case httpRequests = "aaru_http_requests_total"
        case imports = "aaru_imports_total"
        case scrobbles = "aaru_scrobbles_total"
        case push = "aaru_push_total"
        case llmCalls = "aaru_llm_calls_total"

        var help: String {
            switch self {
            case .httpRequests: "HTTP requests by method, route template and status code."
            case .imports: "Import jobs that finished, by source and result (planned or failed)."
            case .scrobbles: "Playback reports received, by player."
            case .push: "Push sends by channel (apns, web, live_activity) and result."
            case .llmCalls: "Model calls by provider and result."
            }
        }
    }

    /// Upper bounds in seconds: Prometheus's default buckets.
    static let durationBuckets: [Double] = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]

    private struct Histogram {
        var buckets = [UInt64](repeating: 0, count: Metrics.durationBuckets.count)
        var sum: Double = 0
        var count: UInt64 = 0
    }

    private struct State {
        /// Counter → rendered label set (`{a="b"}`) → value.
        var counters: [Counter: [String: UInt64]] = [:]
        /// Request duration by route group.
        var durations: [String: Histogram] = [:]
        var inFlight = 0
    }

    private let state = Mutex(State())

    init() {}

    func increment(_ counter: Counter, _ labels: KeyValuePairs<String, String> = [:]) {
        let key = Self.render(labels)
        state.withLock { $0.counters[counter, default: [:]][key, default: 0] += 1 }
    }

    func requestStarted() {
        state.withLock { $0.inFlight += 1 }
    }

    /// `route` is Hummingbird's matched template (`/v1/titles/{id}`); nil, or its `NotFound`, when
    /// nothing matched.
    func requestFinished(method: String, route: String?, status: Int, duration: Duration) {
        let route = route.flatMap { $0 == "NotFound" ? nil : $0 } ?? "unmatched"
        let labels = Self.render(["method": method, "route": route, "code": String(status)])
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        let group = Self.group(route)
        state.withLock { state in
            state.inFlight -= 1
            state.counters[.httpRequests, default: [:]][labels, default: 0] += 1
            var histogram = state.durations[group] ?? Histogram()
            if let index = Self.durationBuckets.firstIndex(where: { seconds <= $0 }) {
                histogram.buckets[index] += 1
            }
            histogram.sum += seconds
            histogram.count += 1
            state.durations[group] = histogram
        }
    }

    /// The first segment after `/v1` (`titles`, `library`, `imports`…), or the first segment of a
    /// path outside it (`stremio`, `oauth`). Keeps the histogram to a few dozen series.
    static func group(_ route: String) -> String {
        if route == "unmatched" {
            return route
        }
        var segments = route.split(separator: "/").map(String.init)
        if segments.first == "v1" {
            segments.removeFirst()
        }
        return segments.first ?? "root"
    }

    /// Prometheus text exposition format 0.0.4, sorted so a scrape is stable.
    func render() -> String {
        let state = state.withLock { $0 }
        var out = ""
        for counter in Counter.allCases {
            out += "# HELP \(counter.rawValue) \(counter.help)\n# TYPE \(counter.rawValue) counter\n"
            for (labels, value) in (state.counters[counter] ?? [:]).sorted(by: { $0.key < $1.key }) {
                out += "\(counter.rawValue)\(labels) \(value)\n"
            }
        }
        out += "# HELP aaru_http_in_flight HTTP requests being handled now.\n# TYPE aaru_http_in_flight gauge\n"
        out += "aaru_http_in_flight \(state.inFlight)\n"
        let name = "aaru_http_request_duration_seconds"
        out += "# HELP \(name) Time spent handling a request, by route group.\n# TYPE \(name) histogram\n"
        for (group, histogram) in state.durations.sorted(by: { $0.key < $1.key }) {
            var cumulative: UInt64 = 0
            for (bound, count) in zip(Self.durationBuckets, histogram.buckets) {
                cumulative += count
                out += "\(name)_bucket\(Self.render(["group": group, "le": Self.number(bound)])) \(cumulative)\n"
            }
            out += "\(name)_bucket\(Self.render(["group": group, "le": "+Inf"])) \(histogram.count)\n"
            out += "\(name)_sum\(Self.render(["group": group])) \(Self.number(histogram.sum))\n"
            out += "\(name)_count\(Self.render(["group": group])) \(histogram.count)\n"
        }
        return out
    }

    private static func render(_ labels: KeyValuePairs<String, String>) -> String {
        guard !labels.isEmpty else { return "" }
        let pairs = labels.map { "\($0.key)=\"\(escaped($0.value))\"" }
        return "{" + pairs.joined(separator: ",") + "}"
    }

    private static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func number(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int64(value)) : String(value)
    }
}
