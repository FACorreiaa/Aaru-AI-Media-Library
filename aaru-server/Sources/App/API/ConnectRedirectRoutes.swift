import Foundation
import Hummingbird

/// The providers' browser redirects after a connect: Trakt's (IMP-002) and MyAnimeList's
/// (SCR-005). Plain, not generated: the generated server would percent-encode the `aaru://`
/// Location. No session: the one-time `state` names the user.
struct ConnectRedirectRoutes {
    let trakt: TraktConnectService
    let mal: MALConnectService

    func register(on router: Router<AppRequestContext>) {
        router.get("/v1/imports/trakt/callback") { request, _ -> Response in
            let query = request.uri.queryParameters
            return try await Self.redirect(trakt.callback(
                code: query["code"].map(String.init), state: query["state"].map(String.init),
                error: query["error"].map(String.init)
            ))
        }
        router.get("/v1/connections/mal/callback") { request, _ -> Response in
            let query = request.uri.queryParameters
            return try await Self.redirect(mal.callback(
                code: query["code"].map(String.init), state: query["state"].map(String.init),
                error: query["error"].map(String.init)
            ))
        }
    }

    private static func redirect(_ next: URL) -> Response {
        Response(status: .found, headers: [.location: next.absoluteString])
    }
}
