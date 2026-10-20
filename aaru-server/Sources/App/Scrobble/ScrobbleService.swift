import AaruCore
import Foundation
import Logging

/// What a playback report did to the library.
enum ScrobbleOutcome: Sendable, Equatable {
    /// Session opened or updated; nothing written to the library.
    case recorded
    /// Stopped past the threshold and written (an episode ticked or a movie finished).
    case watched
    /// Stopped, but short of the threshold, already watched, or a repeat of a stop.
    case stoppedWithoutChange
    /// The player's id matched nothing Aaru knows; kept as an unmatched watch event.
    case unmatched
}

/// SCR-001 (service only): turns player reports into watch events, and a `stop` at 80% or
/// more into a library write through the same `LibraryService` path a tap uses, journaled with
/// the caller's agent token. `start` and `pause` never change progress.
struct ScrobbleService: Sendable {
    /// Aaru's own threshold, documented in ARCHITECTURE.md.
    static let watchedThreshold: Double = 80
    /// A second `stop` for the same item this soon after the first is a repeat, not a rewatch.
    static let repeatWindow: TimeInterval = 10 * 60

    let stores: Stores
    let library: LibraryService
    let resolver: TitleResolver
    var logger = Logger(label: "aaru-scrobble")
    var now: @Sendable () -> Date = { Date() }

    @discardableResult
    func report(_ report: PlaybackReport, from caller: AgentCaller) async throws -> ScrobbleOutcome {
        let now = now()
        let userID = caller.userID
        if report.action == .stop, try await stores.watchEvents.stoppedRecently(
            userID: userID, source: report.source, externalRef: report.externalRef,
            since: now.addingTimeInterval(-Self.repeatWindow)
        ) {
            return .stoppedWithoutChange
        }
        let title = try await resolve(MediaRef(titleID: report.titleID, type: report.type, ids: report.ids))
        let session = try await stores.watchEvents.record(
            report, titleID: title?.id, userID: userID, agentTokenID: caller.token.id, now: now
        )
        guard report.action == .stop else { return title == nil ? .unmatched : .recorded }
        try await stores.watchEvents.close(session.id, at: now)
        guard let title else {
            logger.info("Unmatched scrobble", metadata: [
                "source": "\(report.source.rawValue)", "agentToken": "\(caller.token.id)",
            ])
            return .unmatched
        }
        guard let progress = session.progress, progress >= Self.watchedThreshold else { return .stoppedWithoutChange }
        let wrote = try await markWatched(title, episodes: report.episode.map { [$0] } ?? [], caller: caller)
        return wrote ? .watched : .stoppedWithoutChange
    }

    /// The title a ref names, hydrating it from the catalog when Aaru has not seen it yet; nil
    /// when nothing matches.
    func resolve(_ ref: MediaRef) async throws -> Title? {
        do {
            return try await resolver.resolve(ref)
        } catch is ResolutionError {
            return nil
        } catch let error as ProviderError where error.kind == .notFound {
            return nil
        }
    }

    /// Ticks the episodes (one action), or finishes the movie. A title not in the library is
    /// added first (in progress for a show, finished for a movie). Returns whether anything was
    /// written. A show with no episodes named writes nothing.
    func markWatched(_ title: Title, episodes: [EpisodeKey], caller: AgentCaller) async throws -> Bool {
        let by = Caller.agent(caller.token)
        let ref = MediaRef(titleID: title.id, type: title.type)
        let existing = try await stores.library.item(userID: caller.userID, titleID: title.id)
        if title.type == .show {
            guard !episodes.isEmpty else { return false }
            let id: LibraryItemID
            if let existing {
                id = existing.id
            } else {
                id = try await library.add(ref, status: .inProgress, userID: caller.userID, by: by).item.id
            }
            return try await library.setEpisodes(
                id, userID: caller.userID, keys: episodes, watched: true, by: by
            ) != nil
        }
        guard title.type == .movie else { return false }
        guard let existing else {
            _ = try await library.add(ref, status: .finished, userID: caller.userID, by: by)
            return true
        }
        guard existing.status != .finished else { return false }
        _ = try await library.patch(existing.id, userID: caller.userID, patch: ItemPatch(status: .finished), by: by)
        return true
    }
}
