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
    /// Nil when no APNs key is configured: no Live Activity pushes (SCR-008, SCR-009).
    var liveActivity: LiveSetNotifier?
    var logger = Logger(label: "aaru-scrobble")
    var now: @Sendable () -> Date = { Date() }

    @discardableResult
    func report(_ report: PlaybackReport, from caller: AgentCaller) async throws -> ScrobbleOutcome {
        try await record(report, from: caller).outcome
    }

    /// `report`, also naming the title it matched, so a player can show what Aaru heard (SCR-007).
    func record(
        _ report: PlaybackReport,
        from caller: AgentCaller
    ) async throws -> (outcome: ScrobbleOutcome, title: Title?) {
        Metrics.shared.increment(.scrobbles, ["source": report.source.rawValue, "action": report.action.rawValue])
        let now = now()
        let userID = caller.userID
        if report.action == .stop, try await stores.watchEvents.stoppedRecently(
            userID: userID, source: report.source, externalRef: report.externalRef,
            since: now.addingTimeInterval(-Self.repeatWindow)
        ) {
            return (.stoppedWithoutChange, nil)
        }
        let title = try await resolve(report)
        var ticked: [UUID] = []
        if report.action == .start {
            let open = try await stores.watchEvents.openSessions(userID: userID, source: report.source, limit: 10)
            for previous in open where previous.externalRef != report.externalRef {
                if try await moveOn(from: previous, caller: caller, now: now) {
                    ticked.append(previous.id)
                }
            }
        }
        let session = try await stores.watchEvents.record(
            report, titleID: title?.id, userID: userID, agentTokenID: caller.token.id, now: now
        )
        guard report.action == .stop else {
            await liveActivity?.sync(userID: userID, now: now, ticked: ticked)
            return (title == nil ? .unmatched : .recorded, title)
        }
        try await stores.watchEvents.close(session.id, at: now)
        let outcome = try await stop(session, title: title, report: report, caller: caller)
        await liveActivity?.sync(userID: userID, now: now, ticked: outcome == .watched ? [session.id] : [])
        return (outcome, title)
    }

    /// What a `stop` writes: the episode ticked or the movie finished at 80% or more.
    private func stop(
        _ session: WatchSession, title: Title?, report: PlaybackReport, caller: AgentCaller
    ) async throws -> ScrobbleOutcome {
        guard let title else {
            logger.info("Unmatched scrobble", metadata: [
                "source": "\(report.source.rawValue)", "agentToken": "\(caller.token.id)",
            ])
            return .unmatched
        }
        guard let progress = session.progress, progress >= Self.watchedThreshold else {
            return .stoppedWithoutChange
        }
        let episodes = try await episodes(of: title, in: report)
        return try await markWatched(title, episodes: episodes, caller: caller) ? .watched : .stoppedWithoutChange
    }

    /// The player started something else without stopping `previous` (Stremio's next episode):
    /// it closes, and ticks when the player last reported it at 80% or more. Only the reported
    /// position counts, so a player closed mid-episode never fakes a watch. Returns whether it ticked.
    private func moveOn(from previous: OpenSession, caller: AgentCaller, now: Date) async throws -> Bool {
        try await stores.watchEvents.close(previous.id, at: now)
        guard let progress = previous.reportedProgress, progress >= Self.watchedThreshold,
              let title = try await stores.titles.title(id: previous.titleID)
        else { return false }
        return try await markWatched(title, episodes: previous.episode.map { [$0] } ?? [], caller: caller)
    }

    /// What a player is playing for the user now (SCR-008), or nil.
    func nowPlaying(userID: UserID) async throws -> NowPlaying? {
        let sessions = try await stores.watchEvents.openSessions(userID: userID, source: nil, limit: 5)
        guard let live = NowPlaying.pick(sessions, now: now()),
              let title = try await stores.titles.title(id: live.titleID)
        else { return nil }
        return NowPlaying(session: live, title: title)
    }

    /// The title a report names. A report with no id names its title instead (SCR-007): matched
    /// only when exactly one catalog entry has the name.
    private func resolve(_ report: PlaybackReport) async throws -> Title? {
        guard report.titleID == nil, report.ids.isEmpty, let name = report.title else {
            return try await resolve(MediaRef(titleID: report.titleID, type: report.type, ids: report.ids))
        }
        if let year = report.year {
            return try await resolve(MediaRef(type: report.type, title: name, year: year))
        }
        return try await unlessUnknown { try await resolver.resolve(named: name, type: report.type) }
    }

    /// The title a ref names, hydrating it from the catalog when Aaru has not seen it yet; nil
    /// when nothing matches.
    func resolve(_ ref: MediaRef) async throws -> Title? {
        try await unlessUnknown { try await resolver.resolve(ref) }
    }

    /// nil when the catalog does not know the title, or knows more than one by that name.
    private func unlessUnknown(_ body: () async throws -> Title) async throws -> Title? {
        do {
            return try await body()
        } catch is ResolutionError {
            return nil
        } catch let error as ProviderError where error.kind == .notFound {
            return nil
        }
    }

    /// The episode a stop ticks: the number the player gave, else the one its name matches.
    private func episodes(of title: Title, in report: PlaybackReport) async throws -> [EpisodeKey] {
        if let episode = report.episode {
            return [episode]
        }
        guard let named = report.episodeName else { return [] }
        return try await resolver.episodes(of: title, named: [named])
    }

    /// Ticks the episodes (one action), or finishes the movie. A title not in the library is
    /// added first (in progress for a show, finished for a movie). Returns whether anything was
    /// written. A show with no episodes named writes nothing.
    func markWatched(_ title: Title, episodes: [EpisodeKey], caller: AgentCaller) async throws -> Bool {
        let agent = Caller.agent(caller.token)
        let ref = MediaRef(titleID: title.id, type: title.type)
        let existing = try await stores.library.item(userID: caller.userID, titleID: title.id)
        if title.type == .show {
            guard !episodes.isEmpty else { return false }
            let id: LibraryItemID
            if let existing {
                id = existing.id
            } else {
                id = try await library.add(ref, status: .inProgress, userID: caller.userID, by: agent).item.id
            }
            return try await library.setEpisodes(
                id, userID: caller.userID, keys: episodes, watched: true, by: agent
            ) != nil
        }
        guard title.type == .movie else { return false }
        guard let existing else {
            _ = try await library.add(ref, status: .finished, userID: caller.userID, by: agent)
            return true
        }
        guard existing.status != .finished else { return false }
        _ = try await library.patch(existing.id, userID: caller.userID, patch: ItemPatch(status: .finished), by: agent)
        return true
    }
}
