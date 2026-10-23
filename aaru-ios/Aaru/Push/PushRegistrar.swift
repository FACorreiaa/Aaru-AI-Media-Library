#if os(iOS)
    import AaruAPI
    import UIKit
    import UserNotifications

    /// Pushes on iOS (airing episodes, group mentions and invites): asks the system's permission
    /// when the user turns an alert on, hands the APNs token to the API, and forgets it on
    /// sign-out. The switches themselves are `NotificationsModel`'s, on every platform.
    @MainActor
    final class PushRegistrar {
        /// The app delegate reaches the registrar through this; set once at launch.
        static var current: PushRegistrar?

        private let api: Client?
        private let defaults = UserDefaults.standard
        private static let tokenKey = "push.deviceToken"

        init(api: Client?) {
            self.api = api
        }

        /// Asks the system once; true when alerts may be shown. Registers for the APNs token.
        func requestAuthorization() async -> Bool {
            let granted = (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
            return granted
        }

        /// Refreshes the token when any alert is on: Apple can rotate it.
        func refreshRegistration(for settings: NotificationSettings) async {
            guard settings.airing || settings.groupMentions || settings.groupInvites,
                  await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized
            else { return }
            UIApplication.shared.registerForRemoteNotifications()
        }

        /// From the app delegate: the device's APNs token.
        func register(token: Data) async {
            guard let api else { return }
            let hex = token.map { String(format: "%02x", $0) }.joined()
            #if DEBUG
                let environment = Components.Schemas.DeviceRegistration.EnvironmentPayload.sandbox
            #else
                let environment = Components.Schemas.DeviceRegistration.EnvironmentPayload.production
            #endif
            let registration = Components.Schemas.DeviceRegistration(
                token: hex, environment: environment, bundleId: Bundle.main.bundleIdentifier ?? ""
            )
            if case .noContent = try? await api.registerDevice(body: .json(registration)) {
                defaults.set(hex, forKey: Self.tokenKey)
            }
        }

        /// Before signing out: this device should stop receiving the account's alerts.
        func forgetDevice() async {
            guard let api, let token = defaults.string(forKey: Self.tokenKey) else { return }
            _ = try? await api.unregisterDevice(path: .init(token: token))
            defaults.removeObject(forKey: Self.tokenKey)
        }
    }

    /// Receives the APNs token and shows alerts that arrive while the app is open. At launch it
    /// starts following Live Activity tokens: a push that starts "Now watching" launches the app
    /// in the background, where no signed-in view is built to do it.
    final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
        func application(
            _: UIApplication,
            didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
        ) -> Bool {
            UNUserNotificationCenter.current().delegate = self
            LiveActivityRegistrar.current?.start()
            return true
        }

        func application(_: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
            Task { @MainActor in await PushRegistrar.current?.register(token: token) }
        }

        nonisolated func userNotificationCenter(
            _: UNUserNotificationCenter,
            willPresent _: UNNotification
        ) async -> UNNotificationPresentationOptions {
            [.banner, .sound]
        }

        /// A tap on an airing alert opens the show it announced; one on an agent request or a
        /// capture's plan opens it; one on a mention opens its channel, and one on a group invite
        /// the Groups tab.
        nonisolated func userNotificationCenter(
            _: UNUserNotificationCenter,
            didReceive response: UNNotificationResponse
        ) async {
            let info = response.notification.request.content.userInfo
            let id = info["libraryItemId"] as? String
            let plan = info["planId"] as? String
            let capture = info["importId"] as? String
            let group = (info["url"] as? String).flatMap(URL.init(string:))
            await MainActor.run {
                PushInbox.shared.libraryItemID = id
                PushInbox.shared.planID = plan
                PushInbox.shared.importID = capture
                PushInbox.shared.groupLink = group
            }
        }
    }
#endif
