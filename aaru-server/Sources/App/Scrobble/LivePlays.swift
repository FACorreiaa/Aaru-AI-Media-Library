import AaruCore
import Foundation

/// Something a player reports that is not a Title (SCR-009): a scrobbler's `playing_now` track, or
/// a YouTube video the browser extension reads. It lives only while it plays: never a listen or a
/// watch event, and it never ticks anything.
struct LivePlay: Sendable, Equatable {
    enum Kind: String, Sendable {
        case track, video
    }

    enum Source: String, Sendable {
        case listenbrainz, youtube
    }

    /// New for each thing played; kept while the same `ref` plays on.
    var id: UUID
    var kind: Kind
    var source: Source
    /// The recording's MBID or artist + track key; the video id.
    var ref: String
    var title: String
    /// The artist, or the channel.
    var subtitle: String?
    /// "YouTube Music", "Web Scrobbler", "YouTube".
    var service: String?
    var artworkURL: String?
    var originURL: String?
    var state: OpenSession.State
    /// Where the player was at `updatedAt`. A track's `playing_now` says only that it began.
    var positionMs: Int64
    /// 0 when unknown.
    var durationMs: Int64
    var startedAt: Date
    var updatedAt: Date
    var expiresAt: Date

    /// Past its end by this, a track stops counting: the scrobbler sends no stop.
    static let trackGrace: TimeInterval = 2 * 60
    /// A track with no length counts this long.
    static let unknownTrackLimit: TimeInterval = 10 * 60
    /// A playing video counts this long past its last report, at most: the extension reports every
    /// few seconds, so a closed tab is gone soon after.
    static let videoHeartbeat: TimeInterval = 5 * 60
    static let videoGrace: TimeInterval = 2 * 60
    /// A paused video counts this long, as a paused episode does.
    static let pausedLimit: TimeInterval = NowPlaying.pausedLimit
    /// Text the activity shows is cut to this: the whole push must stay under 4 KB.
    static let maxText = 80

    /// A scrobbler's `playing_now`.
    static func track(_ listen: NewListen, now: Date) -> LivePlay {
        let duration = Int64(max(0, listen.durationMs ?? 0))
        let lasts = duration > 0 ? TimeInterval(duration) / 1000 + trackGrace : unknownTrackLimit
        let artwork = listen.releaseGroupMBID.map { "https://coverartarchive.org/release-group/\($0)/front-250" }
            ?? listen.releaseMBID.map { "https://coverartarchive.org/release/\($0)/front-250" }
        return LivePlay(
            id: UUID(), kind: .track, source: .listenbrainz, ref: listen.recordingMBID ?? listen.trackKey,
            title: cut(listen.track), subtitle: cut(listen.artist), service: listen.musicService ?? listen.client,
            artworkURL: artwork, originURL: listen.originURL, state: .playing, positionMs: 0,
            durationMs: duration, startedAt: now, updatedAt: now, expiresAt: now.addingTimeInterval(lasts)
        )
    }

    /// What the browser extension reports about a YouTube video.
    struct VideoReport: Sendable {
        var id: String
        var title: String
        var channel: String?
        var state: OpenSession.State
        var positionMs: Int64
        var durationMs: Int64
    }

    /// A YouTube video the extension reports playing or paused.
    static func video(_ report: VideoReport, now: Date) -> LivePlay {
        let left = TimeInterval(max(0, report.durationMs - report.positionMs)) / 1000
        let lasts = report.state == .paused ? pausedLimit : min(left, videoHeartbeat) + videoGrace
        return LivePlay(
            id: UUID(), kind: .video, source: .youtube, ref: report.id, title: cut(report.title),
            subtitle: report.channel.map(cut), service: "YouTube",
            artworkURL: "https://i.ytimg.com/vi/\(report.id)/mqdefault.jpg",
            originURL: "https://www.youtube.com/watch?v=\(report.id)", state: report.state,
            positionMs: report.positionMs, durationMs: report.durationMs, startedAt: now, updatedAt: now,
            expiresAt: now.addingTimeInterval(lasts)
        )
    }

    static func cut(_ text: String) -> String {
        String(text.prefix(maxText))
    }
}

/// What the user's "Now playing" activity last showed (SCR-009), so a report pushes only when that
/// changes. `version` guards against two reports saving at once.
struct LiveActivityState: Sendable, Equatable {
    /// A row that just ticked, kept on the activity a moment to read "Watched".
    struct Lingering: Codable, Sendable, Equatable {
        var item: NowPlayingActivityItem
        var until: Date
    }

    /// Nil while no activity runs.
    var pushed: NowPlayingActivityState?
    var lingering: [Lingering]
    var version: Int
    var nextCheckAt: Date?

    static let fresh = LiveActivityState(pushed: nil, lingering: [], version: 0, nextCheckAt: nil)
}

/// One thing playing now: a library episode or movie a player reports, or a play.
enum LiveEntry: Sendable {
    case session(OpenSession, Title)
    case play(LivePlay)

    var updatedAt: Date {
        switch self {
        case let .session(session, _): session.updatedAt
        case let .play(play): play.updatedAt
        }
    }

    /// When it stops counting unless a player reports again.
    var liveUntil: Date {
        switch self {
        case let .session(session, _): NowPlaying.liveUntil(session)
        case let .play(play): play.expiresAt
        }
    }

    /// The activity's row for it.
    var activityItem: NowPlayingActivityItem {
        switch self {
        case let .session(session, title):
            let startedAt = session.updatedAt.addingTimeInterval(-TimeInterval(session.positionMs) / 1000)
            let duration = session.knownDurationMs
            return NowPlayingActivityItem(
                id: session.id.uuidString.lowercased(), kind: title.type == .movie ? .movie : .episode,
                title: LivePlay.cut(title.title), subtitle: Self.episodeLine(session).map(LivePlay.cut),
                service: session.source.label, startedAt: startedAt,
                endsAt: duration > 0 ? startedAt.addingTimeInterval(TimeInterval(duration) / 1000) : nil,
                pausedAt: session.state == .paused ? session.updatedAt : nil,
                libraryItemId: session.libraryItemID?.description, season: session.episode?.season,
                episode: session.episode?.episode, artworkURL: title.posterURL?.absoluteString
            )
        case let .play(play):
            let startedAt = play.kind == .track
                ? play.startedAt : play.updatedAt.addingTimeInterval(-TimeInterval(play.positionMs) / 1000)
            return NowPlayingActivityItem(
                id: play.id.uuidString.lowercased(), kind: play.kind == .track ? .track : .video,
                title: play.title, subtitle: play.subtitle, service: play.service, startedAt: startedAt,
                endsAt: play.durationMs > 0 ? startedAt.addingTimeInterval(TimeInterval(play.durationMs) / 1000) : nil,
                pausedAt: play.state == .paused ? play.updatedAt : nil, artworkURL: play.artworkURL
            )
        }
    }

    /// "S1 · E8 · Lanterns".
    static func episodeLine(_ session: OpenSession) -> String? {
        let number = session.episode.map { "S\($0.season) · E\($0.episode)" }
        let parts = [number, session.episodeName].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Everything playing for a user now (SCR-009), in the activity's order.
enum LiveSet {
    /// Library episodes, movies and videos first, newest first, then tracks; at most
    /// `NowPlayingActivityState.maxItems`. A session must be believable (`NowPlaying.isLive`) and
    /// in the library. A track a scrobbler heard on a video already shown is that video again.
    static func compute(sessions: [(OpenSession, Title)], plays: [LivePlay], now: Date) -> [LiveEntry] {
        let watching = sessions.filter { NowPlaying.isLive($0.0, now: now) && $0.0.libraryItemID != nil }
            .map { LiveEntry.session($0.0, $0.1) }
        let live = plays.filter { $0.expiresAt > now }
        let videos = live.filter { $0.kind == .video }
        let tracks = live.filter { play in
            play.kind == .track && !videos.contains { video in play.originURL?.contains(video.ref) == true }
        }
        let first = (watching + videos.map(LiveEntry.play)).sorted { $0.updatedAt > $1.updatedAt }
        let rest = tracks.sorted { $0.updatedAt > $1.updatedAt }.map(LiveEntry.play)
        return Array((first + rest).prefix(NowPlayingActivityState.maxItems))
    }

    /// Reads and computes the set for `userID`.
    static func load(_ stores: Stores, userID: UserID, now: Date) async throws -> [LiveEntry] {
        let open = try await stores.watchEvents.openSessions(userID: userID, source: nil, limit: 10)
        var sessions: [(OpenSession, Title)] = []
        for session in open where session.libraryItemID != nil && NowPlaying.isLive(session, now: now) {
            if let title = try await stores.titles.title(id: session.titleID) {
                sessions.append((session, title))
            }
        }
        let plays = try await stores.watchEvents.livePlays(userID: userID, now: now)
        return compute(sessions: sessions, plays: plays, now: now)
    }
}

extension WatchSource {
    /// How a person names the player.
    var label: String {
        switch self {
        case .stremio: "Stremio"
        case .netflix: "Netflix"
        case .disneyPlus: "Disney+"
        case .primeVideo: "Prime Video"
        }
    }
}

extension ScrobbleService {
    /// A connection plays `play` (SCR-009): a track's `playing_now`, or a video's report.
    func play(_ play: LivePlay, from caller: AgentCaller) async throws {
        Metrics.shared.increment(.scrobbles, ["source": play.source.rawValue, "action": play.state.rawValue])
        try await stores.watchEvents.savePlay(play, userID: caller.userID, agentTokenID: caller.token.id)
        await liveActivity?.sync(userID: caller.userID, now: now())
    }

    /// The connection stopped its `kind` of play: a video's `stop`.
    func stopPlay(_ kind: LivePlay.Kind, from caller: AgentCaller) async throws {
        try await stores.watchEvents.removePlay(kind, userID: caller.userID, agentTokenID: caller.token.id)
        await liveActivity?.sync(userID: caller.userID, now: now())
    }

    /// Everything playing for the user now, in the activity's order.
    func playingNow(userID: UserID) async throws -> [LiveEntry] {
        try await LiveSet.load(stores, userID: userID, now: now())
    }
}
