import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

public extension Client {
    /// A client for the Aaru API at `baseURL` (the host; every path already starts with `/v1`).
    static func aaru(
        baseURL: URL,
        session: SessionMiddleware,
        timeZone: TimeZoneMiddleware = TimeZoneMiddleware(),
        transport: any ClientTransport = URLSessionTransport()
    ) -> Client {
        Client(
            serverURL: baseURL,
            transport: transport,
            // The retry is last, next to the transport, so a resent read carries the same headers.
            middlewares: [session, timeZone, ChatAudioContentTypeMiddleware(), ConnectionRetryMiddleware()]
        )
    }
}
