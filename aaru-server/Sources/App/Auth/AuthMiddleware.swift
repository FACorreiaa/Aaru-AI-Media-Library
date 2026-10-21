import Hummingbird

/// Resolves `Authorization: Bearer <token>` to a user and enforces sign-in on every
/// `/v1` route except the public ones. Handlers read the user from the context.
struct AuthMiddleware: RouterMiddleware {
    typealias Context = AppRequestContext

    /// Routes reachable without a session.
    static let publicPaths: Set<String> = [
        "/v1/health",
        "/v1/auth/apple",
        "/v1/auth/email/link",
        "/v1/auth/email/verify",
        "/v1/auth/google",
        // Trakt's browser redirect: no session; the one-time `state` names the user.
        "/v1/imports/trakt/callback",
        // MCP authenticates itself with an agent token, never a session (OUT-004).
        "/v1/mcp",
        // Scrobbles authenticate themselves with a scrobble token, never a session (SCR-007).
        "/v1/scrobble/start",
        "/v1/scrobble/pause",
        "/v1/scrobble/stop",
    ]

    /// Whether a path answers without a session: the fixed public routes, and an invite link's
    /// preview (`/v1/invites/{code}`), which a signed-out friend opens before signing up.
    static func isPublic(_ path: String) -> Bool {
        if publicPaths.contains(path) {
            return true
        }
        let invitePrefix = "/v1/invites/"
        guard path.hasPrefix(invitePrefix) else { return false }
        let code = path.dropFirst(invitePrefix.count)
        return !code.isEmpty && !code.contains("/")
    }

    let sessions: any SessionStore

    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        var context = context
        context.clientAddressForRateLimit = context.clientAddress(for: request)
        if let token = Self.bearerToken(request) {
            let hash = OpaqueToken.hash(token)
            if let userID = try await sessions.userID(forTokenHash: hash, now: .now) {
                context.userID = userID
                context.sessionTokenHash = hash
            }
        }
        let path = request.uri.path
        if context.userID == nil, path.hasPrefix("/v1/"), !Self.isPublic(path) {
            throw AppError.unauthorized()
        }
        return try await next(request, context)
    }

    static func bearerToken(_ request: Request) -> String? {
        guard let header = request.headers[.authorization] else { return nil }
        let prefix = "Bearer "
        guard header.hasPrefix(prefix) else { return nil }
        let token = header.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        return token.isEmpty ? nil : token
    }
}
