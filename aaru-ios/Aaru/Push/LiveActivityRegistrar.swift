#if os(iOS)
    import AaruAPI
    import AaruCore
    import ActivityKit
    import Foundation
    import UIKit

    /// Hands ActivityKit's push tokens to the API (SCR-008, SCR-009) so the server can start the
    /// combined "Now playing" activity when the first thing starts playing, and update and end it
    /// as rows come, pause, tick and go: the device's push-to-start token, and the running
    /// activity's own token. Runs from launch, so a background launch for a pushed-in activity
    /// still sends its token; best effort, so a failed upload (signed out, offline) waits for the
    /// next token. The by-hand "Now watching" activity has no push and is not followed.
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
            for await token in Activity<NowPlayingActivityAttributes>.pushToStartTokenUpdates {
                await upload(token, kind: .start)
            }
        }

        /// The activities already running, then each new one, whether the app or a push started it.
        /// Each is followed in its own task by id: an `Activity` does not cross tasks.
        private func followActivities() async {
            await withTaskGroup(of: Void.self) { group in
                for id in Activity<NowPlayingActivityAttributes>.activities.map(\.id) {
                    group.addTask { await self.follow(activityID: id, isNew: false) }
                }
                for await activity in Activity<NowPlayingActivityAttributes>.activityUpdates {
                    let id = activity.id
                    group.addTask { await self.follow(activityID: id, isNew: true) }
                }
            }
        }

        /// One activity: its token goes up first, then a new one ends every other Aaru activity
        /// (one shows at a time; the newest stays, so two arriving together never end each other)
        /// and gets its art, since a push carries URLs only; then the token goes up each time it
        /// changes, and the art is fetched for each state that arrives while the app runs. Token
        /// first: a push-started activity wakes the app for seconds only, and until the server has
        /// the token it can neither update nor end the activity.
        private func follow(activityID: String, isNew: Bool) async {
            guard let activity = Self.activity(activityID) else { return }
            let sent = activity.pushToken
            if let sent {
                await upload(sent, kind: .update)
            }
            if isNew {
                let running = Activity<NowPlayingActivityAttributes>.activities
                if running.last?.id == activity.id {
                    for other in running where other.id != activity.id {
                        await other.end(nil, dismissalPolicy: .immediate)
                    }
                }
                await NowWatching.endAll(dismissal: .immediate)
            }
            await NowPlayingArtwork.store(for: activity.content.state)
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    guard let activity = Self.activity(activityID) else { return }
                    for await token in activity.pushTokenUpdates where token != sent {
                        await self.upload(token, kind: .update)
                    }
                }
                group.addTask {
                    guard let activity = Self.activity(activityID) else { return }
                    for await content in activity.contentUpdates {
                        await NowPlayingArtwork.store(for: content.state)
                    }
                }
            }
        }

        private static func activity(_ id: String) -> Activity<NowPlayingActivityAttributes>? {
            Activity<NowPlayingActivityAttributes>.activities.first { $0.id == id }
        }

        private func upload(
            _ token: Data,
            kind: Components.Schemas.LiveActivityRegistration.KindPayload
        ) async {
            guard let api else { return }
            let hex = token.map { String(format: "%02x", $0) }.joined()
            #if DEBUG
                let environment = Components.Schemas.LiveActivityRegistration.EnvironmentPayload.sandbox
            #else
                let environment = Components.Schemas.LiveActivityRegistration.EnvironmentPayload.production
            #endif
            let registration = Components.Schemas.LiveActivityRegistration(
                token: hex, kind: kind, environment: environment, bundleId: Bundle.main.bundleIdentifier ?? ""
            )
            // A background wake can end mid-request: ask for the time to finish this one.
            let time = await BackgroundTime(named: "Live Activity token")
            _ = try? await api.registerLiveActivityToken(body: .json(registration))
            await time.end()
        }
    }

    /// Extra background time from iOS while one upload finishes; ended early when iOS asks.
    @MainActor private final class BackgroundTime {
        private var id = UIBackgroundTaskIdentifier.invalid

        init(named name: String) {
            id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in self?.end() }
        }

        func end() {
            guard id != .invalid else { return }
            UIApplication.shared.endBackgroundTask(id)
            id = .invalid
        }
    }
#endif
