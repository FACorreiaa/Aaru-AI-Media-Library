import aaruAPI
import AaruCore
import Foundation
import OpenAPIRuntime

/// SOC-001 settings and SOC-003: friend profiles and activity.
extension APIImplementation {
    var friendViews: FriendService {
        FriendService(stores: stores)
    }

    func getSocialSettings(_: Operations.GetSocialSettings.Input) async throws -> Operations.GetSocialSettings.Output {
        let settings = try await friendViews.settings(currentUser())
        return .ok(.init(body: .json(.init(shareLibraryWithFriends: settings.shareLibraryWithFriends))))
    }

    func updateSocialSettings(_ input: Operations.UpdateSocialSettings.Input) async throws
        -> Operations.UpdateSocialSettings.Output
    {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let saved = try await friendViews.save(
            SocialSettings(shareLibraryWithFriends: body.shareLibraryWithFriends), viewer: currentUser()
        )
        return .ok(.init(body: .json(.init(shareLibraryWithFriends: saved.shareLibraryWithFriends))))
    }

    func getFriendProfile(_ input: Operations.GetFriendProfile.Input) async throws
        -> Operations.GetFriendProfile.Output
    {
        guard let id = UUID(uuidString: input.path.userId) else { throw SocialService.noSuchUser }
        let profile = try await friendViews.profile(UserID(id), viewer: currentUser())
        return .ok(.init(body: .json(.init(profile))))
    }

    func listFriendActivity(_ input: Operations.ListFriendActivity.Input) async throws
        -> Operations.ListFriendActivity.Output
    {
        let feed = try await friendViews.activity(currentUser(), before: input.query.before)
        let items: [Components.Schemas.ActivityItem] = feed.items.compactMap { item in
            guard let user = feed.people[item.friend], let title = feed.titles[item.titleID] else { return nil }
            let key = ActivityKey(owner: item.friend, titleID: item.titleID, day: item.day)
            let reactions = feed.reactions[key]
            let counts = (reactions?.counts ?? [:])
                .sorted { ($0.value, Reaction.order($1.key)) > ($1.value, Reaction.order($0.key)) }
                .map { Components.Schemas.ReactionCount(emoji: $0.key, count: $0.value) }
            return .init(
                id: key.id, user: .init(user), title: .init(title), day: item.day, episodes: item.episodes,
                lastSeason: item.lastSeason, lastEpisode: item.lastEpisode, finished: item.finished,
                rating: item.rating, at: item.lastAt, reactions: counts.isEmpty ? nil : counts,
                myReaction: reactions?.mine
            )
        }
        let full = feed.items.count == FriendService.activityPage
        return .ok(.init(body: .json(.init(items: items, nextBefore: full ? feed.items.last?.lastAt : nil))))
    }
}

extension Components.Schemas.FriendProfile {
    init(_ profile: FriendProfile) {
        let titles = profile.titles
        let shelf = profile.shelf
        func item(_ item: FriendItem) -> Components.Schemas.FriendItem? {
            guard let title = titles[item.titleID] else { return nil }
            return .init(
                title: .init(title), status: .init(item.status), rating: item.rating, lastSeason: item.lastSeason,
                lastEpisode: item.lastEpisode, bookPage: item.bookPage, finishedAt: item.finishedAt,
                updatedAt: item.updatedAt
            )
        }
        func summaries(_ ids: [TitleID]) -> [Components.Schemas.TitleSummary] {
            ids.compactMap { titles[$0] }.map { .init($0) }
        }
        self.init(
            user: .init(profile.user),
            friendsSince: profile.friendsSince,
            sharing: profile.sharing,
            counts: shelf.map {
                .init(
                    movie: $0.counts["movie"] ?? 0, show: $0.counts["show"] ?? 0, anime: $0.counts["anime"] ?? 0,
                    book: $0.counts["book"] ?? 0, album: $0.counts["album"] ?? 0
                )
            },
            watching: shelf.map { $0.watching.compactMap(item) },
            recentlyFinished: shelf.map { $0.finished.compactMap(item) },
            compare: shelf.map {
                .init(
                    bothWant: summaries($0.bothWant),
                    bothFinished: $0.bothFinished,
                    theyLoved: summaries($0.theyLoved)
                )
            }
        )
    }
}
