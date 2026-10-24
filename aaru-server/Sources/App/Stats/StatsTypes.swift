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

/// One calendar year, one month of it, all time, or the last 7 or 30 days, in one time zone.
struct StatsPeriod: Sendable, Equatable {
    enum Span: String, Sendable {
        case month, year, all, last7, last30

        /// GAM-006d: the length of a rolling span in days; nil for calendar spans.
        var days: Int? {
            switch self {
            case .last7: 7
            case .last30: 30
            case .month, .year, .all: nil
            }
        }
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

    /// GAM-006d: the `days` days ending with `today`, one bucket per day. `year` is today's.
    init(lastDays span: Span, today: LocalDay, timeZone: TimeZone) {
        let days = span.days ?? 7
        self.init(span: span, from: today.adding(days: 1 - days), until: today.adding(days: 1), timeZone: timeZone)
    }

    private init(span: Span, from: LocalDay, until: LocalDay, timeZone: TimeZone) {
        self.span = span
        year = until.adding(days: -1).year
        month = nil
        self.timeZone = timeZone
        start = from
        end = until
        firstYear = year
    }

    /// A rolling span's equal-length window just before it; nil for calendar spans.
    var previous: StatsPeriod? {
        guard let days = span.days else { return nil }
        return StatsPeriod(span: span, from: start.adding(days: -days), until: start, timeZone: timeZone)
    }

    /// The period's last day, inclusive.
    var lastDay: LocalDay {
        end.adding(days: -1)
    }

    /// Months of the year, days of the month or rolling span, or years from `firstYear`, in order.
    var bucketStarts: [LocalDay] {
        switch span {
        case .all:
            return (min(firstYear, year) ... year).map { LocalDay(year: $0, month: 1, day: 1) }
        case .year:
            return (0 ..< 12).map { start.adding(months: $0) }
        case .month, .last7, .last30:
            return Array(sequence(first: start) { $0.adding(days: 1) }.prefix { $0 < end })
        }
    }

    /// The bucket a day falls in.
    func bucket(of day: LocalDay) -> LocalDay {
        switch span {
        case .all: LocalDay(year: day.year, month: 1, day: 1)
        case .year: LocalDay(year: day.year, month: day.month, day: 1)
        case .month, .last7, .last30: day
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
    /// GAM-006e: the title's stored genres (CAT-018); empty for books and titles not yet filled.
    var genres: [String] = []
}

protocol StatsStore: Sendable {
    /// Activity on local days in `[from, until)` of `timeZone`, ordered by day.
    func activity(userID: UserID, from: LocalDay, until: LocalDay, timeZone: TimeZone) async throws
        -> [StatsActivity]
    /// GAM-006b: one row per library item, and when the account was made.
    func library(userID: UserID) async throws -> (rows: [ProfileRow], memberSince: Date?)
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
        var albumsFinished = 0
        var mangaFinished = 0
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

    /// The kinds a person counts in: anime is its own kind, whatever its type. Albums (MUS-001)
    /// have no minutes; they count as finishes only. So does manga (MNG-001).
    enum Kind: String, Sendable, CaseIterable {
        case movie, show, anime, book, album, manga
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

    /// GAM-006e: time spent in one genre, and how many titles carried it.
    struct GenreTime: Sendable, Equatable {
        var name: String
        var minutes: Int
        var titles: Int
    }

    /// GAM-006e: one word for how the period went, from the user's own numbers only. The first
    /// rule that holds wins, in case order. Clients own the words; the server owns the rule.
    enum Persona: String, Sendable, CaseIterable {
        /// A day of six or more episodes, or two weeks in a row.
        case binger
        /// Books are most of what was finished (at least two).
        case bookworm
        /// Anime is most of the time.
        case anime
        /// 24 or more titles finished.
        case completionist
        /// Three or more kinds of story.
        case explorer
        /// Anything else with activity.
        case steady
    }

    var period: StatsPeriod
    var isPartial: Bool
    var totals: Totals
    /// GAM-006d: the previous equal-length window's totals; rolling spans only.
    var prior: Totals?
    /// Movie, show, anime and book, always; album and manga after them only when the period has one. They
    /// sum to `totals`.
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
    /// GAM-006e: the three genres with the most time, films, shows and anime only.
    var topGenres: [GenreTime] = []
    /// GAM-006e: the single local day with the most time (then episodes); the earliest on a tie.
    var biggestDay: Bucket?
    var persona: Persona?
    /// MUS-008: listening, apart from the library's numbers; nil when nothing was heard.
    var music: ListenSummary?
}
