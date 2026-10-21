import Foundation
import Logging
import ServiceLifecycle

/// MUS-006 · identifies scrobbled tracks on MusicBrainz, each track and album once, so listens
/// gain their album's cover and a link to the album. Listens keep their own spelling; only ids
/// are filled, and never over ids a scrobbler sent.
struct ListenResolver: Sendable {
    /// Tracks per pass. Each is one MusicBrainz request at one a second, shared with album search.
    var passLimit = 30
    /// A track MusicBrainz could not place is asked again after a month: it may have been added.
    static let retryAfter: TimeInterval = 30 * 24 * 60 * 60

    let stores: Stores
    let recordings: any RecordingMatching
    var now: @Sendable () -> Date = { Date() }

    /// Looks up one batch. Returns how many tracks were asked about and how many listens gained
    /// an album. A provider failure ends the pass without recording a miss.
    func runOnce() async throws -> (tracks: Int, listens: Int) {
        let now = now()
        let due = try await stores.listens.unresolved(
            retryBefore: now.addingTimeInterval(-Self.retryAfter), limit: passLimit
        )
        var filled = 0
        for lookup in due {
            try Task.checkCancellation()
            let match = try await recordings.match(lookup.query)
            filled += try await stores.listens.resolve(lookup, as: match, at: now)
        }
        return (due.count, filled)
    }
}

/// Runs the listen resolver every minute in the API process.
struct ListenResolverService: Service {
    let resolver: ListenResolver
    let logger: Logger
    var interval: Duration = .seconds(60)

    func run() async throws {
        try await cancelWhenGracefulShutdown {
            while !Task.isCancelled {
                do {
                    let pass = try await resolver.runOnce()
                    if pass.tracks > 0 {
                        logger.info(
                            "Listens looked up",
                            metadata: ["tracks": "\(pass.tracks)", "listens": "\(pass.listens)"]
                        )
                    }
                } catch is CancellationError {
                    return
                } catch {
                    logger.error("Listen lookup pass failed", metadata: ["error": "\(error)"])
                }
                try? await Task.sleep(for: interval)
            }
        }
    }
}
