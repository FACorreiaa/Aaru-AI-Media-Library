import AaruCore
import Foundation
import Testing
@testable import aaru

extension StremioImportTests {
    /// Bleach: Thousand-Year Blood War in a Stremio history: its own IMDb series in Cinemeta, which
    /// TMDB answers with a near-empty entry, while TVDB's id is Bleach's, where it is season 2.
    @Test("A series TMDB lists apart is imported onto the show TVDB names, ticks placed by release day")
    func tvdbShow() async throws {
        try await LibraryHarness.run { env in
            let (part, own) = (Self.imdb(), Self.imdb())
            let tvdb = Int.random(in: 100_000 ... 999_999)
            let duplicate = stubSplitShow(env, own: own, part: part, tvdb: tvdb)
            let week = Self.week
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let stremio = FakeStremio()
            // Cinemeta: S1E1, S1E2, S2E1, S2E2 out weeks 1 to 4; the first three watched.
            stremio.videos = [part: [(1, 1), (1, 2), (2, 1), (2, 2)].enumerated().map { index, pair in
                [
                    "id": "\(part):\(pair.0):\(pair.1)",
                    "season": pair.0,
                    "episode": pair.1,
                    "released": iso.string(from: week(index + 1)),
                ]
            }]
            stremio.tvdb = [part: tvdb]
            stremio.library = [
                Self.libraryItem(part, "series", state: ["timeOffset": 600, "watched": "\(part):2:2:4:eJxjBwAACAAI"]),
            ]
            let service = service(env, stremio.account)
            _ = try await service.startStremioLink(userID: env.userID)
            stremio.approve()
            guard case let .imported(job) = try await service.pollStremioLink(code: "3AP9", userID: env.userID)
            else { Issue.record("expected an import"); return }
            while try await service.runNext(for: env.userID) {}
            _ = try await service.apply(job.id, userID: env.userID)

            let showItem = try await item(env, own, .show)
            #expect(try await env.stores.library.watched(itemID: showItem.id) == [
                EpisodeKey(season: 2, episode: 1), EpisodeKey(season: 2, episode: 2),
                EpisodeKey(season: 2, episode: 3),
            ])
            #expect(try await env.stores.titles.find(ids: ExternalIDs(tmdb: duplicate), type: .show) == nil)
        }
    }

    /// Week `count` after 2024-01-01.
    static func week(_ count: Int) -> Date {
        Date(timeIntervalSince1970: 1_704_067_200 + Double(count) * 7 * 86400)
    }

    /// The show (its own IMDb id, TVDB's id, season 2 out weeks 1 to 4) and TMDB's one-episode
    /// entry for the part's IMDb id. Returns the entry's TMDB id.
    func stubSplitShow(_ env: LibraryHarness, own: String, part: String, tvdb: Int) -> String {
        let (tmdb, duplicate) = (uniqueID("tmdb"), uniqueID("tmdb"))
        let week = Self.week
        for (id, ids, name) in [
            (tmdb, ExternalIDs(tmdb: tmdb, imdb: own, tvdb: String(tvdb)), "Split Show"),
            (duplicate, ExternalIDs(tmdb: duplicate, imdb: part), "Split Show: Part"),
        ] {
            env.fake.stubTitle(CatalogTitle(
                hit: CatalogHit(
                    type: .show, title: name, originalTitle: nil, year: 2004, posterURL: nil, overview: nil,
                    byline: nil, ids: ids, isAnime: true
                ),
                status: .returning, runtimeMinutes: 24
            ))
            let episodes = id == tmdb
                ? (1 ... 2).map { (1, $0, week($0 - 40)) } + (1 ... 4).map { (2, $0, week($0)) }
                : [(1, 13, week(-30))]
            env.fake.stubEpisodes(id, CatalogEpisodes(status: .returning, episodes: episodes.map { item in
                CatalogEpisode(
                    season: item.0, episode: item.1, name: nil, airsAt: item.2, runtimeMinutes: 24, tmdbEpisodeID: nil
                )
            }))
        }
        return duplicate
    }
}
