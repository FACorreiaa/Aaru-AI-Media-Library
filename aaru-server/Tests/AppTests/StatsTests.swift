import AaruCore
import FluentSQL
import Foundation
import Testing
@testable import aaru

extension UntouchedStore: StatsStore {
    func activity(userID _: UserID, from _: LocalDay, until _: LocalDay, timeZone _: TimeZone) async throws
        -> [StatsActivity]
    {
        throw Touched()
    }
}

@Suite("Period stats, pure (GAM-006a)")
struct StatsDigestTests {
    let utc = TimeZone.gmt

    func day(_ text: String) -> LocalDay {
        LocalDay(text) ?? LocalDay(year: 0, month: 1, day: 1)
    }

    func row(
        _ day: String,
        _ titleID: TitleID,
        type: MediaType = .show,
        anime: Bool = false,
        episodes: Int = 0,
        minutes: Int = 0,
        finished: Bool = false,
        rating: Double? = nil
    ) -> StatsActivity {
        let noon = ISO8601DateFormatter().date(from: "\(day)T12:00:00Z") ?? .distantPast
        return StatsActivity(
            day: self.day(day), titleID: titleID, type: type, isAnime: anime, rating: rating, episodes: episodes,
            minutes: minutes, finished: finished, firstAt: noon, lastAt: noon
        )
    }

    @Test("GAM-006a: a year has 12 month buckets; a month has one per day, leap days included")
    func buckets() {
        #expect(StatsPeriod(year: 2026, month: nil, timeZone: utc).bucketStarts.count == 12)
        #expect(StatsPeriod(year: 2028, month: 2, timeZone: utc).bucketStarts.count == 29)
        #expect(StatsPeriod(year: 2026, month: 12, timeZone: utc).end == day("2027-01-01"))
        #expect(day("2026-12-31").adding(days: 1) == day("2027-01-01"))
    }

    @Test("GAM-006a: the longest run is the earliest of the longest stretches of consecutive days")
    func longestRun() {
        let days = ["2026-01-30", "2026-01-31", "2026-02-01", "2026-03-01", "2026-03-02", "2026-03-03"]
            .map(day)
        let run = StatsDigest.longestRun(Set(days))
        #expect(run == PeriodStats.Run(days: 3, start: day("2026-01-30"), end: day("2026-02-01")))
        #expect(StatsDigest.longestRun([]) == nil)
    }

    @Test("GAM-006a: totals, anime counted once, top titles by time, ratings, busiest month, partial period")
    func digest() {
        let show = TitleID(), anime = TitleID(), movie = TitleID(), book = TitleID()
        let rows = [
            row("2026-03-10", show, episodes: 2, minutes: 90),
            row("2026-03-11", anime, anime: true, episodes: 3, minutes: 72, finished: true, rating: 9),
            row("2026-07-04", movie, type: .movie, minutes: 120, finished: true, rating: 6),
            row("2026-07-05", book, type: .book, finished: true),
        ]
        let digest = StatsDigest(
            rows,
            period: StatsPeriod(year: 2026, month: nil, timeZone: utc),
            today: day("2026-10-16")
        )
        #expect(digest.isPartial)
        #expect(digest.totals == PeriodStats.Totals(
            episodesWatched: 5, minutesWatched: 282, activeDays: 4,
            moviesFinished: 1, showsFinished: 0, animeFinished: 1, booksFinished: 1
        ))
        // A book takes no time, so it is not a top title.
        #expect(digest.topTitles.map(\.titleID) == [movie, show, anime])
        #expect(digest.ratingCount == 2 && digest.ratingMean == 7.5 && digest.highest?.titleID == anime)
        #expect(digest.first?.titleID == show && digest.last?.titleID == book)

        let titles = Dictionary(uniqueKeysWithValues: [show, anime, movie, book].map { id in
            (id, Title(id: id, type: .show, title: id.description))
        })
        let stats = digest.stats(titles: titles)
        #expect(stats.busiest?.start == day("2026-03-01")) // 162 minutes beat July's 120
        #expect(stats.buckets[6].finished == 2)
        #expect(stats.longestRun?.days == 2)

        let finishedYear = StatsDigest(
            [],
            period: StatsPeriod(year: 2025, month: nil, timeZone: utc),
            today: day("2026-10-16")
        )
        #expect(!finishedYear.isPartial)
        #expect(finishedYear.stats(titles: [:]).busiest == nil)
    }

    struct BadPeriod {
        var year: Int
        var month: Int?
        var zone: String
        var field: String
    }

    @Test("GAM-006a: a bad year, month, or time zone is 422 with a field detail")
    func validation() {
        let cases = [
            BadPeriod(year: 2026, month: 13, zone: "UTC", field: "month"),
            BadPeriod(year: 1200, month: nil, zone: "UTC", field: "year"),
            BadPeriod(year: 2026, month: nil, zone: "Mars/Olympus", field: "tz"),
        ]
        for bad in cases {
            #expect {
                try StatsService.period(year: bad.year, month: bad.month, timeZone: bad.zone)
            } throws: { error in
                let error = error as? AppError
                return error?.status == .unprocessableContent && error?.details?[bad.field] != nil
            }
        }
    }
}

@Suite("Period stats over the library (GAM-006a)", .serialized)
struct StatsTests {
    func setWatchedAt(_ itemID: String, season: Int, episode: Int, _ timestamp: String) async throws {
        let id = try #require(UUID(uuidString: itemID))
        try await withSQL { sql in
            try await sql.raw("""
            UPDATE episode_progress SET watched_at = \(bind: timestamp)::timestamptz
            WHERE library_item_id = \(bind: id) AND season = \(bind: season) AND episode = \(bind: episode)
            """).run()
        }
    }

    func totals(_ reply: LibraryHarness.Reply) throws -> [String: Int] {
        try (reply.json()["totals"] as? [String: Int]) ?? [:]
    }

    /// Three real ticks (Mar 10, Mar 11, Dec 31 23:30 UTC), a date-only finished film (Jun 1,
    /// rated 8), a season imported today, and another user's tick.
    func seed(_ env: LibraryHarness) async throws {
        let showID = try await env.add("show", tmdb: env.stubShow("Severance", status: .ended), status: "in_progress")
        for episode in 1 ... 3 {
            _ = try await env.send(.put, "/v1/library/items/\(showID)/episodes/1/\(episode)", json: ["watched": true])
        }
        try await setWatchedAt(showID, season: 1, episode: 1, "2026-03-10T12:00:00Z")
        try await setWatchedAt(showID, season: 1, episode: 2, "2026-03-11T12:00:00Z")
        // New Year's Eve in UTC, already 2027 in Kiritimati (UTC+14).
        try await setWatchedAt(showID, season: 1, episode: 3, "2026-12-31T23:30:00Z")

        // A date-only finish (a Letterboxd import) stays on its day west of UTC too.
        let movieID = try await env.add("movie", tmdb: env.stubMovie("Arrival"), status: "finished")
        _ = try await env.send(.patch, "/v1/library/items/\(movieID)", json: ["rating": 8])
        let movie = try #require(UUID(uuidString: movieID))
        try await withSQL { sql in
            try await sql.raw("""
            UPDATE library_items SET finished_at = '2026-06-01T00:00:00Z' WHERE id = \(bind: movie)
            """).run()
        }

        // Season 2 arrives by import: ticked today, but not watched today.
        let item = try #require(LibraryItemID(uuidString: showID))
        let seasonTwo = try (1 ... 3).map { try EpisodeKey(season: 2, episode: $0) }
        try await env.stores.library.apply(
            .batch([.setEpisodes(item, watch: seasonTwo, unwatch: [])]), userID: env.userID, actor: .user,
            kind: "import", summary: "Imported"
        )

        // Another user's watching never shows.
        let (_, other) = try await signedInUser(env.stores)
        let theirs = try #require(try await env.send(.post, "/v1/library/items", json: [
            "mediaRef": ["type": "show", "ids": ["tmdb": env.stubShow("Theirs", status: .ended)]],
        ], token: other).json()["id"] as? String)
        _ = try await env.send(.put, "/v1/library/items/\(theirs)/episodes/1/1", json: ["watched": true], token: other)
    }

    @Test("GAM-006a: real ticks and dated finishes count; imported ticks and other users' never do")
    func stats() async throws {
        try await LibraryHarness.run { env in
            try await seed(env)
            let reply = try await env.send(.get, "/v1/me/stats?year=2026")
            #expect(reply.status == .ok)
            #expect(try totals(reply) == [
                "episodesWatched": 3, "minutesWatched": 3 * 45 + 100, "activeDays": 4,
                "moviesFinished": 1, "showsFinished": 0, "animeFinished": 0, "booksFinished": 0,
            ])
            let body = try reply.json()
            #expect((body["topTitles"] as? [[String: Any]])?.count == 2)
            #expect((body["ratings"] as? [String: Any])?["mean"] as? Double == 8)
            // June's 100-minute film beats March's two episodes.
            #expect((body["busiest"] as? [String: Any])?["start"] as? String == "2026-06-01")
            #expect((body["longestRun"] as? [String: Any])?["days"] as? Int == 2)
        }
    }

    @Test("GAM-006a: day and month edges are the user's time zone; bad periods are 422")
    func timeZones() async throws {
        try await LibraryHarness.run { env in
            try await seed(env)
            let east = try await env.send(.get, "/v1/me/stats?year=2026&tz=Pacific/Kiritimati")
            #expect(try totals(east)["episodesWatched"] == 2)
            let nextYear = try await env.send(.get, "/v1/me/stats?year=2027&month=1&tz=Pacific/Kiritimati")
            #expect(try totals(nextYear)["episodesWatched"] == 1)
            #expect(try (nextYear.json()["buckets"] as? [Any])?.count == 31)

            let west = try await env.send(.get, "/v1/me/stats?year=2026&month=6&tz=America/Los_Angeles")
            #expect(try totals(west)["moviesFinished"] == 1)

            #expect(try await env.send(.get, "/v1/me/stats?year=2026&month=13").status == .unprocessableContent)
            #expect(try await env.send(.get, "/v1/me/stats?year=2026&tz=Nowhere").status == .unprocessableContent)
        }
    }

    @Test("GAM-006a: undoing a delete restores ticks without making them today's watching")
    func restoreIsNotActivity() async throws {
        try await LibraryHarness.run { env in
            let id = try await env.add("show", tmdb: env.stubShow("Lost", status: .ended))
            _ = try await env.send(.put, "/v1/library/items/\(id)/episodes/1/1", json: ["watched": true])
            _ = try await env.send(.delete, "/v1/library/items/\(id)")
            let actionID = try #require(
                try (await env.send(.get, "/v1/actions?limit=1").json()["items"] as? [[String: Any]])?
                    .first?["id"] as? String
            )
            _ = try await env.send(.post, "/v1/actions/\(actionID)/undo")
            let year = Calendar(identifier: .gregorian).component(.year, from: Date())
            let reply = try await env.send(.get, "/v1/me/stats?year=\(year)")
            #expect(try totals(reply)["episodesWatched"] == 0)
        }
    }
}
