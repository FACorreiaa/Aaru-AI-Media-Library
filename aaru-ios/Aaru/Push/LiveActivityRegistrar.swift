#if os(iOS)
    import AaruAPI
    import AaruCore
    import ActivityKit
    import Foundation

    /// Hands ActivityKit's push tokens to the API (SCR-008) so the server can start "Now watching"
    /// when a scrobble starts, and update and end it as the player pauses, resumes and stops: the
    /// device's push-to-start token, and each scrobble activity's own token with the watch event
    /// it follows. Runs from launch, so a background launch for a pushed-in activity still sends
    /// its token; best effort, so a failed upload (signed out, offline) waits for the next token.
    final class LiveActivityRegistrar: Sendable {
        /// Set once at launch, like `PushRegistrar.current`.
        @MainActor static var current: LiveActivityRegistrar?

        private let api: Client?
        /// The one follower. A second start replaces it rather than running beside it.
        @MainActor private var following: Task<Void, Never>?

        init(api: Client?) {
            self.api = api
        }

        /// Follows the tokens from now on, in place of any earlier follower. The app delegate
        /// starts it at launch and the signed-in root again on sign-in: a fresh follow yields
        /// the current tokens again, so they go up with the new session.
        @MainActor func start() {
            guard api != nil else { return }
            following?.cancel()
            following = Task { await self.follow() }
        }

        private func follow() async {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.followPushToStart() }
                group.addTask { await self.followActivities() }
            }
        }

        private func followPushToStart() async {
            for await token in Activity<NowWatchingAttributes>.pushToStartTokenUpdates {
                await upload(token, kind: .start, watchEventId: nil)
            }
        }

        /// The activities already running, then each new one, whether the app or a push started it.
        /// Each is followed in its own task by id: an `Activity` does not cross tasks.
        private func followActivities() async {
            await withTaskGroup(of: Void.self) { group in
                for id in Activity<NowWatchingAttributes>.activities.map(\.id) {
                    group.addTask { await self.follow(activityID: id, isNew: false) }
                }
                for await activity in Activity<NowWatchingAttributes>.activityUpdates {
                    let id = activity.id
                    group.addTask { await self.follow(activityID: id, isNew: true) }
                }
            }
        }

        /// One scrobble activity: a new one ends any other (one runs at a time) and gets its
        /// poster, since a push cannot carry one; then its token goes up each time it changes.
        private func follow(activityID: String, isNew: Bool) async {
            guard let activity = Activity<NowWatchingAttributes>.activities.first(where: { $0.id == activityID }),
                  let watchEventId = activity.attributes.watchEventId
            else { return }
            if isNew {
                for other in Activity<NowWatchingAttributes>.activities where other.id != activity.id {
                    await other.end(nil, dismissalPolicy: .immediate)
                }
                if NowWatchingArtwork.load(for: activity.attributes.posterURL) == nil {
                    await NowWatching.storeArtwork(for: activity.attributes)
                }
            }
            for await token in activity.pushTokenUpdates {
                await upload(token, kind: .update, watchEventId: watchEventId)
            }
        }

        private func upload(
            _ token: Data,
            kind: Components.Schemas.LiveActivityRegistration.KindPayload,
            watchEventId: UUID?
        ) async {
            guard let api else { return }
            let hex = token.map { String(format: "%02x", $0) }.joined()
            #if DEBUG
                let environment = Components.Schemas.LiveActivityRegistration.EnvironmentPayload.sandbox
            #else
                let environment = Components.Schemas.LiveActivityRegistration.EnvironmentPayload.production
            #endif
            let registration = Components.Schemas.LiveActivityRegistration(
                token: hex, kind: kind, watchEventId: watchEventId?.uuidString.lowercased(),
                environment: environment, bundleId: Bundle.main.bundleIdentifier ?? ""
            )
            _ = try? await api.registerLiveActivityToken(body: .json(registration))
        }
    }
#endif
