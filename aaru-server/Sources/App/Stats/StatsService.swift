import AaruCore
import Foundation

/// GAM-006a/c: period stats for the Recap and Insights. A derived read over the library with no
/// table of its own; imports never count as activity.
struct StatsService: Sendable {
    static let topTitleCount = 5
    static let years = 1900 ... 2200

    let stores: Stores
    var now: @Sendable () -> Date = { Date() }

    /// `span` (all time or a rolling window) takes no year or month; otherwise a year is required.
    func stats(userID: UserID, span: StatsPeriod.Span? = nil, year: Int?, month: Int?, timeZone: String?)
        async throws -> PeriodStats
    {
        var period = try Self.period(span: span, year: year, month: month, timeZone: timeZone, now: now())
        let today = LocalDay(now(), in: period.timeZone)
        // A rolling window reads its previous window in the same query, for the deltas.
        let previous = period.previous
        let rows = try await stores.stats.activity(
            userID: userID, from: previous?.start ?? period.start, until: period.end, timeZone: period.timeZone
        )
        if period.span == .all, let first = rows.map(\.day.year).min() {
            period.firstYear = min(first, period.year)
        }
        let current = rows.filter { $0.day >= period.start }
        let digest = StatsDigest(current, period: period, today: today)
        let titles = try await stores.titles.titles(ids: digest.titleIDs)
        var stats = digest.stats(titles: Dictionary(titles.map { ($0.id, $0) }) { first, _ in first })
        if let previous {
            stats.prior = StatsDigest(rows.filter { $0.day < period.start }, period: previous, today: today).totals
        }
        stats.music = try await music(userID: userID, period: period, previous: previous)
        return stats
    }

    /// MUS-008: the period's listens and minutes, the top artist and their three most played
    /// tracks. Listening never adds to the library's totals.
    private func music(userID: UserID, period: StatsPeriod, previous: StatsPeriod?) async throws -> ListenSummary? {
        let listens = stores.listens
        let artists = try await listens.top(userID: userID, by: .artist, period: period, limit: 1, artist: nil)
        guard artists.listens > 0 else { return nil }
        let prior = if let previous {
            try await listens.top(userID: userID, by: .artist, period: previous, limit: 1, artist: nil)
        } else {
            ListenTop?.none
        }
        let topArtist = artists.items.first
        let tracks = if let topArtist {
            try await listens.top(userID: userID, by: .track, period: period, limit: 3, artist: topArtist.artist).items
        } else {
            [ListenTotal]()
        }
        return ListenSummary(
            listens: artists.listens, durationMs: artists.durationMs, priorListens: prior?.listens,
            priorDurationMs: prior?.durationMs, topArtist: topArtist, topArtistTracks: tracks
        )
    }

    /// GAM-006c/d: a year, a month of it, all time up to today, or the last 7 or 30 days ending
    /// today, in the user's time zone.
    static func period(span: StatsPeriod.Span?, year: Int?, month: Int?, timeZone: String?, now: Date) throws
        -> StatsPeriod
    {
        if let span {
            guard span == .all || span.days != nil else {
                throw invalid(["span": "Use all, last7 or last30."])
            }
            guard year == nil, month == nil else {
                throw invalid(["span": span == .all ? "All time takes no year or month." :
                        "A rolling span takes no year or month."])
            }
            let zone = try zone(timeZone)
            let today = LocalDay(now, in: zone)
            return span == .all
                ? StatsPeriod(allTimeUntil: today, timeZone: zone)
                : StatsPeriod(lastDays: span, today: today, timeZone: zone)
        }
        guard let year else {
            throw invalid(["year": "Send a year, or a span."])
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
    static let topGenreCount = 3

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
    var topGenres: [PeriodStats.GenreTime] = []
    var biggestDay: PeriodStats.Bucket?

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
        topGenres = Self.topGenres(rows)
        biggestDay = Self.biggestDay(Self.days(rows))
    }

    /// GAM-006e: time per genre over films, shows and anime, most first, then by titles, then name.
    static func topGenres(_ rows: [StatsActivity]) -> [PeriodStats.GenreTime] {
        var perGenre: [String: (minutes: Int, titles: Set<TitleID>)] = [:]
        for row in rows where row.minutes > 0 && row.type != .book {
            for genre in Set(row.genres) {
                perGenre[genre, default: (0, [])].minutes += row.minutes
                perGenre[genre]?.titles.insert(row.titleID)
            }
        }
        return perGenre.map {
            PeriodStats.GenreTime(name: $0.key, minutes: $0.value.minutes, titles: $0.value.titles.count)
        }
        .sorted { ($0.minutes, $0.titles, $1.name) > ($1.minutes, $1.titles, $0.name) }
        .prefix(topGenreCount).map(\.self)
    }

    /// Each active local day's totals.
    static func days(_ rows: [StatsActivity]) -> [PeriodStats.Bucket] {
        var perDay: [LocalDay: PeriodStats.Bucket] = [:]
        for row in rows {
            perDay[row.day, default: PeriodStats.Bucket(start: row.day)].episodes += row.episodes
            perDay[row.day]?.minutes += row.minutes
            if row.finished {
                perDay[row.day]?.finished += 1
            }
        }
        return Array(perDay.values)
    }

    /// The day with the most time, then episodes; the earliest among equals. Nil with no time
    /// and no episodes (a day of finished books alone is not a big day).
    static func biggestDay(_ days: [PeriodStats.Bucket]) -> PeriodStats.Bucket? {
        days.filter { $0.minutes > 0 || $0.episodes > 0 }.min {
            ($1.minutes, $1.episodes, $0.start) < ($0.minutes, $0.episodes, $1.start)
        }
    }

    /// GAM-006e: the first persona whose rule holds; nil when nothing happened.
    func persona() -> PeriodStats.Persona? {
        let finished = totals.moviesFinished + totals.showsFinished + totals.animeFinished + totals.booksFinished
            + totals.albumsFinished
        guard totals.activeDays > 0 else { return nil }
        if (biggestDay?.episodes ?? 0) >= 6 || (longestRun?.days ?? 0) >= 14 {
            return .binger
        }
        if finished >= 2, totals.booksFinished * 2 > finished {
            return .bookworm
        }
        let anime = byKind.first { $0.kind == .anime }?.minutes ?? 0
        if totals.minutesWatched > 0, anime * 2 > totals.minutesWatched {
            return .anime
        }
        if finished >= 24 {
            return .completionist
        }
        if byKind.count(where: { $0.minutes > 0 || $0.finished > 0 }) >= 3 {
            return .explorer
        }
        return .steady
    }

    /// The row's place in `byKind`: anime is anime whatever its type.
    private static func kindIndex(_ row: StatsActivity) -> Int {
        let kind: PeriodStats.Kind = switch (row.type, row.isAnime) {
        case (_, true): .anime
        case (.movie, false): .movie
        case (.show, false): .show
        case (.book, false): .book
        case (.album, false): .album
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
        case (.album, false): totals.albumsFinished += 1
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
            // Old clients know four kinds; an album row appears only once there is one to show.
            byKind: byKind.filter { $0.kind != .album || $0.finished > 0 },
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
            last: last.flatMap(moment(titles)),
            topGenres: topGenres,
            biggestDay: biggestDay,
            persona: persona()
        )
    }

    private func moment(_ titles: [TitleID: Title]) -> ((titleID: TitleID, date: Date)) -> PeriodStats.Moment? {
        { mark in titles[mark.titleID].map { PeriodStats.Moment(title: $0, date: mark.date) } }
    }
}
