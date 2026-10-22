import AaruCore
import Foundation

// What one friend may see of another (SOC-001 settings, SOC-003 minimal activity), kept apart
// from the social graph in Stores+Social.swift.

/// A user's social choices. A user with no row has the defaults.
struct SocialSettings: Sendable, Equatable {
    /// Friends see your shelves, activity and compare. Strangers never do.
    var shareLibraryWithFriends = true
}

/// One title on a friend's shelf, without anything private to them (notes, owned).
struct FriendItem: Sendable, Equatable {
    var titleID: TitleID
    var status: LibraryStatus
    var rating: Double?
    /// The last episode they ticked, for shows.
    var lastSeason: Int?
    var lastEpisode: Int?
    var bookPage: Int?
    var finishedAt: Date?
    var updatedAt: Date
}

/// What a friend's profile shows: their shelves, and what the viewer and they share.
struct FriendShelf: Sendable, Equatable {
    var watching: [FriendItem]
    var finished: [FriendItem]
    /// Library size by kind (dropped left out): `movie`, `show`, `anime`, `book`, `album`.
    var counts: [String: Int]
    /// Titles both have planned.
    var bothWant: [TitleID]
    var bothFinished: Int
    /// Titles the friend rated 8 or more that the viewer does not have at all.
    var theyLoved: [TitleID]
}

/// One friend's activity on one title on one day: dated episode ticks, a finish, or both.
/// Imported and restored ticks carry no date and are never activity.
struct FriendActivity: Sendable, Equatable {
    var friend: UserID
    var titleID: TitleID
    /// The UTC day, `yyyy-MM-dd`.
    var day: String
    var episodes: Int
    var lastSeason: Int?
    var lastEpisode: Int?
    var finished: Bool
    var rating: Double?
    /// The latest tick or finish in the row.
    var lastAt: Date
}

protocol FriendViewStore: Sendable {
    func socialSettings(_ id: UserID) async throws -> SocialSettings
    func saveSocialSettings(_ settings: SocialSettings, for id: UserID) async throws
    /// When the two became friends; nil when they are not.
    func friendsSince(_ first: UserID, _ second: UserID) async throws -> Date?
    func shelf(of owner: UserID, viewer: UserID, limit: Int) async throws -> FriendShelf
    /// The viewer's friends' activity at or after `since` and before `before`, newest first.
    /// Friends who hide their library are left out.
    func activity(viewer: UserID, since: Date, before: Date, limit: Int) async throws -> [FriendActivity]
}
