import AaruAPI

/// What the app shares with every screen: the session, the `/v1` client bound to it, and the
/// signed-in user's library.
@MainActor
final class AppServices {
    let session: SessionStore
    /// Where the app is: the destination, Settings' page, and menu-bar requests.
    let router = AppRouter()
    let library = LibraryModel()
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
    var settingsContext: SettingsContext {
        let flow = AuthFlow(api: api, session: session)
        return SettingsContext(
            api: api, imports: imports, models: settings, library: library, lists: lists,
            onSignOut: { Task { await flow.signOut() } },
            onDeleteAccount: { await flow.deleteAccount() }
        )
    }
}
