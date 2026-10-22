#if os(iOS)
    import AaruCore
    import ActivityKit
    import Foundation

    /// The "Now playing" Live Activity (SCR-009): one activity shows everything playing at once,
    /// up to three rows of episodes, movies, tracks and videos. The server starts, updates and
    /// ends it by push (`attributes-type: NowPlayingActivityAttributes`); the app starts it when it
    /// opens on something playing with no activity running, and the server then catches it up.
    /// The types live in AaruCore so the server encodes the same keys; ActivityKit matches a
    /// push-to-start on the type's name, so it stays `NowPlayingActivityAttributes`.
    extension NowPlayingActivityAttributes: @retroactive ActivityAttributes {
        public typealias ContentState = NowPlayingActivityState
    }

    /// Starting, ticking and ending the combined activity. Only one runs at a time, and never
    /// beside a "Now watching" one.
    enum NowPlayingActivity {
        /// How long past a row's end (or its pause) the activity may stay before it is ended.
        static let grace: TimeInterval = 30 * 60
        /// How long a row with no duration counts, as the server counts a playing session.
        static let unknownLength: TimeInterval = 3 * 60 * 60

        static var current: Activity<NowPlayingActivityAttributes>? {
            Activity<NowPlayingActivityAttributes>.activities.first
        }

        /// Starts the activity for what the app read, ending any other Aaru activity. It asks
        /// for a push token, which the registrar hands to the server so it can keep the rows
        /// current. The art is saved first: the Lock Screen view cannot load from the network.
        static func start(_ state: NowPlayingActivityState) async throws {
            await NowWatching.endAll(dismissal: .immediate)
            await endAll(dismissal: .immediate)
            await NowPlayingArtwork.store(for: state)
            _ = try Activity.request(
                attributes: NowPlayingActivityAttributes(),
                content: ActivityContent(state: state, staleDate: aliveUntil(state)),
                pushType: .token
            )
        }

        static func toggleEndTime() async {
            for activity in Activity<NowPlayingActivityAttributes>.activities {
                var state = activity.content.state
                state.showsEndTime.toggle()
                await activity.update(ActivityContent(state: state, staleDate: activity.content.staleDate))
            }
        }

        /// Called after a tick anywhere: the matching rows read "Watched" at once. The server's
        /// next push takes them away.
        static func watched(libraryItemId: String, where matches: (NowPlayingActivityItem) -> Bool) async {
            for activity in Activity<NowPlayingActivityAttributes>.activities {
                var state = activity.content.state
                var changed = false
                for index in state.items.indices
                    where state.items[index].libraryItemId == libraryItemId && !state.items[index].watched
                    && matches(state.items[index])
                {
                    state.items[index].watched = true
                    changed = true
                }
                if changed {
                    await activity.update(ActivityContent(state: state, staleDate: activity.content.staleDate))
                }
            }
        }

        /// Saves the running activity's art: the server's pushes carry URLs only.
        static func storeArtwork() async {
            guard let state = current?.content.state else { return }
            await NowPlayingArtwork.store(for: state)
        }

        /// The server ends the activity when nothing plays; this is the backstop for a push that
        /// never came, run when the app comes forward and in the background refresh.
        static func endStale(now: Date = .now) async {
            for activity in Activity<NowPlayingActivityAttributes>.activities
                where aliveUntil(activity.content.state) <= now
            {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }

        /// When an activity in this state is stale: the last row's end, or its pause if later,
        /// plus the grace.
        static func aliveUntil(_ state: NowPlayingActivityState) -> Date {
            let ends = state.items.map { item in
                let end = item.endsAt ?? item.startedAt.addingTimeInterval(unknownLength)
                return max(end, item.pausedAt ?? end)
            }
            return (ends.max() ?? .now).addingTimeInterval(grace)
        }

        static func endAll(dismissal: ActivityUIDismissalPolicy = .immediate) async {
            for activity in Activity<NowPlayingActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: dismissal)
            }
        }
    }
#endif
