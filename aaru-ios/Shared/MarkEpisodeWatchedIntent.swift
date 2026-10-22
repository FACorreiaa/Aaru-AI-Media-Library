import AaruCore
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
        try await EpisodeWatching.markWatched(libraryItemId: libraryItemId, season: season, episode: episode)
        return .result()
    }
}

/// The one way the widgets and the Live Activity tick an episode outside the app's own models.
enum EpisodeWatching {
    static func markWatched(libraryItemId: String, season: Int, episode: Int) async throws {
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
        #if os(iOS)
            await NowWatching.episodeWatched(libraryItemId: libraryItemId, season: season, episode: episode)
        #endif
        // The real next episode, remaining count and finale flag come from the server.
        try? await WidgetSync.refresh(api: api)
        WidgetCenter.shared.reloadAllTimelines()
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

#if os(iOS)
    /// The Live Activities' "Mark watched" (WID-005, SCR-009), on episode and movie rows. An
    /// episode takes the same tick as the Up Next check; a movie the same `finished` the status
    /// menu sets. Runs in the app's process; the row reads "Watched" once the server has it, and
    /// on failure the activity stays as it was.
    struct MarkNowPlayingWatchedIntent: LiveActivityIntent {
        static let title: LocalizedStringResource = "Mark Now Playing Watched"
        static let isDiscoverable = false

        @Parameter(title: "Library item")
        var libraryItemId: String

        @Parameter(title: "Season")
        var season: Int?

        @Parameter(title: "Episode")
        var episode: Int?

        init() {}

        init(libraryItemId: String, season: Int?, episode: Int?) {
            self.libraryItemId = libraryItemId
            self.season = season
            self.episode = episode
        }

        func perform() async throws -> some IntentResult {
            if let season, let episode {
                try await EpisodeWatching.markWatched(libraryItemId: libraryItemId, season: season, episode: episode)
            } else {
                try await MovieWatching.markFinished(libraryItemId: libraryItemId)
            }
            return .result()
        }
    }

    /// A movie from the Live Activity: `PATCH /v1/library/items/{id}` with `finished`, journaled
    /// like the status menu's.
    enum MovieWatching {
        static func markFinished(libraryItemId: String) async throws {
            guard let api = SharedAPI.client() else { throw EpisodeWatching.SignedOut() }
            do {
                let output = try await api.updateLibraryItem(
                    path: .init(id: libraryItemId),
                    body: .json(.init(status: .finished))
                )
                guard case .ok = output else { throw NotSaved() }
            } catch {
                throw NotSaved()
            }
            await NowPlayingActivity.watched(libraryItemId: libraryItemId) { $0.kind == .movie }
            try? await WidgetSync.refresh(api: api)
            WidgetCenter.shared.reloadAllTimelines()
        }

        struct NotSaved: LocalizedError {
            var errorDescription: String? {
                "The movie was not saved. Try again in Aaru."
            }
        }
    }

    /// Tapping the time label flips "Ends at 1:20 PM" and "41m left".
    struct ToggleEndTimeIntent: LiveActivityIntent {
        static let title: LocalizedStringResource = "Toggle End Time"
        static let isDiscoverable = false

        func perform() async throws -> some IntentResult {
            await NowPlayingActivity.toggleEndTime()
            await NowWatching.toggleEndTime()
            return .result()
        }
    }
#endif
