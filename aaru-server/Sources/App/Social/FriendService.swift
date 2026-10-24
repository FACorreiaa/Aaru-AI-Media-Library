import AaruCore
import Foundation

/// A friend's profile as the viewer may see it.
struct FriendProfile: Sendable {
    var user: SocialUser
    var friendsSince: Date
    /// False when the friend hides their library: then only the header is shown.
    var sharing: Bool
    var shelf: FriendShelf?
    /// Every title the shelf names, by id.
    var titles: [TitleID: Title]
    /// Level and badges; nil when the friend hides them (independent of `sharing`).
    var achievements: (level: Int, badges: [EarnedBadge])?
    /// Their top 10s (FAV-001); nil when they hide their library.
    var favorites: Favorites?
}

/// One activity row with the people and titles it names.
struct ActivityFeed: Sendable {
    var items: [FriendActivity]
    var reactions: [ActivityKey: ReactionSummary] = [:]
    var people: [UserID: SocialUser]
    var titles: [TitleID: Title]
}

/// What friends see of each other (SOC-001 settings, SOC-003 minimal). Friends only: anyone
/// else, and a block either way, is the same 404 as a handle nobody holds. A friend who hides
/// their library shows only their name.
struct FriendService: Sendable {
    let stores: Stores
    var now: @Sendable () -> Date = { Date() }

    static let shelfLimit = 12
    static let activityWindow: TimeInterval = 14 * 24 * 60 * 60
    static let activityPage = 40

    func settings(_ viewer: UserID) async throws -> SocialSettings {
        try await stores.friendViews.socialSettings(viewer)
    }

    func save(_ settings: SocialSettings, viewer: UserID) async throws -> SocialSettings {
        try await stores.friendViews.saveSocialSettings(settings, for: viewer)
        return settings
    }

    func profile(_ friend: UserID, viewer: UserID) async throws -> FriendProfile {
        guard friend != viewer,
              try await !stores.social.isBlocked(viewer, friend),
              let since = try await stores.friendViews.friendsSince(viewer, friend),
              let user = try await stores.social.socialUser(friend)
        else { throw SocialService.noSuchUser }
        let achievements = try await GamificationService(stores: stores, now: now).friendAchievements(friend)
        guard try await stores.friendViews.socialSettings(friend).shareLibraryWithFriends else {
            return FriendProfile(
                user: user, friendsSince: since, sharing: false, shelf: nil, titles: [:], achievements: achievements
            )
        }
        async let shelf = stores.friendViews.shelf(of: friend, viewer: viewer, limit: Self.shelfLimit)
        async let favorites = FavoriteService.favorites(of: friend, stores: stores)
        let shown = try await shelf
        let ids = shown.watching.map(\.titleID) + shown.finished.map(\.titleID) + shown.bothWant + shown.theyLoved
        return try await FriendProfile(
            user: user, friendsSince: since, sharing: true, shelf: shown, titles: titles(ids),
            achievements: achievements, favorites: favorites
        )
    }

    /// Your and your friends' last two weeks, newest first, one page at a time.
    func activity(_ viewer: UserID, before: Date?) async throws -> ActivityFeed {
        let now = now()
        let items = try await stores.friendViews.activity(
            viewer: viewer, since: now.addingTimeInterval(-Self.activityWindow), before: before ?? now,
            limit: Self.activityPage
        )
        var everyone = try await stores.social.friends(viewer)
        if let own = try await stores.social.socialUser(viewer) {
            everyone.append(own)
        }
        let people = Dictionary(everyone.map { ($0.id, $0) }) { first, _ in first }
        // A friend without a handle has no social identity yet; their rows wait until they claim one.
        let shown = items.filter { people[$0.friend] != nil }
        let keys = shown.map { ActivityKey(owner: $0.friend, titleID: $0.titleID, day: $0.day) }
        return try await ActivityFeed(
            items: shown, reactions: stores.interactions.reactions(on: keys, viewer: viewer), people: people,
            titles: titles(shown.map(\.titleID))
        )
    }

    private func titles(_ ids: [TitleID]) async throws -> [TitleID: Title] {
        let unique = Array(Set(ids))
        guard !unique.isEmpty else { return [:] }
        return try await Dictionary(stores.titles.titles(ids: unique).map { ($0.id, $0) }) { first, _ in first }
    }
}
