import AaruCore
import Foundation

/// A calendar day in the user's time zone, with no time of day.
struct LocalDay: Sendable, Hashable, Comparable, CustomStringConvertible {
    var year: Int
    var month: Int
    var day: Int

    /// Gregorian arithmetic on bare dates: UTC, so no day is ever 23 or 25 hours long.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// `YYYY-MM-DD`, as Postgres prints a `date`.
    init?(_ text: String) {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    /// The day `date` falls on in `timeZone`.
    init(_ date: Date, in timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 0, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    func adding(days: Int = 0, months: Int = 0) -> LocalDay {
        guard let start = Self.calendar.date(from: DateComponents(year: year, month: month, day: day)),
              let moved = Self.calendar.date(byAdding: DateComponents(month: months, day: days), to: start)
        else { return self }
        return LocalDay(moved, in: Self.calendar.timeZone)
    }

    static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

/// One calendar year, one month of it, or all time, in one time zone.
struct StatsPeriod: Sendable, Equatable {
    enum Span: String, Sendable {
        case month, year, all
    }

    /// The earliest day any period reaches (`StatsService.years`' lower bound).
    static let firstDay = LocalDay(year: 1900, month: 1, day: 1)

    let span: Span
    /// The last year the period touches: the year asked for, or this year for all time.
    let year: Int
    let month: Int?
    let timeZone: TimeZone
    /// First day of the period.
    let start: LocalDay
    /// First day after the period.
    let end: LocalDay
    /// All time: the first year with activity, where the yearly buckets start. Else `year`.
    var firstYear: Int

    init(year: Int, month: Int?, timeZone: TimeZone) {
        span = month == nil ? .year : .month
        self.year = year
        self.month = month
        self.timeZone = timeZone
        start = LocalDay(year: year, month: month ?? 1, day: 1)
        end = start.adding(months: month == nil ? 12 : 1)
        firstYear = year
    }

    /// Everything through the end of `today`'s year, one bucket per year. It ends where the
    /// year's own period ends, so all time is exactly the years summed.
    init(allTimeUntil today: LocalDay, timeZone: TimeZone) {
        span = .all
        year = today.year
        month = nil
        self.timeZone = timeZone
        start = Self.firstDay
        end = LocalDay(year: today.year + 1, month: 1, day: 1)
        firstYear = today.year
    }

    /// Months of the year, days of the month, or years from `firstYear`, in order.
    var bucketStarts: [LocalDay] {
        switch span {
        case .all:
            return (min(firstYear, year) ... year).map { LocalDay(year: $0, month: 1, day: 1) }
        case .year:
            return (0 ..< 12).map { start.adding(months: $0) }
        case .month:
            return Array(sequence(first: start) { $0.adding(days: 1) }.prefix { $0 < end })
        }
    }

    /// The bucket a day falls in.
    func bucket(of day: LocalDay) -> LocalDay {
        switch span {
        case .all: LocalDay(year: day.year, month: 1, day: 1)
        case .year: LocalDay(year: day.year, month: day.month, day: 1)
        case .month: day
        }
    }
}

/// One title's activity on one local day: episode ticks with known dates, and its finish if it
/// finished that day. Imported or restored ticks are never activity.
struct StatsActivity: Sendable, Equatable {
    var day: LocalDay
    var titleID: TitleID
    var type: MediaType
    var isAnime: Bool
    var rating: Double?
    var episodes: Int
    var minutes: Int
    var finished: Bool
    var firstAt: Date
    var lastAt: Date
}

protocol StatsStore: Sendable {
    /// Activity on local days in `[from, until)` of `timeZone`, ordered by day.
    func activity(userID: UserID, from: LocalDay, until: LocalDay, timeZone: TimeZone) async throws
        -> [StatsActivity]
}

/// GAM-006a/c: what one user watched and read in a period. Derived only from their own library.
struct PeriodStats: Sendable, Equatable {
    struct Totals: Sendable, Equatable {
        var episodesWatched = 0
        var minutesWatched = 0
        var activeDays = 0
        var moviesFinished = 0
        var showsFinished = 0
        var animeFinished = 0
        var booksFinished = 0
    }

    struct Bucket: Sendable, Equatable {
        var start: LocalDay
        var episodes = 0
        var minutes = 0
        var finished = 0

        var isEmpty: Bool {
            episodes == 0 && minutes == 0 && finished == 0
        }
    }

    struct Run: Sendable, Equatable {
        var days: Int
        var start: LocalDay
        var end: LocalDay
    }

    struct TitleTime: Sendable, Equatable {
        var title: Title
        var episodes: Int
        var minutes: Int
    }

    struct Ratings: Sendable, Equatable {
        var count = 0
        var mean: Double?
        var highest: Title?
        var highestRating: Double?
        /// Ten bins on the 1–10 scale: bin `n` holds ratings in (n, n + 1], so a half star
        /// rounds up (7.5 is an 8) and 1 is the first bin.
        var distribution = Array(repeating: 0, count: 10)
    }

    /// The four kinds a person counts in: anime is its own kind, whatever its type.
    enum Kind: String, Sendable, CaseIterable {
        case movie, show, anime, book
    }

    struct KindTotals: Sendable, Equatable {
        var kind: Kind
        var episodes = 0
        var minutes = 0
        var finished = 0
    }

    struct Moment: Sendable, Equatable {
        var title: Title
        var date: Date
    }

    var period: StatsPeriod
    var isPartial: Bool
    var totals: Totals
    /// Movie, show, anime, book, always all four; they sum to `totals`.
    var byKind: [KindTotals]
    var buckets: [Bucket]
    var busiest: Bucket?
    /// Most episodes; nil when none, or when the top count is shared.
    var mostEpisodes: Bucket?
    var longestRun: Run?
    var topTitles: [TitleTime]
    var ratings: Ratings
    var first: Moment?
    var last: Moment?
}
