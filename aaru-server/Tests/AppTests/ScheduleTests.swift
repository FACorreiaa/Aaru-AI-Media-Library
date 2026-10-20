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
                "/v1/calendar?from=\(iso(now))&to=\(iso(now.addingTimeInterval(43 * Self.day)))"
            )
            #expect(tooLong.status == .unprocessableContent)

            // A browser's `toISOString()` carries milliseconds; the server reads it the same.
            let fractional = try await env.send(
                .get,
                "/v1/calendar?from=2026-10-18T00:00:00.000Z&to=2026-10-25T00:00:00.000Z"
            )
            #expect(fractional.status == .ok)
        }
    }

    @Test("APP-010: calendar rows carry the show's banner, network, and whether the time is exact")
    func artworkAndAirTime() async throws {
        try await LibraryHarness.run { env in
            let tmdb = stubAiring(env, "Andor", days: [1, 2])
            // The episode source refreshes the art; the second episode has an exact time.
            let now = Date()
            env.fake.stubEpisodes(tmdb, CatalogEpisodes(
                status: .returning,
                episodes: [
                    CatalogEpisode(
                        season: 1, episode: 1, name: "One", airsAt: now.addingTimeInterval(Self.day),
                        runtimeMinutes: 50, tmdbEpisodeID: nil
                    ),
                    CatalogEpisode(
                        season: 1, episode: 2, name: "Two", airsAt: now.addingTimeInterval(2 * Self.day),
                        runtimeMinutes: 50, tmdbEpisodeID: nil, airTimeKnown: true,
                        overview: "Cassian meets Luthen."
                    ),
                ],
                backdropURL: URL(string: "https://image.tmdb.org/t/p/w780/andor.jpg"),
                network: "Disney+"
            ))
            _ = try await env.add("show", tmdb: tmdb)

            let reply = try await env.send(
                .get,
                "/v1/calendar?from=\(iso(now))&to=\(iso(now.addingTimeInterval(7 * Self.day)))"
            )
            let items = try #require(try reply.json()["items"] as? [[String: Any]])
            #expect(items.compactMap { $0["airTimeKnown"] as? Bool } == [false, true])
            #expect(items.last?["episodeOverview"] as? String == "Cassian meets Luthen.")
            let title = try #require(items.first?["title"] as? [String: Any])
            #expect(title["backdropUrl"] as? String == "https://image.tmdb.org/t/p/w780/andor.jpg")
            #expect(title["network"] as? String == "Disney+")
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

    /// A book the fake catalog can hydrate, added with `status`; returns the item id.
    func addBook(_ env: LibraryHarness, _ name: String, status: String) async throws -> String {
        let olid = uniqueID("OL")
        env.fake.stubTitle(CatalogTitle(
            hit: CatalogHit(
                type: .book, title: name, originalTitle: nil, year: 2001, posterURL: nil, overview: nil,
                byline: nil, ids: ExternalIDs(openLibrary: olid), isAnime: false
            ),
            status: nil, runtimeMinutes: nil
        ))
        let reply = try await env.send(.post, "/v1/library/items", json: [
            "mediaRef": ["type": "book", "ids": ["openLibrary": olid]], "status": status,
        ])
        return try #require(try reply.json()["id"] as? String)
    }

    /// Backdates an item's last change by `days`.
    func touch(_ itemID: String, daysAgo days: Int) async throws {
        let id = try #require(UUID(uuidString: itemID))
        try await withSQL { sql in
            try await sql.raw("""
            UPDATE library_items SET updated_at = now() - \(bind: days)::int * interval '1 day' WHERE id = \(bind: id)
            """).run()
        }
    }

    @Test("UPN-002: counts per status, for the caller only")
    func counts() async throws {
        try await LibraryHarness.run { env in
            _ = try await env.add("movie", tmdb: env.stubMovie("Plan"))
            _ = try await env.add("movie", tmdb: env.stubMovie("Seen"), status: "finished")
            _ = try await env.add("movie", tmdb: env.stubMovie("Quit"), status: "dropped")
            _ = try await addBook(env, "Reading", status: "in_progress")
            let (_, other) = try await signedInUser(env.stores)
            _ = try await env.send(.post, "/v1/library/items", json: [
                "mediaRef": ["type": "movie", "ids": ["tmdb": env.stubMovie("Theirs")]], "status": "dropped",
            ], token: other)

            let counts = try await env.send(.get, "/v1/up-next").json()["counts"] as? [String: Int]
            #expect(counts == ["wishlist": 1, "inProgress": 1, "finished": 1, "dropped": 1])
        }
    }

    @Test("UPN-002: dropped items and 30-day-old progress are unfinished; never also in Continue watching")
    func unfinished() async throws {
        try await LibraryHarness.run { env in
            let dropped = try await env.add(
                "show", tmdb: stubAiring(env, "Lost Cause", days: [-30, -23]), status: "dropped"
            )
            let stale = try await addBook(env, "Old Book", status: "in_progress")
            let fresh = try await addBook(env, "Recent Book", status: "in_progress")
            // In progress, untouched for 40 days, but with an aired episode to watch: Continue watching.
            let continuing = try await env.add(
                "show", tmdb: stubAiring(env, "Paused Show", days: [-60, -50]), status: "in_progress"
            )
            try await touch(stale, daysAgo: 31)
            try await touch(fresh, daysAgo: 29)
            try await touch(continuing, daysAgo: 40)
            try await touch(dropped, daysAgo: 2)
            let (_, other) = try await signedInUser(env.stores)
            _ = try await env.send(.post, "/v1/library/items", json: [
                "mediaRef": ["type": "movie", "ids": ["tmdb": env.stubMovie("Their Drop")]], "status": "dropped",
            ], token: other)

            let home = try await env.send(.get, "/v1/up-next").json()
            let rows = try #require(home["unfinished"] as? [[String: Any]])
            #expect(rows.compactMap { $0["libraryItemId"] as? String } == [dropped, stale], "newest change first")
            #expect(rows.compactMap { $0["reason"] as? String } == ["dropped", "stalled"])
            #expect((rows.first?["next"] as? [String: Any])?["number"] as? Int == 1, "a show resumes where it stopped")
            #expect(rows.last?["next"] == nil)
            #expect(rows.allSatisfy { $0["since"] is String })
            let continued = home["continueWatching"] as? [[String: Any]]
            #expect(continued?.compactMap { $0["libraryItemId"] as? String } == [continuing])
        }
    }
}
