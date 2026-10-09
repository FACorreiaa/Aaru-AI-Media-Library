import aaruAPI
import AaruCore
import OpenAPIRuntime

/// Handlers for the generated `/v1` routes. Talks to the data layer only through
/// `Stores` and to business rules through services.
struct APIImplementation: APIProtocol {
    let stores: Stores
    let auth: AuthService

    func getHealth(_: Operations.GetHealth.Input) async throws -> Operations.GetHealth.Output {
        if await stores.health.isReachable() {
            return .ok(.init(body: .json(.init(status: .ok))))
        }
        return .serviceUnavailable(.init(body: .json(.init(status: .unavailable))))
    }
}

extension APIImplementation {
    /// The signed-in user. `AuthMiddleware` already refused anonymous requests to
    /// non-public routes; this guards against a route that forgot to be listed.
    func currentUser() throws -> UserID {
        guard let userID = AppRequestContext.current?.userID else { throw AppError.unauthorized() }
        return userID
    }

    func currentContext() throws -> AppRequestContext {
        guard let context = AppRequestContext.current else { throw AppError.unauthorized() }
        return context
    }
}
