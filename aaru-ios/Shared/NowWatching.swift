#if os(iOS)
    import AaruCore
    import ActivityKit
    import Foundation

    /// The "Now watching" Live Activity (WID-005): one episode the user started by hand, on the
    /// Lock Screen and in the Dynamic Island, with progress, "Ends at" / "left", and Mark watched.
    /// Local only, with no push: what players report goes to the combined "Now playing"
    /// activity (SCR-009), and starting either ends the other. It draws with the same renderer,
    /// as a one-row `NowPlayingActivityState`.
    extension NowWatchingAttributes: @retroactive ActivityAttributes {
        public typealias ContentState = NowWatchingContent
    }

    extension NowWatchingAttributes {
        /// The episode as the one row the Now playing renderer draws.
        func activityState(_ content: NowWatchingContent) -> NowPlayingActivityState {
            NowPlayingActivityState(
                items: [NowPlayingActivityItem(
                    id: libraryItemId, kind: .episode, title: title, subtitle: episodeLine,
                    startedAt: content.startedAt, endsAt: content.endsAt, pausedAt: content.pausedAt,
                    watched: content.watched, libraryItemId: libraryItemId, season: season, episode: episode,
                    artworkURL: posterURL
                )],
                showsEndTime: content.showsEndTime
            )
        }
    }

    /// Starting, flipping and ending the activity. Only one runs at a time.
    enum NowWatching {
        /// How long past the episode's end (or the pause) an activity may stay before it is ended.
        static let grace: TimeInterval = 30 * 60
        static let fallbackRuntime = 45

        static var current: Activity<NowWatchingAttributes>? {
            Activity<NowWatchingAttributes>.activities.first
        }

        /// Starts watching an episode, ending any other activity, "Now playing" too. The poster
        /// is fetched and downsampled into the App Group first: the Lock Screen view cannot load
        /// from the network.
        static func start(_ attributes: NowWatchingAttributes, now: Date = .now) async throws {
            await endAll(dismissal: .immediate)
            await NowPlayingActivity.endAll(dismissal: .immediate)
            if let posterURL = attributes.posterURL {
                await NowPlayingArtwork.store([posterURL])
            }
            let endsAt = now.addingTimeInterval(TimeInterval(attributes.runtimeMinutes) * 60)
            let state = NowWatchingContent(startedAt: now, endsAt: endsAt, showsEndTime: true, watched: false)
            _ = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: aliveUntil(state)),
                pushType: nil
            )
        }

        static func toggleEndTime() async {
            guard let activity = current else { return }
            var state = activity.content.state
            state.showsEndTime.toggle()
            await activity.update(ActivityContent(state: state, staleDate: activity.content.staleDate))
        }

        /// Called after an episode is ticked anywhere: the matching activity shows "Watched" for a
        /// moment, then goes, and the episode's row in "Now playing" reads "Watched".
        static func episodeWatched(libraryItemId: String, season: Int, episode: Int) async {
            for activity in Activity<NowWatchingAttributes>.activities
                where activity.attributes.matches(libraryItemId: libraryItemId, season: season, episode: episode)
            {
                var state = activity.content.state
                state.watched = true
                await activity.end(
                    ActivityContent(state: state, staleDate: nil),
                    dismissalPolicy: .after(.now.addingTimeInterval(8))
                )
            }
            await NowPlayingActivity.watched(libraryItemId: libraryItemId) {
                $0.season == season && $0.episode == episode
            }
        }

        /// A whole season ticked: any activity for an episode of it ends.
        static func seasonWatched(libraryItemId: String, season: Int) async {
            for activity in Activity<NowWatchingAttributes>.activities
                where activity.attributes.libraryItemId == libraryItemId && activity.attributes.season == season
            {
                await episodeWatched(libraryItemId: libraryItemId, season: season, episode: activity.attributes.episode)
            }
            await NowPlayingActivity.watched(libraryItemId: libraryItemId) { $0.season == season }
        }

        /// Activities never outlive runtime + grace: run when the app comes forward and in the
        /// background refresh. A paused one stays until the pause is that old.
        static func endStale(now: Date = .now) async {
            for activity in Activity<NowWatchingAttributes>.activities
                where aliveUntil(activity.content.state) <= now
            {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }

        /// When an activity in this state is stale: the episode's end, or the pause if later, plus
        /// the grace.
        static func aliveUntil(_ state: NowWatchingContent) -> Date {
            max(state.endsAt, state.pausedAt ?? state.endsAt).addingTimeInterval(grace)
        }

        static func endAll(dismissal: ActivityUIDismissalPolicy = .immediate) async {
            for activity in Activity<NowWatchingAttributes>.activities {
                await activity.end(nil, dismissalPolicy: dismissal)
            }
        }
    }
#endif
