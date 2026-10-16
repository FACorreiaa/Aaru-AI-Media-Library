import AaruAPI
import Foundation

typealias Stats = Components.Schemas.Stats
typealias StatsTitle = Components.Schemas.StatsTitle
typealias StatsMoment = Components.Schemas.StatsMoment
typealias TitleSummary = Components.Schemas.TitleSummary

/// One recap: a whole year, or one month of it.
struct RecapPeriod: Hashable, Identifiable {
    var year: Int
    var month: Int?

    var id: String {
        month.map { "\(year)-\($0)" } ?? "\(year)"
    }

    /// "October 2026", or "2026".
    var label: String {
        guard let month else { return "\(year)" }
        return "\(RecapDeck.months[month - 1]) \(year)"
    }

    /// The recap Home offers today, if any: the year review from Dec 1 to Jan 15, and last
    /// month's recap in the first week of a month. The same windows as the web.
    static func offered(now: Date, calendar: Calendar) -> RecapPeriod? {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        if month == 12 {
            return RecapPeriod(year: year)
        }
        if month == 1, day <= 15 {
            return RecapPeriod(year: year - 1)
        }
        if day <= 7 {
            return previousMonth(now: now, calendar: calendar)
        }
        return nil
    }

    static func previousMonth(now: Date, calendar: Calendar) -> RecapPeriod {
        let parts = calendar.dateComponents([.year, .month], from: now)
        let (year, month) = (parts.year ?? 2000, parts.month ?? 1)
        return month == 1 ? RecapPeriod(year: year - 1, month: 12) : RecapPeriod(year: year, month: month - 1)
    }

    /// Settings' shortcuts: this year so far, last month, last year.
    static func shortcuts(now: Date, calendar: Calendar) -> [RecapPeriod] {
        let year = calendar.component(.year, from: now)
        return [RecapPeriod(year: year), previousMonth(now: now, calendar: calendar), RecapPeriod(year: year - 1)]
    }
}

/// GAM-006a: one full-screen card of the Recap story.
enum RecapCard {
    struct Bar: Hashable {
        var label: String
        /// 0…1 of the tallest bucket.
        var height: Double
        var busiest: Bool
    }

    case intro(heading: String, partial: Bool)
    case time(minutes: Int, caption: String)
    case episodes(count: Int, bars: [Bar], busiest: String?)
    case top(StatsTitle)
    case topList([StatsTitle])
    case finished([(kind: MediaKind, count: Int)])
    case run(days: Int, range: String)
    case ratings(mean: Double, count: Int, highest: TitleSummary?, highestRating: Double?)
    case bookends(first: StatsMoment, last: StatsMoment)
    case summary
}

/// The Recap's pure parts, the twin of the web's `lib/recap/model.ts`: cards with nothing to say
/// are left out, and a period with no activity has no deck at all.
enum RecapDeck {
    static let months = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]

    static func isEmpty(_ stats: Stats) -> Bool {
        stats.totals.activeDays == 0
    }

    static func cards(from stats: Stats) -> [RecapCard] {
        guard !isEmpty(stats) else { return [] }
        let totals = stats.totals
        let period = RecapPeriod(year: stats.year, month: stats.month)
        var deck: [RecapCard] = [
            .intro(
                heading: stats.month == nil ? "Your \(stats.year) in Aaru" : "Your \(period.label)",
                partial: stats.isPartial
            ),
        ]
        if totals.minutesWatched > 0 {
            deck.append(.time(minutes: totals.minutesWatched, caption: timeCaption(totals.minutesWatched)))
        }
        if totals.episodesWatched > 0 {
            deck.append(.episodes(count: totals.episodesWatched, bars: bars(stats), busiest: busiestLine(stats)))
        }
        if let top = stats.topTitles.first {
            deck.append(.top(top))
        }
        if stats.topTitles.count > 1 {
            deck.append(.topList(stats.topTitles))
        }
        let parts: [(kind: MediaKind, count: Int)] = [
            (.film, totals.moviesFinished), (.show, totals.showsFinished),
            (.anime, totals.animeFinished), (.book, totals.booksFinished),
        ].filter { $0.count >= 1 }
        if !parts.isEmpty {
            deck.append(.finished(parts))
        }
        if let run = stats.longestRun, run.days > 1 {
            deck.append(.run(days: run.days, range: "\(dayLabel(run.start)) – \(dayLabel(run.end))"))
        }
        if let mean = stats.ratings.mean {
            deck.append(.ratings(
                mean: mean, count: stats.ratings.count,
                highest: stats.ratings.highest, highestRating: stats.ratings.highestRating
            ))
        }
        if let first = stats.first, let last = stats.last, first.title.id != last.title.id {
            deck.append(.bookends(first: first, last: last))
        }
        deck.append(.summary)
        return deck
    }

    static func timeCaption(_ minutes: Int) -> String {
        let hours = Double(minutes) / 60
        if hours < 2 {
            return "That's \(minutes) minutes of stories."
        }
        if hours < 48 {
            return "That's about \(Int(hours.rounded())) hours."
        }
        let days = (hours / 24 * 10).rounded() / 10
        return "That's about \(days.formatted(.number.precision(.fractionLength(0 ... 1)))) days, end to end."
    }

    /// The bucket with the most episodes; the earliest among equals. Nil when no episodes.
    static func mostEpisodes(_ stats: Stats) -> Components.Schemas.StatsBucket? {
        stats.buckets.reduce(nil) { best, bucket in
            bucket.episodes > (best?.episodes ?? 0) ? bucket : best
        }
    }

    /// Episodes per bucket; the one with the most is marked. The server's `busiest` is by time,
    /// which a long film can win, so the episodes card does not use it.
    static func bars(_ stats: Stats) -> [RecapCard.Bar] {
        let tallest = max(1, stats.buckets.map(\.episodes).max() ?? 1)
        let top = mostEpisodes(stats)
        return stats.buckets.map { bucket in
            let parts = bucket.start.split(separator: "-").compactMap { Int($0) }
            let label = stats.month == nil ? String(months[(
                parts[safe: 1] ?? 1
            ) - 1].prefix(1)) : "\(parts[safe: 2] ?? 1)"
            return RecapCard.Bar(
                label: label, height: Double(bucket.episodes) / Double(tallest),
                busiest: bucket.start == top?.start
            )
        }
    }

    /// "Most episodes in June." / "on Apr 3." Nil when the top is shared: a tie says nothing.
    private static func busiestLine(_ stats: Stats) -> String? {
        guard let top = mostEpisodes(stats),
              stats.buckets.filter({ $0.episodes == top.episodes }).count == 1
        else { return nil }
        if stats.month != nil {
            return "Most episodes on \(dayLabel(top.start))."
        }
        let month = top.start.split(separator: "-").compactMap { Int($0) }[safe: 1] ?? 1
        return "Most episodes in \(months[month - 1])."
    }

    /// "Mar 10" from a local `YYYY-MM-DD`.
    static func dayLabel(_ day: String) -> String {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return day }
        return "\(months[parts[1] - 1].prefix(3)) \(parts[2])"
    }

    static func countLabel(_ kind: MediaKind, _ count: Int) -> String {
        let words = switch kind {
        case .film: ("film", "films")
        case .show: ("show", "shows")
        case .anime: ("anime", "anime")
        case .book: ("book", "books")
        }
        return "\(count) \(count == 1 ? words.0 : words.1)"
    }

    static func ratingLabel(_ rating: Double) -> String {
        rating.formatted(.number.precision(.fractionLength(0 ... 1)))
    }

    /// The lines the share image prints. Only the user's own numbers.
    static func shareLines(_ stats: Stats) -> [String] {
        let totals = stats.totals
        var lines: [String] = []
        if totals.minutesWatched > 0 {
            lines.append("\(totals.minutesWatched.formatted()) minutes")
        }
        if totals.episodesWatched > 0 {
            lines.append("\(totals.episodesWatched.formatted()) episodes")
        }
        let finished = [
            (MediaKind.film, totals.moviesFinished), (.show, totals.showsFinished),
            (.anime, totals.animeFinished), (.book, totals.booksFinished),
        ].filter { $0.1 > 0 }.map { countLabel($0.0, $0.1) }
        if !finished.isEmpty {
            lines.append("Finished \(finished.joined(separator: ", "))")
        }
        if let top = stats.topTitles.first {
            lines.append("Most watched: \(top.title.title)")
        }
        if let run = stats.longestRun, run.days > 1 {
            lines.append("\(run.days) days in a row")
        }
        return lines
    }
}

extension TitleSummary {
    var mediaKind: MediaKind {
        MediaKind(type: _type, isAnime: isAnime)
    }

    var posterURL: URL? {
        posterUrl.flatMap(URL.init(string:))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
