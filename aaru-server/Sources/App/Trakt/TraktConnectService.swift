import AaruCore
import Crypto
import Foundation

/// IMP-002: connect a Trakt account with PKCE. The verifier never leaves the server; the
/// tokens are stored sealed; the browser only ever carries a one-time `state` and `code`.
struct TraktConnectService: Sendable {
    static let requestLifetime: TimeInterval = 10 * 60

    let stores: Stores
    let settings: TraktSettings?
    let api: TraktAPI?
    var now: @Sendable () -> Date = { Date() }

    struct Status: Sendable {
        var connected: Bool
        var username: String?
        var connectedAt: Date?
    }

    private func enabled() throws -> (TraktSettings, TraktAPI) {
        guard let settings, let api else {
            throw AppError(
                status: .serviceUnavailable, code: "trakt_unavailable",
                message: "Trakt is not available on this server yet."
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
        try await stores.trakt.createAuthRequest(
            stateHash: OpaqueToken.hash(state),
            request: TraktAuthRequest(userID: userID, codeVerifier: verifier, returnTo: returnTo),
            expiresAt: now().addingTimeInterval(Self.requestLifetime)
        )
        var components = URLComponents(url: TraktSettings.authorizeURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: settings.clientID),
            URLQueryItem(name: "redirect_uri", value: settings.redirectURI.absoluteString),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        guard let url = components?.url else { throw AppError(
            status: .internalServerError,
            code: "internal",
            message: ""
        ) }
        return url
    }

    /// Trakt's redirect back. Returns where to send the browser next, with `trakt=` telling the
    /// app how it went. An unknown or expired `state` is refused outright.
    func callback(code: String?, state: String?, error: String?) async throws -> URL {
        let (settings, api) = try enabled()
        guard let state, let request = try await stores.trakt.consumeAuthRequest(
            stateHash: OpaqueToken.hash(state), now: now()
        ) else {
            throw AppError(
                status: .badRequest, code: "trakt_state_invalid",
                message: "This Trakt sign-in expired or was already used. Start again from Aaru."
            )
        }
        guard error == nil, let code else { return Self.returning(request.returnTo, result: "denied") }
        do {
            let tokens = try await api.exchange(code: code, verifier: request.codeVerifier)
            let username = try? await api.username(token: tokens.accessToken)
            try await save(tokens, username: username, userID: request.userID, settings: settings)
            return Self.returning(request.returnTo, result: "connected")
        } catch {
            return Self.returning(request.returnTo, result: "failed")
        }
    }

    func status(userID: UserID) async throws -> Status {
        guard let connection = try await stores.trakt.connection(userID: userID)
        else { return Status(connected: false) }
        return Status(connected: true, username: connection.username, connectedAt: connection.connectedAt)
    }

    /// Revokes the tokens on Trakt first, which frees one of the user's Trakt app slots (free
    /// accounts get two). Best effort: forgetting the tokens here is what disconnects.
    func disconnect(userID: UserID) async throws {
        if let settings, let api, let connection = try await stores.trakt.connection(userID: userID),
           let token = try? settings.tokenCipher.open(connection.sealedAccessToken)
        {
            try? await api.revoke(token)
        }
        try await stores.trakt.deleteConnection(userID: userID)
    }

    /// A usable access token, refreshed first when it expires within the hour. Nil when the
    /// user has not connected Trakt. Trakt's refresh tokens are single use, so the refresh runs
    /// with the connection locked and a caller that waited reuses the token the first one got.
    /// A refresh Trakt refuses means the user must connect again (`.unauthorized`).
    func accessToken(userID: UserID) async throws -> String? {
        let (settings, api) = try enabled()
        guard let connection = try await stores.trakt.connection(userID: userID) else { return nil }
        if isFresh(connection) {
            return try settings.tokenCipher.open(connection.sealedAccessToken)
        }
        let refreshed = try await stores.trakt.refreshConnection(userID: userID) { current in
            if isFresh(current) {
                return current
            }
            let tokens: TraktAPI.Tokens
            do {
                tokens = try await api.refresh(settings.tokenCipher.open(current.sealedRefreshToken))
            } catch let error as ProviderError where error.kind == .refused(400) {
                throw ProviderError(provider: error.provider, kind: .unauthorized) // invalid_grant
            }
            return try record(tokens, username: current.username, connectedAt: current.connectedAt, settings: settings)
        }
        return try refreshed.map { try settings.tokenCipher.open($0.sealedAccessToken) }
    }

    private func isFresh(_ connection: TraktConnectionRecord) -> Bool {
        connection.expiresAt > now().addingTimeInterval(60 * 60)
    }

    private func save(
        _ tokens: TraktAPI.Tokens,
        username: String?,
        userID: UserID,
        settings: TraktSettings
    ) async throws {
        try await stores.trakt.saveConnection(
            record(tokens, username: username, connectedAt: now(), settings: settings), userID: userID
        )
    }

    /// Trakt says how long the token lives (24 hours or 7 days, it has changed); trust that.
    private func record(
        _ tokens: TraktAPI.Tokens,
        username: String?,
        connectedAt: Date,
        settings: TraktSettings
    ) throws -> TraktConnectionRecord {
        try TraktConnectionRecord(
            sealedAccessToken: settings.tokenCipher.seal(tokens.accessToken),
            sealedRefreshToken: settings.tokenCipher.seal(tokens.refreshToken),
            expiresAt: now().addingTimeInterval(TimeInterval(tokens.expiresIn)),
            username: username,
            connectedAt: connectedAt
        )
    }

    static func returning(_ base: String, result: String) -> URL {
        var components = URLComponents(string: base) ?? URLComponents()
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "trakt", value: result)]
        return components.url ?? URL(string: "aaru://")!
    }
}
