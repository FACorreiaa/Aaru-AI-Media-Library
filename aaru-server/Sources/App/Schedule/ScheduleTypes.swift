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

/// A wishlist title to start.
struct StartEntry: Sendable, Equatable {
    var libraryItemID: LibraryItemID
    var title: Title
    var runtimeMinutes: Int?
}

protocol ScheduleStore: Sendable {
    /// Episodes of the user's tracked shows (wishlist or in progress) airing in [from, to).
    func calendar(userID: UserID, from: Date, until: Date, now: Date) async throws -> [CalendarEntry]
    func continueWatching(userID: UserID, now: Date, limit: Int) async throws -> [ContinueEntry]
    func startWatching(userID: UserID, limit: Int) async throws -> [StartEntry]
    /// Tracked shows whose episodes were never fetched.
    func unhydratedTrackedShows(userID: UserID, limit: Int) async throws -> [TitleID]
}
