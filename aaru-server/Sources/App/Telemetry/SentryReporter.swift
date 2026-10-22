import Foundation
import Logging

/// Sends server errors (5xx) to Sentry's envelope endpoint. There is no Sentry SDK for Swift on
/// Linux, and an event is one POST, so this speaks the wire format itself.
///
/// What an event holds is what `docs/privacy.md` promises: the error's type, the route template
/// and the operation, the status, the release. Never the path with its ids, a query, a header, a
/// body, the error's text (a decoding or database error can quote what the user sent) or who
/// the user is.
struct SentryReporter: Sendable {
    let endpoint: URL
    let publicKey: String
    let environment: String
    let release: String?
    let transport: any HTTPTransport

    /// Nil, so reporting is off, when `dsn` is empty or not a Sentry DSN
    /// (`https://<key>@<host>/<project id>`).
    init?(dsn: String, environment: String, release: String?, transport: any HTTPTransport) {
        guard let url = URL(string: dsn.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme, let host = url.host, let key = url.user, !key.isEmpty
        else { return nil }
        let project = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !project.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = url.port
        components.path = "/api/\(project)/envelope/"
        guard let endpoint = components.url else { return nil }
        self.endpoint = endpoint
        publicKey = key
        self.environment = environment
        self.release = release?.nilIfBlank
        self.transport = transport
    }

    /// One failed request. `route` is the matched template (`/v1/titles/{id}`), never the path.
    struct Failure: Sendable, Equatable {
        var errorType: String
        var code: String
        var status: Int
        var method: String
        var route: String
        var operation: String?
        var provider: String?
    }

    /// Fire and forget: reporting never slows or fails the request it is about.
    func report(_ failure: Failure, logger: Logger) {
        Task.detached(priority: .utility) {
            do {
                let response = try await transport.send(request(for: failure))
                if response.status >= 300 {
                    logger.warning("Sentry refused an error report", metadata: ["status": "\(response.status)"])
                }
            } catch {
                logger.debug("Sentry error report failed", metadata: ["errorType": "\(type(of: error))"])
            }
        }
    }

    func request(for failure: Failure, now: Date = Date()) throws -> OutboundRequest {
        let eventID = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let timestamp = now.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        var tags = [
            "http.method": failure.method,
            "http.route": failure.route,
            "http.status_code": String(failure.status),
            "code": failure.code,
        ]
        tags["operation"] = failure.operation
        tags["provider"] = failure.provider
        var event: [String: Any] = [
            "event_id": eventID,
            "timestamp": timestamp,
            "platform": "other",
            "level": "error",
            "logger": "aaru-server",
            "environment": environment,
            "server_name": "aaru-api",
            "transaction": "\(failure.method) \(failure.route)",
            "exception": ["values": [["type": failure.errorType, "value": "\(failure.status) \(failure.code)"]]],
            "tags": tags,
        ]
        event["release"] = release
        let header: [String: Any] = ["event_id": eventID, "sent_at": timestamp]
        let lines = try [header, ["type": "event"], event].map {
            try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys, .withoutEscapingSlashes])
        }
        return OutboundRequest(
            method: "POST",
            url: endpoint,
            headers: [
                ("content-type", "application/x-sentry-envelope"),
                ("x-sentry-auth", "Sentry sentry_version=7, sentry_client=aaru-server/1.0, sentry_key=\(publicKey)"),
            ],
            body: Data(lines.joined(separator: Data("\n".utf8))),
            timeout: .seconds(5)
        )
    }
}

/// Error reports, or nil (with a notice) when `SENTRY_DSN` is unset or not a DSN.
func makeSentryReporter(_ settings: SentrySettings?, transport: any HTTPTransport, logger: Logger) -> SentryReporter? {
    guard let settings else {
        logger.notice("Error reports disabled: SENTRY_DSN is not set")
        return nil
    }
    guard let reporter = SentryReporter(
        dsn: settings.dsn, environment: settings.environment, release: settings.release, transport: transport
    ) else {
        logger.error("Error reports disabled: SENTRY_DSN is not a Sentry DSN")
        return nil
    }
    return reporter
}
