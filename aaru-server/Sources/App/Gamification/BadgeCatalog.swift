import Foundation

/// Everything the badge rules read, gathered for one user in one pass (GAM-004).
///
/// Milestone facts come from the library and the other tables a user owns, so imported history
/// counts. Activity facts come from the points ledger and streak days, which only live writes
/// fill (owner decision 2026-10-22).
struct AchievementFacts: Sendable, Equatable {
    // Library (imports count)
    var filmsFinished = 0
    var filmsBefore1960 = 0
    var episodesTicked = 0
    var showsFinished = 0
    var seasonsComplete = 0
    var endedShowsComplete = 0
    var longShowsComplete = 0
    var animeFinished = 0
    var animeEpisodes = 0
    var booksFinished = 0
    var pagesRead = 0
    var longBooksFinished = 0
    var albumsFinished = 0
    var ratings = 0
    var perfectTens = 0
    var ratingMean: Double?
    var notes = 0
    var lists = 0
    var shelves = 0
    var owned = 0
    var genres = 0
    var decades = 0
    var networks = 0
    // Music
    var listens = 0
    var artists = 0
    // Imports
    var importsApplied = 0
    var importSources: Set<String> = []
    // Social
    var friends = 0
    var invitesRedeemed = 0
    var recommendationsSent = 0
    var recommendationsAdded = 0
    var reactions = 0
    // Ledger and streak days (live only)
    var doubleFeatureDays = 0
    var marathonDays = 0
    var bingedSeasons = 0
    var dayOneEpisodes = 0
    var finaleNights = 0
    var nightOwlWrites = 0
    var longestBookRun = 0
    var watchParties = 0
    var longestStreak = 0
    var comeback = false

    /// Kinds with at least one finish: film, show, anime, book, album.
    var kindsFinished: Int {
        [filmsFinished, showsFinished, animeFinished, booksFinished, albumsFinished].filter { $0 > 0 }.count
    }
}

enum BadgeFamily: String, Sendable, CaseIterable {
    case films, shows, anime, books, music, ratings, lists, imports, discovery, streaks, social
}

/// One badge. Tiers are 1…`thresholds.count`; tier `i` is earned when `value(facts)` reaches
/// `thresholds[i - 1]`. Copy for hidden badges never leaves the server until earned.
struct BadgeDefinition: Sendable {
    let id: String
    let family: BadgeFamily
    let name: String
    let thresholds: [Int]
    let hidden: Bool
    /// Never shown to friends: badges about notes and owned items (friends never see either).
    let isPrivate: Bool
    let describe: @Sendable (Int) -> String
    let value: @Sendable (AchievementFacts) -> Int

    init(
        _ id: String,
        _ family: BadgeFamily,
        _ name: String,
        tiers thresholds: [Int] = [1],
        hidden: Bool = false,
        isPrivate: Bool = false,
        describe: @escaping @Sendable (Int) -> String,
        value: @escaping @Sendable (AchievementFacts) -> Int
    ) {
        self.id = id
        self.family = family
        self.name = name
        self.thresholds = thresholds
        self.hidden = hidden
        self.isPrivate = isPrivate
        self.describe = describe
        self.value = value
    }

    var maxTier: Int {
        thresholds.count
    }

    /// The highest tier the facts reach, 0 for none.
    func tier(for facts: AchievementFacts) -> Int {
        let reached = value(facts)
        return thresholds.lastIndex { reached >= $0 }.map { $0 + 1 } ?? 0
    }
}

/// The catalog: 62 badges, 9 hidden. Names are plain with a little wit (owner,
/// 2026-10-22). Order is display order within each family.
enum BadgeCatalog {
    static let all: [BadgeDefinition] = films + shows + anime + books + music + ratings + lists + imports
        + discovery + streaks + social

    static let byID: [String: BadgeDefinition] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func plural(_ count: Int, _ one: String, _ many: String) -> String {
        "\(count.formatted()) \(count == 1 ? one : many)"
    }

    static let films: [BadgeDefinition] = [
        .init("first_film", .films, "Opening Night", describe: { _ in "Finish a film" }, value: \.filmsFinished),
        .init(
            "films",
            .films,
            "Cinephile",
            tiers: [10, 100, 250, 1000],
            describe: { "Finish \(plural($0, "film", "films"))" },
            value: \.filmsFinished
        ),
        .init(
            "silver_screen",
            .films,
            "Silver Screen",
            hidden: true,
            describe: { _ in "Finish a film released before 1960" },
            value: \.filmsBefore1960
        ),
        .init(
            "double_feature",
            .films,
            "Double Feature",
            describe: { _ in "Finish two films in one day" },
            value: \.doubleFeatureDays
        ),
    ]

    static let shows: [BadgeDefinition] = [
        .init("first_episode", .shows, "Pilot", describe: { _ in "Tick an episode" }, value: \.episodesTicked),
        .init(
            "episodes",
            .shows,
            "Box Set",
            tiers: [100, 1000, 5000, 10000],
            describe: { "Watch \(plural($0, "episode", "episodes"))" },
            value: \.episodesTicked
        ),
        .init(
            "shows",
            .shows,
            "Credits Roll",
            tiers: [5, 25, 100],
            describe: { "Finish \(plural($0, "show", "shows"))" },
            value: \.showsFinished
        ),
        .init(
            "seasons",
            .shows,
            "Season Pass",
            tiers: [10, 50, 200],
            describe: { "Watch every episode of \(plural($0, "season", "seasons"))" },
            value: \.seasonsComplete
        ),
        .init(
            "completionist",
            .shows,
            "Completionist",
            tiers: [1, 10, 25],
            describe: { "Watch every episode of \(plural($0, "ended show", "ended shows"))" },
            value: { $0.endedShowsComplete }
        ),
        .init(
            "long_haul",
            .shows,
            "Long Haul",
            hidden: true,
            describe: { _ in "Watch every episode of a show with 100 or more" },
            value: \.longShowsComplete
        ),
        .init(
            "binge",
            .shows,
            "One More Episode",
            hidden: true,
            describe: { _ in "Watch a whole season of six or more episodes in one day" },
            value: \.bingedSeasons
        ),
        .init(
            "marathon",
            .shows,
            "Marathon",
            describe: { _ in "Watch 10 episodes in one day" },
            value: \.marathonDays
        ),
        .init(
            "day_one",
            .shows,
            "Day One",
            tiers: [1, 10, 50],
            describe: { "Watch \(plural($0, "episode", "episodes")) within a day of airing" },
            value: { $0.dayOneEpisodes }
        ),
        .init(
            "finale_night",
            .shows,
            "Finale Night",
            hidden: true,
            describe: { _ in "Watch a season finale the day it airs" },
            value: \.finaleNights
        ),
    ]

    static let anime: [BadgeDefinition] = [
        .init("first_anime", .anime, "Opening Theme", describe: { _ in "Finish an anime" }, value: \.animeFinished),
        .init(
            "anime",
            .anime,
            "Simulcast",
            tiers: [5, 25, 100],
            describe: { "Finish \(plural($0, "anime", "anime"))" },
            value: \.animeFinished
        ),
        .init(
            "anime_episodes",
            .anime,
            "Filler Arc",
            tiers: [100, 500, 2000],
            describe: { "Watch \(plural($0, "anime episode", "anime episodes"))" },
            value: \.animeEpisodes
        ),
    ]

    static let books: [BadgeDefinition] = [
        .init("first_book", .books, "Bookmark", describe: { _ in "Finish a book" }, value: \.booksFinished),
        .init(
            "books",
            .books,
            "Bookworm",
            tiers: [10, 50, 100, 250],
            describe: { "Finish \(plural($0, "book", "books"))" },
            value: \.booksFinished
        ),
        .init(
            "pages",
            .books,
            "Page Turner",
            tiers: [1000, 10000, 50000, 100_000],
            describe: { "Read \(plural($0, "page", "pages"))" },
            value: \.pagesRead
        ),
        .init(
            "doorstopper",
            .books,
            "Doorstopper",
            hidden: true,
            describe: { _ in "Finish a book of 800 pages or more" },
            value: \.longBooksFinished
        ),
        .init(
            "chapter_a_day",
            .books,
            "Chapter a Day",
            tiers: [7],
            describe: { _ in "Read on seven days in a row" },
            value: \.longestBookRun
        ),
    ]

    static let music: [BadgeDefinition] = [
        .init("first_listen", .music, "Needle Drop", describe: { _ in "Log a listen" }, value: \.listens),
        .init(
            "listens",
            .music,
            "Heavy Rotation",
            tiers: [100, 1000, 10000, 50000],
            describe: { "Log \(plural($0, "listen", "listens"))" },
            value: \.listens
        ),
        .init(
            "artists",
            .music,
            "Crate Digger",
            tiers: [25, 100, 500],
            describe: { "Listen to \(plural($0, "artist", "artists"))" },
            value: \.artists
        ),
        .init(
            "albums",
            .music,
            "Liner Notes",
            tiers: [5, 25, 100],
            describe: { "Mark \(plural($0, "album", "albums")) listened" },
            value: \.albumsFinished
        ),
    ]

    static let ratings: [BadgeDefinition] = [
        .init("first_rating", .ratings, "First Verdict", describe: { _ in "Rate a title" }, value: \.ratings),
        .init(
            "ratings",
            .ratings,
            "Critic",
            tiers: [25, 100, 500, 1000],
            describe: { "Rate \(plural($0, "title", "titles"))" },
            value: \.ratings
        ),
        .init(
            "perfect_ten",
            .ratings,
            "Ten Out of Ten",
            tiers: [10],
            hidden: true,
            describe: { _ in "Give ten titles a 10" },
            value: \.perfectTens
        ),
        .init(
            "tough_crowd",
            .ratings,
            "Tough Crowd",
            hidden: true,
            describe: { _ in "Rate 25 titles with an average below 5" },
            value: { $0.ratings >= 25 && ($0.ratingMean ?? 10) < 5 ? 1 : 0 }
        ),
        .init(
            "notes",
            .ratings,
            "Margin Notes",
            tiers: [10, 50, 200],
            isPrivate: true,
            describe: { "Write notes on \(plural($0, "title", "titles"))" },
            value: \.notes
        ),
    ]

    static let lists: [BadgeDefinition] = [
        .init("first_list", .lists, "Curator", describe: { _ in "Make a list" }, value: \.lists),
        .init(
            "lists",
            .lists,
            "Archivist",
            tiers: [3, 10, 25],
            describe: { "Make \(plural($0, "list", "lists"))" },
            value: \.lists
        ),
        .init("first_shelf", .lists, "Shelf Life", describe: { _ in "Save a shelf" }, value: \.shelves),
        .init(
            "collector",
            .lists,
            "Collector",
            tiers: [25, 100, 500],
            isPrivate: true,
            describe: { "Mark \(plural($0, "title", "titles")) as owned" },
            value: \.owned
        ),
    ]
}
