import Foundation
import HTTPTypes
import Hummingbird
import Logging

/// MUS-005: ListenBrainz's submit API, so scrobblers that let you set a ListenBrainz server
/// (Web Scrobbler, Pano Scrobbler, Navidrome, Jellyfin's plugin, Multi-Scrobbler) send listens
/// to Aaru. Outside `/v1` and the OpenAPI spec like Stremio's routes, because it speaks
/// ListenBrainz's shapes: `Authorization: Token …`, `{listen_type, payload}`, and
/// `{code, error}` errors. Only a music token (`aaru_lb_…`) gets in.
struct ListenBrainzRoutes: Sendable {
    static let path = "/listenbrainz/1"
    /// ListenBrainz's own limits: 10 MB a request, 1,000 listens an import.
    static let maxBody = 10 * 1024 * 1024
    static let maxListens = 1000

    let listens: ListenService
    /// Hears `playing_now`, for the "Now playing" activity (SCR-009).
    let scrobble: ScrobbleService
    let tokens: AgentTokenService
    var now: @Sendable () -> Date = { Date() }
    var logger = Logger(label: "aaru-listenbrainz")

    func register(on router: Router<AppRequestContext>) {
        router.post(RouterPath("\(Self.path)/submit-listens")) { request, _ in
            await submit(request)
        }
        router.get(RouterPath("\(Self.path)/validate-token")) { request, _ in
            await validate(request)
        }
        // Browser scrobblers fetch from a page or an extension; nothing here reads a cookie.
        for path in ["submit-listens", "validate-token"] {
            router.on(RouterPath("\(Self.path)/\(path)"), method: .options) { _, _ in
                Response(status: .noContent, headers: Self.cors)
            }
        }
    }

    func submit(_ request: Request) async -> Response {
        do {
            guard let secret = Self.token(request),
                  let caller = try await tokens.authenticate(secret, for: .music)
            else {
                return Self.error(.unauthorized, "Invalid authorization token. Connect the scrobbler in Aaru again.")
            }
            guard caller.has(.scrobbleWrite) else {
                return Self.error(.forbidden, "This connection may not send listens.")
            }
            guard await tokens.allow(caller) else {
                return Self.error(.tooManyRequests, "Too many requests. Wait a minute.")
            }
            let body: ByteBuffer
            do {
                body = try await request.body.collect(upTo: Self.maxBody)
            } catch {
                return Self.error(.contentTooLarge, "A submission is at most 10 MB.")
            }
            let submission: ListenSubmission
            do {
                submission = try ListenSubmission(json: Data(buffer: body), now: now())
            } catch let error as ListenSubmission.Invalid {
                return Self.error(.badRequest, error.message)
            }
            if !submission.listens.isEmpty {
                _ = try await listens.submit(submission.listens, from: caller)
            }
            if let track = submission.playingNow {
                try await scrobble.play(.track(track, now: now()), from: caller)
            }
            return Self.json(.ok, ["status": "ok"])
        } catch {
            logger.error("Listen submission failed", metadata: ["error": "\(error)"])
            return Self.error(.internalServerError, "Something went wrong.")
        }
    }

    /// ListenBrainz answers 200 either way and says in `valid` whether the token works.
    func validate(_ request: Request) async -> Response {
        let secret = Self.token(request) ?? request.uri.queryParameters["token"].map(String.init)
        guard let secret, !secret.isEmpty else {
            return Self.error(.badRequest, "You need to provide an Authorization token.")
        }
        do {
            guard let caller = try await tokens.authenticate(secret, for: .music) else {
                return Self.json(
                    .ok,
                    ListenBrainzTokenCheck(code: 200, message: "Token invalid.", valid: false, userName: nil)
                )
            }
            // Clients show this as the account they are signed in to; the token's name says which.
            return Self.json(
                .ok, ListenBrainzTokenCheck(
                    code: 200,
                    message: "Token valid.",
                    valid: true,
                    userName: caller.token.name
                )
            )
        } catch {
            logger.error("Token check failed", metadata: ["error": "\(error)"])
            return Self.error(.internalServerError, "Something went wrong.")
        }
    }

    /// `Authorization: Token …` as ListenBrainz documents it, or `Bearer …`.
    static func token(_ request: Request) -> String? {
        guard let header = request.headers[.authorization] else { return nil }
        let parts = header.split(separator: " ", maxSplits: 1)
        guard parts.count == 2, ["token", "bearer"].contains(parts[0].lowercased()) else { return nil }
        let token = parts[1].trimmingCharacters(in: .whitespaces)
        return token.isEmpty ? nil : token
    }

    static let cors: HTTPFields = [
        .accessControlAllowOrigin: "*",
        .accessControlAllowHeaders: "Authorization, Content-Type",
        .accessControlAllowMethods: "GET, POST, OPTIONS",
        .accessControlMaxAge: "86400",
    ]

    private static func json(_ status: HTTPResponse.Status, _ value: some Encodable) -> Response {
        var headers = cors
        headers[.contentType] = "application/json"
        headers[.cacheControl] = "no-store"
        let body = (try? JSONEncoder().encode(value)) ?? Data()
        return Response(status: status, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: body)))
    }

    /// ListenBrainz's error shape.
    private static func error(_ status: HTTPResponse.Status, _ message: String) -> Response {
        json(status, ListenBrainzFailure(code: status.code, error: message))
    }
}

private struct ListenBrainzTokenCheck: Encodable {
    var code: Int
    var message: String
    var valid: Bool
    var userName: String?

    enum CodingKeys: String, CodingKey {
        case code, message, valid
        case userName = "user_name"
    }
}

private struct ListenBrainzFailure: Encodable {
    var code: Int
    var error: String
}
