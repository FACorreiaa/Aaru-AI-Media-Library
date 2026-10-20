import AaruCore
import Foundation

/// GAM-006a/c: period stats for the Recap and Insights. A derived read over the library with no
/// table of its own; imports never count as activity.
struct StatsService: Sendable {
    static let topTitleCount = 5
    static let years = 1900 ... 2200

    let stores: Stores
    var now: @Sendable () -> Date = { Date() }

    /// `allTime` takes no year or month; otherwise a year is required.
    func stats(userID: UserID, allTime: Bool = false, year: Int?, month: Int?, timeZone: String?) async throws
        -> PeriodStats
    {
        var period = try Self.period(allTime: allTime, year: year, month: month, timeZone: timeZone, now: now())
        let rows = try await stores.stats.activity(
            userID: userID, from: period.start, until: period.end, timeZone: period.timeZone
        )
        if period.span == .all, let first = rows.map(\.day.year).min() {
            period.firstYear = min(first, period.year)
        }
        let digest = StatsDigest(rows, period: period, today: LocalDay(now(), in: period.timeZone))
        let titles = try await stores.titles.titles(ids: digest.titleIDs)
        return digest.stats(titles: Dictionary(titles.map { ($0.id, $0) }) { first, _ in first })
    }

    /// GAM-006c: a year, a month of it, or all time up to today in the user's time zone.
    static func period(allTime: Bool, year: Int?, month: Int?, timeZone: String?, now: Date) throws -> StatsPeriod {
        if allTime {
            guard year == nil, month == nil else {
                throw invalid(["span": "All time takes no year or month."])
            }
            let zone = try zone(timeZone)
            return StatsPeriod(allTimeUntil: LocalDay(now, in: zone), timeZone: zone)
        }
        guard let year else {
            throw invalid(["year": "Send a year, or span=all."])
        }
        return try period(year: year, month: month, timeZone: timeZone)
    }

    static func period(year: Int, month: Int?, timeZone: String?) throws -> StatsPeriod {
        var details: [String: String] = [:]
        if !years.contains(year) {
            details["year"] = "Use a year between \(years.lowerBound) and \(years.upperBound)."
        }
        if let month, !(1 ... 12).contains(month) {
            details["month"] = "Use a month from 1 to 12."
        }
        let zone = TimeZone(identifier: timeZone ?? "UTC")
        if zone == nil {
            details["tz"] = zoneMessage
        }
        guard details.isEmpty, let zone else {
            throw invalid(details)
        }
        return StatsPeriod(year: year, month: month, timeZone: zone)
    }

    private static let zoneMessage = "Use an IANA time zone such as Europe/Lisbon."

    private static func zone(_ identifier: String?) throws -> TimeZone {
        guard let zone = TimeZone(identifier: identifier ?? "UTC") else {
            throw invalid(["tz": zoneMessage])
        }
        return zone
    }

    private static func invalid(_ details: [String: String]) -> AppError {
        AppError(
            status: .unprocessableContent, code: "validation_failed",
            message: details.values.sorted().joined(separator: " "), details: details
        )
    }
}

/// Everything the stats need, computed from activity rows alone. Titles are looked up after,
/// only for the few that are shown.
struct StatsDigest {
    struct TitleTime: Equatable {
        var titleID: TitleID
        var episodes: Int
        var minutes: Int
    }

    var period: StatsPeriod
    var isPartial: Bool
    var totals = PeriodStats.Totals()
    var byKind = PeriodStats.Kind.allCases.map { PeriodStats.KindTotals(kind: $0) }
    var distribution = Array(repeating: 0, count: 10)
    var buckets: [PeriodStats.Bucket]
    var longestRun: PeriodStats.Run?
    var topTitles: [TitleTime] = []
    var ratingCount = 0
    var ratingMean: Double?
    var highest: Rated?
    var first: (titleID: TitleID, date: Date)?
    var last: (titleID: TitleID, date: Date)?

    /// A finished title's rating, and when it finished.
    struct Rated {
        var titleID: TitleID
        var rating: Double
        var date: Date
    }

    init(_ rows: [StatsActivity], period: StatsPeriod, today: LocalDay) {
        self.period = period
        isPartial = today < period.end
        var buckets = Dictionary(uniqueKeysWithValues: period.bucketStarts.map { ($0, PeriodStats.Bucket(start: $0)) })
        var perTitle: [TitleID: TitleTime] = [:]
        var ratings: [Rated] = []
        for row in rows {
            totals.episodesWatched += row.episodes
            totals.minutesWatched += row.minutes
            let kind = Self.kindIndex(row)
            byKind[kind].episodes += row.episodes
            byKind[kind].minutes += row.minutes
            buckets[period.bucket(of: row.day)]?.episodes += row.episodes
            buckets[period.bucket(of: row.day)]?.minutes += row.minutes
            if row.episodes > 0 || row.minutes > 0 {
                perTitle[row.titleID, default: TitleTime(titleID: row.titleID, episodes: 0, minutes: 0)]
                    .episodes += row.episodes
                perTitle[row.titleID]?.minutes += row.minutes
            }
            if row.finished {
                buckets[period.bucket(of: row.day)]?.finished += 1
                byKind[kind].finished += 1
                Self.countFinish(row, in: &totals)
                if let rating = row.rating {
                    ratings.append(Rated(titleID: row.titleID, rating: rating, date: row.lastAt))
                    distribution[Self.ratingBin(rating)] += 1
                }
            }
            if first.map({ row.firstAt < $0.date }) ?? true {
                first = (row.titleID, row.firstAt)
            }
            if last.map({ row.lastAt >= $0.date }) ?? true {
                last = (row.titleID, row.lastAt)
            }
        }
        self.buckets = period.bucketStarts.compactMap { buckets[$0] }
        let days = Set(rows.map(\.day))
        totals.activeDays = days.count
        longestRun = Self.longestRun(days)
        topTitles = perTitle.values.sorted {
            ($0.minutes, $0.episodes, $1.titleID.rawValue.uuidString)
                > ($1.minutes, $1.episodes, $0.titleID.rawValue.uuidString)
        }.prefix(StatsService.topTitleCount).map { $0 }
        ratingCount = ratings.count
        if !ratings.isEmpty {
            ratingMean = ratings.map(\.rating).reduce(0, +) / Double(ratings.count)
        }
        // The highest rating; among ties, the latest finish.
        highest = ratings.max { ($0.rating, $0.date) < ($1.rating, $1.date) }
    }

    /// The row's place in `byKind`: anime is anime whatever its type.
    private static func kindIndex(_ row: StatsActivity) -> Int {
        let kind: PeriodStats.Kind = switch (row.type, row.isAnime) {
        case (_, true): .anime
        case (.movie, false): .movie
        case (.show, false): .show
        case (.book, false): .book
        }
        return PeriodStats.Kind.allCases.firstIndex(of: kind) ?? 0
    }

    /// The histogram bin of a 1–10 rating: (n, n + 1] is bin n, so half stars round up.
    static func ratingBin(_ rating: Double) -> Int {
        min(9, max(0, Int(rating.rounded(.up)) - 1))
    }

    /// Anime counts once, as anime, whatever its type.
    private static func countFinish(_ row: StatsActivity, in totals: inout PeriodStats.Totals) {
        switch (row.type, row.isAnime) {
        case (_, true): totals.animeFinished += 1
        case (.movie, false): totals.moviesFinished += 1
        case (.show, false): totals.showsFinished += 1
        case (.book, false): totals.booksFinished += 1
        }
    }

    /// The one bucket with the most episodes. A shared top count names no winner.
    static func mostEpisodes(_ buckets: [PeriodStats.Bucket]) -> PeriodStats.Bucket? {
        guard let top = buckets.max(by: { $0.episodes < $1.episodes }), top.episodes > 0,
              buckets.count(where: { $0.episodes == top.episodes }) == 1
        else { return nil }
        return top
    }

    /// The longest stretch of consecutive active days; the earliest among equals.
    static func longestRun(_ days: Set<LocalDay>) -> PeriodStats.Run? {
        var best: PeriodStats.Run?
        var current: PeriodStats.Run?
        for day in days.sorted() {
            if let run = current, run.end.adding(days: 1) == day {
                current = PeriodStats.Run(days: run.days + 1, start: run.start, end: day)
            } else {
                current = PeriodStats.Run(days: 1, start: day, end: day)
            }
            if let run = current, run.days > best?.days ?? 0 {
                best = run
            }
        }
        return best
    }

    /// Titles the stats show: the top list, the highest rated, the first and the last.
    var titleIDs: [TitleID] {
        var ids = topTitles.map(\.titleID)
        ids += [highest?.titleID, first?.titleID, last?.titleID].compactMap(\.self)
        var seen: Set<TitleID> = []
        return ids.filter { seen.insert($0).inserted }
    }

    func stats(titles: [TitleID: Title]) -> PeriodStats {
        PeriodStats(
            period: period,
            isPartial: isPartial,
            totals: totals,
            byKind: byKind,
            buckets: buckets,
            busiest: buckets.filter { !$0.isEmpty }.max {
                ($0.minutes, $0.episodes, $0.finished) < ($1.minutes, $1.episodes, $1.finished)
            },
            mostEpisodes: Self.mostEpisodes(buckets),
            longestRun: longestRun,
            topTitles: topTitles.compactMap { entry in
                titles[entry.titleID].map {
                    PeriodStats.TitleTime(title: $0, episodes: entry.episodes, minutes: entry.minutes)
                }
            },
            ratings: PeriodStats.Ratings(
                count: ratingCount, mean: ratingMean,
                highest: highest.flatMap { titles[$0.titleID] }, highestRating: highest?.rating,
                distribution: distribution
            ),
            first: first.flatMap(moment(titles)),
            last: last.flatMap(moment(titles))
        )
    }

    private func moment(_ titles: [TitleID: Title]) -> ((titleID: TitleID, date: Date)) -> PeriodStats.Moment? {
        { mark in titles[mark.titleID].map { PeriodStats.Moment(title: $0, date: mark.date) } }
    }
}
