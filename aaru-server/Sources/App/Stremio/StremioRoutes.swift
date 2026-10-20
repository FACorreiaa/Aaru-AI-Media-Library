import Foundation
import HTTPTypes
import Hummingbird
import Logging

/// SCR-003 · the addon's HTTP surface, hand-written because the Stremio protocol fixes the
/// paths. Every answer carries `Access-Control-Allow-Origin: *` (Stremio Web fetches from the
/// browser), errors included. The token in the path is a bearer secret: it is never logged
/// (`RedactedLogRequestsMiddleware`), and a revoked one gets a 404 manifest and empty catalogs.
struct StremioRoutes: Sendable {
    let service: StremioService
    let tokens: AgentTokenService
    var logger = Logger(label: "aaru-stremio")

    func register(on router: Router<AppRequestContext>) {
        router.get("/stremio/**") { request, _ in
            await respond(to: request)
        }
        router.on("/stremio/**", method: .options) { _, _ in
            Self.response(status: .noContent, body: Data(), maxAge: 86400)
        }
    }

    func respond(to request: Request) async -> Response {
        guard let parsed = StremioRequest(path: request.uri.path) else {
            return Self.json(StremioMessage(err: "Not a Stremio addon path."), status: .notFound, maxAge: 0)
        }
        do {
            let caller = try await tokens.authenticate(parsed.token)
            if let caller, await !tokens.allow(caller) {
                return Self.json(StremioMessage(err: "Too many requests."), status: .tooManyRequests, maxAge: 0)
            }
            return try await answer(parsed.route, caller: caller)
        } catch {
            logger.error("Stremio request failed", metadata: ["error": "\(error)"])
            return Self.json(StremioMessage(err: "Something went wrong."), status: .internalServerError, maxAge: 0)
        }
    }

    private func answer(_ route: StremioRequest.Route, caller: AgentCaller?) async throws -> Response {
        switch route {
        case .manifest:
            guard caller != nil else {
                return Self.json(
                    StremioMessage(err: "This Aaru link was revoked. Connect Stremio again in Aaru's Settings."),
                    status: .notFound, maxAge: 0
                )
            }
            return Self.json(StremioService.manifest, status: .ok, maxAge: 3600)
        case .configure:
            return Response(
                status: .found,
                headers: [.location: StremioService.configureURL.absoluteString, .accessControlAllowOrigin: "*"]
            )
        case let .resource(name, type, id, extra):
            return try await resource(name, type: type, id: id, extra: extra, caller: caller)
        }
    }

    private func resource(
        _ name: String, type: String, id: String, extra: [String: String], caller: AgentCaller?
    ) async throws -> Response {
        switch name {
        case "catalog":
            // A revoked or unknown token sees empty catalogs rather than an error.
            var metas: [StremioMetaPreview] = []
            if let caller {
                metas = try await service.catalog(id: id, type: type, extra: extra, caller: caller)
            }
            return Self.json(StremioCatalogResponse(metas: metas), status: .ok, maxAge: 60)
        case "meta":
            guard let caller, let meta = try await service.meta(id: id, caller: caller) else {
                return Self.json(StremioMessage(err: "Unknown title."), status: .notFound, maxAge: 0)
            }
            return Self.json(StremioMetaResponse(meta: meta), status: .ok, maxAge: 3600)
        case "player", "library":
            guard let caller else {
                return Self.json(StremioMessage(err: "This Aaru link was revoked."), status: .notFound, maxAge: 0)
            }
            let result = name == "player"
                ? try await service.player(type: type, videoID: id, extra: extra, caller: caller)
                : try await service.library(type: type, metaID: id, extra: extra, caller: caller)
            if result == .forbidden {
                return Self.json(StremioMessage(err: "This link may not do that."), status: .forbidden, maxAge: 0)
            }
            return Self.json(StremioMessage(), status: .ok, maxAge: 0)
        default:
            // `stream` and `subtitles` included: Aaru serves neither.
            return Self.json(StremioMessage(err: "Not supported."), status: .notFound, maxAge: 0)
        }
    }

    static func json(_ body: some Encodable, status: HTTPResponse.Status, maxAge: Int) -> Response {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        let data = (try? encoder.encode(body)) ?? Data("{}".utf8)
        var response = response(status: status, body: data, maxAge: maxAge)
        response.headers[.contentType] = "application/json; charset=utf-8"
        return response
    }

    static func response(status: HTTPResponse.Status, body: Data, maxAge: Int) -> Response {
        Response(
            status: status,
            headers: [
                .accessControlAllowOrigin: "*",
                .accessControlAllowHeaders: "*",
                .accessControlAllowMethods: "GET, OPTIONS",
                // Private: every answer is one user's library.
                .cacheControl: maxAge > 0 ? "private, max-age=\(maxAge)" : "no-store",
            ],
            body: .init(byteBuffer: ByteBuffer(bytes: body))
        )
    }
}
