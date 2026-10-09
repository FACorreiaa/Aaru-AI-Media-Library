import AaruCore
import Foundation
import HTTPTypes
import Hummingbird
import NIOCore

/// Request context for every route. `AuthMiddleware` fills in the signed-in user.
struct AppRequestContext: RequestContext {
    var coreContext: CoreRequestContextStorage
    /// Set when the request carries a valid session token.
    var userID: UserID?
    /// Hash of the presented session token, so sign-out can delete exactly that session.
    var sessionTokenHash: String?
    /// The socket peer. Behind Traefik this is the proxy; `clientAddress` prefers the forwarded hop.
    let peerAddress: String?
    /// `clientAddress(for:)` resolved once by `AuthMiddleware`, for handlers that rate-limit.
    var clientAddressForRateLimit = "unknown"

    init(source: Source) {
        coreContext = .init(source: source)
        peerAddress = source.channel.remoteAddress?.ipAddress
    }
}

extension AppRequestContext {
    /// The address used for per-client rate limits: Traefik's first `X-Forwarded-For` hop,
    /// else the socket peer. Only ever a rate-limit key — never an authorization input.
    func clientAddress(for request: Request) -> String {
        if let forwarded = request.headers[.xForwardedFor]?.split(separator: ",").first {
            return forwarded.trimmingCharacters(in: .whitespaces)
        }
        return peerAddress ?? "unknown"
    }
}

extension HTTPField.Name {
    // swiftlint:disable:next force_unwrapping
    static let xForwardedFor = Self("X-Forwarded-For")!
}
