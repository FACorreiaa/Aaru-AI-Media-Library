import Foundation
import Sentry

/// Crash, hang and error reports to Sentry (`docs/privacy.md`, "Error reports"). Off when the
/// build has no DSN (Debug, a fresh clone) and under tests.
///
/// Errors only: no performance tracing, no session replay, no screenshots or view hierarchy, no
/// breadcrumbs (they would carry request URLs and screen names), and nothing about the user.
enum CrashReporting {
    static func start() {
        guard let dsn = Bundle.main.object(forInfoDictionaryKey: "AaruSentryDSN") as? String, !dsn.isEmpty,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        else { return }
        let environment = Bundle.main.object(forInfoDictionaryKey: "AaruSentryEnvironment") as? String
        SentrySDK.start { options in
            options.dsn = dsn
            options.environment = environment.flatMap { $0.isEmpty ? nil : $0 } ?? "production"
            options.sendDefaultPii = false
            options.tracesSampleRate = 0
            options.enableAutoPerformanceTracing = false
            options.enableAutoBreadcrumbTracking = false
            options.enableNetworkBreadcrumbs = false
            options.enableCaptureFailedRequests = false
            #if os(iOS)
                // UIKit-only options; macOS never attaches either.
                options.attachScreenshot = false
                options.attachViewHierarchy = false
            #endif
            options.enableAppHangTracking = true
            options.beforeSend = { event in
                event.user = nil
                event.request = nil
                event.breadcrumbs = nil
                return event
            }
        }
    }
}
