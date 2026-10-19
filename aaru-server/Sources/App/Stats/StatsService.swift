import AaruCore
import Foundation

/// GAM-006a: period stats for the Recap. A derived read over the library with no table of its
/// own; imports never count as activity.
struct StatsService: Sendable {
    static let topTitleCount = 5
    static let years = 1900 ... 2200

    let stores: Stores
    var now: @Sendable () -> Date = { Date() }

    func stats(userID: UserID, year: Int, month: Int?, timeZone: String?) async throws -> PeriodStats {
        let period = try Self.period(year: year, month: month, timeZone: timeZone)
        let rows = try await stores.stats.activity(
            userID: userID, from: period.start, until: period.end, timeZone: period.timeZone
        )
        let digest = StatsDigest(rows, period: period, today: LocalDay(now(), in: period.timeZone))
        let titles = try await stores.titles.titles(ids: digest.titleIDs)
        return digest.stats(titles: Dictionary(titles.map { ($0.id, $0) }) { first, _ in first })
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
            details["tz"] = "Use an IANA time zone such as Europe/Lisbon."
        }
        guard details.isEmpty, let zone else {
            throw AppError(
                status: .unprocessableContent, code: "validation_failed",
                message: details.values.sorted().joined(separator: " "), details: details
            )
        }
        return StatsPeriod(year: year, month: month, timeZone: zone)
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
            buckets[period.bucket(of: row.day)]?.episodes += row.episodes
            buckets[period.bucket(of: row.day)]?.minutes += row.minutes
            if row.episodes > 0 || row.minutes > 0 {
                perTitle[row.titleID, default: TitleTime(titleID: row.titleID, episodes: 0, minutes: 0)]
                    .episodes += row.episodes
                perTitle[row.titleID]?.minutes += row.minutes
            }
            if row.finished {
                buckets[period.bucket(of: row.day)]?.finished += 1
                Self.countFinish(row, in: &totals)
                if let rating = row.rating {
                    ratings.append(Rated(titleID: row.titleID, rating: rating, date: row.lastAt))
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
                highest: highest.flatMap { titles[$0.titleID] }, highestRating: highest?.rating
            ),
            first: first.flatMap(moment(titles)),
            last: last.flatMap(moment(titles))
        )
    }

    private func moment(_ titles: [TitleID: Title]) -> ((titleID: TitleID, date: Date)) -> PeriodStats.Moment? {
        { mark in titles[mark.titleID].map { PeriodStats.Moment(title: $0, date: mark.date) } }
    }
}
