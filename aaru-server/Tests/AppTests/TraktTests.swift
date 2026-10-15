import AaruCore
import Crypto
import FluentSQL
import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
@testable import aaru

/// IMP-002/003 against a stubbed Trakt. No network, no real client id.
@Suite("Trakt", .serialized)
struct TraktTests {
    /// Canned Trakt: routes by path; `nil` means 404. Records every request.
    final class FakeTrakt: @unchecked Sendable {
        // @unchecked: test-only; `lock` guards `routes`.
        private let lock = NSLock()
        private var routes: [String: (Int, String)] = [:]
        let transport: StubTransport

        init() {
            let box = FakeTraktBox()
            transport = StubTransport { request in box.trakt?.answer(request) ?? OutboundResponse(
                status: 500,
                body: Data()
            ) }
            box.trakt = self
        }

        func route(_ path: String, status: Int = 200, _ body: String) {
            lock.withLock { routes[path] = (status, body) }
        }

        private func answer(_ request: OutboundRequest) -> OutboundResponse {
            let path = String(request.url.path.dropFirst())
            guard let (status, body) = lock.withLock({ routes[path] }) else {
                return OutboundResponse(status: 404, body: Data())
            }
            return OutboundResponse(status: status, body: Data(body.utf8))
        }

        func requests(to path: String) -> [OutboundRequest] {
            transport.requests.filter { $0.url.path == "/" + path }
        }
    }

    static let cipher: TokenCipher = {
        let key = Data((0 ..< 32).map { _ in UInt8.random(in: 0 ... 255) }).base64EncodedString()
        guard let cipher = try? TokenCipher(base64Key: key) else { preconditionFailure("32 random bytes") }
        return cipher
    }()

    func api(_ fake: FakeTrakt) -> TraktAPI {
        TraktAPI(
            client: ProviderClient(
                name: "trakt", transport: fake.transport, pacer: RequestPacer(requestsPerSecond: 1000, burst: 100)
            ),
            settings: TraktSettings(
                clientID: "test-client",
                redirectURI: URL(string: "https://api.aaru.test/v1/imports/trakt/callback")!,
                returnPrefixes: ["aaru://", "https://web.aaru.test/"],
                tokenCipher: Self.cipher
            )
        )
    }

    func tokens(_ access: String, refresh: String = "rt-1") -> String {
        #"{"access_token":"\#(access)","refresh_token":"\#(refresh)","expires_in":7776000,"created_at":0}"#
    }

    /// Runs connect and the callback; returns the callback's Location.
    func connect(_ env: LibraryHarness, _ fake: FakeTrakt, returnTo: String = "aaru://settings") async throws
        -> (location: String, authorize: URLComponents)
    {
        fake.route("oauth/token", tokens("at-123"))
        fake.route("users/settings", #"{"user":{"username":"ana"}}"#)
        let start = try await env.send(.post, "/v1/imports/trakt/connect", json: ["returnTo": returnTo]).json()
        let authorize = try #require(URLComponents(string: start["authorizeUrl"] as? String ?? ""))
        let state = try #require(authorize.queryItems?.first { $0.name == "state" }?.value)
        let location = try await env.client.execute(
            uri: "/v1/imports/trakt/callback?code=abc&state=\(state)", method: .get
        ) { response in
            #expect(response.status == .found)
            return response.headers[.location] ?? ""
        }
        return (location, authorize)
    }

    @Test("IMP-002: PKCE S256 with no client secret; tokens sealed at rest; a callback works once")
    func connectWithPKCE() async throws {
        let fake = FakeTrakt()
        try await LibraryHarness.run(trakt: api(fake)) { env in
            let (location, authorize) = try await connect(env, fake)
            #expect(location == "aaru://settings?trakt=connected")
            let query = Dictionary(uniqueKeysWithValues: (authorize.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            #expect(authorize.host == "auth.trakt.tv")
            #expect(query["client_id"] == "test-client")
            #expect(query["code_challenge_method"] == "S256")

            let exchange = try #require(fake.requests(to: "oauth/token").first?.body)
            let sent = try #require(try JSONSerialization.jsonObject(with: exchange) as? [String: String])
            #expect(sent["client_secret"] == nil, "PKCE only: no secret, ever")
            #expect(PKCE.challenge(sent["code_verifier"] ?? "") == query["code_challenge"])
            #expect(sent["code"] == "abc")

            let stored = try await withSQL { sql in
                try await sql.raw("""
                SELECT access_token FROM trakt_connections WHERE user_id = \(bind: env.userID.rawValue)
                """).first(decoding: [String: String].self)?["access_token"]
            }
            let sealed = try #require(stored)
            #expect(!sealed.contains("at-123"), "the token is never stored in clear")
            #expect(try Self.cipher.open(sealed) == "at-123")

            let status = try await env.send(.get, "/v1/imports/trakt/connection").json()
            #expect(status["connected"] as? Bool == true)
            #expect(status["username"] as? String == "ana")

            let state = authorize.queryItems?.first { $0.name == "state" }?.value ?? ""
            try await env.client.execute(uri: "/v1/imports/trakt/callback?code=abc&state=\(state)", method: .get) {
                #expect($0.status == .badRequest, "a replayed callback is refused")
            }
            let evil = try await env.send(.post, "/v1/imports/trakt/connect", json: ["returnTo": "https://evil.test/"])
            #expect(evil.status == .unprocessableContent, "the browser only returns to Aaru")
        }
    }

    @Test("IMP-002: a token near expiry is refreshed before use, still without a secret")
    func refreshesExpiringToken() async throws {
        let fake = FakeTrakt()
        try await LibraryHarness.run(trakt: api(fake)) { env in
            _ = try await connect(env, fake)
            try await withSQL { sql in
                try await sql.raw("""
                UPDATE trakt_connections SET expires_at = now() - interval '1 day'
                WHERE user_id = \(bind: env.userID.rawValue)
                """).run()
            }
            fake.route("oauth/token", tokens("at-fresh", refresh: "rt-2"))
            let service = TraktConnectService(stores: env.stores, settings: api(fake).settings, api: api(fake))
            #expect(try await service.accessToken(userID: env.userID) == "at-fresh")
            let refresh = try #require(fake.requests(to: "oauth/token").last?.body)
            let sent = try #require(try JSONSerialization.jsonObject(with: refresh) as? [String: String])
            #expect(sent["grant_type"] == "refresh_token")
            #expect(sent["client_secret"] == nil)
        }
    }

    @Test(
        "IMP-003: history, episodes, watchlist, ratings and lists plan then apply; list-only stays off the shelf"
    )
    func traktImport() async throws {
        let fake = FakeTrakt()
        try await LibraryHarness.run(trakt: api(fake)) { env in
            _ = try await connect(env, fake)
            stubLibrary(env, fake)

            let created = try await env.send(.post, "/v1/imports/trakt")
            #expect(created.status == .accepted)
            let id = try #require(created.json()["id"] as? String)
            let planned = try await plan(env, fake, id: id)
            let rows = try #require(planned["rows"] as? [[String: Any]])
            let outcomes = Dictionary(uniqueKeysWithValues: rows.map {
                ($0["title"] as? String ?? "", $0["outcome"] as? String ?? "")
            })
            #expect(outcomes == ["Heat": "create", "Severance": "create", "Dune": "create", "Arrival": "skip"])

            #expect(try await env.send(.post, "/v1/imports/\(id)/apply").status == .ok)
            let items = try #require(try await env.send(.get, "/v1/library/sync").json()["items"] as? [[String: Any]])
            let byTitle = Dictionary(uniqueKeysWithValues: items.map {
                (($0["title"] as? [String: Any])?["title"] as? String ?? "", $0)
            })
            #expect(byTitle["Heat"]?["status"] as? String == "finished")
            #expect(byTitle["Heat"]?["rating"] as? Double == 9)
            #expect(byTitle["Dune"]?["status"] as? String == "wishlist")
            #expect(byTitle["Arrival"] == nil, "a list-only title does not join the library")
            let showID = try #require(byTitle["Severance"]?["id"] as? String)
            let show = try await env.send(.get, "/v1/library/items/\(showID)").json()
            #expect((show["watchedEpisodes"] as? [[String: Int]])?.count == 2)
            let lists = try await env.send(.get, "/v1/lists").json()
            let faves = try #require((lists["items"] as? [[String: Any]])?.first { $0["name"] as? String == "Faves" })
            #expect(faves["itemCount"] as? Int == 2, "Heat and the list-only Arrival")
        }
    }

    /// Four titles in the fake catalog and a Trakt library over them: Heat watched and rated,
    /// Severance with two episodes, Dune on the watchlist, Arrival only on the "Faves" list.
    func stubLibrary(_ env: LibraryHarness, _ fake: FakeTrakt) {
        let ids = (0 ..< 4).map { _ in Int.random(in: 10_000_000 ... 99_999_999) }
        let (heat, severance, dune, arrival) = (ids[0], ids[1], ids[2], ids[3])
        for (title, id, type) in [
            ("Heat", heat, MediaType.movie), ("Severance", severance, .show),
            ("Dune", dune, .movie), ("Arrival", arrival, .movie),
        ] {
            env.fake.stubTitle(CatalogTitle(
                hit: CatalogHit(
                    type: type, title: title, originalTitle: nil, year: 2000, posterURL: nil, overview: nil,
                    byline: nil, ids: ExternalIDs(tmdb: String(id)), isAnime: false
                ),
                status: type == .show ? .ended : nil, runtimeMinutes: nil
            ))
        }
        func media(_ title: String, _ id: Int) -> String {
            #"{"title":"\#(title)","year":2000,"ids":{"trakt":\#(id),"tmdb":\#(id)}}"#
        }
        let episodes = #"[{"number":1,"episodes":[{"number":1},{"number":2}]}]"#
        fake.route(
            "sync/watched/movies", #"[{"last_watched_at":"2024-02-01T20:00:00.000Z","movie":\#(media("Heat", heat))}]"#
        )
        fake.route("sync/watched/shows", #"[{"show":\#(media("Severance", severance)),"seasons":\#(episodes)}]"#)
        fake.route("sync/watchlist", #"[{"type":"movie","movie":\#(media("Dune", dune))}]"#)
        fake.route("sync/ratings", #"[{"type":"movie","rating":9,"movie":\#(media("Heat", heat))}]"#)
        fake.route("users/me/lists", #"[{"name":"Faves","ids":{"trakt":77}}]"#)
        let listed = [media("Heat", heat), media("Arrival", arrival)].map { #"{"type":"movie","movie":\#($0)}"# }
        fake.route("users/me/lists/77/items", "[" + listed.joined(separator: ",") + "]")
    }

    func importer(_ env: LibraryHarness, _ fake: FakeTrakt) -> ImportService {
        ImportService(
            stores: env.stores,
            resolver: TitleResolver(stores: env.stores, catalogs: FakeCatalog.providers(env.fake)),
            trakt: TraktImport(
                connect: TraktConnectService(stores: env.stores, settings: api(fake).settings, api: api(fake)),
                importer: TraktImporter(api: api(fake))
            )
        )
    }

    /// Runs this user's import through the worker until it leaves the queue.
    func plan(_ env: LibraryHarness, _ fake: FakeTrakt, id: String) async throws -> [String: Any] {
        let service = importer(env, fake)
        var detail: [String: Any] = [:]
        for _ in 0 ..< 50 {
            detail = try await env.send(.get, "/v1/imports/\(id)").json()
            let state = (detail["job"] as? [String: Any])?["state"] as? String
            if state != "queued", state != "running" {
                break
            }
            guard try await service.runNext(for: env.userID) else { break }
        }
        return detail
    }

    @Test("IMP-003: a revoked Trakt token fails the import at once and disconnects")
    func revokedToken() async throws {
        let fake = FakeTrakt()
        try await LibraryHarness.run(trakt: api(fake)) { env in
            _ = try await connect(env, fake)
            for path in [
                "sync/watched/movies",
                "sync/watched/shows",
                "sync/watchlist",
                "sync/ratings",
                "users/me/lists",
            ] {
                fake.route(path, status: 401, "{}")
            }
            let id = try #require(try await env.send(.post, "/v1/imports/trakt").json()["id"] as? String)
            let job = try #require(try await plan(env, fake, id: id)["job"] as? [String: Any])
            #expect(job["state"] as? String == "failed")
            #expect((job["errorSummary"] as? String)?.contains("Connect Trakt again") == true)
            let status = try await env.send(.get, "/v1/imports/trakt/connection").json()
            #expect(status["connected"] as? Bool == false)
        }
    }

    @Test("Without TRAKT_CLIENT_ID, connecting answers 503 and nothing else breaks")
    func notConfigured() async throws {
        try await LibraryHarness.run { env in
            let reply = try await env.send(.post, "/v1/imports/trakt/connect", json: ["returnTo": "aaru://settings"])
            #expect(reply.status == .serviceUnavailable)
            #expect(try await env.send(.post, "/v1/imports/trakt").status == .conflict)
        }
    }
}

/// Lets the stub transport reach the fake that owns it without a retain cycle.
final class FakeTraktBox: @unchecked Sendable {
    // @unchecked: test-only; set once in FakeTrakt.init before any request.
    weak var trakt: TraktTests.FakeTrakt?
}
