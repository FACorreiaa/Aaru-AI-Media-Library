import AaruCore
import Foundation
import Testing
@testable import aaru

/// Stremio's episode numbers put on the TMDB show by release day (live test, 2026-10-22: Bleach:
/// Thousand-Year Blood War is its own IMDb series, seasons 1 to 4; TMDB keeps it as Bleach S2).
@Suite("Stremio episode numbers on the TMDB show", .serialized)
struct StremioEpisodeMapTests {
    static let start = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01, midnight UTC

    /// `count` weeks after `start`, at `hours` past midnight.
    static func week(_ count: Int, hours: Double = 0) -> Date {
        start.addingTimeInterval(Double(count) * 7 * 86400 + hours * 3600)
    }

    static func video(_ season: Int, _ episode: Int, _ released: Date?) -> StremioWatched.Video {
        StremioWatched.Video(id: "tt1:\(season):\(episode)", season: season, episode: episode, released: released)
    }

    static func aired(_ season: Int, _ episode: Int, _ airsAt: Date?) -> CatalogEpisode {
        CatalogEpisode(
            season: season, episode: episode, name: nil, airsAt: airsAt, runtimeMinutes: 24, tmdbEpisodeID: nil
        )
    }

    static func key(_ season: Int, _ episode: Int) throws -> EpisodeKey {
        try EpisodeKey(season: season, episode: episode)
    }

    @Test("An episode matches the TMDB episode out the same day, a few hours either way")
    func sameDay() throws {
        let listed = [Self.video(1, 1, Self.week(10)), Self.video(2, 1, Self.week(11))]
        let episodes = [
            Self.aired(1, 1, Self.week(0)), Self.aired(2, 1, Self.week(10, hours: 15)),
            Self.aired(2, 2, Self.week(11, hours: -9)),
        ]
        #expect(try StremioEpisodeMap.match(Self.key(2, 1), listed: listed, episodes: episodes) == Self.key(2, 2))
        #expect(try StremioEpisodeMap.match(Self.key(1, 1), listed: listed, episodes: episodes) == Self.key(2, 1))
    }

    @Test("Two episodes out one day pair up in order, only when both lists have two that day")
    func doubleBill() throws {
        let listed = [Self.video(1, 1, Self.week(3)), Self.video(1, 2, Self.week(3))]
        let both = [Self.aired(4, 7, Self.week(3)), Self.aired(4, 8, Self.week(3))]
        #expect(try StremioEpisodeMap.match(Self.key(1, 2), listed: listed, episodes: both) == Self.key(4, 8))
        #expect(try StremioEpisodeMap.match(Self.key(1, 2), listed: listed, episodes: [both[0]]) == nil)
    }

    @Test("No release day, no episode that day, or an unknown episode places nothing")
    func unplaced() throws {
        let listed = [Self.video(1, 1, nil), Self.video(1, 2, Self.week(5))]
        let episodes = [Self.aired(2, 1, Self.week(1)), Self.aired(0, 1, Self.week(5))]
        #expect(try StremioEpisodeMap.match(Self.key(1, 1), listed: listed, episodes: episodes) == nil)
        #expect(try StremioEpisodeMap.match(Self.key(1, 2), listed: listed, episodes: episodes) == nil)
        #expect(try StremioEpisodeMap.match(Self.key(3, 1), listed: listed, episodes: episodes) == nil)
    }

    // MARK: Through the addon

    /// A show (its own IMDb id) whose season 2 is IMDb series `part` in Cinemeta, seasons 1 and 2
    /// of two episodes each. Returns the show's TMDB id.
    func splitShow(_ env: LibraryHarness, part: String) -> String {
        let tmdb = uniqueID("tmdb")
        func title(_ imdb: String) -> CatalogTitle {
            CatalogTitle(
                hit: CatalogHit(
                    type: .show, title: "Split Show", originalTitle: nil, year: 2004, posterURL: nil, overview: nil,
                    byline: nil, ids: ExternalIDs(tmdb: tmdb, imdb: imdb), isAnime: true
                ),
                status: .returning, runtimeMinutes: 24
            )
        }
        env.fake.stubTitle(title("tt\(Int.random(in: 10_000_000 ... 99_999_999))"))
        // What TMDB answers for the part's IMDb id: the same show.
        env.fake.stubTitle(title(part))
        env.fake.stubEpisodes(tmdb, CatalogEpisodes(
            status: .returning,
            episodes:
            (1 ... 3).map { Self.aired(1, $0, Self.week($0 - 10)) }
                + (1 ... 4).map { Self.aired(2, $0, Self.week($0)) }
        ))
        return tmdb
    }

    func account(part: String, tvdb: String? = nil, cinemetaUp: Bool = true) -> StremioAccount {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let videos = [(1, 1), (1, 2), (2, 1), (2, 2)].enumerated().map { index, pair in
            [
                "id": "\(part):\(pair.0):\(pair.1)",
                "season": pair.0,
                "episode": pair.1,
                "released": iso.string(from: Self.week(index + 1)),
            ] as [String: Any]
        }
        var meta: [String: Any] = ["videos": videos]
        meta["tvdb_id"] = tvdb.flatMap { Int($0) }
        let body = (try? JSONSerialization.data(withJSONObject: ["meta": meta])) ?? Data()
        let transport = StubTransport { request in
            guard cinemetaUp else { return OutboundResponse(status: 500, body: Data()) }
            return request.url.path() == "/meta/series/\(part).json"
                ? OutboundResponse(status: 200, body: body) : OutboundResponse(status: 404, body: Data())
        }
        var client = ProviderClient(name: "cinemeta", transport: transport, pacer: RequestPacer(
            requestsPerSecond: 1000, burst: 100
        ))
        client.sleep = { _ in }
        client.maxAttempts = 1
        return StremioAccount(link: client, api: client, cinemeta: client)
    }

    @Test("A player stop and a library mark tick the TMDB episodes Stremio's numbers name")
    func translated() async throws {
        let part = "tt\(Int.random(in: 10_000_000 ... 99_999_999))"
        try await LibraryHarness.run(stremio: account(part: part)) { env in
            let addon = StremioTests()
            let (secret, _) = try await addon.connect(env)
            let tmdb = splitShow(env, part: part)
            let item = try await env.add("show", tmdb: tmdb, status: "in_progress")

            let stop = "/stremio/\(secret)/player/series/\(part)%3A2%3A1/"
                + "action=stop&currentTime=1400000&duration=1440000.json"
            #expect(try await addon.get(env, stop).status == .ok)
            #expect(try await addon.watched(env, item: item) == ["2x3"])

            let videos = ["1%3A1", "1%3A2"].map { "\(part)%3A\($0)" }.joined(separator: ",")
            _ = try await addon.get(
                env, "/stremio/\(secret)/library/series/\(part)/action=watched&videoId=\(videos).json"
            )
            #expect(try await addon.watched(env, item: item).sorted() == ["2x1", "2x2", "2x3"])
        }
    }

    @Test("With Cinemeta down, another IMDb series' numbers tick nothing rather than the wrong episode")
    func cinemetaDown() async throws {
        let part = "tt\(Int.random(in: 10_000_000 ... 99_999_999))"
        try await LibraryHarness.run(stremio: account(part: part, cinemetaUp: false)) { env in
            let addon = StremioTests()
            let (secret, _) = try await addon.connect(env)
            let tmdb = splitShow(env, part: part)
            let item = try await env.add("show", tmdb: tmdb, status: "in_progress")
            let stop = "/stremio/\(secret)/player/series/\(part)%3A1%3A1/"
                + "action=stop&currentTime=1400000&duration=1440000.json"
            _ = try await addon.get(env, stop)
            #expect(try await addon.watched(env, item: item).isEmpty)
        }
    }

    @Test("A series TMDB lists as a near-empty entry of its own is found by its TVDB id")
    func duplicateEntry() async throws {
        let part = "tt\(Int.random(in: 10_000_000 ... 99_999_999))"
        let tvdb = String(Int.random(in: 100_000 ... 999_999))
        try await LibraryHarness.run(stremio: account(part: part, tvdb: tvdb)) { env in
            let addon = StremioTests()
            let (secret, _) = try await addon.connect(env)
            // The show, with TVDB's id, and TMDB's own entry for the part's IMDb id, as Bleach's
            // `30984` and `336301` (one episode).
            let tmdb = uniqueID("tmdb")
            let duplicate = uniqueID("tmdb")
            for (id, ids) in [
                (tmdb, ExternalIDs(tmdb: tmdb, imdb: "tt\(Int.random(in: 10_000_000 ... 99_999_999))", tvdb: tvdb)),
                (duplicate, ExternalIDs(tmdb: duplicate, imdb: part)),
            ] {
                env.fake.stubTitle(CatalogTitle(
                    hit: CatalogHit(
                        type: .show, title: id == tmdb ? "Split Show" : "Split Show: Part", originalTitle: nil,
                        year: 2004, posterURL: nil, overview: nil, byline: nil, ids: ids, isAnime: true
                    ),
                    status: .returning, runtimeMinutes: 24
                ))
            }
            env.fake.stubEpisodes(tmdb, CatalogEpisodes(
                status: .returning, episodes: (1 ... 4).map { Self.aired(2, $0, Self.week($0)) }
            ))
            env.fake.stubEpisodes(duplicate, CatalogEpisodes(
                status: .returning, episodes: [Self.aired(1, 13, Self.week(-40))]
            ))
            let item = try await env.add("show", tmdb: tmdb, status: "in_progress")

            let stop = "/stremio/\(secret)/player/series/\(part)%3A2%3A2/"
                + "action=stop&currentTime=1400000&duration=1440000.json"
            #expect(try await addon.get(env, stop).status == .ok)
            #expect(try await addon.watched(env, item: item) == ["2x4"])
            // TMDB's own entry for the part never becomes a title.
            #expect(try await env.stores.titles.find(ids: ExternalIDs(tmdb: duplicate), type: .show) == nil)
        }
    }
}
