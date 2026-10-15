import AaruCore
import Foundation

/// Trakt's API, through the paced provider client. PKCE only: no request carries a client
/// secret, because Trakt issues none to this app.
struct TraktAPI: Sendable {
    let client: ProviderClient
    let settings: TraktSettings

    struct Tokens: Decodable, Sendable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int
        let createdAt: Int
    }

    func exchange(code: String, verifier: String) async throws -> Tokens {
        try await token([
            "code": code, "client_id": settings.clientID, "redirect_uri": settings.redirectURI.absoluteString,
            "grant_type": "authorization_code", "code_verifier": verifier,
        ])
    }

    func refresh(_ refreshToken: String) async throws -> Tokens {
        try await token([
            "refresh_token": refreshToken, "client_id": settings.clientID,
            "redirect_uri": settings.redirectURI.absoluteString, "grant_type": "refresh_token",
        ])
    }

    private func token(_ body: [String: String]) async throws -> Tokens {
        try await client.decode(Tokens.self, OutboundRequest(
            method: "POST",
            url: TraktSettings.apiURL.appendingPathComponent("oauth/token"),
            headers: [("Content-Type", "application/json")],
            body: JSONEncoder().encode(body)
        ), decoder: Self.decoder)
    }

    func username(token: String) async throws -> String? {
        try await get(TraktUserSettings.self, "users/settings", token: token).user?.username
    }

    func get<T: Decodable>(_: T.Type, _ path: String, token: String) async throws -> T {
        try await client.decode(T.self, OutboundRequest(
            url: TraktSettings.apiURL.appendingPathComponent(path),
            headers: [
                ("Content-Type", "application/json"), ("trakt-api-version", "2"),
                ("trakt-api-key", settings.clientID), ("Authorization", "Bearer \(token)"),
            ],
            timeout: .seconds(30)
        ), decoder: Self.decoder)
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}

// MARK: Trakt's shapes (only what the import reads)

struct TraktIDs: Decodable, Sendable {
    let trakt: Int?
    let imdb: String?
    let tmdb: Int?
    let tvdb: Int?

    var externalIDs: ExternalIDs {
        ExternalIDs(tmdb: tmdb.map(String.init), imdb: imdb, trakt: trakt.map(String.init), tvdb: tvdb.map(String.init))
    }
}

struct TraktMedia: Decodable, Sendable {
    let title: String?
    let year: Int?
    let ids: TraktIDs
}

struct TraktWatchedMovie: Decodable {
    let lastWatchedAt: String?
    let movie: TraktMedia
}

struct TraktWatchedShow: Decodable {
    let lastWatchedAt: String?
    let show: TraktMedia
    let seasons: [TraktSeason]?
}

struct TraktSeason: Decodable {
    let number: Int
    let episodes: [TraktEpisodeNumber]
}

struct TraktEpisodeNumber: Decodable {
    let number: Int
}

struct TraktUserSettings: Decodable {
    struct User: Decodable { let username: String? }
    let user: User?
}

/// A watchlist, rating or list entry: one of movie or show (episodes and seasons are skipped).
struct TraktItem: Decodable {
    let type: String
    let rating: Int?
    let movie: TraktMedia?
    let show: TraktMedia?
}

struct TraktList: Decodable {
    struct IDs: Decodable { let trakt: Int }
    let name: String
    let ids: IDs
}
