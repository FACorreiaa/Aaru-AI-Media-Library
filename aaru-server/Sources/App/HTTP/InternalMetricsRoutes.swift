import Foundation
import HTTPTypes
import Hummingbird

/// `GET /internal/metrics` → `{"users": N}` for the board at facorreia.com/apps, which calls it
/// in-cluster with the shared `METRICS_SECRET`. An operator endpoint, so it sits outside `/v1` and
/// outside `openapi.yaml`. Bearer only, compared in constant time. An empty secret turns the route
/// off (404), so a deploy without the key never answers unauthenticated.
struct InternalMetricsRoutes: Sendable {
    static let path = "/internal/metrics"

    let users: any UserStore
    let secret: String

    func register(on router: Router<AppRequestContext>) {
        router.get(RouterPath(Self.path)) { request, _ in
            try await respond(to: request)
        }
    }

    func respond(to request: Request) async throws -> Response {
        guard !secret.isEmpty else { return Response(status: .notFound) }
        guard let presented = AuthMiddleware.bearerToken(request),
              Self.constantTimeEquals(presented, secret)
        else {
            return Response(status: .unauthorized)
        }
        let count = try await users.count()
        let body = try JSONEncoder().encode(["users": count])
        return Response(
            status: .ok,
            headers: [.contentType: "application/json", .cacheControl: "no-store"],
            body: .init(byteBuffer: ByteBuffer(bytes: body))
        )
    }

    /// No early exit, so the comparison time does not leak how much of the secret matched.
    static func constantTimeEquals(_ presented: String, _ expected: String) -> Bool {
        let lhs = Array(presented.utf8), rhs = Array(expected.utf8)
        guard lhs.count == rhs.count else { return false }
        var diff: UInt8 = 0
        for (left, right) in zip(lhs, rhs) {
            diff |= left ^ right
        }
        return diff == 0
    }
}
