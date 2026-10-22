import AaruCore
import Foundation
import Hummingbird
import HummingbirdTesting
import Logging
import Synchronization
import Testing
@testable import aaru

/// Sentry error reports and PostHog product events: what leaves the server, and that nothing
/// does without configuration. Stub transports only; no real DSN or token.
@Suite("Telemetry", .serialized)
struct TelemetryTests {
    private static let testDSN = "https://publickey@o1.ingest.de.sentry.io/42"
    private static let logger = Logger(label: "aaru-tests")

    private static func ok() -> StubTransport {
        StubTransport { _ in OutboundResponse(status: 200, body: Data()) }
    }

    @Test("a DSN becomes the envelope endpoint; anything else turns reports off", arguments: [
        ("", nil), ("not a dsn", nil), ("https://o1.ingest.de.sentry.io/42", nil),
        ("https://publickey@o1.ingest.de.sentry.io/", nil),
        (testDSN, "https://o1.ingest.de.sentry.io/api/42/envelope/"),
    ])
    func dsn(dsn: String, endpoint: String?) {
        let reporter = SentryReporter(dsn: dsn, environment: "test", release: nil, transport: Self.ok())
        #expect(reporter?.endpoint.absoluteString == endpoint)
    }

    @Test("a 5xx reaches Sentry with the route template and nothing from the request")
    func serverError() async throws {
        struct Leaky: Error, CustomStringConvertible {
            var description: String {
                "secret-text from the user"
            }
        }
        let transport = Self.ok()
        let reporter = try #require(
            SentryReporter(dsn: Self.testDSN, environment: "test", release: "abc123", transport: transport)
        )
        let router = Router()
        router.addMiddleware { ErrorMiddleware(sentry: reporter) }
        router.get("/v1/titles/:id") { _, _ -> String in throw Leaky() }
        router.get("/v1/missing") { _, _ -> String in throw HTTPError(.notFound) }
        try await Application(router: router).test(.router) { client in
            try await client.execute(
                uri: "/v1/missing", method: .get
            ) { #expect($0.status == .notFound) }
            try await client.execute(
                uri: "/v1/titles/0b6a2f63-id?q=private", method: .get,
                headers: [.authorization: "Bearer session-token", .cookie: "aaru_session=cookie"]
            ) { #expect($0.status == .internalServerError) }
        }
        for _ in 0 ..< 100 where transport.requests.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        let sent = try #require(transport.requests.first)
        #expect(transport.requests.count == 1, "a 404 is not reported")
        #expect(sent.url.absoluteString == "https://o1.ingest.de.sentry.io/api/42/envelope/")
        #expect(sent.headers.contains { $0.1.contains("sentry_key=publickey") })
        let data = try #require(sent.body)
        let body = String(bytes: data, encoding: .utf8) ?? ""
        for leak in ["0b6a2f63", "private", "session-token", "cookie", "secret-text"] {
            #expect(!body.contains(leak), "\(leak) left the server")
        }
        let lines = body.split(separator: "\n")
        #expect(lines.count == 3)
        let event = try #require(JSONSerialization.jsonObject(with: Data(lines[2].utf8)) as? [String: Any])
        #expect(event["user"] == nil)
        #expect(event["request"] == nil)
        #expect(event["release"] as? String == "abc123")
        #expect(event["environment"] as? String == "test")
        let tags = try #require(event["tags"] as? [String: String])
        #expect(tags["http.route"] == "/v1/titles/{id}")
        #expect(tags["http.status_code"] == "500")
    }

    @Test("PostHog gets the event, the account id and only the allowed properties")
    func postHog() async throws {
        let transport = Self.ok()
        let client = try PostHogClient(
            projectToken: "phc_test", host: #require(URL(string: "https://eu.i.posthog.com")), transport: transport,
            logger: Self.logger
        )
        let user = UserID(UUID())
        client.capture(.accountCreated, userID: user, properties: ["provider": "apple"])
        await client.flush()
        #expect(client.pending.isEmpty)
        let sent = try #require(transport.requests.first)
        #expect(sent.url.absoluteString == "https://eu.i.posthog.com/batch/")
        let data = try #require(sent.body)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["api_key"] as? String == "phc_test")
        let event = try #require((body["batch"] as? [[String: Any]])?.first)
        #expect(event["event"] as? String == "account_created")
        #expect(event["distinct_id"] as? String == user.rawValue.uuidString.lowercased())
        let properties = try #require(event["properties"] as? [String: Any])
        #expect(Set(properties.keys) == ["provider", "$process_person_profile", "$geoip_disable", "$lib"])
        #expect(properties["$process_person_profile"] as? Bool == false)
        #expect(properties["$geoip_disable"] as? Bool == true)
    }

    @Test("nothing is sent without configuration")
    func unconfigured() {
        #expect(makeSentryReporter(nil, transport: Self.ok(), logger: Self.logger) == nil)
        #expect(makePostHogClient(nil, transport: Self.ok(), logger: Self.logger) == nil)
    }

    @Test("creating a list counts the list and the library action, after the write")
    func events() async throws {
        let sink = RecordingSink()
        ProductEvents.install(sink)
        defer { ProductEvents.install(nil) }
        try await withMigratedStores { stores in
            let auth = AuthService(stores: stores, apple: UntouchedAppleVerifier(), magicLinks: nil)
            let services = Services.make(stores: stores, catalogs: FakeCatalog.providers(FakeCatalog()), auth: auth)
            let (user, _) = try await signedInUser(stores)
            _ = try await services.lists.create(name: "Weekend", userID: user)
            let events = sink.events(for: user)
            #expect(events.contains { $0.0 == .listCreated && $0.1.isEmpty })
            #expect(events.contains { $0.0 == .libraryAction && $0.1 == ["kind": "list", "actor": "user"] })
            #expect(events.allSatisfy { !$0.1.values.contains("Weekend") })
        }
    }
}

/// Keeps what was captured, per account, so other suites running at once do not interfere.
private final class RecordingSink: AnalyticsSink {
    private struct Captured {
        var userID: UserID
        var event: ProductEvent
        var properties: [String: String]
    }

    private let captured = Mutex<[Captured]>([])

    func capture(_ event: ProductEvent, userID: UserID, properties: [String: String]) {
        captured.withLock { $0.append(Captured(userID: userID, event: event, properties: properties)) }
    }

    func events(for user: UserID) -> [(ProductEvent, [String: String])] {
        captured.withLock { $0.filter { $0.userID == user }.map { ($0.event, $0.properties) } }
    }
}
