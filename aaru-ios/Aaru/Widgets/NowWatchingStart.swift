#if os(iOS)
    import ActivityKit
    import Foundation

    /// Starting "Now watching" from the app (WID-005): title detail's episode menu and Home's
    /// Continue watching card. Returns a problem to show, or nil when the activity started.
    enum NowWatchingStart {
        static func start(_ attributes: NowWatchingAttributes) async -> String? {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                return "Live Activities are off for Aaru. Turn them on in Settings → Aaru."
            }
            do {
                try await NowWatching.start(attributes)
                return nil
            } catch {
                return "Aaru could not start the Live Activity. Try again."
            }
        }

        /// The episode's runtime, or the fallback when the catalog has none.
        static func runtime(_ minutes: Int?) -> Int {
            minutes.flatMap { $0 > 0 ? $0 : nil } ?? NowWatching.fallbackRuntime
        }
    }
#endif
