import Foundation

/// MyAnimeList's API v2, through the paced provider client. Token calls and list writes are
/// form-encoded, as MAL asks; reads are JSON.
struct MALAPI: Sendable {
    let client: ProviderClient
    let settings: MALSettings

    struct Tokens: Decodable, Sendable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int
    }

    func exchange(code: String, verifier: String) async throws -> Tokens {
        try await token([
            ("grant_type", "authorization_code"), ("code", code), ("code_verifier", verifier),
            ("redirect_uri", settings.redirectURI.absoluteString),
        ])
    }

    func refresh(_ refreshToken: String) async throws -> Tokens {
        try await token([("grant_type", "refresh_token"), ("refresh_token", refreshToken)])
    }

    private func token(_ fields: [(String, String)]) async throws -> Tokens {
        var fields = [("client_id", settings.clientID)] + fields
        if let secret = settings.clientSecret {
            fields.append(("client_secret", secret))
        }
        return try await client.decode(Tokens.self, OutboundRequest(
            method: "POST", url: MALSettings.tokenURL,
            headers: [("Content-Type", "application/x-www-form-urlencoded")], body: Self.form(fields)
        ), decoder: Self.decoder)
    }

    func username(token: String) async throws -> String? {
        struct User: Decodable { let name: String? }
        return try await client.decode(
            User.self,
            OutboundRequest(url: MALSettings.apiURL.appendingPathComponent("users/@me"), headers: auth(token)),
            decoder: Self.decoder
        ).name
    }

    /// Creates or updates the user's entry for one anime. MAL answers with the entry as stored.
    func updateListStatus(malID: String, _ state: MALEntryState, token: String) async throws {
        _ = try await client.data(OutboundRequest(
            method: "PATCH",
            url: MALSettings.apiURL.appendingPathComponent("anime/\(malID)/my_list_status"),
            headers: auth(token) + [("Content-Type", "application/x-www-form-urlencoded")],
            body: Self.form([
                ("status", state.status.rawValue), ("num_watched_episodes", String(state.episodes)),
                ("score", String(state.score)),
            ])
        ))
    }

    private func auth(_ token: String) -> [(String, String)] {
        [("Authorization", "Bearer \(token)")]
    }

    static func form(_ fields: [(String, String)]) -> Data {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let pairs = fields.map { name, value in
            "\(name)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }
        return Data(pairs.joined(separator: "&").utf8)
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}

/// MAL publishes no rate limit; bursts get 403s, so one request a second across all users.
func makeMALAPI(_ settings: MALSettings, _ transport: any HTTPTransport) -> MALAPI {
    MALAPI(
        client: ProviderClient(name: "mal", transport: transport, pacer: RequestPacer(requestsPerSecond: 1, burst: 3)),
        settings: settings
    )
}
