#if os(iOS)
    import AaruAPI
    import Observation
    import UIKit
    import UserNotifications

    /// Airing-episode pushes on iOS: asks permission when the user turns the setting on, hands the
    /// APNs token to the API, and forgets it on sign-out. Mac push is not on yet.
    @MainActor
    @Observable
    final class PushRegistrar {
        /// The app delegate reaches the registrar through this; set once at launch.
        static var current: PushRegistrar?

        private(set) var airing = false
        var problem: String?

        @ObservationIgnored private let api: Client?
        @ObservationIgnored private let defaults = UserDefaults.standard
        private static let tokenKey = "push.deviceToken"

        init(api: Client?) {
            self.api = api
        }

        func loadSetting() async {
            guard let api, case let .ok(response) = try? await api.getNotificationSettings() else { return }
            airing = (try? response.body.json.airing) ?? false
            // Refresh the token each launch: Apple can rotate it.
            if airing,
               await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized
            {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }

        /// Turns airing alerts on or off. On asks the system first; a refusal leaves it off.
        func setAiring(_ enabled: Bool) async {
            guard let api else { return }
            problem = nil
            if enabled {
                let granted = (try? await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
                guard granted else {
                    problem = "Notifications are off for Aaru. Turn them on in the Settings app, then try again."
                    return
                }
                UIApplication.shared.registerForRemoteNotifications()
            }
            do {
                if case let .ok(response) = try await api
                    .updateNotificationSettings(body: .json(.init(airing: enabled)))
                {
                    airing = try response.body.json.airing
                }
            } catch {
                problem = "That was not saved. Aaru could not reach the server."
            }
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
            airing = false
        }
    }

    /// Receives the APNs token and shows alerts that arrive while the app is open.
    final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
        func application(
            _: UIApplication,
            didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
        ) -> Bool {
            UNUserNotificationCenter.current().delegate = self
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

        /// A tap on an airing alert opens the show it announced.
        nonisolated func userNotificationCenter(
            _: UNUserNotificationCenter,
            didReceive response: UNNotificationResponse
        ) async {
            let id = response.notification.request.content.userInfo["libraryItemId"] as? String
            await MainActor.run { PushInbox.shared.libraryItemID = id }
        }
    }
#endif
