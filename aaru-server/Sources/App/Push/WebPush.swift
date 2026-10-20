import Foundation
import Logging
import WebPush

/// Sends one alert to one browser subscription (RFC 8030, encrypted per RFC 8291, signed with
/// VAPID per RFC 8292). Named for the wire format, not a vendor: every browser's push service
/// speaks it.
protocol WebPushSending: Sendable {
    /// The VAPID public key (base64url) a browser subscribes with.
    var publicKey: String { get }
    func send(_ message: PushMessage, to subscription: WebPushSubscription) async throws -> PushOutcome
}

/// The real sender over `swift-webpush`. Its manager joins the app's `ServiceGroup`, so in-flight
/// sends finish on shutdown.
struct WebPushSender: WebPushSending {
    let manager: WebPushManager
    /// Where a tap lands when the browser opens the alert itself (declarative push).
    static let webApp = URL(string: "https://aaruapp.com")!

    var publicKey: String {
        manager.nextVAPIDKeyID.description
    }

    init(configurationJSON: String, logger: Logger) throws {
        let configuration = try JSONDecoder().decode(VAPID.Configuration.self, from: Data(configurationJSON.utf8))
        manager = WebPushManager(vapidConfiguration: configuration, backgroundActivityLogger: logger)
    }

    func send(_ message: PushMessage, to subscription: WebPushSubscription) async throws -> PushOutcome {
        let subscriber = try Self.subscriber(subscription)
        let path = message.payload["libraryItemId"].map { "/app/title/\($0)" } ?? "/app"
        let notification = WebPush.PushMessage.Notification(
            destination: Self.webApp.appending(path: path),
            title: message.title,
            body: message.body,
            // The service worker opens this path on its own origin, so the staging web app stays put.
            data: AlertData(path: path)
        )
        do {
            try await manager.send(notification: notification, to: subscriber)
            return .sent
        } catch is BadSubscriberError {
            return .deadToken
        }
    }

    private static func subscriber(_ subscription: WebPushSubscription) throws -> Subscriber {
        guard let endpoint = URL(string: subscription.endpoint) else { throw BadSubscriberError() }
        // VAPID.Key.ID has no public initialiser; it decodes from its string form.
        let keyID = try JSONDecoder().decode(VAPID.Key.ID.self, from: JSONEncoder().encode(subscription.vapidKeyID))
        return try Subscriber(
            endpoint: endpoint,
            userAgentKeyMaterial: UserAgentKeyMaterial(
                publicKey: subscription.p256dh,
                authenticationSecret: subscription.auth
            ),
            vapidKeyID: keyID
        )
    }
}

/// What the service worker reads from an alert.
struct AlertData: Codable, Hashable, Sendable {
    var path: String
}

/// Which endpoints a browser may hand us. The server POSTs to whatever is saved, so only the
/// browsers' own push services are accepted (no request forgery against anything else).
enum WebPushEndpoints {
    static let hosts = ["fcm.googleapis.com", "updates.push.services.mozilla.com", "web.push.apple.com"]
    static let suffixes = [".push.apple.com", ".push.services.mozilla.com", ".notify.windows.com"]

    static func isAllowed(_ endpoint: String) -> Bool {
        guard endpoint.count <= 2048, let url = URL(string: endpoint), url.scheme == "https",
              url.user == nil, url.port == nil, let host = url.host()?.lowercased()
        else { return false }
        return hosts.contains(host) || suffixes.contains { host.hasSuffix($0) }
    }
}
