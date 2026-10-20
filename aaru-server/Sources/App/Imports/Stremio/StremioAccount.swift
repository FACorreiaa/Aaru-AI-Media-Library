import Foundation

/// The parts of Stremio's account API one history import needs (IMP-016). Unofficial: it is what
/// Stremio's own apps call. Used once per import: a link code the user approves on stremio.com,
/// one library read, then logout. No password reaches Aaru and the session key is never stored
/// or logged; it lives in one request's local variables.
struct StremioAccount: Sendable {
    /// `link.stremio.com`: the device-link codes.
    let link: ProviderClient
    /// `api.strem.io`: the library read and logout.
    let api: ProviderClient
    /// Cinemeta: a show's episode list, which the watched bitfield is laid over.
    let cinemeta: ProviderClient
    var linkBase = URL(string: "https://link.stremio.com")!
    var apiBase = URL(string: "https://api.strem.io")!
    var cinemetaBase = URL(string: "https://v3-cinemeta.strem.io")!

    /// Stremio's edge refuses requests without one.
    static let userAgent = "Aaru/1.0 (+https://aaruapp.com)"
    /// How long a link code stays valid on Stremio's side. Pending and expired codes read the
    /// same there, so Aaru keeps the deadline itself.
    static let linkLifetime: TimeInterval = 5 * 60

    struct LinkCode: Equatable, Sendable {
        var code: String
        /// The page where the user approves the code.
        var link: URL
        /// A QR image of `link`, for scanning from a phone.
        var qrcode: URL
    }

    func createLink() async throws -> LinkCode {
        struct Created: Decodable {
            let code: String
            let link: URL
            let qrcode: URL
        }
        let created = try await call(link, Created.self, get(linkBase, "api/v2/create", ["type": "Create"]))
        return LinkCode(code: created.code, link: created.link, qrcode: created.qrcode)
    }

    /// The session key once the user has approved the code; nil while it is still pending.
    func readLink(code: String) async throws -> String? {
        struct Approved: Decodable {
            let authKey: String
        }
        do {
            return try await call(link, Approved.self, get(linkBase, "api/v2/read", ["type": "Read", "code": code]))
                .authKey
        } catch let error as StremioAPIError where error.code == 101 {
            return nil
        }
    }

    /// Every library item, including removed ones and ones only ever played (`temp`).
    func library(authKey: String) async throws -> [StremioLibraryItem] {
        try await call(api, [Lenient<StremioLibraryItem>].self, post(apiBase, "api/datastoreGet", [
            "authKey": .string(authKey), "collection": .string("libraryItem"), "ids": .array([]), "all": .bool(true),
        ])).compactMap(\.value)
    }

    /// Ends the session the link code opened. Best effort: the import is done either way.
    func logout(authKey: String) async {
        _ = try? await api.data(post(apiBase, "api/logout", [
            "type": .string("Logout"), "authKey": .string(authKey),
        ]))
    }

    /// A show's episodes in Cinemeta, which Stremio's ids (`tt…:season:episode`) come from.
    /// Empty when Cinemeta does not know the show.
    func videos(imdb: String) async throws -> [StremioWatched.Video] {
        guard imdb.hasPrefix("tt"), imdb.dropFirst(2).allSatisfy(\.isNumber) else { return [] }
        let url = cinemetaBase.appending(path: "meta/series/\(imdb).json")
        let envelope: CinemetaEnvelope
        do {
            envelope = try await cinemeta.decode(CinemetaEnvelope.self, request(url))
        } catch let error as ProviderError where error.kind == .notFound {
            return []
        }
        return (envelope.meta?.videos ?? []).compactMap { video in
            guard let season = video.season, let episode = video.episode ?? video.number else { return nil }
            return StremioWatched.Video(
                id: video.id, season: season, episode: episode, released: video.released.flatMap(Self.date)
            )
        }
    }

    static func date(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    // MARK: Wire

    private func request(_ url: URL, method: String = "GET", body: Data? = nil) -> OutboundRequest {
        var headers = [("User-Agent", Self.userAgent), ("Accept", "application/json")]
        if body != nil {
            headers.append(("Content-Type", "application/json"))
        }
        return OutboundRequest(method: method, url: url, headers: headers, body: body)
    }

    private func get(_ base: URL, _ path: String, _ query: [String: String]) -> OutboundRequest {
        let url = base.appending(path: path)
            .appending(queryItems: query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) })
        return request(url)
    }

    private func post(_ base: URL, _ path: String, _ body: [String: JSONValue]) -> OutboundRequest {
        // Encoding a dictionary of JSON values cannot fail.
        request(base.appending(path: path), method: "POST", body: try? JSONEncoder().encode(body))
    }

    /// Stremio answers `{"result": …}` or `{"error": {"code", "message"}}`, both with status 200.
    private func call<T: Decodable>(
        _ client: ProviderClient,
        _: T.Type,
        _ request: OutboundRequest
    ) async throws -> T {
        let envelope = try await client.decode(StremioEnvelope<T>.self, request)
        if let result = envelope.result {
            return result
        }
        throw StremioAPIError(code: envelope.error?.code ?? 0)
    }
}

/// Cinemeta's `meta/series/{id}.json`, only the episode list.
private struct CinemetaEnvelope: Decodable {
    struct Meta: Decodable {
        let videos: [CinemetaVideo]?
    }

    let meta: Meta?
}

private struct CinemetaVideo: Decodable {
    let id: String
    let season: Int?
    let episode: Int?
    /// Older entries number episodes here instead.
    let number: Int?
    let released: String?
}

/// One element of a list that may not decode: an odd library item is dropped, not the import.
private struct Lenient<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: any Decoder) throws {
        value = try? T(from: decoder)
    }
}

/// Stremio's response shape.
private struct StremioEnvelope<T: Decodable>: Decodable {
    struct Failure: Decodable {
        let code: Int?
    }

    let result: T?
    let error: Failure?
}

/// An error Stremio's API reported in its body. 101 on a link read means "not approved yet".
struct StremioAPIError: Error, Equatable {
    let code: Int
}

/// A small JSON value, for request bodies.
private enum JSONValue: Encodable, Sendable {
    case string(String)
    case bool(Bool)
    case array([JSONValue])

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        }
    }
}
