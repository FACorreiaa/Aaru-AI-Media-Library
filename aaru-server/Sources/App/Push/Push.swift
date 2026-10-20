import APNS
import APNSCore
import Crypto
import Foundation
import NIOPosix

/// APNs credentials: one token-based key (`.p8`) signs for both apps and both gateways.
struct PushSettings: Sendable {
    var keyID: String
    var teamID: String
    /// The `.p8` contents (PEM). Sealed in `aaru-env`, never on disk in the image.
    var privateKeyPEM: String
}

/// The bundle ids a device may register for: Release and Beta are separate APNs topics.
enum PushTopics {
    static let allowed: Set<String> = ["com.fernandocorreia.aaru", "com.fernandocorreia.aaru.beta"]
}

struct PushMessage: Sendable, Equatable {
    var title: String
    var body: String
    /// Read by the app to open the right screen.
    var payload: [String: String]
}

enum PushOutcome: Sendable, Equatable {
    case sent
    /// Apple will never deliver to this token again; forget it.
    case deadToken
}

protocol PushSending: Sendable {
    func send(_ message: PushMessage, to device: PushDevice) async throws -> PushOutcome
}

/// The real sender: one APNs client per gateway, so Xcode builds (sandbox) and TestFlight or App
/// Store builds (production) reach the same API.
struct APNSPushSender: PushSending {
    let sandbox: APNSClient<JSONDecoder, JSONEncoder>
    let production: APNSClient<JSONDecoder, JSONEncoder>

    /// Reasons Apple gives for a token that is gone for good.
    static let deadReasons: Set<String> = ["BadDeviceToken", "Unregistered", "DeviceTokenNotForTopic"]

    init(settings: PushSettings) throws {
        let key = try P256.Signing.PrivateKey(pemRepresentation: settings.privateKeyPEM)
        func client(_ environment: APNSEnvironment) -> APNSClient<JSONDecoder, JSONEncoder> {
            APNSClient(
                configuration: APNSClientConfiguration(
                    authenticationMethod: .jwt(
                        privateKey: key, keyIdentifier: settings.keyID, teamIdentifier: settings.teamID
                    ),
                    environment: environment
                ),
                eventLoopGroupProvider: .shared(MultiThreadedEventLoopGroup.singleton),
                responseDecoder: JSONDecoder(),
                requestEncoder: JSONEncoder()
            )
        }
        sandbox = client(.development)
        production = client(.production)
    }

    func send(_ message: PushMessage, to device: PushDevice) async throws -> PushOutcome {
        let notification = APNSAlertNotification(
            alert: APNSAlertNotificationContent(
                title: .raw(message.title), body: .raw(message.body), sound: .default
            ),
            expiration: .none,
            priority: .immediately,
            topic: device.topic,
            payload: message.payload
        )
        let client = device.environment == .production ? production : sandbox
        do {
            _ = try await client.sendAlertNotification(notification, deviceToken: device.token)
            return .sent
        } catch let error as APNSError {
            if let reason = error.reason?.reason, Self.deadReasons.contains(reason) {
                return .deadToken
            }
            throw error
        }
    }
}

/// Announces newly aired episodes of shows a user is watching (2026-10-15 decision). Each episode
/// is claimed in Postgres before it is sent, so two replicas or a restart never send it twice.
struct AiringNotifier: Sendable {
    /// How far back a run looks: episodes that aired while the server was down still go out.
    static let window: TimeInterval = 2 * 24 * 60 * 60

    let stores: Stores
    /// Nil when no APNs key is configured: devices still register, nothing is sent.
    let sender: (any PushSending)?
    var now: @Sendable () -> Date = { Date() }

    /// One pass. Returns how many notifications went out.
    @discardableResult
    func runOnce() async throws -> Int {
        guard let sender else { return 0 }
        let due = try await stores.push.dueAirings(now: now(), since: now().addingTimeInterval(-Self.window))
        var sent = 0
        for airing in due where try await stores.push.claim(airing) {
            let message = Self.message(airing)
            for device in try await stores.push.devices(userID: airing.userID) {
                switch try? await sender.send(message, to: device) {
                case .sent?: sent += 1
                case .deadToken?: try await stores.push.forget(token: device.token)
                case nil: continue // one failing device does not stop the others
                }
            }
        }
        return sent
    }

    static func message(_ airing: DueAiring) -> PushMessage {
        let episode = "S\(airing.season) E\(airing.episode)"
        let body = airing.episodeName.map { "\(episode) · “\($0)” is out" } ?? "\(episode) is out"
        return PushMessage(
            title: airing.title,
            body: body,
            payload: [
                "titleId": airing.titleID.description,
                "libraryItemId": airing.libraryItemID.description,
                "season": String(airing.season),
                "episode": String(airing.episode),
            ]
        )
    }
}
