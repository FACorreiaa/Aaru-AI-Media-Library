import AaruAPI

/// What the app shares with every screen: the session, the `/v1` client bound to it, and the
/// signed-in user's library.
@MainActor
final class AppServices {
    let session: SessionStore
    let library = LibraryModel()
    let lists: ListsModel
    let imports: ImportsModel
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
    }
}
