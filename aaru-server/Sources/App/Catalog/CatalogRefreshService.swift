import Foundation
import Logging
import ServiceLifecycle

/// Keeps tracked shows' episodes current (JOB-001's second kind). The hydration timestamps
/// are the queue: each pass loads shows nobody has loaded yet (imports, a provider outage
/// at add time), then shows past their CAT-006 window. Title detail still hydrates on read.
struct CatalogRefresher: Sendable {
    /// Shows per pass. Each costs one TMDB call per season, so this stays well inside TMDB's
    /// limit while user traffic shares it.
    var passLimit = 40
    /// A show whose refresh was attempted this recently is skipped.
    static let retryAfter: TimeInterval = 60 * 60

    let stores: Stores
    let catalog: CatalogService
    var now: @Sendable () -> Date = { Date() }

    /// Refreshes one batch and returns how many shows were attempted.
    func runOnce() async throws -> Int {
        let now = now()
        let due = try await stores.titles.staleTrackedShows(
            now: now, retryAfter: now.addingTimeInterval(-Self.retryAfter), limit: passLimit
        )
        for id in due {
            try Task.checkCancellation()
            // Stamped first: a show the provider no longer knows would otherwise come back every pass.
            try await stores.titles.markEpisodesAttempted(id, at: now)
            _ = try? await catalog.detail(id)
        }
        return due.count
    }
}

/// Runs the catalog refresher every five minutes in the API process.
struct CatalogRefreshService: Service {
    let refresher: CatalogRefresher
    let logger: Logger
    var interval: Duration = .seconds(300)

    func run() async throws {
        try await cancelWhenGracefulShutdown {
            while !Task.isCancelled {
                do {
                    let attempted = try await refresher.runOnce()
                    if attempted > 0 {
                        logger.info("Show episodes refreshed", metadata: ["count": "\(attempted)"])
                    }
                } catch is CancellationError {
                    return
                } catch {
                    logger.error("Show refresh pass failed", metadata: ["error": "\(error)"])
                }
                try? await Task.sleep(for: interval)
            }
        }
    }
}
