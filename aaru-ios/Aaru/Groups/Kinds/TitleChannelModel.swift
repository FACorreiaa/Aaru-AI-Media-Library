import AaruAPI
import Foundation
import Observation

typealias ChannelProgress = Components.Schemas.ChannelProgress
typealias MemberProgress = Components.Schemas.MemberProgress

/// GRP-007: a title channel's title, the viewer's progress, the progress of members who share
/// theirs in this group, and the viewer's own share switch (off until they turn it on).
@MainActor
@Observable
final class TitleChannelModel {
    private(set) var progress: ChannelProgress?
    /// Why the first load failed; nil once it has loaded (UX-063).
    private(set) var loadProblem: String?

    @ObservationIgnored private let api: Client?
    @ObservationIgnored let groupID: String
    @ObservationIgnored let channelID: String

    init(api: Client?, groupID: String, channelID: String) {
        self.api = api
        self.groupID = groupID
        self.channelID = channelID
    }

    func load() async {
        guard let api else { return }
        do {
            switch try await api.getChannelProgress(path: .init(groupId: groupID, channelId: channelID)) {
            case let .ok(response):
                progress = try response.body.json
                loadProblem = nil
            case let .default(_, error):
                if progress == nil {
                    loadProblem = (try? error.body.json.message) ?? "This title could not be loaded."
                }
            }
        } catch {
            // A refresh that fails keeps what is on screen.
            if progress == nil {
                loadProblem = "This title could not be loaded. Aaru could not reach the server."
            }
        }
    }
}

extension MemberProgress {
    /// In the kind's own words: "S1 · E3", "Watched", "Read", "Plan to watch"; "Not started"
    /// when it is not in their library (UX-043, UX-045).
    func summary(for kind: MediaKind) -> String {
        if status != .finished, let season, let episode {
            return EpisodeCode.text(season: season, episode: episode)
        }
        return status?.label(for: kind) ?? "Not started"
    }
}

extension GroupsModel {
    /// Shows or hides the user's progress in this group's title channels.
    func setShareProgress(_ groupID: String, share: Bool) async {
        guard let api else { return }
        await run("That setting was not saved.") {
            switch try await api.updateMyMembership(
                path: .init(groupId: groupID), body: .json(.init(shareProgress: share))
            ) {
            case .ok: await loadDetail(groupID)
            case let .default(_, error): throw Failure(try? error.body.json)
            }
        }
    }
}
