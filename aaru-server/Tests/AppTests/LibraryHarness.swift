import AaruCore
import Foundation
import Hummingbird
import HummingbirdTesting
@testable import aaru

/// HTTP tests against Postgres with a fake catalog: one signed-in user per test.
struct LibraryHarness {
    let client: any TestClientProtocol
    let stores: Stores
    let fake: FakeCatalog
    let token: String
    let userID: UserID

    struct Reply {
        let status: HTTPResponse.Status
        let body: Data

        func json() throws -> [String: Any] {
            try (JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
        }

        var text: String {
            String(bytes: body, encoding: .utf8) ?? ""
        }
    }

    static func run(
        clock: TestClock? = nil,
        _ body: @escaping @Sendable (LibraryHarness) async throws -> Void
    ) async throws {
        try await withMigratedStores { stores in
            let fake = FakeCatalog()
            let (userID, token) = try await signedInUser(stores)
            let auth = AuthService(stores: stores, apple: UntouchedAppleVerifier(), magicLinks: nil)
            var services = Services.make(stores: stores, catalogs: FakeCatalog.providers(fake), auth: auth)
            if let clock {
                services.catalog.now = { clock.now }
                services.library = LibraryService(
                    stores: stores,
                    resolver: TitleResolver(stores: stores, catalogs: FakeCatalog.providers(fake)),
                    catalog: services.catalog,
                    now: { clock.now }
                )
            }
            let app = try Application(router: buildRouter(stores: stores, services: services))
            try await app.test(.router) { client in
                try await body(LibraryHarness(client: client, stores: stores, fake: fake, token: token, userID: userID))
            }
        }
    }

    func send(
        _ method: HTTPRequest.Method,
        _ uri: String,
        json: Any? = nil,
        token: String? = nil
    ) async throws -> Reply {
        var headers: HTTPFields = [.authorization: "Bearer \(token ?? self.token)"]
        var buffer: ByteBuffer?
        if let json {
            headers[.contentType] = "application/json"
            buffer = try ByteBuffer(bytes: JSONSerialization.data(withJSONObject: json))
        }
        return try await client.execute(uri: uri, method: method, headers: headers, body: buffer) { response in
            Reply(status: response.status, body: Data(buffer: response.body))
        }
    }

    /// A movie the fake catalog can hydrate.
    func stubMovie(_ name: String) -> String {
        let tmdb = uniqueID("tmdb")
        fake.stubTitle(CatalogTitle(
            hit: CatalogHit(
                type: .movie, title: name, originalTitle: nil, year: 2001, posterURL: nil, overview: nil,
                byline: nil, ids: ExternalIDs(tmdb: tmdb), isAnime: false
            ),
            status: nil, runtimeMinutes: 100
        ))
        return tmdb
    }

    /// A show with `seasons` × `perSeason` episodes; `unaired` makes the last episode of
    /// the last season air in the future.
    func stubShow(
        _ name: String,
        status: TitleStatus,
        seasons: Int = 2,
        perSeason: Int = 3,
        unaired: Bool = false,
        now: Date = Date()
    ) -> String {
        let tmdb = uniqueID("tmdb")
        fake.stubTitle(CatalogTitle(
            hit: CatalogHit(
                type: .show, title: name, originalTitle: nil, year: 2020, posterURL: nil, overview: nil,
                byline: nil, ids: ExternalIDs(tmdb: tmdb), isAnime: false
            ),
            status: status, runtimeMinutes: nil
        ))
        var episodes: [CatalogEpisode] = []
        for season in 1 ... seasons {
            for episode in 1 ... perSeason {
                let isLast = season == seasons && episode == perSeason
                let airsAt = unaired && isLast ? now.addingTimeInterval(7 * 86400) : now
                    .addingTimeInterval(-400 * 86400)
                episodes.append(CatalogEpisode(
                    season: season, episode: episode, name: "S\(season)E\(episode)", airsAt: airsAt,
                    runtimeMinutes: 45, tmdbEpisodeID: nil
                ))
            }
        }
        fake.stubEpisodes(tmdb, CatalogEpisodes(status: status, episodes: episodes))
        return tmdb
    }

    /// Adds a title by tmdb id and returns the item's id.
    func add(_ type: String, tmdb: String, status: String? = nil) async throws -> String {
        var body: [String: Any] = ["mediaRef": ["type": type, "ids": ["tmdb": tmdb]]]
        body["status"] = status
        let reply = try await send(.post, "/v1/library/items", json: body)
        guard reply.status == .ok, let id = try reply.json()["id"] as? String else {
            throw HarnessError.unexpected(reply.status, reply.text)
        }
        return id
    }

    func actionCount() async throws -> Int {
        try await withSQL { sql in
            try await sql.raw("SELECT count(*)::int AS count FROM actions WHERE user_id = \(bind: userID.rawValue)")
                .first(decoding: CountRow.self)?.count ?? 0
        }
    }

    enum HarnessError: Error {
        case unexpected(HTTPResponse.Status, String)
    }
}
