import AaruCore
import Foundation

/// What a player is playing for the user right now (SCR-008): the newest open session that is
/// still believable. Nothing is swept: a session a player never stopped simply stops counting.
struct NowPlaying: Sendable, Equatable {
    var session: OpenSession
    var title: Title

    /// A playing session lasts until its end plus this, since the player may report late.
    static let playingGrace: TimeInterval = 10 * 60
    /// A playing session with no known duration lasts this long from its last report.
    static let unknownDurationLimit: TimeInterval = 3 * 60 * 60
    /// A paused session lasts this long from the pause.
    static let pausedLimit: TimeInterval = 30 * 60

    /// When `session` stops counting. Stremio sends no heartbeat, so a playing session is assumed
    /// to keep playing from its last report.
    static func liveUntil(_ session: OpenSession) -> Date {
        switch session.state {
        case .paused:
            return session.updatedAt.addingTimeInterval(pausedLimit)
        case .playing:
            let duration = session.knownDurationMs
            guard duration > 0 else { return session.updatedAt.addingTimeInterval(unknownDurationLimit) }
            let left = TimeInterval(max(0, duration - session.positionMs)) / 1000
            return session.updatedAt.addingTimeInterval(left + playingGrace)
        }
    }

    /// Whether `session` still counts at `now`.
    static func isLive(_ session: OpenSession, now: Date) -> Bool {
        now <= liveUntil(session)
    }

    /// The first live session of `sessions` (newest first).
    static func pick(_ sessions: [OpenSession], now: Date) -> OpenSession? {
        sessions.first { isLive($0, now: now) }
    }
}
