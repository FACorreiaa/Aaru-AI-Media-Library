import aaruAPI
import AaruCore
import OpenAPIRuntime

/// Handlers for the generated `/v1` routes. Talks to the data layer only through
/// `Stores` and to business rules through services.
///
/// The stores and services sit behind one reference: the generated `registerHandlers` copies
/// this value into a closure per route in a single stack frame, and by value they overflowed a
/// 512 KB cooperative-thread stack once the route count grew.
struct APIImplementation: APIProtocol {
    private let context: Context

    init(stores: Stores, services: Services) {
        context = Context(stores: stores, services: services)
    }

    private final class Context: Sendable {
        let stores: Stores
        let services: Services

        init(stores: Stores, services: Services) {
            self.stores = stores
            self.services = services
        }
    }

    var stores: Stores {
        context.stores
    }

    var services: Services {
        context.services
    }

    var auth: AuthService {
        services.auth
    }

    var catalog: CatalogService {
        services.catalog
    }

    var library: LibraryService {
        services.library
    }

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
