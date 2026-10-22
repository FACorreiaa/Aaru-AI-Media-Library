import AaruCore
import APNS
import APNSCore
import Foundation

/// One push to the "Now playing" Live Activity (SCR-008, SCR-009): start it on a device, or update
/// or end the one running there.
struct LiveActivityPush: Sendable, Equatable {
    enum Event: Sendable, Equatable {
        /// Push-to-start, with the alert the device shows as it appears.
        case start(alertTitle: String, alertBody: String)
        case update
        /// Ends the activity; it leaves the Lock Screen at `dismissal`.
        case end(dismissal: Date)
    }

    /// APNs' `apns-priority`: Apple budgets the immediate ones.
    enum Priority: Sendable, Equatable {
        case immediate
        case considerate
    }

    var event: Event
    var content: NowPlayingActivityState
    /// After this the activity reads as stale.
    var staleDate: Date?
    /// Apple drops a push older than the last one it delivered to the activity.
    var timestamp: Date
    var priority: Priority = .immediate
}

protocol LiveActivityPushing: Sendable {
    func send(_ push: LiveActivityPush, to token: LiveActivityToken) async throws -> PushOutcome
}

/// The type name ActivityKit matches a push-to-start against: the app's `NowPlayingActivityAttributes`.
private let attributesType = "NowPlayingActivityAttributes"

extension APNSPushSender: LiveActivityPushing {
    func send(_ push: LiveActivityPush, to token: LiveActivityToken) async throws -> PushOutcome {
        let client = token.environment == .production ? production : sandbox
        let timestamp = Int(push.timestamp.timeIntervalSince1970)
        let staleDate = push.staleDate.map { Int($0.timeIntervalSince1970) }
        let priority: APNSPriority = push.priority == .immediate ? .immediately : .consideringDevicePower
        do {
            switch push.event {
            case let .start(alertTitle, alertBody):
                _ = try await client.sendStartLiveActivityNotification(
                    APNSStartLiveActivityNotification(
                        expiration: .none, priority: priority, appID: token.topic,
                        contentState: push.content, timestamp: timestamp, staleDate: staleDate,
                        attributes: NowPlayingActivityAttributes(), attributesType: attributesType,
                        alert: APNSAlertNotificationContent(title: .raw(alertTitle), body: .raw(alertBody))
                    ),
                    pushToStartToken: token.token
                )
            case .update:
                _ = try await client.sendLiveActivityNotification(
                    APNSLiveActivityNotification(
                        expiration: .none, priority: priority, appID: token.topic,
                        contentState: push.content, event: .update, timestamp: timestamp, staleDate: staleDate
                    ),
                    deviceToken: token.token
                )
            case let .end(dismissal):
                _ = try await client.sendLiveActivityNotification(
                    APNSLiveActivityNotification(
                        expiration: .none, priority: priority, appID: token.topic,
                        contentState: push.content, event: .end, timestamp: timestamp,
                        dismissalDate: .date(dismissal)
                    ),
                    deviceToken: token.token
                )
            }
            return .sent
        } catch let error as APNSError {
            // An ended activity's token answers ExpiredToken.
            if let reason = error.reason?.reason, Self.deadReasons.contains(reason) || reason == "ExpiredToken" {
                return .deadToken
            }
            throw error
        }
    }
}
