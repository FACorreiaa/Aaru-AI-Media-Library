import AaruCore
import Foundation
import Testing
@testable import aaru

// GAM-006e: the Year in Review's genres, biggest day and persona.

extension StatsDigestTests {
    func row(
        _ day: String,
        _ titleID: TitleID,
        genres: [String],
        type: MediaType = .show,
        minutes: Int
    ) -> StatsActivity {
        var row = row(day, titleID, type: type, episodes: type == .show ? 1 : 0, minutes: minutes)
        row.genres = genres
        return row
    }

    var year: StatsPeriod {
        StatsPeriod(year: 2026, month: nil, timeZone: utc)
    }

    @Test("GAM-006e: top genres by time, then titles, then name; books and genre-less titles add nothing")
    func topGenres() {
        let severance = TitleID(), bear = TitleID(), fargo = TitleID(), book = TitleID()
        let rows = [
            row("2026-02-01", severance, genres: ["Drama", "Mystery"], minutes: 100),
            row("2026-02-02", bear, genres: ["Drama", "Comedy"], minutes: 50),
            row("2026-02-03", fargo, genres: ["Comedy", "Crime"], minutes: 50),
            row("2026-02-04", TitleID(), genres: [], minutes: 500),
            row("2026-02-05", book, genres: ["Fiction"], type: .book, minutes: 0),
        ]
        let digest = StatsDigest(rows, period: year, today: day("2026-12-31"))
        #expect(digest.topGenres == [
            PeriodStats.GenreTime(name: "Drama", minutes: 150, titles: 2),
            PeriodStats.GenreTime(name: "Comedy", minutes: 100, titles: 2),
            PeriodStats.GenreTime(name: "Mystery", minutes: 100, titles: 1),
        ])
    }

    @Test("GAM-006e: the biggest day is the one with the most time, the earliest on a tie")
    func biggestDay() {
        let show = TitleID()
        let rows = [
            row("2026-03-01", show, episodes: 2, minutes: 90),
            row("2026-03-05", show, episodes: 3, minutes: 90),
            row("2026-04-01", show, episodes: 1, minutes: 45),
            row("2026-04-02", TitleID(), type: .book, finished: true),
        ]
        let digest = StatsDigest(rows, period: year, today: day("2026-12-31"))
        // 90 minutes twice: more episodes wins.
        #expect(digest.biggestDay?.start == day("2026-03-05"))
        #expect(StatsDigest.biggestDay([
            PeriodStats.Bucket(start: day("2026-05-02"), episodes: 1, minutes: 30),
            PeriodStats.Bucket(start: day("2026-05-01"), episodes: 1, minutes: 30),
        ])?.start == day("2026-05-01"))
        #expect(StatsDigest.biggestDay([PeriodStats.Bucket(start: day("2026-05-01"), finished: 1)]) == nil)
    }

    @Test("GAM-006e: the persona is the first rule that holds, and none without activity")
    func persona() {
        func persona(_ rows: [StatsActivity]) -> PeriodStats.Persona? {
            StatsDigest(rows, period: year, today: day("2026-12-31")).persona()
        }
        let show = TitleID()
        #expect(persona([]) == nil)
        #expect(persona([row("2026-01-10", show, episodes: 6, minutes: 270)]) == .binger)
        let fortnight = (1 ... 14).map { row(String(format: "2026-06-%02d", $0), show, episodes: 1, minutes: 45) }
        #expect(persona(fortnight) == .binger)
        let books = (1 ... 2).map { row("2026-02-0\($0)", TitleID(), type: .book, finished: true) }
        #expect(persona(books + [row("2026-02-03", TitleID(), type: .movie, minutes: 100, finished: true)]) ==
            .bookworm)
        #expect(
            persona([row("2026-02-01", TitleID(), type: .book, finished: true)]) == .steady,
            "one book is not a habit"
        )
        #expect(persona([
            row("2026-03-01", TitleID(), anime: true, episodes: 2, minutes: 48),
            row("2026-03-02", TitleID(), type: .movie, minutes: 40, finished: true),
        ]) == .anime)
        let finishes = (1 ... 24).map { row(
            "2026-05-\(String(format: "%02d", $0))",
            TitleID(),
            type: .movie,
            minutes: 90,
            finished: true
        ) }
        #expect(persona(finishes) == .binger, "24 days in a row is a run before it is a count")
        let spread = (0 ..< 24).map { row(
            day("2026-01-01").adding(days: $0 * 2).description,
            TitleID(),
            type: .movie,
            minutes: 90,
            finished: true
        ) }
        #expect(persona(spread) == .completionist)
        #expect(persona([
            row("2026-07-01", TitleID(), type: .movie, minutes: 90, finished: true),
            row("2026-07-03", TitleID(), episodes: 1, minutes: 45),
            row("2026-07-05", TitleID(), type: .book, finished: true),
        ]) == .explorer)
        #expect(persona([row("2026-07-01", show, episodes: 1, minutes: 45)]) == .steady)
    }
}

extension StatsTests {
    @Test("GAM-006e: stored genres reach the stats; a title without genres adds none")
    func genresInStats() async throws {
        try await LibraryHarness.run { env in
            let showID = try await env.add(
                "show",
                tmdb: env.stubShow("Severance", status: .ended),
                status: "in_progress"
            )
            for episode in 1 ... 2 {
                _ = try await env.send(
                    .put,
                    "/v1/library/items/\(showID)/episodes/1/\(episode)",
                    json: ["watched": true]
                )
            }
            try await setWatchedAt(showID, season: 1, episode: 1, "2026-03-10T12:00:00Z")
            try await setWatchedAt(showID, season: 1, episode: 2, "2026-03-10T13:00:00Z")
            let item = try #require(UUID(uuidString: showID))
            try await withSQL { sql in
                try await sql.raw("""
                UPDATE titles SET genres = ARRAY['Drama', 'Mystery']
                WHERE id = (SELECT title_id FROM library_items WHERE id = \(bind: item))
                """).run()
            }
            let body = try await env.send(.get, "/v1/me/stats?year=2026").json()
            let genres = try #require(body["topGenres"] as? [[String: Any]])
            #expect(genres.compactMap { $0["name"] as? String } == ["Drama", "Mystery"])
            #expect(genres.first?["minutes"] as? Int == 90)
            #expect((body["biggestDay"] as? [String: Any])?["start"] as? String == "2026-03-10")
            #expect(body["persona"] as? String == "steady")
        }
    }
}
