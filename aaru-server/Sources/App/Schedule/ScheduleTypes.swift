import AaruCore
import Foundation

/// One airing episode of a tracked show (CAL-001). Times are UTC; clients localize.
struct CalendarEntry: Sendable, Equatable {
    enum Kind: String, Sendable {
        case premiere, finale, regular
    }

    var libraryItemID: LibraryItemID
    var title: Title
    var key: EpisodeKey
    var episodeName: String?
    var airsAt: Date
    var runtimeMinutes: Int?
    var watched: Bool
    var kind: Kind
    /// False when the source gives only a date: `airsAt` is then midnight UTC of that date and
    /// clients show the day without a time.
    var airTimeKnown = false
    var episodeOverview: String?
    /// The episode's still (TMDB), for the calendar's episode sheet.
    var stillURL: URL?
}

/// A show to continue (UPN-001): the next aired episode not yet watched.
struct ContinueEntry: Sendable, Equatable {
    var libraryItemID: LibraryItemID
    var title: Title
    var next: EpisodeKey
    var nextName: String?
    var nextRuntimeMinutes: Int?
    /// Aired, unwatched, non-special episodes, including `next`.
    var remainingCount: Int
    var remainingMinutes: Int
    /// `next` is the last episode of its season.
    var isFinale: Bool
}

/// One title on Library's Watching page (APP-018): the library entry, a show's status and next
/// episode to air, and what is left to watch when an aired episode is.
struct WatchingRow: Sendable, Equatable {
    var entry: LibraryEntry
    var airing: TitleAiring?
    var next: ContinueEntry?
}

/// A wishlist title to start.
struct StartEntry: Sendable, Equatable {
    var libraryItemID: LibraryItemID
    var title: Title
    var runtimeMinutes: Int?
}

/// How many of the user's items are in each status (UPN-002).
struct LibraryCounts: Sendable, Equatable {
    var wishlist = 0
    var inProgress = 0
    var onHold = 0
    var finished = 0
    var dropped = 0
}

/// Unfinished business (UPN-002): a dropped item, or one in progress and untouched for a while.
struct UnfinishedEntry: Sendable, Equatable {
    enum Reason: String, Sendable {
        case dropped, stalled
    }

    var libraryItemID: LibraryItemID
    var title: Title
    var reason: Reason
    /// The item's last change.
    var since: Date
    /// Shows only: the first aired episode not yet watched.
    var next: EpisodeKey?
}

/// Everything the home screen's rows need, in one answer.
struct UpNext: Sendable, Equatable {
    var continueWatching: [ContinueEntry]
    var startWatching: [StartEntry]
    var counts: LibraryCounts
    var unfinished: [UnfinishedEntry]
}

protocol ScheduleStore: Sendable {
    /// Episodes of the user's tracked shows (wishlist or in progress) airing in [from, to).
    func calendar(userID: UserID, from: Date, until: Date, now: Date) async throws -> [CalendarEntry]
    func continueWatching(userID: UserID, now: Date, limit: Int) async throws -> [ContinueEntry]
    func startWatching(userID: UserID, limit: Int) async throws -> [StartEntry]
    func libraryCounts(userID: UserID) async throws -> LibraryCounts
    /// Every dropped item, and in-progress items last changed before `stalledBefore` that are not
    /// in Continue watching (a show with an aired, unwatched episode). Newest change first.
    func unfinished(userID: UserID, stalledBefore: Date, now: Date, limit: Int) async throws -> [UnfinishedEntry]
    /// Tracked shows whose episodes were never fetched nor attempted. A show the provider does
    /// not know drops out after its first attempt, so a client waiting on this count stops.
    func pendingShowCount(userID: UserID) async throws -> Int
}
