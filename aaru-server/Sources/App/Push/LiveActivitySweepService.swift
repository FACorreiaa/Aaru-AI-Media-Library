import Foundation
import Logging
import ServiceLifecycle

/// Looks again at users whose "Now playing" activity is due to change with no report to say so
/// (SCR-009): a song that ended, a tab closed on a video, an episode past its end, a "Watched" row
/// done lingering. Each user's check is claimed, so two replicas never push the same change.
struct LiveActivitySweepService: Service {
    /// Nil when no APNs key is configured: there is no activity to keep.
    let notifier: LiveSetNotifier?
    let stores: Stores
    let logger: Logger
    var interval: Duration = .seconds(15)
    var now: @Sendable () -> Date = { Date() }

    func run() async throws {
        // Without APNs there is nothing to sweep, but returning would end the service group and
        // take the server down with it: wait for shutdown instead.
        guard let notifier else {
            try? await gracefulShutdown()
            return
        }
        try await cancelWhenGracefulShutdown {
            while !Task.isCancelled {
                do {
                    try await sweep(notifier)
                } catch is CancellationError {
                    return
                } catch {
                    logger.error("Live Activity sweep failed", metadata: ["error": "\(error)"])
                }
                try? await Task.sleep(for: interval)
            }
        }
    }

    func sweep(_ notifier: LiveSetNotifier) async throws {
        let now = now()
        for userID in try await stores.watchEvents.claimDueLiveActivityChecks(now: now, limit: 100) {
            await notifier.sync(userID: userID, now: now)
        }
    }
}
