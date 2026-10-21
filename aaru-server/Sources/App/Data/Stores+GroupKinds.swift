import AaruCore
import Foundation

// Title, shelf and watch channels (GRP-007…GRP-009).

enum ChannelKind: String, Sendable, CaseIterable {
    case text
    case title
    case watch
    case shelf
}

/// A point in a show: season and episode, ordered as watched.
struct EpisodePoint: Sendable, Hashable, Comparable {
    var season: Int
    var episode: Int

    static func < (lhs: EpisodePoint, rhs: EpisodePoint) -> Bool {
        (lhs.season, lhs.episode) < (rhs.season, rhs.episode)
    }
}

/// What a message may give away: up to an episode, or the ending of anything.
enum SpoilerStamp: Sendable, Hashable {
    case episode(EpisodePoint)
    case ending
}

/// One user's progress in one title: their library status and the furthest episode they ticked.
struct TitleProgress: Sendable, Equatable {
    var status: LibraryStatus
    var furthest: EpisodePoint?
}

/// One title on a shelf channel. `addedBy` is nil once that account is gone.
struct ShelfItem: Sendable, Equatable {
    var titleID: TitleID
    var addedBy: SocialUser?
    var addedAt: Date
    var position: Int
    /// The viewer's own library status for the title, when they have it.
    var myStatus: LibraryStatus?
}

/// A watch party in a watch channel. Lobby until `startsAt` is set, then a countdown until it
/// passes, then live until `endedAt`.
struct WatchParty: Sendable, Equatable {
    var id: UUID
    var channelID: UUID
    var titleID: TitleID
    var episode: EpisodePoint?
    var createdBy: SocialUser?
    var startsAt: Date?
    var endedAt: Date?
    var createdAt: Date
    var ready: [SocialUser] = []
}

/// The data behind title, shelf and watch channels. Rules live in `GroupService`.
protocol GroupKindStore: Sendable {
    func setShareProgress(_ group: UUID, user: UserID, share: Bool) async throws
    /// Each user's progress in a title; users without it in their library are absent.
    func progress(title: TitleID, users: [UserID]) async throws -> [UserID: TitleProgress]

    /// Shelf titles by position, with the viewer's own status for each.
    func shelfItems(_ channel: UUID, viewer: UserID) async throws -> [ShelfItem]
    /// Adds a title at the end. False when it was already there.
    func addShelfItem(_ channel: UUID, title: TitleID, by user: UserID, now: Date) async throws -> Bool
    func removeShelfItem(_ channel: UUID, title: TitleID) async throws -> Bool

    /// The channel's newest party, ended or not.
    func latestParty(_ channel: UUID) async throws -> WatchParty?
    /// `StoreConflict` when the channel already has an open session.
    func createSession(_ session: WatchParty) async throws
    func setReady(_ session: UUID, user: UserID, ready: Bool) async throws
    func startSession(_ session: UUID, at startsAt: Date) async throws
    func endSession(_ session: UUID, now: Date) async throws
}
