import AaruAPI
import Foundation
import Observation

typealias NotificationSettings = Components.Schemas.NotificationSettings

/// Settings → Notifications: the three alerts, per account (GET/PATCH /v1/me/notifications). The
/// same switches on every platform; on iPhone, turning one on also asks the system and registers
/// this device (`PushRegistrar`). The Mac shows them too: alerts go to the iPhone and browsers.
@MainActor
@Observable
final class NotificationsModel {
    private(set) var settings = NotificationSettings(airing: false, groupMentions: false, groupInvites: false)
    private(set) var hasLoaded = false
    var problem: String?

    @ObservationIgnored private let api: Client?

    init(api: Client?) {
        self.api = api
    }

    func load() async {
        guard let api else { return }
        do {
            if case let .ok(response) = try await api.getNotificationSettings() {
                settings = try response.body.json
                hasLoaded = true
                #if os(iOS)
                    await PushRegistrar.current?.refreshRegistration(for: settings)
                #endif
            }
        } catch {
            problem = "Your notification settings could not be loaded. Aaru could not reach the server."
        }
    }

    /// Turns one alert on or off. On iPhone, on asks the system first; a refusal leaves it off.
    func set(_ setting: WritableKeyPath<NotificationSettings, Bool>, _ enabled: Bool) async {
        guard let api else { return }
        problem = nil
        #if os(iOS)
            if enabled, await PushRegistrar.current?.requestAuthorization() == false {
                problem = "Notifications are off for Aaru. Turn them on in the Settings app, then try again."
                return
            }
        #endif
        var update = Components.Schemas.NotificationSettingsUpdate()
        switch setting {
        case \.airing: update.airing = enabled
        case \.groupMentions: update.groupMentions = enabled
        default: update.groupInvites = enabled
        }
        do {
            switch try await api.updateNotificationSettings(body: .json(update)) {
            case let .ok(response):
                settings = try response.body.json
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "That was not saved."
            }
        } catch {
            problem = "That was not saved. Aaru could not reach the server."
        }
    }

    func reset() {
        settings = NotificationSettings(airing: false, groupMentions: false, groupInvites: false)
        hasLoaded = false
        problem = nil
    }
}
