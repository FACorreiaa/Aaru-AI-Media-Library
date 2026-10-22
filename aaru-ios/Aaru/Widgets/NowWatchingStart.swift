#if os(iOS)
    import AaruCore
    import ActivityKit
    import Foundation

    /// Starting "Now watching" from the app (WID-005): title detail's episode menu and Home's
    /// Continue watching card, and Home's Now playing for a scrobble (SCR-008).
    @MainActor
    enum NowWatchingStart {
        /// Scrobble sessions already given a Live Activity, or seen with one, so an activity the
        /// user swiped away is not started again on the next poll.
        private static var followedSessions: Set<String> = []

        /// Returns a problem to show, or nil when the activity started.
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

        /// Starts "Now watching" for an episode a player started, when the server's push has not
        /// already. Once per session, and silent: the user did not ask for it.
        static func follow(_ playing: NowPlaying, now: Date) async {
            guard !followedSessions.contains(playing.watchEventId),
                  case let (attributes, content)? = playing.liveActivity(
                      now: now, fallbackMinutes: NowWatching.fallbackRuntime
                  ),
                  let watchEventId = attributes.watchEventId
            else { return }
            followedSessions.insert(playing.watchEventId)
            guard NowWatching.activity(watchEventId: watchEventId) == nil,
                  ActivityAuthorizationInfo().areActivitiesEnabled
            else { return }
            try? await NowWatching.startFromScrobble(attributes, content: content)
        }

        /// The episode's runtime, or the fallback when the catalog has none.
        static func runtime(_ minutes: Int?) -> Int {
            minutes.flatMap { $0 > 0 ? $0 : nil } ?? NowWatching.fallbackRuntime
        }
    }
#endif
