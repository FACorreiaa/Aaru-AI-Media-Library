import AaruCore
import Foundation
import Testing
@testable import aaru

// GAM-006d: the last 7 and 30 days, beside the calendar spans in StatsTests.swift.

extension StatsDigestTests {
    @Test("GAM-006d: the last 7 or 30 days end today, one bucket per day, the window before is prior")
    func rollingPeriod() throws {
        let week = StatsPeriod(lastDays: .last7, today: day("2026-10-21"), timeZone: utc)
        #expect(week.start == day("2026-10-15") && week.end == day("2026-10-22"))
        #expect(week.lastDay == day("2026-10-21"))
        #expect(week.bucketStarts.count == 7 && week.bucket(of: day("2026-10-17")) == day("2026-10-17"))
        let prior = try #require(week.previous)
        #expect(prior.start == day("2026-10-08") && prior.end == day("2026-10-15"))
        #expect(prior.bucketStarts.count == 7)

        let month = StatsPeriod(lastDays: .last30, today: day("2027-01-03"), timeZone: utc)
        #expect(month.start == day("2026-12-05") && month.bucketStarts.count == 30)
        #expect(month.year == 2027, "the last year the window touches")
        #expect(StatsPeriod(year: 2026, month: 3, timeZone: utc).previous == nil)

        let digest = StatsDigest(
            [row("2026-10-15", TitleID(), episodes: 1), row("2026-10-21", TitleID(), episodes: 2)],
            period: week, today: day("2026-10-21")
        )
        #expect(digest.isPartial)
        #expect(digest.buckets.map(\.episodes) == [1, 0, 0, 0, 0, 0, 2])
    }

    @Test("GAM-006d: a rolling span takes no year or month")
    func rollingValidation() throws {
        let now = Date()
        for span in [StatsPeriod.Span.last7, .last30] {
            #expect {
                try StatsService.period(span: span, year: 2026, month: nil, timeZone: nil, now: now)
            } throws: { ($0 as? AppError)?.details?["span"] != nil }
        }
        let tokyo = try StatsService.period(span: .last30, year: nil, month: nil, timeZone: "Asia/Tokyo", now: now)
        #expect(tokyo.span == .last30 && tokyo.lastDay == LocalDay(now, in: tokyo.timeZone))
    }
}

extension StatsTests {
    /// Noon UTC `days` days before today, as `setWatchedAt` takes it.
    func daysAgo(_ days: Int) -> String {
        let day = LocalDay(Date(), in: .gmt).adding(days: -days)
        return "\(day)T12:00:00Z"
    }

    @Test("GAM-006d: the last 7 and 30 days, with the window before as prior; imports never count")
    func rolling() async throws {
        try await LibraryHarness.run { env in
            let showID = try await env.add(
                "show", tmdb: env.stubShow("Severance", status: .ended, perSeason: 4), status: "in_progress"
            )
            for episode in 1 ... 4 {
                _ = try await env.send(
                    .put,
                    "/v1/library/items/\(showID)/episodes/1/\(episode)",
                    json: ["watched": true]
                )
            }
            // Today, three days ago, nine days ago (last week's window), forty days ago (neither).
            for (episode, days) in [(1, 0), (2, 3), (3, 9), (4, 40)] {
                try await setWatchedAt(showID, season: 1, episode: episode, daysAgo(days))
            }
            // A season imported today is not today's watching.
            let item = try #require(LibraryItemID(uuidString: showID))
            try await env.stores.library.apply(
                .batch([.setEpisodes(item, watch: [EpisodeKey(season: 2, episode: 1)], unwatch: [])]),
                userID: env.userID, actor: .user, kind: "import", summary: "Imported"
            )

            let week = try await env.send(.get, "/v1/me/stats?span=last7")
            #expect(week.status == .ok)
            let body = try week.json()
            #expect(body["span"] as? String == "last7")
            #expect(body["until"] as? String == LocalDay(Date(), in: .gmt).description)
            #expect(body["from"] as? String == LocalDay(Date(), in: .gmt).adding(days: -6).description)
            #expect((body["buckets"] as? [Any])?.count == 7)
            #expect(try totals(week)["episodesWatched"] == 2)
            #expect(try totals(week)["activeDays"] == 2)
            let prior = try #require(body["prior"] as? [String: Int])
            #expect(prior["episodesWatched"] == 1)

            let month = try await env.send(.get, "/v1/me/stats?span=last30")
            #expect(try totals(month)["episodesWatched"] == 3)
            #expect(try ((month.json()["prior"] as? [String: Int])?["episodesWatched"]) == 1)
            #expect(try (month.json()["buckets"] as? [Any])?.count == 30)

            let calendar = try await env.send(.get, "/v1/me/stats?year=2026")
            #expect(try calendar.json()["prior"] == nil && calendar.json()["from"] == nil)
            for bad in ["span=last7&year=2026", "span=last30&month=2"] {
                #expect(try await env.send(.get, "/v1/me/stats?\(bad)").status == .unprocessableContent, "\(bad)")
            }
        }
    }
}
