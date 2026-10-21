import AaruCore
import Foundation
import Logging

/// Keeps the "Now watching" Live Activity in step with scrobbles (SCR-008): a session's first
/// `start` starts it on every device by push, later reports update it, and the session's end
/// ends it. Best effort: a push outage never fails a scrobble.
struct NowPlayingNotifier: Sendable {
    /// How long past its end, or past a pause, an activity stays before it reads "Did you finish?".
    static let staleGrace: TimeInterval = 30 * 60
    /// How long a "Watched" activity stays on the Lock Screen.
    static let watchedLinger: TimeInterval = 8

    let stores: Stores
    let sender: any LiveActivityPushing
    var logger = Logger(label: "aaru-now-playing")

    /// The player started or paused `session`.
    func changed(_ session: OpenSession, title: Title, userID: UserID, now: Date) async {
        guard let attributes = Self.attributes(session, title: title) else { return }
        let content = NowPlaying.content(session, now: now)
        let staleDate = session.state == .paused
            ? now.addingTimeInterval(Self.staleGrace) : content.endsAt.addingTimeInterval(Self.staleGrace)
        do {
            let running = try await stores.watchEvents.liveActivityUpdateTokens(watchEventID: session.id)
            if !running.isEmpty {
                let push = LiveActivityPush(event: .update, content: content, staleDate: staleDate, timestamp: now)
                await deliver(push, to: running)
            } else if session.state == .playing,
                      try await stores.watchEvents.claimLiveActivityStart(session.id, at: now)
            {
                let push = LiveActivityPush(
                    event: .start(
                        attributes,
                        alertTitle: "Now playing",
                        alertBody: "\(title.title) · \(attributes.episodeLine)"
                    ),
                    content: content, staleDate: staleDate, timestamp: now
                )
                try await deliver(push, to: stores.watchEvents.liveActivityStartTokens(userID: userID))
            }
        } catch {
            logger.warning("Live Activity push failed", metadata: ["error": "\(error)"])
        }
    }

    /// `session` closed: by its stop, or because the player moved on. `watched` when it ticked.
    func ended(_ session: OpenSession, now: Date, watched: Bool) async {
        do {
            let running = try await stores.watchEvents.liveActivityUpdateTokens(watchEventID: session.id)
            guard !running.isEmpty else { return }
            let push = LiveActivityPush(
                event: .end(dismissal: watched ? now.addingTimeInterval(Self.watchedLinger) : now),
                content: NowPlaying.content(session, now: now, watched: watched), staleDate: nil, timestamp: now
            )
            await deliver(push, to: running)
        } catch {
            logger.warning("Live Activity end failed", metadata: ["error": "\(error)"])
        }
    }

    /// What the activity shows. Nil for a movie (the activity is per episode) or a title not in
    /// the library yet (its link opens the library item).
    static func attributes(_ session: OpenSession, title: Title) -> NowWatchingAttributes? {
        guard let item = session.libraryItemID, let episode = session.episode else { return nil }
        let runtime = session.knownDurationMs > 0
            ? Int((session.knownDurationMs + 59999) / 60000) : NowPlaying.fallbackRuntimeMinutes
        return NowWatchingAttributes(
            libraryItemId: item.description, title: title.title, season: episode.season, episode: episode.episode,
            episodeName: session.episodeName, posterURL: title.posterURL?.absoluteString,
            runtimeMinutes: runtime, watchEventId: session.id
        )
    }

    private func deliver(_ push: LiveActivityPush, to tokens: [LiveActivityToken]) async {
        for token in tokens {
            switch try? await sender.send(push, to: token) {
            case .deadToken?: try? await stores.watchEvents.forgetLiveActivity(token: token.token)
            case .sent?, nil: continue
            }
        }
    }
}
