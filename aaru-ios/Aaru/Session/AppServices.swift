import AaruAPI
import WidgetKit

/// What the app shares with every screen: the session, the `/v1` client bound to it, and the
/// signed-in user's library.
@MainActor
final class AppServices {
    let session: SessionStore
    /// Where the app is: the destination, Settings' page, and menu-bar requests.
    let router = AppRouter()
    let library = LibraryModel()
    /// AI sharing (PRV-002): the user's yes or no to Aaru sending their data to its AI provider.
    let aiSharing: AISharingModel
    /// The Assistant card's Chat (ASK-009), one for the whole app.
    let assistant: AssistantModel
    let lists: ListsModel
    let imports: ImportsModel
    /// The models behind Settings' pages.
    let settings: SettingsServices
    let groups: GroupsModel
    /// Level, streak, badges and the unlock toast (GAM-001…005), read after every library write.
    let progress: ProgressModel
    /// Aaru Plus (BIL-004): the entitlement and the App Store's products.
    let plus: PlusModel
    /// The `/v1/ws` socket (GRP-006): open while signed in and active.
    let realtime: RealtimeClient
    #if os(iOS)
        let push: PushRegistrar
        /// Live Activity push tokens (SCR-008), followed from launch.
        let liveActivities: LiveActivityRegistrar
    #endif
    /// `nil` only when the build has no API host configured.
    let api: Client?
    /// Everyone's photos (SOC-001b), read through `api` and kept by URL.
    let avatars: AvatarLoader

    init() {
        let session = SessionStore()
        self.session = session
        api = AppEnvironment.apiBaseURL.map { baseURL in
            Client.aaru(
                baseURL: baseURL,
                session: SessionMiddleware(
                    token: { await session.token },
                    onUnauthorized: { await session.sessionWasRejected() }
                )
            )
        }
        let aiSharing = AISharingModel(api: api)
        self.aiSharing = aiSharing
        assistant = AssistantModel(api: api, library: library, aiSharing: aiSharing)
        avatars = AvatarLoader(api: api)
        lists = ListsModel(api: api)
        imports = ImportsModel(api: api)
        settings = SettingsServices(api: api)
        realtime = RealtimeClient(baseURL: AppEnvironment.apiBaseURL) { session.token }
        groups = GroupsModel(api: api, realtime: realtime)
        let progress = ProgressModel(api: api)
        self.progress = progress
        plus = PlusModel(api: api)
        #if os(iOS)
            push = PushRegistrar(api: api)
            PushRegistrar.current = push
            liveActivities = LiveActivityRegistrar(api: api)
            LiveActivityRegistrar.current = liveActivities
        #endif
        library.onWrite = { progress.refreshSoon() }
    }

    /// What Settings' pages need, for the Mac Settings scene (the main window builds its own).
    /// Signing out (or deleting the account) here resets the models itself: with the main window
    /// closed, no `RootView` is there to see the session change.
    var settingsContext: SettingsContext {
        let flow = AuthFlow(api: api, session: session)
        return SettingsContext(
            api: api, imports: imports, models: settings, library: library, lists: lists,
            onSignOut: { [weak self] in
                Task {
                    await flow.signOut()
                    self?.signedOut()
                }
            },
            onDeleteAccount: { [weak self] in
                let problem = await flow.deleteAccount()
                if problem == nil {
                    self?.signedOut()
                }
                return problem
            }
        )
    }

    /// A signed-out device keeps nothing of the last user's data. Every reset is safe to run
    /// twice: the Mac's Settings scene and `RootView` may both call this for one sign-out.
    func signedOut() {
        library.reset()
        aiSharing.reset()
        Task { await assistant.reset() }
        lists.reset()
        imports.reset()
        settings.reset()
        groups.reset()
        progress.reset()
        plus.reset()
        realtime.reset()
        router.reset()
        HomeCache().clear()
        WidgetSnapshotStore.clear()
        WidgetCenter.shared.reloadAllTimelines()
        #if os(iOS)
            Task {
                await NowWatching.endAll()
                await NowPlayingActivity.endAll()
                NowPlayingArtwork.clear()
            }
        #endif
    }
}
