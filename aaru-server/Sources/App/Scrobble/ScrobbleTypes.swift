import AaruCore
import Foundation

/// Where a watch event came from: Stremio's addon, or a streaming site through the browser
/// extension (SCR-007).
enum WatchSource: String, Codable, Sendable, CaseIterable {
    case stremio
    case netflix
    case disneyPlus = "disney_plus"
    case primeVideo = "prime_video"
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
    /// Set when the player already names an Aaru title (Stremio's `aaru:` ids).
    var titleID: TitleID?
    /// Set for an episode; nil for a movie.
    var episode: EpisodeKey?
    /// A player with no ids names what plays instead (SCR-007): matched by name, never guessed.
    var title: String?
    /// With `title`: matched by title + year when the player knows the year.
    var year: Int?
    /// The episode's own name, when the player gives no number Aaru can trust.
    var episodeName: NamedEpisode?
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
    func close(_ id: UUID, at date: Date) async throws
    /// Whether a session for this item was closed since `since`: a second `stop` is a repeat.
    func stoppedRecently(userID: UserID, source: WatchSource, externalRef: String, since: Date) async throws -> Bool
    /// The user's open, matched sessions, newest report first; only `source`'s when given.
    func openSessions(userID: UserID, source: WatchSource?, limit: Int) async throws -> [OpenSession]
    /// A token belongs to one user: registering it again moves it.
    func registerLiveActivity(_ token: LiveActivityToken, userID: UserID, now: Date) async throws
    /// Whether the user has any Live Activity token: a user with none has no activity to keep.
    func hasLiveActivityTokens(userID: UserID) async throws -> Bool
    /// The user's push-to-start tokens, one per device.
    func liveActivityStartTokens(userID: UserID) async throws -> [LiveActivityToken]
    /// The tokens of the user's running activities, one per device.
    func liveActivityUpdateTokens(userID: UserID) async throws -> [LiveActivityToken]
    /// Apple said the token is dead (activity ended, app removed).
    func forgetLiveActivity(token: String) async throws
    /// The activities ended: their tokens will not answer again.
    func forgetLiveActivityUpdates(userID: UserID) async throws

    /// Saves what a connection plays now (SCR-009), replacing its last play of that kind. The
    /// same `ref` again keeps the row's id and start, so the activity hears no change.
    func savePlay(_ play: LivePlay, userID: UserID, agentTokenID: UUID) async throws
    /// The connection stopped playing that kind of thing.
    func removePlay(_ kind: LivePlay.Kind, userID: UserID, agentTokenID: UUID) async throws
    /// The user's plays that have not expired, newest report first. Expired ones are deleted.
    func livePlays(userID: UserID, now: Date) async throws -> [LivePlay]
    /// What the user's activity last showed; a fresh state when there is none yet.
    func liveActivityState(userID: UserID) async throws -> LiveActivityState
    /// Saves `state` if no one saved since it was read (its `version`). False when someone did.
    func saveLiveActivityState(_ state: LiveActivityState, userID: UserID) async throws -> Bool
    /// The sweep looks at the user again at `date`, unless it already will sooner.
    func scheduleLiveActivityCheck(userID: UserID, at date: Date) async throws
    /// Claims the users whose check is due, so one sweep alone looks at each.
    func claimDueLiveActivityChecks(now: Date, limit: Int) async throws -> [UserID]
}

/// An ActivityKit push token the app handed over (SCR-008).
struct LiveActivityToken: Sendable, Equatable {
    enum Kind: String, Sendable {
        /// Push-to-start: lets the server start the "Now playing" activity on this device.
        case start
        /// One running activity's own token, for updates and the end.
        case update
    }

    var token: String
    var kind: Kind
    var environment: PushEnvironment
    /// The app's bundle id; APNs gets `<topic>.push-type.liveactivity`.
    var topic: String
}

/// A matched session no `stop` has closed yet, with what Home and the Live Activity show (SCR-008).
struct OpenSession: Sendable, Equatable {
    enum State: String, Sendable {
        case playing, paused
    }

    var id: UUID
    var source: WatchSource
    var externalRef: String
    var titleID: TitleID
    /// Nil when the title is not in the user's library yet (a first episode, before its stop).
    var libraryItemID: LibraryItemID?
    var episode: EpisodeKey?
    var episodeName: String?
    /// The episode's runtime, else the title's: a duration before the player reports one.
    var runtimeMinutes: Int?
    var state: State
    /// Where the player was at its last report.
    var positionMs: Int64
    var durationMs: Int64
    /// When the player last reported. Stremio reports only on start, pause and stop.
    var updatedAt: Date

    /// The player's duration, else the catalog runtime; 0 when neither is known.
    var knownDurationMs: Int64 {
        durationMs > 0 ? durationMs : Int64(runtimeMinutes ?? 0) * 60000
    }

    /// The reported progress in percent, nil while no duration is known. Never extrapolated: a
    /// player closed mid-episode must not count as watched.
    var reportedProgress: Double? {
        durationMs > 0 ? min(100, Double(positionMs) / Double(durationMs) * 100) : nil
    }
}
