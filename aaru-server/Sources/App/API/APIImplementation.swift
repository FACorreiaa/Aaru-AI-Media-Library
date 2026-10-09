import aaruAPI
import OpenAPIRuntime

/// Handlers for the generated `/v1` routes. Talks to the data layer only through `Stores`.
struct APIImplementation: APIProtocol {
    let stores: Stores

    func getHealth(_: Operations.GetHealth.Input) async throws -> Operations.GetHealth.Output {
        if await stores.health.isReachable() {
            return .ok(.init(body: .json(.init(status: .ok))))
        }
        return .serviceUnavailable(.init(body: .json(.init(status: .unavailable))))
    }
}
