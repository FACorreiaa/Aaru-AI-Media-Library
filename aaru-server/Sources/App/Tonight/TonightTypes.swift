import AaruCore
import Foundation

/// One thing to start tonight (AG-005), with why it is here and about how long it takes.
struct TonightPick: Sendable, Equatable {
    enum Kind: String, Sendable {
        /// The next aired episode of a show in progress.
        case `continue`
        /// An episode of a tracked show airing today.
        case airing
        /// A book in progress.
        case reading
        /// A film on the wishlist.
        case start
    }

    var libraryItemID: LibraryItemID
    var title: Title
    var kind: Kind
    var episode: EpisodeKey?
    var episodeName: String?
    var minutes: Int?
    var airsAt: Date?
    var airTimeKnown = false
    /// "52 min · 3 left", "Airs 21:00 · 44 min", "64 pages left", "2 h 04 · on your list 41 days".
    var reason: String
}

/// The strip for one local day.
struct Tonight: Sendable, Equatable {
    var day: LocalDay
    var picks: [TonightPick]
}

/// The user's answer to a pick. "Not tonight" hides it for the day; "not for me" (rejected) weighs
/// against it for two weeks.
enum TonightVerdict: String, Sendable {
    case rejected
    case notTonight = "not_tonight"
}

struct TonightFeedback: Sendable, Equatable {
    var libraryItemID: LibraryItemID
    var verdict: TonightVerdict
    var day: LocalDay
    var createdAt: Date
}

/// A book in progress, for Tonight.
struct ReadingEntry: Sendable, Equatable {
    var libraryItemID: LibraryItemID
    var title: Title
    var pageCount: Int?
    var bookPage: Int?
    var bookPercent: Double?
    var lastChange: Date
}

/// When the user last touched an item, and when it joined the library.
struct ItemDates: Sendable, Equatable {
    var addedAt: Date
    var lastChange: Date
}

protocol TonightStore: Sendable {
    func reading(userID: UserID, limit: Int) async throws -> [ReadingEntry]
    func itemDates(_ ids: [LibraryItemID], userID: UserID) async throws -> [LibraryItemID: ItemDates]
    func feedback(userID: UserID, since: Date) async throws -> [TonightFeedback]
    /// Nil when the item is not the user's.
    func saveFeedback(_ feedback: TonightFeedback, userID: UserID) async throws -> TonightFeedback?
    /// Removes the user's verdicts on the item given on `day`: the Undo after one.
    func clearFeedback(itemID: LibraryItemID, day: LocalDay, userID: UserID) async throws
    /// Records what the strip showed on `day`, the latest showing winning. True when this is the
    /// first time the strip showed anything that day.
    func recordPicks(_ ids: [LibraryItemID], day: LocalDay, userID: UserID, servedAt: Date) async throws -> Bool
}
