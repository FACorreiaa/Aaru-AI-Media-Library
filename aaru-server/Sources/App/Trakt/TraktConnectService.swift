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

    func disconnect(userID: UserID) async throws {
        try await stores.trakt.deleteConnection(userID: userID)
    }

    /// A usable access token, refreshed first when it expires within the hour. Nil when the
    /// user has not connected Trakt.
    func accessToken(userID: UserID) async throws -> String? {
        let (settings, api) = try enabled()
        guard let connection = try await stores.trakt.connection(userID: userID) else { return nil }
        if connection.expiresAt > now().addingTimeInterval(60 * 60) {
            return try settings.tokenCipher.open(connection.sealedAccessToken)
        }
        let refresh = try settings.tokenCipher.open(connection.sealedRefreshToken)
        let tokens = try await api.refresh(refresh)
        try await save(tokens, username: connection.username, userID: userID, settings: settings)
        return tokens.accessToken
    }

    private func save(
        _ tokens: TraktAPI.Tokens,
        username: String?,
        userID: UserID,
        settings: TraktSettings
    ) async throws {
        try await stores.trakt.saveConnection(TraktConnectionRecord(
            sealedAccessToken: settings.tokenCipher.seal(tokens.accessToken),
            sealedRefreshToken: settings.tokenCipher.seal(tokens.refreshToken),
            expiresAt: now().addingTimeInterval(TimeInterval(tokens.expiresIn)),
            username: username,
            connectedAt: now()
        ), userID: userID)
    }

    static func returning(_ base: String, result: String) -> URL {
        var components = URLComponents(string: base) ?? URLComponents()
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "trakt", value: result)]
        return components.url ?? URL(string: "aaru://")!
    }
}
