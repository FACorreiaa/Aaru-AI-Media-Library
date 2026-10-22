import Foundation

/// One local day with at least one live progress write (GAM-003). The server stores these as
/// `check_ins`; the UI calls them streak days. `date` is `yyyy-MM-dd` in `timeZone`.
public struct StreakDay: Hashable, Sendable, Codable {
    public var date: String
    public var timeZone: String
    public var firstAt: Date

    public init(date: String, timeZone: String, firstAt: Date) {
        self.date = date
        self.timeZone = timeZone
        self.firstAt = firstAt
    }
}

/// A run of consecutive streak days, first and last date inclusive.
public struct StreakRun: Hashable, Sendable {
    public var start: String
    public var end: String
    public var days: Int

    public init(start: String, end: String, days: Int) {
        self.start = start
        self.end = end
        self.days = days
    }
}

public struct StreakSummary: Hashable, Sendable {
    /// Days in the run that is still alive (its last day is today or yesterday); 0 when broken.
    public var current: Int
    public var longest: Int
    /// Whether today already counts.
    public var today: Bool
    /// The live run's first date, the key for its milestone bonuses.
    public var runStart: String?

    public init(current: Int, longest: Int, today: Bool, runStart: String?) {
        self.current = current
        self.longest = longest
        self.today = today
        self.runStart = runStart
    }

    public static let none = StreakSummary(current: 0, longest: 0, today: false, runStart: nil)
}

/// The streak rule, shared by the server and the widget so both agree at midnight.
///
/// Days are never recomputed: a day belongs to the date it was written under, so changing time
/// zone never breaks a streak after the fact. One allowance for travel: a single missing date is
/// bridged when the days either side were written in different time zones and their first writes
/// are at most 48 hours apart (a flight across the date line can skip a calendar date).
public enum Streak {
    public static let milestones = [7, 30, 100, 365]
    static let travelGrace: TimeInterval = 48 * 60 * 60

    public static func runs(_ days: [StreakDay]) -> [StreakRun] {
        let sorted = days.compactMap { day in dayNumber(day.date).map { (number: $0, day: day) } }
            .sorted { $0.number < $1.number }
        var runs: [StreakRun] = []
        var previous: (number: Int, day: StreakDay)?
        for entry in sorted {
            if let last = previous, var run = runs.last, continues(from: last, to: entry) {
                run.end = entry.day.date
                run.days += 1
                runs[runs.count - 1] = run
            } else if previous?.number != entry.number {
                runs.append(StreakRun(start: entry.day.date, end: entry.day.date, days: 1))
            }
            previous = entry
        }
        return runs
    }

    public static func summarize(_ days: [StreakDay], today: String) -> StreakSummary {
        let all = runs(days)
        let longest = all.map(\.days).max() ?? 0
        guard let last = all.last, let end = dayNumber(last.end), let now = dayNumber(today) else {
            return StreakSummary(current: 0, longest: longest, today: false, runStart: nil)
        }
        let alive = now - end <= 1 && now >= end
        return StreakSummary(
            current: alive ? last.days : 0, longest: longest, today: end == now,
            runStart: alive ? last.start : nil
        )
    }

    /// `yyyy-MM-dd` for `instant` in `timeZone`.
    public static func localDate(_ instant: Date, in timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: instant)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The date `days` after `date` (negative goes back).
    public static func adding(_ days: Int, to date: String) -> String? {
        dayNumber(date).map { dateString(dayNumber: $0 + days) }
    }

    /// Days since 1970-01-01 for a `yyyy-MM-dd` string.
    public static func dayNumber(_ date: String) -> Int? {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard let instant = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return nil }
        return Int((instant.timeIntervalSince1970 / 86400).rounded(.down))
    }

    static func dateString(dayNumber: Int) -> String {
        localDate(Date(timeIntervalSince1970: Double(dayNumber) * 86400), in: TimeZone(identifier: "UTC") ?? .current)
    }

    private static func continues(from last: (number: Int, day: StreakDay), to next: (number: Int, day: StreakDay))
        -> Bool
    {
        switch next.number - last.number {
        case 1: true
        case 2: last.day.timeZone != next.day.timeZone
            && next.day.firstAt.timeIntervalSince(last.day.firstAt) <= travelGrace
        default: false
        }
    }
}
