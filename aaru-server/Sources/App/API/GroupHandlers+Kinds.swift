import aaruAPI
import AaruCore
import Foundation
import OpenAPIRuntime

/// Title, shelf and watch channels (GRP-007…GRP-009).
extension APIImplementation {
    func updateMyMembership(_ input: Operations.UpdateMyMembership.Input) async throws
        -> Operations.UpdateMyMembership.Output
    {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let summary = try await services.groups.setShareProgress(
            groupID(input.path.groupId), share: body.shareProgress, viewer: currentUser()
        )
        return .ok(.init(body: .json(.init(summary))))
    }

    func getChannelProgress(_ input: Operations.GetChannelProgress.Input) async throws
        -> Operations.GetChannelProgress.Output
    {
        let viewer = try currentUser()
        let progress = try await services.groups.titleProgress(
            groupID(input.path.groupId), channel: channelID(input.path.channelId), viewer: viewer
        )
        let viewerUser = try await stores.social.socialUser(viewer)
        return .ok(.init(body: .json(.init(
            title: .init(progress.title),
            mine: viewerUser.map { .init(.init(user: $0, progress: progress.mine)) },
            members: progress.members.map { .init($0) }
        ))))
    }

    func listChannelItems(_ input: Operations.ListChannelItems.Input) async throws
        -> Operations.ListChannelItems.Output
    {
        try await .ok(.init(body: .json(shelf(input.path.groupId, input.path.channelId))))
    }

    func addChannelItem(_ input: Operations.AddChannelItem.Input) async throws -> Operations.AddChannelItem.Output {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        _ = try await services.groups.addToShelf(
            groupID(input.path.groupId), channel: channelID(input.path.channelId), title: MediaRef(body.title),
            viewer: currentUser()
        )
        return try await .ok(.init(body: .json(shelf(input.path.groupId, input.path.channelId))))
    }

    func removeChannelItem(_ input: Operations.RemoveChannelItem.Input) async throws
        -> Operations.RemoveChannelItem.Output
    {
        guard let title = TitleID(uuidString: input.path.titleId) else {
            throw AppError.notFound("That title is not on this shelf.")
        }
        try await services.groups.removeFromShelf(
            groupID(input.path.groupId), channel: channelID(input.path.channelId), title: title, viewer: currentUser()
        )
        return .noContent(.init())
    }

    func getWatchParty(_ input: Operations.GetWatchParty.Input) async throws -> Operations.GetWatchParty.Output {
        let found = try await services.groups.party(
            groupID(input.path.groupId), channel: channelID(input.path.channelId), viewer: currentUser()
        )
        return .ok(.init(body: .json(partyView(found))))
    }

    func openWatchParty(_ input: Operations.OpenWatchParty.Input) async throws -> Operations.OpenWatchParty.Output {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let episode = body.season.flatMap { season in body.episode.map { EpisodePoint(season: season, episode: $0) } }
        let found = try await services.groups.openParty(
            groupID(input.path.groupId), channel: channelID(input.path.channelId), title: MediaRef(body.title),
            episode: episode, viewer: currentUser()
        )
        return .ok(.init(body: .json(partyView(found))))
    }

    func setWatchPartyReady(_ input: Operations.SetWatchPartyReady.Input) async throws
        -> Operations.SetWatchPartyReady.Output
    {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let found = try await services.groups.setReady(
            groupID(input.path.groupId), channel: channelID(input.path.channelId), ready: body.ready,
            viewer: currentUser()
        )
        return .ok(.init(body: .json(partyView(found))))
    }

    func startWatchParty(_ input: Operations.StartWatchParty.Input) async throws -> Operations.StartWatchParty.Output {
        var seconds: Int?
        if case let .json(body) = input.body {
            seconds = body.countdownSeconds
        }
        let found = try await services.groups.startCountdown(
            groupID(input.path.groupId), channel: channelID(input.path.channelId), seconds: seconds,
            viewer: currentUser()
        )
        return .ok(.init(body: .json(partyView(found))))
    }

    func endWatchParty(_ input: Operations.EndWatchParty.Input) async throws -> Operations.EndWatchParty.Output {
        let found = try await services.groups.endParty(
            groupID(input.path.groupId), channel: channelID(input.path.channelId), viewer: currentUser()
        )
        return .ok(.init(body: .json(partyView(found))))
    }

    func markWatchPartyWatched(_ input: Operations.MarkWatchPartyWatched.Input) async throws
        -> Operations.MarkWatchPartyWatched.Output
    {
        try await services.groups.markWatched(
            groupID(input.path.groupId), channel: channelID(input.path.channelId), viewer: currentUser()
        )
        return .noContent(.init())
    }

    private func shelf(_ group: String, _ channel: String) async throws -> Components.Schemas.ChannelItemList {
        let items = try await services.groups.shelf(groupID(group), channel: channelID(channel), viewer: currentUser())
        return .init(items: items.map { item, title in
            .init(
                title: .init(title), addedBy: item.addedBy.map { .init($0) }, addedAt: item.addedAt,
                myStatus: item.myStatus.map(Components.Schemas.LibraryStatus.init)
            )
        })
    }

    private func partyView(_ found: (WatchParty, Title)?) -> Components.Schemas.WatchPartyView {
        let now = Date()
        return .init(party: found.map { .init($0.0, title: $0.1, now: now) }, serverTime: now)
    }
}

extension Components.Schemas.MemberProgress {
    init(_ member: GroupService.MemberProgress) {
        self.init(
            user: .init(member.user),
            status: member.progress.map { Components.Schemas.LibraryStatus($0.status) },
            season: member.progress?.furthest?.season,
            episode: member.progress?.furthest?.episode
        )
    }
}

extension Components.Schemas.WatchParty {
    init(_ party: WatchParty, title: Title, now: Date) {
        let state: StatePayload = if party.endedAt != nil {
            .ended
        } else if let startsAt = party.startsAt {
            startsAt > now ? .countdown : .live
        } else {
            .lobby
        }
        self.init(
            id: party.id.uuidString, title: .init(title), season: party.episode?.season,
            episode: party.episode?.episode, state: state, startsAt: party.startsAt, endedAt: party.endedAt,
            host: party.createdBy.map { .init($0) }, ready: party.ready.map { .init($0) }
        )
    }
}
