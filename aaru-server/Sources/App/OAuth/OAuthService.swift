import AaruCore
import Crypto
import Foundation
import HTTPTypes

/// An OAuth error as RFC 6749 §5.2 shapes it, safe to show the client.
struct OAuthError: Error, Sendable {
    var status: HTTPResponse.Status = .badRequest
    var error: String
    var description: String
}

/// OUT-004 · the OAuth 2.1 front door the MCP authorization spec asks of a remote server, so
/// Claude (claude.ai, Desktop, mobile) can add Aaru as a custom connector. Clients register
/// themselves, the user approves on the web (`/oauth/consent`), and the tokens are an ordinary
/// agent token: the same scopes, the same MCP surface, revocable in Settings.
struct OAuthService: Sendable {
    struct Settings: Sendable {
        /// This API (`PUBLIC_BASE_URL`): issuer, endpoints and the MCP resource.
        var publicBaseURL: URL
        /// Where the consent page lives (`WEB_BASE_URL`).
        var webBaseURL: URL
        /// `Domain` of the binding cookie, so the web app can read what the API set. Nil: host-only.
        var cookieDomain: String?
    }

    static let accessLifetime: TimeInterval = 60 * 60
    static let refreshLifetime: TimeInterval = 30 * 24 * 60 * 60
    static let requestLifetime: TimeInterval = 10 * 60
    static let codeLifetime: TimeInterval = 60
    static let bindingCookie = "aaru_oauth"
    static let clientPrefix = "aaru_oc_"
    static let refreshPrefix = "aaru_ort_"

    let stores: Stores
    let oauth: any OAuthStore
    let settings: Settings
    /// Registrations per client address per hour: registering is anonymous.
    let registrations = FixedWindowRateLimiter(limit: 20, window: 60 * 60)
    var now: @Sendable () -> Date = { Date() }

    var issuer: String {
        settings.publicBaseURL.absoluteString.trimmingSuffix("/")
    }

    var resource: String {
        AgentSetup.endpoint(settings.publicBaseURL)
    }

    var resourceMetadataURL: String {
        issuer + "/.well-known/oauth-protected-resource/v1/mcp"
    }

    // MARK: Metadata

    var protectedResource: [String: JSONValue] {
        [
            "resource": .string(resource),
            "resource_name": .string("Aaru"),
            "authorization_servers": .array([.string(issuer)]),
            "scopes_supported": .array([.string("library:read"), .string("library:write")]),
            "bearer_methods_supported": .array([.string("header")]),
        ]
    }

    var authorizationServer: [String: JSONValue] {
        [
            "issuer": .string(issuer),
            "authorization_endpoint": .string(issuer + "/oauth/authorize"),
            "token_endpoint": .string(issuer + "/oauth/token"),
            "registration_endpoint": .string(issuer + "/oauth/register"),
            "revocation_endpoint": .string(issuer + "/oauth/revoke"),
            "response_types_supported": .array([.string("code")]),
            "grant_types_supported": .array([.string("authorization_code"), .string("refresh_token")]),
            "code_challenge_methods_supported": .array([.string("S256")]),
            "token_endpoint_auth_methods_supported": .array([.string("none")]),
            "scopes_supported": .array([.string("library:read"), .string("library:write")]),
        ]
    }

    // MARK: Registration (RFC 7591)

    // Every client is public: whatever auth method it asks for, it is registered with `none`
    // (RFC 7591 lets the server substitute), and PKCE is what protects the code.

    struct Registration: Decodable {
        // swiftlint:disable identifier_name
        var client_name: String?
        var redirect_uris: [String]?
        // swiftlint:enable identifier_name
    }

    func register(_ body: Registration, clientAddress: String) async throws -> [String: JSONValue] {
        guard await registrations.allow(clientAddress, now: now()) else {
            throw OAuthError(status: .tooManyRequests, error: "slow_down", description: "Too many registrations.")
        }
        let uris = body.redirect_uris ?? []
        guard (1 ... 10).contains(uris.count), uris.allSatisfy(Self.acceptableRedirect) else {
            throw OAuthError(
                error: "invalid_redirect_uri",
                description: "Redirect URIs must be https, or http on localhost, without a fragment."
            )
        }
        let name = String((body.client_name ?? "MCP client").trimmingCharacters(in: .whitespaces).prefix(80))
        let client = OAuthClient(
            id: Self.clientPrefix + OpaqueToken.generate().prefix(22), name: name.isEmpty ? "MCP client" : name,
            redirectURIs: uris, createdAt: now()
        )
        try await oauth.register(client)
        return [
            "client_id": .string(client.id),
            "client_name": .string(client.name),
            "redirect_uris": .array(uris.map(JSONValue.string)),
            "grant_types": .array([.string("authorization_code"), .string("refresh_token")]),
            "response_types": .array([.string("code")]),
            "token_endpoint_auth_method": .string("none"),
            "client_id_issued_at": .number(client.createdAt.timeIntervalSince1970.rounded(.down)),
        ]
    }

    // MARK: Authorize

    enum Authorization {
        /// The client or redirect cannot be trusted: say so here, never redirect.
        case refuse(String)
        /// A protocol error the client should hear about, at its redirect URI.
        case redirect(URL)
        /// Off to the consent page, with the binding cookie for this browser.
        case consent(URL, binding: String)
    }

    func authorize(_ query: [String: String]) async throws -> Authorization {
        guard let clientID = query["client_id"], let client = try await oauth.client(id: clientID) else {
            return .refuse("This app is not registered with Aaru. Try connecting again from the app.")
        }
        guard let redirect = query["redirect_uri"].flatMap({ Self.registered($0, in: client.redirectURIs) }) else {
            return .refuse("This app's return address does not match what it registered.")
        }
        let state = query["state"]
        func fail(_ error: String, _ description: String) -> Authorization {
            .redirect(Self.redirectURL(redirect, [
                "error": error, "error_description": description, "state": state, "iss": issuer,
            ]))
        }
        guard query["response_type"] == "code" else {
            return fail("unsupported_response_type", "Only the code flow is supported.")
        }
        guard query["code_challenge_method"] == "S256", let challenge = query["code_challenge"],
              (43 ... 128).contains(challenge.count)
        else { return fail("invalid_request", "PKCE with S256 is required.") }
        if let resource = query["resource"], resource.trimmingSuffix("/") != self.resource {
            return fail("invalid_target", "Aaru's MCP endpoint is \(self.resource).")
        }
        let binding = OpaqueToken.generate()
        let request = OAuthRequest(
            id: UUID(), clientID: client.id, redirectURI: redirect, state: state, codeChallenge: challenge,
            resource: query["resource"], bindingHash: OpaqueToken.hash(binding),
            expiresAt: now().addingTimeInterval(Self.requestLifetime)
        )
        try await oauth.createRequest(request)
        var consent = URLComponents(
            url: settings.webBaseURL.appendingPathComponent("oauth/consent"), resolvingAgainstBaseURL: false
        )
        consent?.queryItems = [URLQueryItem(name: "request", value: request.id.uuidString.lowercased())]
        return .consent(consent?.url ?? settings.webBaseURL, binding: binding)
    }

    func bindingCookie(_ binding: String) -> String {
        var cookie = "\(Self.bindingCookie)=\(binding); Path=/; Max-Age=\(Int(Self.requestLifetime)); HttpOnly; "
            + "SameSite=Lax"
        if settings.publicBaseURL.scheme == "https" {
            cookie += "; Secure"
        }
        if let domain = settings.cookieDomain, !domain.isEmpty {
            cookie += "; Domain=\(domain)"
        }
        return cookie
    }

    // MARK: Consent (signed in, through /v1)

    func pending(_ id: UUID) async throws -> (OAuthRequest, OAuthClient) {
        guard let request = try await oauth.request(id: id, now: now()),
              let client = try await oauth.client(id: request.clientID)
        else { throw AppError.notFound("This connection request expired. Start again from the app.") }
        return (request, client)
    }

    func approve(_ id: UUID, userID: UserID, binding: String, name: String?, allowWrites: Bool) async throws -> URL {
        let (request, client) = try await answer(id, binding: binding)
        let code = OpaqueToken.generate()
        let kind = Self.kind(forClientName: client.name)
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        try await oauth.createCode(OAuthCode(
            clientID: client.id, userID: userID, redirectURI: request.redirectURI,
            codeChallenge: request.codeChallenge, resource: request.resource,
            name: trimmed.isEmpty ? kind.label : String(trimmed.prefix(80)), kind: kind, allowWrites: allowWrites,
            expiresAt: now().addingTimeInterval(Self.codeLifetime)
        ), hash: OpaqueToken.hash(code))
        return Self.redirectURL(request.redirectURI, ["code": code, "state": request.state, "iss": issuer])
    }

    func deny(_ id: UUID, binding: String) async throws -> URL {
        let (request, _) = try await answer(id, binding: binding)
        return Self.redirectURL(request.redirectURI, [
            "error": "access_denied", "error_description": "The user said no.", "state": request.state,
            "iss": issuer,
        ])
    }

    /// Only the browser that started the request may answer it, and only once.
    private func answer(_ id: UUID, binding: String) async throws -> (OAuthRequest, OAuthClient) {
        let (request, client) = try await pending(id)
        guard OpaqueToken.hash(binding) == request.bindingHash else {
            throw AppError(
                status: .forbidden, code: "forbidden",
                message: "Open this from the app you are connecting, in this browser."
            )
        }
        guard try await oauth.consumeRequest(id: id, now: now()) != nil else {
            throw AppError.notFound("This connection request was already answered.")
        }
        return (request, client)
    }

    // MARK: Token

    func token(_ form: [String: String]) async throws -> [String: JSONValue] {
        switch form["grant_type"] {
        case "authorization_code": try await exchange(form)
        case "refresh_token": try await refresh(form)
        default: throw OAuthError(
                error: "unsupported_grant_type",
                description: "Use authorization_code or refresh_token."
            )
        }
    }

    private func exchange(_ form: [String: String]) async throws -> [String: JSONValue] {
        let invalid = OAuthError(error: "invalid_grant", description: "The code is invalid, used or expired.")
        guard let code = form["code"], let verifier = form["code_verifier"], let clientID = form["client_id"] else {
            throw OAuthError(error: "invalid_request", description: "code, code_verifier and client_id are required.")
        }
        let codeHash = OpaqueToken.hash(code)
        guard case let .fresh(grant)? = try await oauth.redeemCode(hash: codeHash, now: now()),
              grant.clientID == clientID, form["redirect_uri"].map({ $0 == grant.redirectURI }) ?? true,
              Self.challenge(for: verifier) == grant.codeChallenge,
              form["resource"].map({ $0.trimmingSuffix("/") == resource }) ?? true
        else { throw invalid }
        var scopes: Set<AgentScope> = [.libraryRead]
        if grant.allowWrites {
            scopes.insert(.libraryWrite)
        }
        let token = AgentToken(
            id: UUID(), name: grant.name, kind: grant.kind, scopes: scopes, createdAt: now(), lastUsedAt: nil
        )
        let access = AgentTokenService.oauthPrefix + OpaqueToken.generate()
        let refresh = Self.refreshPrefix + OpaqueToken.generate()
        try await oauth.issue(
            token, userID: grant.userID, clientID: clientID, codeHash: codeHash,
            accessHash: OpaqueToken.hash(access), accessExpiresAt: now().addingTimeInterval(Self.accessLifetime),
            refreshHash: OpaqueToken.hash(refresh), refreshExpiresAt: now().addingTimeInterval(Self.refreshLifetime)
        )
        return Self.tokens(OAuthGrant(accessToken: access, refreshToken: refresh, scopes: scopes))
    }

    private func refresh(_ form: [String: String]) async throws -> [String: JSONValue] {
        guard let presented = form["refresh_token"], let clientID = form["client_id"] else {
            throw OAuthError(error: "invalid_request", description: "refresh_token and client_id are required.")
        }
        let access = AgentTokenService.oauthPrefix + OpaqueToken.generate()
        let refresh = Self.refreshPrefix + OpaqueToken.generate()
        let outcome = try await oauth.rotate(
            refreshHash: OpaqueToken.hash(presented), clientID: clientID, now: now(),
            accessHash: OpaqueToken.hash(access), accessExpiresAt: now().addingTimeInterval(Self.accessLifetime),
            newRefreshHash: OpaqueToken.hash(refresh), refreshExpiresAt: now().addingTimeInterval(Self.refreshLifetime)
        )
        guard case let .rotated(scopes) = outcome else {
            throw OAuthError(error: "invalid_grant", description: "Connect Aaru again.")
        }
        return Self.tokens(OAuthGrant(accessToken: access, refreshToken: refresh, scopes: scopes))
    }

    func revoke(_ form: [String: String]) async throws {
        if let token = form["token"], !token.isEmpty {
            try await oauth.revoke(tokenHash: OpaqueToken.hash(token), now: now())
        }
    }
}

/// RFC details: PKCE, redirect matching, token answers.
extension OAuthService {
    static func tokens(_ grant: OAuthGrant) -> [String: JSONValue] {
        [
            "access_token": .string(grant.accessToken),
            "token_type": .string("Bearer"),
            "expires_in": .number(accessLifetime),
            "refresh_token": .string(grant.refreshToken),
            "scope": .string(grant.scopes.map(\.rawValue).sorted().joined(separator: " ")),
        ]
    }

    /// base64url(SHA-256(verifier)), RFC 7636 §4.2.
    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// https anywhere, or http on the loopback interface (RFC 8252); never a fragment or userinfo.
    static func acceptableRedirect(_ raw: String) -> Bool {
        guard let url = URLComponents(string: raw), let host = url.host, !host.isEmpty,
              url.fragment == nil, url.user == nil, url.password == nil
        else { return false }
        return url.scheme == "https" || (url.scheme == "http" && isLoopback(host))
    }

    /// The registered URI a presented one matches: exactly, or for loopback on any port.
    static func registered(_ presented: String, in uris: [String]) -> String? {
        if uris.contains(presented) {
            return presented
        }
        guard var asked = URLComponents(string: presented), asked.scheme == "http",
              let host = asked.host, isLoopback(host)
        else { return nil }
        asked.port = nil
        let match = uris.contains { uri in
            guard var known = URLComponents(string: uri) else { return false }
            known.port = nil
            return known == asked
        }
        return match ? presented : nil
    }

    private static func isLoopback(_ host: String) -> Bool {
        ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
    }

    static func redirectURL(_ base: String, _ parameters: [String: String?]) -> URL {
        var components = URLComponents(string: base) ?? URLComponents()
        var items = components.queryItems ?? []
        for (name, value) in parameters.sorted(by: { $0.key < $1.key }) {
            if let value {
                items.append(URLQueryItem(name: name, value: value))
            }
        }
        components.queryItems = items
        return components.url ?? URL(string: base) ?? URL(fileURLWithPath: "/")
    }

    /// Which agent a registered client is, by the name it gave, for Settings' label.
    static func kind(forClientName name: String) -> AgentTokenKind {
        let name = name.lowercased()
        if name.contains("claude code") {
            return .claudeCode
        }
        if name.contains("claude") {
            return .claude
        }
        for kind in [AgentTokenKind.codex, .gemini, .hermes] where name.contains(kind.rawValue) {
            return kind
        }
        return .other
    }
}

extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
