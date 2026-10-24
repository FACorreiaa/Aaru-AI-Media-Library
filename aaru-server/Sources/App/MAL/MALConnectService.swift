import AaruCore
import Foundation

/// SCR-005: connect a MyAnimeList account. The same flow as Trakt's (`TraktConnectService`),
/// except MAL accepts only the `plain` PKCE method: the challenge is the verifier itself. The
/// tokens are stored sealed; the browser only ever carries a one-time `state` and `code`.
struct MALConnectService: Sendable {
    static let requestLifetime: TimeInterval = 10 * 60

    let stores: Stores
    let settings: MALSettings?
    let api: MALAPI?
    var now: @Sendable () -> Date = { Date() }

    struct Status: Sendable {
        var connected: Bool
        var username: String?
        var connectedAt: Date?
        /// MAL refused the tokens: the user must connect again before anything is pushed.
        var needsReconnect = false
        /// When the list was last read back (SCR-010).
        var pulledAt: Date?
        /// Entries removed on MAL that Aaru keeps.
        var removed: [MALRemovedEntry] = []
    }

    private func enabled() throws -> (MALSettings, MALAPI) {
        guard let settings, let api else {
            throw AppError(
                status: .serviceUnavailable, code: "mal_unavailable",
                message: "MyAnimeList is not available on this server yet."
            )
        }
        return (settings, api)
    }

    /// Starts a sign-in and returns where to send the browser.
    func start(userID: UserID, returnTo: String) async throws -> URL {
        let (settings, _) = try enabled()
        guard settings.allowsReturn(to: returnTo) else {
            throw AppError(
                status: .unprocessableContent, code: "validation_failed",
                message: "That return address is not allowed.", details: ["returnTo": "Not an Aaru address."]
            )
        }
        let state = OpaqueToken.generate()
        let verifier = PKCE.verifier()
        try await stores.mal.createAuthRequest(
            stateHash: OpaqueToken.hash(state),
            request: MALAuthRequest(userID: userID, codeVerifier: verifier, returnTo: returnTo),
            expiresAt: now().addingTimeInterval(Self.requestLifetime)
        )
        var components = URLComponents(url: MALSettings.authorizeURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: settings.clientID),
            URLQueryItem(name: "redirect_uri", value: settings.redirectURI.absoluteString),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: verifier),
            URLQueryItem(name: "code_challenge_method", value: "plain"),
        ]
        guard let url = components?.url else {
            throw AppError(status: .internalServerError, code: "internal", message: "")
        }
        return url
    }

    /// MAL's redirect back. Returns where to send the browser next, with `mal=` telling the app
    /// how it went. An unknown or expired `state` is refused outright.
    func callback(code: String?, state: String?, error: String?) async throws -> URL {
        let (settings, api) = try enabled()
        guard let state, let request = try await stores.mal.consumeAuthRequest(
            stateHash: OpaqueToken.hash(state), now: now()
        ) else {
            throw AppError(
                status: .badRequest, code: "mal_state_invalid",
                message: "This MyAnimeList sign-in expired or was already used. Start again from Aaru."
            )
        }
        guard error == nil, let code else { return Self.returning(request.returnTo, result: "denied") }
        do {
            let tokens = try await api.exchange(code: code, verifier: request.codeVerifier)
            let username = try? await api.username(token: tokens.accessToken)
            // Only writes from now on go out: connecting never overwrites the MAL list with the
            // library as it was.
            try await stores.mal.saveConnection(
                record(tokens, username: username, connectedAt: now(), settings: settings),
                cursor: now(), userID: request.userID
            )
            return Self.returning(request.returnTo, result: "connected")
        } catch {
            return Self.returning(request.returnTo, result: "failed")
        }
    }

    func status(userID: UserID) async throws -> Status {
        guard let connection = try await stores.mal.connection(userID: userID) else { return Status(connected: false) }
        return try await Status(
            connected: true, username: connection.username, connectedAt: connection.connectedAt,
            needsReconnect: connection.revokedAt != nil, pulledAt: connection.pulledAt,
            removed: stores.mal.removedEntries(userID: userID)
        )
    }

    /// A client opened Aaru (SCR-010): read this user's list on the next sync pass, unless it was
    /// read in the last 10 minutes. False when nothing was asked.
    @discardableResult
    func requestPull(userID: UserID) async throws -> Bool {
        let now = now()
        return try await stores.mal.requestPull(userID: userID, now: now, notBefore: now.addingTimeInterval(-600))
    }

    /// MAL has no revoke endpoint: forgetting the tokens here is what disconnects. The user can
    /// also remove Aaru under MAL's Account Settings → API.
    func disconnect(userID: UserID) async throws {
        try await stores.mal.deleteConnection(userID: userID)
    }

    /// A usable access token, refreshed first when it expires within the hour. Nil when the user
    /// has not connected MAL or MAL refused the tokens. A refresh MAL refuses marks the connection
    /// for reconnecting (`.unauthorized`).
    func accessToken(userID: UserID) async throws -> String? {
        let (settings, api) = try enabled()
        guard let connection = try await stores.mal.connection(userID: userID), connection.revokedAt == nil
        else { return nil }
        if isFresh(connection) {
            return try settings.tokenCipher.open(connection.sealedAccessToken)
        }
        let refreshed = try await stores.mal.refreshConnection(userID: userID) { current in
            if isFresh(current) {
                return current
            }
            let tokens: MALAPI.Tokens
            do {
                tokens = try await api.refresh(settings.tokenCipher.open(current.sealedRefreshToken))
            } catch let error as ProviderError where error.kind == .refused(400) {
                throw ProviderError(provider: error.provider, kind: .unauthorized) // invalid_grant
            }
            var next = try record(
                tokens,
                username: current.username,
                connectedAt: current.connectedAt,
                settings: settings
            )
            next.revokedAt = current.revokedAt
            return next
        }
        return try refreshed.map { try settings.tokenCipher.open($0.sealedAccessToken) }
    }

    private func isFresh(_ connection: MALConnectionRecord) -> Bool {
        connection.expiresAt > now().addingTimeInterval(60 * 60)
    }

    /// MAL says how long the token lives (31 days today, though its docs say an hour); trust that.
    private func record(
        _ tokens: MALAPI.Tokens,
        username: String?,
        connectedAt: Date,
        settings: MALSettings
    ) throws -> MALConnectionRecord {
        try MALConnectionRecord(
            sealedAccessToken: settings.tokenCipher.seal(tokens.accessToken),
            sealedRefreshToken: settings.tokenCipher.seal(tokens.refreshToken),
            expiresAt: now().addingTimeInterval(TimeInterval(tokens.expiresIn)),
            username: username,
            connectedAt: connectedAt
        )
    }

    static func returning(_ base: String, result: String) -> URL {
        var components = URLComponents(string: base) ?? URLComponents()
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "mal", value: result)]
        return components.url ?? URL(string: "aaru://")!
    }
}
