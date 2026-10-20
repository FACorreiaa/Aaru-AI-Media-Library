import AaruCore
import Foundation

/// Title channels and the spoiler guard (GRP-007), shelf channels (GRP-008) and watch parties
/// (GRP-009). Nothing here writes to anyone's library but the viewer's own, through
/// `LibraryService`, journaled like any tap.
extension GroupService {
    static let maxShelfItems = 200
    static let countdownRange = 3 ... 60
    /// Reactions a watch party carries. A fixed set keeps the socket from carrying free text.
    static let reactions: Set<String> = ["😂", "😱", "😭", "❤️", "👏", "🔥"]

    /// One member's progress in a title channel's title.
    struct MemberProgress: Sendable, Equatable {
        var user: SocialUser
        var progress: TitleProgress?
    }

    /// A title channel's header: its title, the viewer's progress, and members who share theirs.
    struct ChannelProgress: Sendable, Equatable {
        var title: Title
        var mine: TitleProgress?
        var members: [MemberProgress]
    }

    // MARK: Progress and spoilers

    /// Shows or hides the viewer's progress in this group's title channels.
    func setShareProgress(_ group: UUID, share: Bool, viewer: UserID) async throws -> GroupSummary {
        _ = try await role(group, viewer)
        try await stores.groupKinds.setShareProgress(group, user: viewer, share: share)
        await announce(.groupUpdated(group: group), in: group)
        guard let summary = try await stores.groups.summary(group, viewer: viewer) else { throw Self.noSuchGroup }
        return summary
    }

    /// A title channel's title, the viewer's own progress, and the progress of members who share
    /// theirs in this group. Nobody else appears.
    func titleProgress(_ group: UUID, channel: UUID, viewer: UserID) async throws -> ChannelProgress {
        _ = try await role(group, viewer)
        let found = try await requireChannel(group, channel)
        guard let titleID = found.titleID, let title = try await stores.titles.title(id: titleID) else {
            throw Self.invalid("channelId", "That channel is not about a title.")
        }
        let sharing = try await stores.groups.members(group).filter { $0.shareProgress && $0.user.id != viewer }
        let progress = try await stores.groupKinds.progress(title: titleID, users: sharing.map(\.user.id) + [viewer])
        return ChannelProgress(
            title: title, mine: progress[viewer],
            members: sharing.map { MemberProgress(user: $0.user, progress: progress[$0.user.id]) }
        )
    }

    /// The stamp a message gets by default: where the author is in the show, or the ending once
    /// they finished it. Nothing for a title they have not started.
    static func autoStamp(_ progress: TitleProgress) -> SpoilerStamp? {
        if progress.status == .finished {
            return .ending
        }
        return progress.furthest.map { .episode($0) }
    }

    /// Whether a stamp hides the message from a reader with this progress. Finishing a title
    /// unveils everything about it.
    static func veils(_ stamp: SpoilerStamp?, _ reader: TitleProgress?) -> Bool {
        guard let stamp else { return false }
        if reader?.status == .finished {
            return false
        }
        switch stamp {
        case .ending:
            return true
        case let .episode(point):
            guard let furthest = reader?.furthest else { return true }
            return furthest < point
        }
    }

    /// Members a message is veiled for. The author never is.
    static func veiledFor(
        _ message: GroupMessage, members: [GroupMember], progress: [UserID: TitleProgress]?
    ) -> Set<UserID> {
        guard let progress, message.spoiler != nil else { return [] }
        return Set(members.map(\.user.id).filter { $0 != message.author?.id && veils(message.spoiler, progress[$0]) })
    }

    // MARK: Shelf

    func shelf(_ group: UUID, channel: UUID, viewer: UserID) async throws -> [(ShelfItem, Title)] {
        _ = try await role(group, viewer)
        try await requireKind(.shelf, group, channel)
        let items = try await stores.groupKinds.shelfItems(channel, viewer: viewer)
        let titles = try await stores.titles.titles(ids: items.map(\.titleID))
        let byID = Dictionary(titles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return items.compactMap { item in byID[item.titleID].map { (item, $0) } }
    }

    /// Any member adds a title. Adding one already there changes nothing.
    func addToShelf(_ group: UUID, channel: UUID, title ref: MediaRef, viewer: UserID) async throws -> Title {
        _ = try await role(group, viewer)
        try await requireKind(.shelf, group, channel)
        guard try await stores.groupKinds.shelfItems(channel, viewer: viewer).count < Self.maxShelfItems else {
            throw Self.invalid("title", "A shelf holds \(Self.maxShelfItems) titles.")
        }
        let title = try await resolver.resolve(ref)
        if try await stores.groupKinds.addShelfItem(channel, title: title.id, by: viewer, now: now()) {
            await announce(.shelfUpdated(group: group, channel: channel), in: group)
        }
        return title
    }

    /// Any member removes a title.
    func removeFromShelf(_ group: UUID, channel: UUID, title: TitleID, viewer: UserID) async throws {
        _ = try await role(group, viewer)
        try await requireKind(.shelf, group, channel)
        guard try await stores.groupKinds.removeShelfItem(channel, title: title) else {
            throw AppError.notFound("That title is not on this shelf.")
        }
        await announce(.shelfUpdated(group: group, channel: channel), in: group)
    }

    // MARK: Watch parties

    /// The channel's newest party with its title, or nil before the first one.
    func party(_ group: UUID, channel: UUID, viewer: UserID) async throws -> (WatchParty, Title)? {
        _ = try await role(group, viewer)
        try await requireKind(.watch, group, channel)
        guard let party = try await stores.groupKinds.latestParty(channel),
              let title = try await stores.titles.title(id: party.titleID)
        else { return nil }
        return (party, title)
    }

    /// Opens a party in the lobby. A show needs the episode; a channel holds one open party.
    func openParty(
        _ group: UUID, channel: UUID, title ref: MediaRef, episode: EpisodePoint?, viewer: UserID
    ) async throws -> (WatchParty, Title) {
        _ = try await role(group, viewer)
        try await requireKind(.watch, group, channel)
        let host = try await social.requireHandle(viewer)
        let title = try await resolver.resolve(ref)
        if title.type == .show {
            guard let episode, episode.season >= 0, episode.episode >= 1 else {
                throw Self.invalid("episode", "Pick the episode you are watching.")
            }
        }
        try await stores.groupKinds.createSession(WatchParty(
            id: UUID(), channelID: channel, titleID: title.id, episode: title.type == .show ? episode : nil,
            createdBy: host, createdAt: now()
        ))
        await announce(.watchUpdated(group: group, channel: channel), in: group)
        return try await requireParty(group, channel, viewer)
    }

    func setReady(_ group: UUID, channel: UUID, ready: Bool, viewer: UserID) async throws -> (WatchParty, Title) {
        let (party, _) = try await requireParty(group, channel, viewer, open: true)
        try await stores.groupKinds.setReady(party.id, user: viewer, ready: ready)
        await announce(.watchUpdated(group: group, channel: channel), in: group)
        return try await requireParty(group, channel, viewer)
    }

    /// Starts the countdown. The host or an admin does; every client counts down to the same
    /// server time.
    func startCountdown(
        _ group: UUID, channel: UUID, seconds: Int?, viewer: UserID
    ) async throws -> (WatchParty, Title) {
        let (party, _) = try await requireParty(group, channel, viewer, open: true)
        try await requireHost(party, group, viewer)
        let seconds = seconds ?? 10
        guard Self.countdownRange.contains(seconds) else {
            throw Self.invalid("countdownSeconds", "Count down from 3 to 60 seconds.")
        }
        try await stores.groupKinds.startSession(party.id, at: now().addingTimeInterval(TimeInterval(seconds)))
        await announce(.watchUpdated(group: group, channel: channel), in: group)
        return try await requireParty(group, channel, viewer)
    }

    func endParty(_ group: UUID, channel: UUID, viewer: UserID) async throws -> (WatchParty, Title) {
        let (party, _) = try await requireParty(group, channel, viewer, open: true)
        try await requireHost(party, group, viewer)
        try await stores.groupKinds.endSession(party.id, now: now())
        await announce(.watchUpdated(group: group, channel: channel), in: group)
        return try await requireParty(group, channel, viewer)
    }

    /// Marks the party's episode, or the film or book, watched in the viewer's own library only:
    /// the same journaled writes as ticking it on the title page.
    func markWatched(_ group: UUID, channel: UUID, viewer: UserID) async throws {
        let (party, title) = try await requireParty(group, channel, viewer)
        guard party.startsAt != nil else { throw Self.invalid("party", "The party has not started yet.") }
        let ref = MediaRef(titleID: title.id, type: title.type)
        if let episode = party.episode {
            let entry = try await library.add(ref, status: .inProgress, userID: viewer)
            _ = try await library.setEpisode(
                entry.item.id, userID: viewer, key: EpisodeKey(season: episode.season, episode: episode.episode),
                watched: true
            )
        } else {
            let entry = try await library.add(ref, status: .finished, userID: viewer)
            if entry.item.status != .finished {
                var patch = ItemPatch()
                patch.status = .finished
                _ = try await library.patch(entry.item.id, userID: viewer, patch: patch)
            }
        }
    }

    /// A reaction from the socket, for the other members. Anything outside the set is dropped.
    func react(_ group: UUID, channel: UUID, emoji: String, viewer: UserID) async throws {
        guard Self.reactions.contains(emoji) else { return }
        _ = try await role(group, viewer)
        try await requireKind(.watch, group, channel)
        let user = try await social.requireHandle(viewer)
        await announce(.watchReaction(group: group, channel: channel, user, emoji), in: group, except: viewer)
    }

    // MARK: Rules

    private func requireKind(_ kind: ChannelKind, _ group: UUID, _ channel: UUID) async throws {
        guard try await requireChannel(group, channel).kind == kind else {
            throw Self.invalid("channelId", "That is not a \(kind.rawValue) channel.")
        }
    }

    private func requireParty(
        _ group: UUID, _ channel: UUID, _ viewer: UserID, open: Bool = false
    ) async throws -> (WatchParty, Title) {
        guard let found = try await party(group, channel: channel, viewer: viewer),
              !open || found.0.endedAt == nil
        else { throw AppError.notFound("No watch party is open here.") }
        return found
    }

    private func requireHost(_ party: WatchParty, _ group: UUID, _ viewer: UserID) async throws {
        let manages = try await role(group, viewer).manages
        guard party.createdBy?.id == viewer || manages else {
            throw Self.forbidden("Only whoever opened the party, or an admin, can do that.")
        }
    }
}
