#if os(iOS)
    import AaruCore
    import ActivityKit
    import Foundation

    /// Starting the Live Activities from the app: "Now watching" by hand from title detail's
    /// episode menu and Home's Continue watching card (WID-005), and "Now playing" for what
    /// players report when Home sees it before the server's push did (SCR-009).
    @MainActor
    enum NowWatchingStart {
        /// Items already given an activity, or seen with one running, so an activity the user
        /// swiped away is not started again on the next poll; only something new starts one.
        private static var followedItems: Set<String> = []

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

        /// Follows what plays now. With "Now playing" running, the server keeps it current and
        /// only the art is saved; without one, it starts for the items, once per item, silently:
        /// the user did not ask for it.
        static func follow(_ items: [NowPlayingItem]) async {
            guard !items.isEmpty else { return }
            let state = NowPlayingActivityState(
                items: items.prefix(NowPlayingActivityState.maxItems).map(\.activityItem)
            )
            let ids = Set(state.items.map(\.id))
            guard NowPlayingActivity.current == nil else {
                followedItems.formUnion(ids)
                await NowPlayingArtwork.store(for: state)
                await NowPlayingActivity.storeArtwork()
                return
            }
            guard !ids.isSubset(of: followedItems) else { return }
            followedItems.formUnion(ids)
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            try? await NowPlayingActivity.start(state)
        }

        /// The episode's runtime, or the fallback when the catalog has none.
        static func runtime(_ minutes: Int?) -> Int {
            minutes.flatMap { $0 > 0 ? $0 : nil } ?? NowWatching.fallbackRuntime
        }
    }
#endif
