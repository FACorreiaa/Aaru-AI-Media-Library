import AaruCore
import Foundation

/// Where a watch event came from. Only Stremio until SCR-002.
enum WatchSource: String, Codable, Sendable {
    case stremio
}

enum PlaybackAction: String, Sendable {
    case start, pause, stop

    var state: String {
        switch self {
        case .start: "playing"
        case .pause: "paused"
        case .stop: "stopped"
        }
    }
}

/// One playback report from a player, already mapped to ids Aaru understands.
struct PlaybackReport: Sendable {
    var source: WatchSource
    /// The player's own id for what is playing, kept verbatim (e.g. `tt0903747:1:2`).
    var externalRef: String
    var type: MediaType
    var ids: ExternalIDs
    /// Set for an episode; nil for a movie.
    var episode: EpisodeKey?
    var action: PlaybackAction
    var positionMs: Int64
    /// 0 when the player does not know it yet (Stremio's first `start`).
    var durationMs: Int64
}

/// The open (or just closed) session a report landed in.
struct WatchSession: Sendable, Equatable {
    var id: UUID
    var titleID: TitleID?
    var positionMs: Int64
    /// The longest non-zero duration any report in this session gave.
    var durationMs: Int64

    /// Percent watched, or nil while the duration is unknown.
    var progress: Double? {
        durationMs > 0 ? min(100, Double(positionMs) / Double(durationMs) * 100) : nil
    }
}

protocol WatchEventStore: Sendable {
    /// Opens or updates the session for this user, source and item, and returns it.
    func record(
        _ report: PlaybackReport, titleID: TitleID?, userID: UserID, agentTokenID: UUID?, now: Date
    ) async throws -> WatchSession
    /// Closes a session.
    func close(_ id: UUID, at: Date) async throws
    /// Whether a session for this item was closed since `since`: a second `stop` is a repeat.
    func stoppedRecently(userID: UserID, source: WatchSource, externalRef: String, since: Date) async throws -> Bool
}
