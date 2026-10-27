import HTTPTypes
import Hummingbird

/// Lets a private cache keep an avatar for a week (SOC-001b): its URL carries the version, so it
/// is never stale. Set here, not in `openapi.yaml`, because the generated server percent-encodes
/// header values and no cache reads `private%2C%20max-age%3D604800`.
struct AvatarCacheMiddleware<Context: RequestContext>: RouterMiddleware {
    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        var response = try await next(request, context)
        if request.method == .get, response.status == .ok, Self.isAvatar(request.uri.path) {
            response.headers[.cacheControl] = "private, max-age=604800"
        }
        return response
    }

    static func isAvatar(_ path: String) -> Bool {
        path.hasPrefix("/v1/users/") && path.hasSuffix("/avatar")
    }
}
