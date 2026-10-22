import Foundation
import Logging
import ServiceLifecycle

/// Evaluates badges the request path did not: imports and approved plans that failed inline,
/// retries after a failed after-write hook, and the first run over every existing user's
/// library (GAM-004). Leased like the import worker, so a crash leaves the user re-runnable.
struct GamificationWorker: Service {
    let gamification: GamificationService
    let logger: Logger
    var idle: Duration = .seconds(5)
    /// A pause between users, so a deploy's backfill never crowds out request traffic.
    var pace: Duration = .milliseconds(200)

    static let lease: TimeInterval = 120

    func run() async throws {
        try await cancelWhenGracefulShutdown {
            await workerLoops(1, idle: idle) {
                try await step()
            } failed: { error in
                logger.error("Gamification worker step failed", metadata: ["error": "\(error)"])
            }
        }
    }

    /// Seeds progress rows for users who have none, then evaluates one claimed user.
    func step() async throws -> Bool {
        let store = gamification.stores.gamification
        _ = try await store.seedProgress(limit: 100)
        guard let claimed = try await store.claimDirty(lease: Self.lease) else { return false }
        try await gamification.streakBonuses(claimed.userID)
        try await gamification.evaluate(claimed.userID, origin: claimed.origin, actionID: nil)
        try? await Task.sleep(for: pace)
        return true
    }
}
