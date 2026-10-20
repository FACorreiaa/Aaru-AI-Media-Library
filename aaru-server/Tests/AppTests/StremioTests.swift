import AaruCore
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import Testing
@testable import aaru

@Suite("Stremio addon (SCR-003)", .serialized)
struct StremioTests {
    struct Got {
        let status: HTTPResponse.Status
        let headers: HTTPFields
        let body: Data

        func json() throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: body) as? [String: Any] ?? [:]
        }
    }

    func get(_ env: LibraryHarness, _ uri: String, method: HTTPRequest.Method = .get) async throws -> Got {
        try await env.client.execute(uri: uri, method: method) { response in
            Got(status: response.status, headers: response.headers, body: Data(buffer: response.body))
        }
    }

    func connect(_ env: LibraryHarness, libraryWrites: Bool = false) async throws -> (secret: String, id: String) {
        let body = try await env.send(.post, "/v1/agent/tokens", json: [
            "kind": "stremio", "allowLibraryWrites": libraryWrites,
        ]).json()
        let token = try #require(body["token"] as? [String: Any])
        return try (#require(body["secret"] as? String), #require(token["id"] as? String))
    }

    func titleID(_ env: LibraryHarness, item: String) async throws -> String {
        let entry = try await env.send(.get, "/v1/library/items/\(item)").json()
        return try #require((entry["title"] as? [String: Any])?["id"] as? String)
    }

    /// An ended show with an IMDb id (so Stremio names it `tt…`) and two aired seasons of three.
    func stubIMDbShow(_ env: LibraryHarness, _ name: String) -> (tmdb: String, imdb: String) {
        let tmdb = uniqueID("tmdb")
        let imdb = "tt\(Int.random(in: 10_000_000 ... 99_999_999))"
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
        return (tmdb, imdb)
    }

    func watched(_ env: LibraryHarness, item: String) async throws -> [String] {
        let entry = try await env.send(.get, "/v1/library/items/\(item)").json()
        return (entry["watchedEpisodes"] as? [[String: Any]] ?? []).compactMap {
            guard let season = $0["season"] as? Int, let number = $0["number"] as? Int else { return nil }
            return "\(season)x\(number)"
        }
    }

    // MARK: Paths

    @Test("Paths parse with encoded ids and extra segments")
    func paths() throws {
        let player = try #require(StremioRequest(
            path: "/stremio/aaru_st_x/player/series/tt0903747%3A1%3A2/action=stop&currentTime=1200&duration=2400.json"
        ))
        #expect(player.token == "aaru_st_x")
        #expect(player.route == .resource(
            name: "player", type: "series", id: "tt0903747:1:2",
            extra: ["action": "stop", "currentTime": "1200", "duration": "2400"]
        ))
        let library = try #require(StremioRequest(
            path: "/stremio/t/library/series/tt1/action=watched&videoId=tt1%3A1%3A1%2Ctt1%3A1%3A2.json"
        ))
        #expect(library.route == .resource(
            name: "library", type: "series", id: "tt1", extra: ["action": "watched", "videoId": "tt1:1:1,tt1:1:2"]
        ))
        #expect(StremioRequest(path: "/stremio/t/catalog/movie/aaru-wishlist/skip=100.json")?.route
            == .resource(name: "catalog", type: "movie", id: "aaru-wishlist", extra: ["skip": "100"]))
        #expect(StremioRequest(path: "/stremio/t/manifest.json")?.route == .manifest)
        #expect(StremioRequest(path: "/stremio/t/configure")?.route == .configure)
        #expect(StremioRequest(path: "/stremio/t/meta/series/x") == nil, "no .json")
        #expect(StremioRequest(path: "/stremio/t/action%3Dstop%26currentTime%3D5.json") == nil)
        #expect(StremioRequest.extra("action%3Dstop%26currentTime%3D5") == ["action": "stop", "currentTime": "5"])

        #expect(try StremioID("tt0903747:1:2") == StremioID(
            base: .imdb("tt0903747"),
            episode: EpisodeKey(season: 1, episode: 2)
        ))
        #expect(StremioID("tt0903747")?.episode == nil)
        let uuid = UUID()
        #expect(StremioID("aaru:\(uuid.uuidString):0:3")?.base == .aaru(TitleID(uuid)))
        #expect(StremioID("kitsu:123:4") == nil)
        #expect(StremioID("tt12:x:1") == nil)
    }

    // MARK: Manifest and catalogs

    @Test("The manifest declares catalogs, meta, player and library, never stream; CORS on every answer")
    func manifest() async throws {
        try await LibraryHarness.run { env in
            let (secret, id) = try await connect(env)
            let got = try await get(env, "/stremio/\(secret)/manifest.json")
            #expect(got.status == .ok)
            #expect(got.headers[.accessControlAllowOrigin] == "*")
            let manifest = try got.json()
            let resources = (manifest["resources"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
            #expect(resources == ["catalog", "meta", "player", "library"])
            #expect(String(bytes: got.body, encoding: .utf8)?.contains("stream") == false)
            #expect((manifest["catalogs"] as? [Any])?.count == 4)
            // APP-014: the name reads per kind; the id installed addons use does not change.
            let catalogs = manifest["catalogs"] as? [[String: Any]] ?? []
            #expect(catalogs.filter { $0["id"] as? String == "aaru-wishlist" }.compactMap { $0["name"] as? String }
                == ["Aaru · Plan to watch", "Aaru · Plan to watch"])

            let options = try await get(env, "/stremio/\(secret)/manifest.json", method: .options)
            #expect(options.headers[.accessControlAllowOrigin] == "*")
            let stream = try await get(env, "/stremio/\(secret)/stream/movie/tt0133093.json")
            #expect(stream.status == .notFound && stream.headers[.accessControlAllowOrigin] == "*")
            let configure = try await get(env, "/stremio/\(secret)/configure")
            #expect(configure.status == .found)

            #expect(try await env.send(.delete, "/v1/agent/tokens/\(id)").status == .noContent)
            let revoked = try await get(env, "/stremio/\(secret)/manifest.json")
            #expect(revoked.status == .notFound && revoked.headers[.accessControlAllowOrigin] == "*")
        }
    }

    @Test("Catalogs: continue watching (tt and aaru: ids), the watchlist with skip, and empty once revoked")
    func catalogs() async throws {
        try await LibraryHarness.run { env in
            let (secret, id) = try await connect(env)
            let (tmdb, imdb) = stubIMDbShow(env, "Breaking Point")
            _ = try await env.add("show", tmdb: tmdb, status: "in_progress")
            let plain = try await env.add("show", tmdb: env.stubShow("No IMDb", status: .ended), status: "in_progress")
            let plainTitle = try await titleID(env, item: plain)
            _ = try await env.add("movie", tmdb: env.stubMovie("Wishlisted"))

            let continuing = try await get(env, "/stremio/\(secret)/catalog/series/aaru-continue.json").json()
            let ids = (continuing["metas"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
            #expect(ids.contains(imdb))
            #expect(ids.contains("aaru:\(plainTitle.lowercased())"))

            let movies = try await get(env, "/stremio/\(secret)/catalog/movie/aaru-wishlist.json").json()
            #expect((movies["metas"] as? [[String: Any]])?.compactMap { $0["name"] as? String } == ["Wishlisted"])
            let skipped = try await get(env, "/stremio/\(secret)/catalog/movie/aaru-wishlist/skip=100.json").json()
            #expect((skipped["metas"] as? [Any])?.isEmpty == true)

            let meta = try await get(env, "/stremio/\(secret)/meta/series/aaru%3A\(plainTitle.lowercased()).json")
            let videos = try (meta.json()["meta"] as? [String: Any])?["videos"] as? [[String: Any]]
            #expect(videos?.count == 6)
            #expect(videos?.first?["id"] as? String == "aaru:\(plainTitle.lowercased()):1:1")

            _ = try await env.send(.delete, "/v1/agent/tokens/\(id)")
            let revoked = try await get(env, "/stremio/\(secret)/catalog/series/aaru-continue.json")
            #expect(revoked.status == .ok)
            #expect(try (revoked.json()["metas"] as? [Any])?.isEmpty == true)
        }
    }

    // MARK: Events

    @Test("A player stop past 80% ticks the episode, by tt id and by aaru: id")
    func playerEvents() async throws {
        try await LibraryHarness.run { env in
            let (secret, _) = try await connect(env)
            let (tmdb, imdb) = stubIMDbShow(env, "Played Show")
            let item = try await env.add("show", tmdb: tmdb, status: "in_progress")
            let start = try await get(
                env,
                "/stremio/\(secret)/player/series/\(imdb)%3A1%3A2/action=start&currentTime=0&duration=0.json"
            )
            #expect(start.status == .ok)
            let stop = try await get(
                env,
                "/stremio/\(secret)/player/series/\(imdb)%3A1%3A2/action=stop&currentTime=2700000&duration=3000000.json"
            )
            #expect(stop.status == .ok)
            #expect(try await watched(env, item: item) == ["1x2"])

            let title = try await titleID(env, item: item).lowercased()
            _ = try await get(
                env,
                "/stremio/\(secret)/player/series/aaru%3A\(title)%3A1%3A3/action=stop&currentTime=95&duration=100.json"
            )
            #expect(try await watched(env, item: item).sorted() == ["1x2", "1x3"])
        }
    }

    @Test("library: watched ticks named episodes as one action; remove and add need opt-in or never apply")
    func libraryEvents() async throws {
        try await LibraryHarness.run { env in
            let (secret, _) = try await connect(env)
            let (tmdb, imdb) = stubIMDbShow(env, "Marked Show")
            let item = try await env.add("show", tmdb: tmdb, status: "in_progress")
            let before = try await env.actionCount()
            let videos = ["1:1", "1:2", "1:3"].map { "\(imdb)%3A\($0.replacingOccurrences(of: ":", with: "%3A"))" }
                .joined(separator: "%2C")
            let marked = try await get(
                env,
                "/stremio/\(secret)/library/series/\(imdb)/action=watched&videoId=\(videos).json"
            )
            #expect(marked.status == .ok)
            #expect(try await watched(env, item: item).sorted() == ["1x1", "1x2", "1x3"])
            #expect(try await env.actionCount() == before + 1)

            _ = try await get(env, "/stremio/\(secret)/library/series/\(imdb)/action=libraryRemove.json")
            _ = try await get(env, "/stremio/\(secret)/library/series/\(imdb)/action=unwatched&videoId=\(videos).json")
            let other = stubIMDbShow(env, "Not Added")
            _ = try await get(env, "/stremio/\(secret)/library/series/\(other.imdb)/action=libraryAdd.json")
            #expect(try await env.actionCount() == before + 1, "remove ignored; unwatched and add need library:write")
            #expect(try await env.send(.get, "/v1/library/items/\(item)").status == .ok, "still in the library")

            let writer = try await connect(env, libraryWrites: true)
            _ = try await get(env, "/stremio/\(writer.secret)/library/series/\(other.imdb)/action=libraryAdd.json")
            #expect(try await env.actionCount() == before + 2, "added to the watchlist with the opt-in")
        }
    }

    @Test("A token without scrobble:write is refused player events with 403")
    func scopes() async throws {
        try await LibraryHarness.run { env in
            let secret = AgentTokenService.stremioPrefix + OpaqueToken.generate()
            try await env.stores.agentTokens.create(
                AgentToken(
                    id: UUID(),
                    name: "Read only",
                    kind: .stremio,
                    scopes: [.libraryRead],
                    createdAt: Date(),
                    lastUsedAt: nil
                ),
                tokenHash: OpaqueToken.hash(secret), userID: env.userID
            )
            let got = try await get(
                env,
                "/stremio/\(secret)/player/movie/tt0133093/action=stop&currentTime=9&duration=10.json"
            )
            #expect(got.status == .forbidden)
            #expect(got.headers[.accessControlAllowOrigin] == "*")
        }
    }
}
