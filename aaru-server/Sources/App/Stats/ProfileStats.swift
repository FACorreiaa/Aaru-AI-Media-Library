import AaruCore
import Foundation

/// GAM-006b: one library item as the profile counts it. Unlike `StatsActivity` it is the
/// library's state, not dated activity: every tick counts, imported and undated ones included.
struct ProfileRow: Sendable, Equatable {
    var titleID: TitleID
    var type: MediaType
    var isAnime: Bool
    var status: LibraryStatus
    var rating: Double?
    /// Episodes ticked, every one.
    var episodes: Int
    /// Ticked episodes' runtime, plus the runtime of a finished film.
    var minutes: Int
    /// A finished book's page count; 0 when unknown or not finished.
    var pages: Int
    var genres: [String] = []
    var network: String?
}

/// GAM-006b: all-time numbers for the profile, from the user's own library.
struct ProfileStats: Sendable, Equatable {
    /// Items per status for one kind.
    struct Counts: Sendable, Equatable {
        var wishlist = 0
        var inProgress = 0
        var onHold = 0
        var finished = 0
        var dropped = 0
    }

    struct Share: Sendable, Equatable {
        var name: String
        var minutes: Int
        var titles: Int
    }

    var memberSince: Date?
    var episodesWatched = 0
    var minutesWatched = 0
    var pagesRead = 0
    var shows = Counts()
    var anime = Counts()
    var movies = Counts()
    var books = Counts()
    /// Movie, show, anime and book, as in `PeriodStats.byKind`; finished is the finished count.
    var byKind: [PeriodStats.KindTotals] = []
    var topGenres: [Share] = []
    var topNetworks: [Share] = []
    var mostWatched: [PeriodStats.TitleTime] = []
    var ratings = PeriodStats.Ratings()
}

/// The profile's numbers, worked out from rows alone. Titles are looked up after, for the few shown.
struct ProfileDigest {
    static let genreCount = 8
    static let networkCount = 5
    static let mostWatchedCount = 3

    var stats = ProfileStats()
    var mostWatched: [StatsDigest.TitleTime] = []
    var highest: TitleID?

    init(_ rows: [ProfileRow]) {
        stats.byKind = Self.kinds.map { PeriodStats.KindTotals(kind: $0) }
        var rated: [(titleID: TitleID, rating: Double)] = []
        // Albums and manga have no place in the profile's watch-and-read stats yet.
        for row in rows where row.type != .album && row.type != .manga {
            add(row)
            if let rating = row.rating {
                rated.append((row.titleID, rating))
                stats.ratings.distribution[StatsDigest.ratingBin(rating)] += 1
            }
        }
        stats.ratings.count = rated.count
        if !rated.isEmpty {
            stats.ratings.mean = rated.map(\.rating).reduce(0, +) / Double(rated.count)
        }
        if let top = rated.max(by: { $0.rating < $1.rating }) {
            highest = top.titleID
            stats.ratings.highestRating = top.rating
        }
        let timed = rows.filter { $0.minutes > 0 && $0.type != .book && $0.type != .album }
        stats.topGenres = Self.shares(
            timed.flatMap { row in Set(row.genres).map { ($0, row) } },
            limit: Self.genreCount
        )
        stats.topNetworks = Self.shares(
            timed.compactMap { row in row.network.map { ($0, row) } },
            limit: Self.networkCount
        )
        mostWatched = timed.sorted {
            ($0.minutes, $0.episodes, $1.titleID.rawValue.uuidString)
                > ($1.minutes, $1.episodes, $0.titleID.rawValue.uuidString)
        }.prefix(Self.mostWatchedCount).map {
            StatsDigest.TitleTime(titleID: $0.titleID, episodes: $0.episodes, minutes: $0.minutes)
        }
    }

    private static let kinds: [PeriodStats.Kind] = [.movie, .show, .anime, .book]

    /// One item's totals, its status under its kind, and its kind's time. Anime is anime whatever
    /// its type.
    private mutating func add(_ row: ProfileRow) {
        stats.episodesWatched += row.episodes
        stats.minutesWatched += row.minutes
        stats.pagesRead += row.pages
        let kind: PeriodStats.Kind = switch (row.type, row.isAnime) {
        case (_, true): .anime
        case (.movie, false): .movie
        case (.book, false): .book
        default: .show
        }
        switch kind {
        case .anime: Self.count(row.status, in: &stats.anime)
        case .movie: Self.count(row.status, in: &stats.movies)
        case .book: Self.count(row.status, in: &stats.books)
        default: Self.count(row.status, in: &stats.shows)
        }
        guard let index = Self.kinds.firstIndex(of: kind) else { return }
        stats.byKind[index].episodes += row.episodes
        stats.byKind[index].minutes += row.minutes
        if row.status == .finished {
            stats.byKind[index].finished += 1
        }
    }

    var titleIDs: [TitleID] {
        mostWatched.map(\.titleID) + [highest].compactMap(\.self)
    }

    func stats(titles: [TitleID: Title], memberSince: Date?) -> ProfileStats {
        var stats = stats
        stats.memberSince = memberSince
        stats.mostWatched = mostWatched.compactMap { entry in
            titles[entry.titleID].map { PeriodStats.TitleTime(
                title: $0,
                episodes: entry.episodes,
                minutes: entry.minutes
            ) }
        }
        stats.ratings.highest = highest.flatMap { titles[$0] }
        return stats
    }

    /// Time per name, most first, then by titles, then name.
    private static func shares(_ pairs: [(String, ProfileRow)], limit: Int) -> [ProfileStats.Share] {
        var per: [String: (minutes: Int, titles: Set<TitleID>)] = [:]
        for (name, row) in pairs {
            per[name, default: (0, [])].minutes += row.minutes
            per[name]?.titles.insert(row.titleID)
        }
        return per.map { ProfileStats.Share(name: $0.key, minutes: $0.value.minutes, titles: $0.value.titles.count) }
            .sorted { ($0.minutes, $0.titles, $1.name) > ($1.minutes, $1.titles, $0.name) }
            .prefix(limit).map(\.self)
    }

    private static func count(_ status: LibraryStatus, in counts: inout ProfileStats.Counts) {
        switch status {
        case .wishlist: counts.wishlist += 1
        case .inProgress: counts.inProgress += 1
        case .onHold: counts.onHold += 1
        case .finished: counts.finished += 1
        case .dropped: counts.dropped += 1
        }
    }
}

extension StatsService {
    /// GAM-006b: the profile's all-time numbers.
    func profile(userID: UserID) async throws -> ProfileStats {
        let (rows, memberSince) = try await stores.stats.library(userID: userID)
        let digest = ProfileDigest(rows)
        let titles = try await stores.titles.titles(ids: digest.titleIDs)
        return digest.stats(
            titles: Dictionary(titles.map { ($0.id, $0) }) { first, _ in first },
            memberSince: memberSince
        )
    }
}
