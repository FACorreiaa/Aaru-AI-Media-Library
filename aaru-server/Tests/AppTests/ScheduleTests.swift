import AaruCore
import Foundation
import Testing
@testable import aaru

@Suite("Calendar and Up Next (CAL-001, UPN-001)", .serialized)
struct ScheduleTests {
    static let day: TimeInterval = 86400

    /// A show whose episodes air at the given offsets (in days) from now, all season 1.
    func stubAiring(_ env: LibraryHarness, _ name: String, days: [Double], status: TitleStatus = .returning) -> String {
        let tmdb = uniqueID("tmdb")
        env.fake.stubTitle(CatalogTitle(
            hit: CatalogHit(
                type: .show, title: name, originalTitle: nil, year: 2026, posterURL: nil, overview: nil,
                byline: nil, ids: ExternalIDs(tmdb: tmdb), isAnime: false
            ),
            status: status, runtimeMinutes: nil
        ))
        let now = Date()
        env.fake.stubEpisodes(tmdb, CatalogEpisodes(status: status, episodes: days.enumerated().map { index, offset in
            CatalogEpisode(
                season: 1, episode: index + 1, name: "\(name) \(index + 1)",
                airsAt: now.addingTimeInterval(offset * Self.day), runtimeMinutes: 50, tmdbEpisodeID: nil
            )
        }))
        return tmdb
    }

    func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    @Test("CAL-001: one row per airing episode of tracked shows, by air time, premiere and finale flagged")
    func week() async throws {
        try await LibraryHarness.run { env in
            // Season premieres in 1 day; episodes 2 and 3 (the finale) air in 3 and 5 days.
            _ = try await env.add("show", tmdb: stubAiring(env, "Arcane", days: [1, 3, 5]), status: "wishlist")
            // Aired long ago: not in this week.
            _ = try await env.add("show", tmdb: stubAiring(env, "Old", days: [-200, -199]), status: "in_progress")
            // Airing this week, but dropped: not tracked.
            _ = try await env.add("show", tmdb: stubAiring(env, "Dropped", days: [2]), status: "dropped")
            // Another user's show airing this week.
            let (_, other) = try await signedInUser(env.stores)
            _ = try await env.send(.post, "/v1/library/items", json: [
                "mediaRef": ["type": "show", "ids": ["tmdb": stubAiring(env, "Theirs", days: [2])]],
            ], token: other)

            let now = Date()
            let reply = try await env.send(
                .get,
                "/v1/calendar?from=\(iso(now))&to=\(iso(now.addingTimeInterval(7 * Self.day)))"
            )
            let items = try #require(try reply.json()["items"] as? [[String: Any]])
            #expect(items.compactMap { $0["number"] as? Int } == [1, 2, 3])
            #expect(items.compactMap { $0["kind"] as? String } == ["premiere", "regular", "finale"])
            #expect(items.allSatisfy { ($0["title"] as? [String: Any])?["title"] as? String == "Arcane" })

            let tooLong = try await env.send(
                .get,
                "/v1/calendar?from=\(iso(now))&to=\(iso(now.addingTimeInterval(40 * Self.day)))"
            )
            #expect(tooLong.status == .unprocessableContent)
        }
    }

    @Test("UPN-001: ticking the next episode advances the row; a caught-up show drops out; one call for home")
    func upNext() async throws {
        try await LibraryHarness.run { env in
            // Three aired episodes and one airing next week.
            let id = try await env.add("show", tmdb: stubAiring(env, "Severance", days: [-30, -23, -16, 7]))
            _ = try await env.send(.put, "/v1/library/items/\(id)/episodes/1/1", json: ["watched": true])
            let movie = try await env.add("movie", tmdb: env.stubMovie("Arrival"))

            var home = try await env.send(.get, "/v1/up-next").json()
            var row = try #require((home["continueWatching"] as? [[String: Any]])?.first)
            #expect((row["next"] as? [String: Any])?["number"] as? Int == 2)
            #expect(row["remainingCount"] as? Int == 2)
            #expect(row["remainingMinutes"] as? Int == 100, "two aired episodes of 50 minutes")
            #expect(row["isFinale"] as? Bool == false)
            #expect((home["startWatching"] as? [[String: Any]])?
                .compactMap { $0["libraryItemId"] as? String } == [movie])

            _ = try await env.send(.put, "/v1/library/items/\(id)/episodes/1/2", json: ["watched": true])
            home = try await env.send(.get, "/v1/up-next").json()
            row = try #require((home["continueWatching"] as? [[String: Any]])?.first)
            #expect((row["next"] as? [String: Any])?["number"] as? Int == 3)

            _ = try await env.send(.put, "/v1/library/items/\(id)/episodes/1/3", json: ["watched": true])
            home = try await env.send(.get, "/v1/up-next").json()
            #expect((home["continueWatching"] as? [Any])?.isEmpty == true, "caught up until episode 4 airs")
        }
    }

    @Test("UPN-001: the last aired episode of a season is flagged as the finale")
    func finaleFlag() async throws {
        try await LibraryHarness.run { env in
            let id = try await env.add("show", tmdb: stubAiring(env, "Shogun", days: [-20, -13], status: .ended))
            _ = try await env.send(.put, "/v1/library/items/\(id)/episodes/1/1", json: ["watched": true])
            let row =
                try #require(try (await env.send(.get, "/v1/up-next").json()["continueWatching"] as? [[String: Any]])?
                    .first)
            #expect(row["isFinale"] as? Bool == true)
        }
    }
}
