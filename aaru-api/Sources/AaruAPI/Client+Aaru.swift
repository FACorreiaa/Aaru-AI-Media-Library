import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

public extension Client {
    /// A client for the Aaru API at `baseURL` (the host; every path already starts with `/v1`).
    static func aaru(
        baseURL: URL,
        session: SessionMiddleware,
        transport: any ClientTransport = URLSessionTransport()
    ) -> Client {
        Client(serverURL: baseURL, transport: transport, middlewares: [session])
    }
}
