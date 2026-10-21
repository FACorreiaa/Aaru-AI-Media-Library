import AaruCore
import Foundation

/// A client that registered itself (RFC 7591): public, PKCE only, no secret.
struct OAuthClient: Sendable, Equatable {
    var id: String
    var name: String
    var redirectURIs: [String]
    var createdAt: Date
}

/// One authorization in progress: the client asked, the user has not answered yet. Only the
/// browser that started it holds the binding, so a link sent to someone else approves nothing.
struct OAuthRequest: Sendable, Equatable {
    var id: UUID
    var clientID: String
    var redirectURI: String
    var state: String?
    var codeChallenge: String
    var resource: String?
    var bindingHash: String
    var expiresAt: Date
}

/// What the user approved, waiting to be exchanged for tokens (60 seconds, once).
struct OAuthCode: Sendable, Equatable {
    var clientID: String
    var userID: UserID
    var redirectURI: String
    var codeChallenge: String
    var resource: String?
    var name: String
    var kind: AgentTokenKind
    var allowWrites: Bool
    var expiresAt: Date
}

enum CodeRedemption: Sendable {
    case fresh(OAuthCode)
    /// Already exchanged: the tokens it gave are revoked, per RFC 6749 §4.1.2.
    case reused
}

/// Tokens issued in one exchange or refresh.
struct OAuthGrant: Sendable {
    var accessToken: String
    var refreshToken: String
    var scopes: Set<AgentScope>
}

enum RefreshOutcome: Sendable {
    case rotated(scopes: Set<AgentScope>)
    /// A spent refresh token came back: someone copied it, so the connection is revoked.
    case reused
    case invalid
}

protocol OAuthStore: Sendable {
    func register(_ client: OAuthClient) async throws
    func client(id: String) async throws -> OAuthClient?
    func createRequest(_ request: OAuthRequest) async throws
    /// A request not yet answered and not expired.
    func request(id: UUID, now: Date) async throws -> OAuthRequest?
    /// Marks a live request answered; nil when it was answered already or expired.
    func consumeRequest(id: UUID, now: Date) async throws -> OAuthRequest?
    func createCode(_ code: OAuthCode, hash: String) async throws
    /// Marks the code used. Nil when unknown or expired.
    func redeemCode(hash: String, now: Date) async throws -> CodeRedemption?
    // swiftlint:disable function_parameter_count
    /// In one transaction: the connection's `agent_tokens` row, its first refresh token, and the
    /// code pointing at the row (so a reused code can revoke it).
    func issue(
        _ token: AgentToken,
        userID: UserID,
        clientID: String,
        codeHash: String,
        accessHash: String,
        accessExpiresAt: Date,
        refreshHash: String,
        refreshExpiresAt: Date
    ) async throws
    func rotate(
        refreshHash: String,
        clientID: String,
        now: Date,
        accessHash: String,
        accessExpiresAt: Date,
        newRefreshHash: String,
        refreshExpiresAt: Date
    ) async throws -> RefreshOutcome
    // swiftlint:enable function_parameter_count
    /// Revokes the connection an access or refresh token belongs to. Unknown tokens are ignored.
    func revoke(tokenHash: String, now: Date) async throws
}
