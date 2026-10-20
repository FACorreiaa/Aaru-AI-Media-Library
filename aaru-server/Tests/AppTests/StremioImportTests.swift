import AaruCore
import FluentSQL
import Foundation
import Testing
@testable import aaru

/// Stremio's three hosts and Cinemeta behind one stub. `approve()` flips the link read.
final class FakeStremio: @unchecked Sendable {
    // @unchecked: test-only; `lock` guards `isApproved`.
    private let lock = NSLock()
    private var isApproved = false
    let transport: StubTransport
    var library: [[String: Any]] = []
    var videos: [String: [[String: Any]]] = [:]

    init() {
        transport = StubTransport { _ in OutboundResponse(status: 500, body: Data()) }
    }

    func approve() {
        lock.withLock { isApproved = true }
    }

    var account: StremioAccount {
        func client(_ name: String) -> ProviderClient {
            var client = ProviderClient(
                name: name, transport: transport, pacer: RequestPacer(requestsPerSecond: 1000, burst: 100)
            )
            client.sleep = { _ in }
            return client
        }
        // JSON bodies made up front: the stub's closure is @Sendable.
        func encoded(_ object: Any) -> Data {
            (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        }
        let library = encoded(["result": library])
        let videos = videos.mapValues { list in encoded(["meta": ["videos": list]]) }
        transport.respond { [self] request in
            let path = request.url.path()
            func json(_ object: Any) -> OutboundResponse {
                OutboundResponse(status: 200, body: (try? JSONSerialization.data(withJSONObject: object)) ?? Data())
            }
            switch path {
            case "/api/v2/create":
                return json(["result": [
                    "success": true, "code": "3AP9", "link": "https://link.stremio.com/3AP9",
                    "qrcode": "https://link.stremio.com/qr?data=3AP9",
                ]])
            case "/api/v2/read":
                return lock.withLock { isApproved }
                    ? json(["result": ["success": true, "authKey": StremioImportTests.authKey]])
                    : json(["error": ["code": 101, "message": "Invalid or expired token"]])
            case "/api/datastoreGet":
                return OutboundResponse(status: 200, body: library)
            case "/api/logout":
                return json(["result": ["success": true]])
            default:
                let imdb = path.replacingOccurrences(of: "/meta/series/", with: "")
                    .replacingOccurrences(of: ".json", with: "")
                return OutboundResponse(status: videos[imdb] == nil ? 404 : 200, body: videos[imdb] ?? Data())
            }
        }
        return StremioAccount(link: client("stremio-link"), api: client("stremio"), cinemeta: client("cinemeta"))
    }

    func calls(_ path: String) -> [OutboundRequest] {
        transport.requests.filter { $0.url.path() == path }
    }
}

/// IMP-016: a Stremio account's history through a link code, against stub transports. No real
/// Stremio account, no network.
@Suite("Stremio history import", .serialized)
struct StremioImportTests {
    static let authKey = "stub-session-key-never-stored"

    static func imdb() -> String {
        "tt\(Int.random(in: 10_000_000 ... 99_999_999))"
    }

    /// Cinemeta's list for a show with a special and two seasons of three.
    static func videos(_ imdb: String) -> [[String: Any]] {
        [[0, 1], [1, 1], [1, 2], [1, 3], [2, 1], [2, 2], [2, 3]].map { pair in
            [
                "id": "\(imdb):\(pair[0]):\(pair[1])",
                "season": pair[0],
                "episode": pair[1],
                "released": "2020-01-0\(pair[1])T00:00:00.000Z",
            ]
        }
    }

    func service(_ env: LibraryHarness, _ stremio: StremioAccount) -> ImportService {
        ImportService(
            stores: env.stores,
            resolver: TitleResolver(stores: env.stores, catalogs: FakeCatalog.providers(env.fake)),
            stremio: stremio
        )
    }

    func stubShow(_ env: LibraryHarness, _ name: String, imdb: String) {
        let tmdb = uniqueID("tmdb")
        env.fake.stubTitle(CatalogTitle(
            hit: CatalogHit(
                type: .show, title: name, originalTitle: nil, year: 2020, posterURL: nil, overview: nil,
                byline: nil, ids: ExternalIDs(tmdb: tmdb, imdb: imdb), isAnime: false
            ),
            status: .ended, runtimeMinutes: nil
        ))
        let aired = Date().addingTimeInterval(-400 * 86400)
        env.fake.stubEpisodes(tmdb, CatalogEpisodes(status: .ended, episodes: (1 ... 2).flatMap { season in
            (1 ... 3).map { CatalogEpisode(
                season: season, episode: $0, name: "S\(season)E\($0)", airsAt: aired, runtimeMinutes: 45,
                tmdbEpisodeID: nil
            ) }
        }))
    }

    func stubMovie(_ env: LibraryHarness, _ name: String, imdb: String) {
        env.fake.stubTitle(CatalogTitle(
            hit: CatalogHit(
                type: .movie, title: name, originalTitle: nil, year: 2020, posterURL: nil, overview: nil,
                byline: nil, ids: ExternalIDs(tmdb: uniqueID("tmdb"), imdb: imdb), isAnime: false
            ),
            status: nil, runtimeMinutes: 100
        ))
    }

    func item(_ env: LibraryHarness, _ imdb: String, _ type: MediaType) async throws -> LibraryItem {
        let title = try #require(try await env.stores.titles.find(ids: ExternalIDs(imdb: imdb), type: type))
        return try #require(try await env.stores.library.item(userID: env.userID, titleID: title.id))
    }

    // MARK: Bitfield

    @Test("The watched bitfield marks the right episodes, and specials are left out")
    func bitfield() throws {
        let videos = (Self.videos("tt1") as [[String: Any]]).map { video in
            StremioWatched.Video(
                id: video["id"] as? String ?? "", season: video["season"] as? Int ?? 0,
                episode: video["episode"] as? Int ?? 0, released: nil
            )
        }.shuffled()
        // Bits 1, 2 and 4 (0b10110) over S0E1, S1E1, S1E2, S1E3, S2E1…: S1E1, S1E2, S2E1.
        let ticks = StremioWatched.episodes("tt1:2:3:7:eJwTAwAAFwAX", videos: videos)
        #expect(try ticks == [
            EpisodeKey(season: 1, episode: 1),
            EpisodeKey(season: 1, episode: 2),
            EpisodeKey(season: 2, episode: 1),
        ])
        // Written when the list was S1E1–S1E3 (bits 0 and 2), read after a special and S2 appeared.
        let grown = StremioWatched.episodes("tt1:1:3:3:eJxjBQAABgAG", videos: videos)
        #expect(try grown == [EpisodeKey(season: 1, episode: 1), EpisodeKey(season: 1, episode: 3)])
        // An anchor no longer in the list: nothing, as in Stremio.
        #expect(StremioWatched.episodes("tt1:9:9:3:eJxjBQAABgAG", videos: videos).isEmpty)
        #expect(StremioWatched.episodes("garbage", videos: videos).isEmpty)
    }

    // MARK: Mapper

    @Test("Library items map to rows: watched films finish, started ones are in progress, removed ones stay out")
    func mapper() throws {
        func item(
            _ id: String, _ type: String, removed: Bool = false, temp: Bool = false, state: [String: Any] = [:]
        ) throws -> StremioLibraryItem {
            let object: [String: Any] = [
                "_id": id, "type": type, "name": id, "removed": removed, "temp": temp, "state": state,
            ]
            return try JSONDecoder().decode(
                StremioLibraryItem.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }
        let rows = try StremioLibraryMapper.rows([
            item("tt1", "movie", state: ["timesWatched": 1, "lastWatched": "2024-05-01T20:00:00.000Z"]),
            item("tt2", "movie", state: ["timeOffset": 1200]),
            item("tt3", "movie"),
            item("tt4", "movie", removed: true),
            item("tt5", "series", removed: true, temp: true, state: ["watched": "tt5:1:1:1:eJxjBQAABgAG"]),
            item("tt6", "movie", removed: true, temp: true),
            item("kitsu:7", "series", state: ["timeOffset": 10]),
            item("tt8", "channel"),
        ])
        #expect(rows.map(\.sourceKey) == ["tt1", "tt2", "tt3", "tt5", "kitsu:7"])
        #expect(rows.map(\.status) == [.finished, .inProgress, .wishlist, .inProgress, .inProgress])
        #expect(rows[0].finishedAt == StremioAccount.date("2024-05-01T20:00:00.000Z"))
        #expect(rows[3].stremioWatched == "tt5:1:1:1:eJxjBQAABgAG" && rows[3].ids.imdb == "tt5")
        #expect(rows[4].unsupported != nil && rows[4].ids.imdb == nil)
    }

    // MARK: Link flow

    static func libraryItem(_ id: String, _ type: String, state: [String: Any]) -> [String: Any] {
        ["_id": id, "type": type, "name": id, "removed": false, "temp": false, "state": state]
    }

    @Test("Pending, then approved: the library is read once, logged out, and imported with its ticks")
    func linkFlow() async throws {
        try await LibraryHarness.run { env in
            let (film, show) = (Self.imdb(), Self.imdb())
            stubMovie(env, "Watched Film", imdb: film)
            stubShow(env, "Ticked Show", imdb: show)
            let stremio = FakeStremio()
            stremio.library = [
                Self.libraryItem(film, "movie", state: ["timesWatched": 2, "lastWatched": "2024-05-01T20:00:00.000Z"]),
                Self.libraryItem(show, "series", state: ["timeOffset": 600, "watched": "\(show):2:3:7:eJwTAwAAFwAX"]),
                ["_id": 42, "type": "movie"],
            ]
            stremio.videos = [show: Self.videos(show)]
            let service = service(env, stremio.account)

            let link = try await service.startStremioLink(userID: env.userID)
            #expect(link.code == "3AP9" && link.link.absoluteString == "https://link.stremio.com/3AP9")
            #expect(try await service.pollStremioLink(code: "3AP9", userID: env.userID) == .pending)
            stremio.approve()
            guard case let .imported(job) = try await service.pollStremioLink(code: "3AP9", userID: env.userID)
            else { Issue.record("expected an import"); return }
            #expect(job.source == .stremio)
            #expect(stremio.calls("/api/datastoreGet").count == 1)
            #expect(stremio.calls("/api/logout").count == 1, "the session is logged out")
            #expect(stremio.transport.requests.allSatisfy { request in
                request.headers.contains { $0.0 == "User-Agent" && $0.1 == StremioAccount.userAgent }
            })
            await #expect(throws: AppError.self, "single use") {
                try await service.pollStremioLink(code: "3AP9", userID: env.userID)
            }

            while try await service.runNext(for: env.userID) {}
            let planned = try await env.stores.importJobs.rows(jobID: job.id)
            #expect(planned.map(\.outcome) == [.create, .create])
            #expect(planned[1].row.stremioWatched == nil, "the bitfield is decoded once and kept as ticks")
            _ = try await service.apply(job.id, userID: env.userID)

            #expect(try await item(env, film, .movie).status == .finished)
            let showItem = try await item(env, show, .show)
            #expect(showItem.status == .inProgress)
            #expect(try await env.stores.library.watched(itemID: showItem.id) == [
                EpisodeKey(season: 1, episode: 1), EpisodeKey(season: 1, episode: 2),
                EpisodeKey(season: 2, episode: 1),
            ])

            #expect(try await Self.rowsMentioningKey() == 0, "the session key is never stored")
        }
    }

    static func rowsMentioningKey() async throws -> Int? {
        try await withSQL { sql in
            try await sql.raw("""
            SELECT count(*)::int AS count FROM import_rows WHERE row::text LIKE \(bind: "%\(authKey)%")
            """).first(decoding: Count.self)?.count
        }
    }

    struct Count: Decodable {
        let count: Int
    }

    @Test("An expired code answers 410 and is forgotten; someone else's code is not found")
    func expiry() async throws {
        try await LibraryHarness.run { env in
            let stremio = FakeStremio()
            let clock = TestClock(Date())
            var service = service(env, stremio.account)
            service.now = { clock.now }
            _ = try await service.startStremioLink(userID: env.userID)
            await #expect(throws: AppError.self) {
                try await service.pollStremioLink(code: "3AP9", userID: UserID())
            }
            clock.advance(by: StremioAccount.linkLifetime + 1)
            do {
                _ = try await service.pollStremioLink(code: "3AP9", userID: env.userID)
                Issue.record("expected 410")
            } catch let error as AppError {
                #expect(error.status == .gone && error.code == "stremio_link_expired")
            }
            #expect(try await env.stores.importJobs.stremioLinkExpiry(code: "3AP9", userID: env.userID) == nil)
            #expect(stremio.calls("/api/v2/read").isEmpty, "an expired code is not even asked about")
        }
    }

    @Test("Over HTTP: start returns the code, a pending poll is 204")
    func routes() async throws {
        let stremio = FakeStremio()
        try await LibraryHarness.run(stremio: stremio.account) { env in
            let start = try await env.send(.post, "/v1/imports/stremio/link")
            #expect(start.status == .ok)
            let body = try start.json()
            #expect(body["code"] as? String == "3AP9")
            #expect(body["qrcode"] as? String == "https://link.stremio.com/qr?data=3AP9")
            #expect(try await env.send(.post, "/v1/imports/stremio/link/3AP9").status == .noContent)
        }
    }
}
