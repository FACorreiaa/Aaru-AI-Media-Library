import Foundation

/// The "Now playing" Live Activity's fixed part (SCR-009): one activity per device shows
/// everything that plays at once, so nothing about one item is fixed. The server starts it by push
/// (`attributes-type: NowPlayingActivityAttributes`); the app adds `ActivityAttributes`.
public struct NowPlayingActivityAttributes: Codable, Hashable, Sendable {
    public init() {}
}

/// The activity's changing part: what plays now, primary first. Dates encode as Foundation's
/// default (seconds since 2001), which is what ActivityKit decodes from a push.
public struct NowPlayingActivityState: Codable, Hashable, Sendable {
    /// At most `maxItems`: catalog episodes, movies and videos first, newest first, then tracks.
    public var items: [NowPlayingActivityItem]
    /// "Ends at 1:20 PM" instead of "41m left"; tapping the label flips it.
    public var showsEndTime: Bool

    public static let maxItems = 3

    public init(items: [NowPlayingActivityItem], showsEndTime: Bool = false) {
        self.items = items
        self.showsEndTime = showsEndTime
    }
}

/// One row of the activity: a library episode or movie, a track, or a video.
public struct NowPlayingActivityItem: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case episode, movie, track, video
    }

    /// The watch event or the play: stable while the same thing plays, new for the next one.
    public var id: String
    public var kind: Kind
    /// The show, film, track or video name.
    public var title: String
    /// "S1 · E8 · Lanterns", the artist, or the channel.
    public var subtitle: String?
    /// Where it plays: "Stremio", "Netflix", "YouTube Music".
    public var service: String?
    /// When playback would have started had it run without a break: progress is `now - startedAt`.
    public var startedAt: Date
    /// Nil when the player gives no duration.
    public var endsAt: Date?
    /// Set while paused: progress stands still at this moment.
    public var pausedAt: Date?
    /// Set when the episode or movie just ticked: the row reads "Watched" before it leaves.
    public var watched: Bool
    /// Episodes and movies only: what Mark watched and a tap open.
    public var libraryItemId: String?
    public var season: Int?
    public var episode: Int?
    /// The poster, cover or thumbnail. The widget shows it only once the app has saved it.
    public var artworkURL: String?

    public init(
        id: String, kind: Kind, title: String, subtitle: String? = nil, service: String? = nil,
        startedAt: Date, endsAt: Date? = nil, pausedAt: Date? = nil, watched: Bool = false,
        libraryItemId: String? = nil, season: Int? = nil, episode: Int? = nil, artworkURL: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.service = service
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.pausedAt = pausedAt
        self.watched = watched
        self.libraryItemId = libraryItemId
        self.season = season
        self.episode = episode
        self.artworkURL = artworkURL
    }
}
