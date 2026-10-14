import AaruAPI

/// What the app shares with every screen: the session and the `/v1` client bound to it.
@MainActor
final class AppServices {
    let session: SessionStore
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
    }
}
