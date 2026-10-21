import AaruAPI
import Foundation

typealias Stats = Components.Schemas.Stats
typealias StatsTitle = Components.Schemas.StatsTitle
typealias StatsMoment = Components.Schemas.StatsMoment
typealias StatsGenre = Components.Schemas.StatsGenre
typealias Persona = Components.Schemas.Stats.PersonaPayload
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

/// GAM-006a/e: one full-screen card of the Recap story.
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
    case biggestDay(day: String, episodes: Int, minutes: Int)
    case top(StatsTitle)
    case topList([StatsTitle])
    /// MUS-008: the period's top artist and its three most played tracks.
    case onRepeat(artist: String, plays: Int, minutes: Int, tracks: [String])
    case genres([StatsGenre])
    case kinds([(kind: MediaKind, share: Double)])
    case finished([(kind: MediaKind, count: Int)])
    case run(days: Int, range: String)
    case ratings(mean: Double, count: Int, highest: TitleSummary?, highestRating: Double?)
    case bookends(first: StatsMoment, last: StatsMoment)
    case persona(title: String, line: String)
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
        deck += titleCards(stats)
        deck += closingCards(stats)
        deck.append(.summary)
        return deck
    }

    /// The year's biggest day, then the titles and genres and kinds the time went to.
    private static func titleCards(_ stats: Stats) -> [RecapCard] {
        var deck: [RecapCard] = []
        // A month's bars already show its days; the biggest day is a year's card.
        if stats.month == nil, let day = stats.biggestDay {
            deck.append(.biggestDay(day: dayLabel(day.start), episodes: day.episodes, minutes: day.minutes))
        }
        if let top = stats.topTitles.first {
            deck.append(.top(top))
        }
        if stats.topTitles.count > 1 {
            deck.append(.topList(stats.topTitles))
        }
        // MUS-008: only when something was heard.
        if let music = stats.music, let artist = music.topArtist {
            deck.append(.onRepeat(
                artist: artist.artist, plays: artist.count, minutes: artist.minutes,
                tracks: music.topArtistTracks.map(\.track)
            ))
        }
        if !stats.topGenres.isEmpty {
            deck.append(.genres(stats.topGenres))
        }
        let kinds = kindShares(stats)
        if stats.month == nil, kinds.count > 1 {
            deck.append(.kinds(kinds))
        }
        return deck
    }

    /// What was finished, the run, ratings, bookends, and the year's persona.
    private static func closingCards(_ stats: Stats) -> [RecapCard] {
        let totals = stats.totals
        var deck: [RecapCard] = []
        let parts = finishedCounts(totals)
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
        if stats.month == nil, let persona = stats.persona {
            let words = personaWords(persona)
            deck.append(.persona(title: words.title, line: words.line))
        }
        return deck
    }

    /// GAM-006e: the words for each persona; the twin of the web's `PERSONAS`. The server picks
    /// one by rule; these are drafts the owner signs off.
    static func personaWords(_ persona: Persona) -> (title: String, line: String) {
        switch persona {
        case .binger: ("The Binger", "When a story grabs you, you stay for the next one.")
        case .bookworm: ("The Bookworm", "Pages won out over screens.")
        case .anime: ("The Anime Devotee", "Most of your hours went to anime.")
        case .completionist: ("The Completionist", "You finish what you start.")
        case .explorer: ("The Explorer", "Films, shows, anime, books: you went everywhere.")
        case .steady: ("The Steady One", "A little, often. Stories at your own pace.")
        }
    }

    /// Kinds with time, biggest share first. Books have no minutes, so they never show here.
    static func kindShares(_ stats: Stats) -> [(kind: MediaKind, share: Double)] {
        let total = stats.byKind.map(\.minutes).reduce(0, +)
        guard total > 0 else { return [] }
        return stats.byKind.filter { $0.minutes > 0 }
            .sorted { $0.minutes > $1.minutes }
            .map { (MediaKind($0.kind), Double($0.minutes) / Double(total)) }
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

    /// Episodes per bucket; the server's `mostEpisodes` is marked (none on a tie). Its `busiest` is
    /// by time, which a long film can win, so the episodes card does not use it.
    static func bars(_ stats: Stats) -> [RecapCard.Bar] {
        let tallest = max(1, stats.buckets.map(\.episodes).max() ?? 1)
        let top = stats.mostEpisodes
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
        // The server leaves `mostEpisodes` out on a tie: a shared top says nothing.
        guard let top = stats.mostEpisodes else { return nil }
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
        case .music: ("album", "albums")
        }
        return "\(count) \(count == 1 ? words.0 : words.1)"
    }

    /// What the period finished, per kind, leaving out kinds with none. Albums (MUS-001) come
    /// last and only when one was listened to.
    static func finishedCounts(_ totals: Components.Schemas.StatsTotals) -> [(kind: MediaKind, count: Int)] {
        [
            (.film, totals.moviesFinished), (.show, totals.showsFinished),
            (.anime, totals.animeFinished), (.book, totals.booksFinished), (.music, totals.albumsFinished),
        ].filter { $0.count >= 1 }
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
        let finished = finishedCounts(totals).map { countLabel($0.kind, $0.count) }
        if !finished.isEmpty {
            lines.append("Finished \(finished.joined(separator: ", "))")
        }
        if let top = stats.topTitles.first {
            lines.append("Most watched: \(top.title.title)")
        }
        if let run = stats.longestRun, run.days > 1 {
            lines.append("\(run.days) days in a row")
        }
        if let genre = stats.topGenres.first {
            lines.append("Top genre: \(genre.name)")
        }
        if stats.month == nil, let persona = stats.persona {
            lines.append(personaWords(persona).title)
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
