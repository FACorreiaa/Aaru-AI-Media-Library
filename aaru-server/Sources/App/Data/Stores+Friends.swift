import AaruCore
import Foundation

// What one friend may see of another (SOC-001 settings, SOC-003 minimal activity), kept apart
// from the social graph in Stores+Social.swift.

/// A user's social choices. A user with no row has the defaults.
struct SocialSettings: Sendable, Equatable {
    /// Friends see your shelves, activity and compare. Strangers never do.
    var shareLibraryWithFriends = true
    /// Friends see your level and badges (GAM-004, owner 2026-10-22). Private badges never.
    var showAchievementsToFriends = true
    /// You appear on friends' weekly board, and see it (GAM-005). Off until you join.
    var leaderboardOptIn = false
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
    /// The last chapter they read, for manga.
    var mangaChapter: Int?
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
    /// The viewer's and their friends' activity at or after `since` and before `before`, newest
    /// first. Friends who hide their library are left out.
    func activity(viewer: UserID, since: Date, before: Date, limit: Int) async throws -> [FriendActivity]
}

// MARK: Reactions and recommendations (SOC-007, SOC-006)

/// One activity row: a person's title on one UTC day. Its id is `{owner}-{title}-{yyyy-MM-dd}`.
struct ActivityKey: Hashable, Sendable {
    var owner: UserID
    var titleID: TitleID
    var day: String

    var id: String {
        "\(owner)-\(titleID)-\(day)"
    }

    init(owner: UserID, titleID: TitleID, day: String) {
        self.owner = owner
        self.titleID = titleID
        self.day = day
    }

    /// Parses an id; nil for anything malformed.
    init?(id: String) {
        let uuidLength = 36
        guard id.count == uuidLength * 2 + 12 else { return nil }
        let owner = id.prefix(uuidLength)
        let title = id.dropFirst(uuidLength + 1).prefix(uuidLength)
        let day = String(id.suffix(10))
        guard let ownerID = UUID(uuidString: String(owner)), let titleID = UUID(uuidString: String(title)),
              day.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil
        else { return nil }
        self.init(owner: UserID(ownerID), titleID: TitleID(titleID), day: day)
    }
}

/// The reactions Aaru offers, the only ones the table accepts.
enum Reaction {
    static let all = ["❤️", "😂", "😮", "😭", "🔥", "👏"]

    /// Where an emoji sits in the set, for a stable order between equal counts.
    static func order(_ emoji: String) -> Int {
        all.firstIndex(of: emoji) ?? all.count
    }
}

/// Reactions on one activity row: how many of each, and the viewer's own.
struct ReactionSummary: Sendable, Equatable {
    var counts: [String: Int] = [:]
    var mine: String?
}

/// A title one friend sent another, waiting to be added or dismissed.
struct Recommendation: Sendable, Equatable {
    var id: UUID
    var sender: UserID
    var recipient: UserID
    var titleID: TitleID
    var note: String?
    var createdAt: Date
}

protocol InteractionStore: Sendable {
    func reactions(on rows: [ActivityKey], viewer: UserID) async throws -> [ActivityKey: ReactionSummary]
    /// Sets the viewer's reaction on a row, or removes it when `emoji` is nil.
    func react(_ emoji: String?, on row: ActivityKey, by user: UserID, now: Date) async throws
    /// True when the owner has the title in their library at all: a row can only be about that.
    func hasTitle(_ owner: UserID, _ titleID: TitleID) async throws -> Bool
    /// Inserts recommendations; one already waiting for the same pair and title is left alone.
    func recommend(_ recommendations: [Recommendation]) async throws
    /// Waiting recommendations to `user` from people who are still their friends, newest first.
    func inbox(_ user: UserID, limit: Int) async throws -> [Recommendation]
    /// Marks a waiting recommendation to `user` added or dismissed. Nil when none was waiting.
    func resolve(_ id: UUID, to user: UserID, added: Bool, now: Date) async throws -> Recommendation?
}
