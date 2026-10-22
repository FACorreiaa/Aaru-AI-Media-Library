import Foundation
import Testing
@testable import AaruCore

struct StreakTests {
    private let lisbon = "Europe/Lisbon"

    private func day(
        _ date: String,
        _ zone: String = "Europe/Lisbon",
        hoursAfterMidnightUTC: Double = 12
    ) -> StreakDay {
        let base = Double(Streak.dayNumber(date) ?? 0) * 86400
        return StreakDay(
            date: date,
            timeZone: zone,
            firstAt: Date(timeIntervalSince1970: base + hoursAfterMidnightUTC * 3600)
        )
    }

    @Test func localMidnightSplitsTwoDays() throws {
        let zone = try #require(TimeZone(identifier: lisbon))
        // 2026-10-22 23:50 and 2026-10-23 00:10 in Lisbon (UTC+1 in October).
        let before = try #require(ISO8601DateFormatter().date(from: "2026-10-22T22:50:00Z"))
        let after = try #require(ISO8601DateFormatter().date(from: "2026-10-22T23:10:00Z"))
        #expect(Streak.localDate(before, in: zone) == "2026-10-22")
        #expect(Streak.localDate(after, in: zone) == "2026-10-23")
        let summary = Streak.summarize([day("2026-10-22"), day("2026-10-23")], today: "2026-10-23")
        #expect(summary == StreakSummary(current: 2, longest: 2, today: true, runStart: "2026-10-22"))
    }

    @Test func aliveUntilTheEndOfTheNextDay() {
        let days = ["2026-10-20", "2026-10-21", "2026-10-22"].map { day($0) }
        #expect(Streak.summarize(days, today: "2026-10-23").current == 3)
        #expect(Streak.summarize(days, today: "2026-10-23").today == false)
        #expect(Streak.summarize(days, today: "2026-10-24").current == 0)
        #expect(Streak.summarize(days, today: "2026-10-24").longest == 3)
    }

    @Test func changingTimeZoneNeverBreaksPastDays() {
        // Days keep the date they were written under, whatever zone the user is in now.
        let days = [
            day("2026-10-20", "Europe/Lisbon"),
            day("2026-10-21", "America/New_York"),
            day("2026-10-22", "Asia/Tokyo"),
        ]
        #expect(Streak.summarize(days, today: "2026-10-22").current == 3)
    }

    @Test func travelGraceBridgesOneSkippedDate() {
        // Flying west to east over the date line: the 21st never happened locally.
        let skipped = [
            day("2026-10-20", "America/Los_Angeles", hoursAfterMidnightUTC: 30),
            day("2026-10-22", "Asia/Tokyo", hoursAfterMidnightUTC: 2),
        ]
        #expect(Streak.summarize(skipped, today: "2026-10-22").current == 2)
        // Same zone either side: a missed day is a missed day.
        let missed = [day("2026-10-20"), day("2026-10-22")]
        #expect(Streak.summarize(missed, today: "2026-10-22").current == 1)
        // Different zones but days apart: no bridge.
        let far = [
            day("2026-10-20", "Europe/Lisbon", hoursAfterMidnightUTC: 1),
            day("2026-10-22", "Asia/Tokyo", hoursAfterMidnightUTC: 23),
        ]
        #expect(Streak.summarize(far, today: "2026-10-22").current == 1)
    }

    @Test func runsAndLongest() {
        let days = ["2026-01-01", "2026-01-02", "2026-01-03", "2026-01-05", "2026-01-06"].map { day($0) }
        #expect(Streak.runs(days) == [
            StreakRun(start: "2026-01-01", end: "2026-01-03", days: 3),
            StreakRun(start: "2026-01-05", end: "2026-01-06", days: 2),
        ])
        #expect(Streak.summarize(days, today: "2026-01-06").longest == 3)
        #expect(Streak.summarize([], today: "2026-01-06") == .none)
    }

    @Test func dateArithmetic() {
        #expect(Streak.adding(1, to: "2026-12-31") == "2027-01-01")
        #expect(Streak.adding(-1, to: "2026-03-01") == "2026-02-28")
        #expect(Streak.dayNumber("1970-01-02") == 1)
    }
}
