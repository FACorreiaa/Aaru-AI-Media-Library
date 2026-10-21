import AaruAPI

/// What the app shares with every screen: the session, the `/v1` client bound to it, and the
/// signed-in user's library.
@MainActor
final class AppServices {
    let session: SessionStore
    let library = LibraryModel()
    let lists: ListsModel
    let imports: ImportsModel
    let groups: GroupsModel
    /// The `/v1/ws` socket (GRP-006): open while signed in and active.
    let realtime: RealtimeClient
    #if os(iOS)
        let push: PushRegistrar
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
        realtime = RealtimeClient(baseURL: AppEnvironment.apiBaseURL) { session.token }
        groups = GroupsModel(api: api, realtime: realtime)
        #if os(iOS)
            push = PushRegistrar(api: api)
            PushRegistrar.current = push
        #endif
    }
}
