import AaruCore
import Foundation
import Logging
import ServiceLifecycle
import Synchronization

/// The product events Aaru's server counts (`docs/privacy.md` "Product counts"). Each carries
/// the account's random id and a few fixed words, never a title, a name, an email or text.
enum ProductEvent: String, Sendable {
    /// `provider`: apple, google, email.
    case accountCreated = "account_created"
    /// `source`, `result` (planned, failed).
    case importCompleted = "import_completed"
    /// `kind` (add, update, remove, list, tv, import, undo), `actor` (user, agent, external_agent).
    case libraryAction = "library_action"
    case listCreated = "list_created"
    case groupCreated = "group_created"
    case friendAdded = "friend_added"
    /// `decision`: approved, denied.
    case agentPlanDecided = "agent_plan_decided"
    /// The Tonight strip showed at least one pick, once per local day (AG-005).
    case tonightShown = "tonight_shown"
    /// Progress landed on a pick within six hours of it showing; once per local day.
    case tonightAccepted = "tonight_accepted"
    /// `verdict`: rejected, not_tonight.
    case tonightRejected = "tonight_rejected"
    /// `kind`: text, image, url (AG-006).
    case captureSubmitted = "capture_submitted"
    /// `decision`: approved (applied), denied (a planned capture deleted).
    case capturePlanDecided = "capture_plan_decided"
    /// `reason`: capture_quota. The server refused and the apps offer Plus.
    case paywallShown = "paywall_shown"
    /// `product`: the App Store product id. The first time a subscription is seen active.
    case plusPurchased = "plus_purchased"
}

/// Where product events go. `PostHogClient` in production; nothing until one is installed.
protocol AnalyticsSink: Sendable {
    /// Never blocks and never throws: counting must not slow or fail a request.
    func capture(_ event: ProductEvent, userID: UserID, properties: [String: String])
}

/// The process-wide seam call sites use, so none of them knows whether PostHog is configured.
enum ProductEvents {
    private static let sink = Mutex<(any AnalyticsSink)?>(nil)

    static func install(_ newSink: (any AnalyticsSink)?) {
        sink.withLock { $0 = newSink }
    }

    static func capture(_ event: ProductEvent, userID: UserID, _ properties: [String: String] = [:]) {
        sink.withLock { $0 }?.capture(event, userID: userID, properties: properties)
    }
}

/// One queued event, as PostHog's batch endpoint reads it.
struct PostHogEvent: Encodable, Sendable, Equatable {
    enum Value: Encodable, Sendable, Equatable {
        case string(String)
        case bool(Bool)

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case let .string(value): try container.encode(value)
            case let .bool(value): try container.encode(value)
            }
        }
    }

    var event: String
    var distinctID: String
    var timestamp: String
    var properties: [String: Value]

    enum CodingKeys: String, CodingKey {
        case event, timestamp, properties
        case distinctID = "distinct_id"
    }
}

private struct PostHogBatch: Encodable {
    var apiKey: String
    var batch: [PostHogEvent]

    enum CodingKeys: String, CodingKey {
        case batch
        case apiKey = "api_key"
    }
}

/// PostHog's batch capture API, spoken directly (its Swift SDK is Apple-only). `capture` queues;
/// the service posts every 10 seconds and drains the queue on shutdown. Best effort: a failed
/// post is logged and dropped, never retried.
final class PostHogClient: AnalyticsSink, Service, Sendable {
    let endpoint: URL
    private let projectToken: String
    private let transport: any HTTPTransport
    private let flushInterval: Duration
    private let logger: Logger
    private let queue = Mutex<[PostHogEvent]>([])
    static let maxQueue = 2000
    static let maxBatch = 100

    init(
        projectToken: String, host: URL, transport: any HTTPTransport, flushInterval: Duration = .seconds(10),
        logger: Logger
    ) {
        endpoint = host.appendingPathComponent("batch/")
        self.projectToken = projectToken
        self.transport = transport
        self.flushInterval = flushInterval
        self.logger = logger
    }

    func capture(_ event: ProductEvent, userID: UserID, properties: [String: String]) {
        var values = properties.mapValues(PostHogEvent.Value.string)
        // No person profile per account, and no location from the (server's) address.
        values["$process_person_profile"] = .bool(false)
        values["$geoip_disable"] = .bool(true)
        values["$lib"] = .string("aaru-server")
        let item = PostHogEvent(
            event: event.rawValue,
            distinctID: userID.rawValue.uuidString.lowercased(),
            timestamp: Date().formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)),
            properties: values
        )
        queue.withLock { queue in
            if queue.count < Self.maxQueue {
                queue.append(item)
            }
        }
    }

    var pending: [PostHogEvent] {
        queue.withLock { $0 }
    }

    func run() async throws {
        await cancelWhenGracefulShutdown {
            while !Task.isCancelled {
                do { try await Task.sleep(for: self.flushInterval) } catch { break }
                await self.flush()
            }
        }
        await flush()
    }

    func flush() async {
        while true {
            let batch = queue.withLock { queue in
                let batch = Array(queue.prefix(Self.maxBatch))
                queue.removeFirst(batch.count)
                return batch
            }
            guard !batch.isEmpty else { return }
            await post(batch)
            if batch.count < Self.maxBatch {
                return
            }
        }
    }

    private func post(_ batch: [PostHogEvent]) async {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            let body = try encoder.encode(PostHogBatch(apiKey: projectToken, batch: batch))
            let response = try await transport.send(OutboundRequest(
                method: "POST", url: endpoint, headers: [("content-type", "application/json")], body: body,
                timeout: .seconds(10)
            ))
            if response.status >= 300 {
                logger.warning("PostHog refused events", metadata: [
                    "status": "\(response.status)", "events": "\(batch.count)",
                ])
            }
        } catch {
            logger.warning("PostHog post failed", metadata: [
                "errorType": "\(type(of: error))", "events": "\(batch.count)",
            ])
        }
    }
}

/// Product events, or nil (with a notice) when `POSTHOG_PROJECT_TOKEN` is unset.
func makePostHogClient(_ settings: PostHogSettings?, transport: any HTTPTransport, logger: Logger) -> PostHogClient? {
    guard let settings else {
        logger.notice("Product events disabled: POSTHOG_PROJECT_TOKEN is not set")
        return nil
    }
    return PostHogClient(projectToken: settings.projectToken, host: settings.host, transport: transport, logger: logger)
}
