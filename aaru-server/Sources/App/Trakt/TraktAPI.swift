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
            url: TraktSettings.authURL.appendingPathComponent("oauth/token"),
            headers: headers(token: nil),
            body: JSONEncoder().encode(body)
        ), decoder: Self.decoder)
    }

    /// Ends this app's access on the user's Trakt account, which frees one of their app slots.
    func revoke(_ accessToken: String) async throws {
        _ = try await client.data(OutboundRequest(
            method: "POST",
            url: TraktSettings.authURL.appendingPathComponent("oauth/revoke"),
            headers: headers(token: nil),
            body: JSONEncoder().encode(["token": accessToken, "client_id": settings.clientID])
        ))
    }

    func username(token: String) async throws -> String? {
        try await get(TraktUserSettings.self, "users/settings", token: token).user?.username
    }

    func get<T: Decodable>(_: T.Type, _ path: String, token: String) async throws -> T {
        try await client.decode(T.self, request(path, token: token), decoder: Self.decoder)
    }

    /// Most pages Trakt allows per request; a larger `limit` is silently capped.
    static let pageSize = 250
    /// A runaway guard: 400 pages of 250 is 100,000 items of one kind.
    static let maxPages = 400

    /// Every page of a list. Trakt pages lists, watchlists, ratings and watched (and without
    /// `page`/`limit` returns only the first 10–100 items), and may send fewer items than asked.
    /// An endpoint that does not page sends no `X-Pagination-Page-Count`: one call has it all.
    func paged<T: Decodable>(
        _: T.Type,
        _ path: String,
        query: [URLQueryItem] = [],
        token: String
    ) async throws -> [T] {
        var items: [T] = []
        for page in 1 ... Self.maxPages {
            let response = try await client.response(request(path, query: query + [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "limit", value: String(Self.pageSize)),
            ], token: token))
            guard let batch = try? Self.decoder.decode([T].self, from: response.body) else {
                throw ProviderError(provider: client.name, kind: .malformed)
            }
            items += batch
            guard !batch.isEmpty, let pages = response.header("X-Pagination-Page-Count").flatMap(Int.init),
                  page < pages
            else { break }
        }
        return items
    }

    private func request(_ path: String, query: [URLQueryItem] = [], token: String) -> OutboundRequest {
        var url = TraktSettings.apiURL.appendingPathComponent(path)
        if !query.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = query
            url = components.url ?? url
        }
        return OutboundRequest(url: url, headers: headers(token: token), timeout: .seconds(30))
    }

    /// What Trakt asks of every call; the bearer token only on the user's own data.
    private func headers(token: String?) -> [(String, String)] {
        var headers = [
            ("Content-Type", "application/json"), ("User-Agent", TraktSettings.userAgent),
            ("trakt-api-version", "2"), ("trakt-api-key", settings.clientID),
        ]
        if let token {
            headers.append(("Authorization", "Bearer \(token)"))
        }
        return headers
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
