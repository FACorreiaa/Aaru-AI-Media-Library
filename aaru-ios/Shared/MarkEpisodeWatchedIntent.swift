import AppIntents
import Foundation
import WidgetKit

/// Marks one episode watched (WID-002). The Up Next widget's check runs it in place: the row
/// advances at once, then the same `PUT .../episodes/{s}/{e}` as a tap in the app (so the server
/// journals it like one), then the snapshot is rebuilt from the server's answer.
struct MarkEpisodeWatchedIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark Episode Watched"
    static let description = IntentDescription("Marks the next episode of a show as watched in Aaru.")
    /// Widget-only: the parameters are library ids, not something to type into Shortcuts.
    static let isDiscoverable = false

    @Parameter(title: "Library item")
    var libraryItemId: String

    @Parameter(title: "Season")
    var season: Int

    @Parameter(title: "Episode")
    var episode: Int

    init() {}

    init(libraryItemId: String, season: Int, episode: Int) {
        self.libraryItemId = libraryItemId
        self.season = season
        self.episode = episode
    }

    func perform() async throws -> some IntentResult {
        guard let api = SharedAPI.client() else { throw SignedOut() }
        let before = WidgetSnapshotStore.advance(libraryItemId: libraryItemId)
        WidgetCenter.shared.reloadAllTimelines()
        do {
            let output = try await api.setEpisodeWatched(
                path: .init(id: libraryItemId, season: season, episode: episode),
                body: .json(.init(watched: true))
            )
            guard case .ok = output else { throw NotSaved() }
        } catch {
            if let before {
                WidgetSync.publish(before)
            }
            throw NotSaved()
        }
        WidgetSnapshotStore.setWatched(libraryItemId: libraryItemId, season: season, number: episode, watched: true)
        // The real next episode, remaining count and finale flag come from the server.
        try? await WidgetSync.refresh(api: api)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }

    struct SignedOut: LocalizedError {
        var errorDescription: String? {
            "Open Aaru and sign in first."
        }
    }

    struct NotSaved: LocalizedError {
        var errorDescription: String? {
            "The episode was not saved. Try again in Aaru."
        }
    }
}
