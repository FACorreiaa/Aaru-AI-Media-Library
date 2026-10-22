import Foundation

/// The "Now watching" Live Activity's fixed part (WID-005, SCR-008). The app starts it by hand or
/// when it sees a scrobble; the server starts it by push (`attributes-type: NowWatchingAttributes`).
/// Both encode this one type, so the keys never drift. The app adds `ActivityAttributes`.
public struct NowWatchingAttributes: Codable, Hashable, Sendable {
    public var libraryItemId: String
    public var title: String
    public var season: Int
    public var episode: Int
    public var episodeName: String?
    public var posterURL: String?
    public var runtimeMinutes: Int
    /// The scrobble session this activity follows; nil for one started by hand. The app uploads
    /// the activity's push token with it, so the server can update and end it.
    public var watchEventId: UUID?

    public init(
        libraryItemId: String, title: String, season: Int, episode: Int, episodeName: String? = nil,
        posterURL: String? = nil, runtimeMinutes: Int, watchEventId: UUID? = nil
    ) {
        self.libraryItemId = libraryItemId
        self.title = title
        self.season = season
        self.episode = episode
        self.episodeName = episodeName
        self.posterURL = posterURL
        self.runtimeMinutes = runtimeMinutes
        self.watchEventId = watchEventId
    }

    /// "S1 · E8 · Lanterns".
    public var episodeLine: String {
        ["S\(season) · E\(episode)", episodeName].compactMap(\.self).joined(separator: " · ")
    }

    public func matches(libraryItemId: String, season: Int, episode: Int) -> Bool {
        self.libraryItemId == libraryItemId && self.season == season && self.episode == episode
    }
}

/// The Live Activity's changing part. Dates encode as Foundation's default (seconds since 2001),
/// which is what ActivityKit decodes from a push.
public struct NowWatchingContent: Codable, Hashable, Sendable {
    public var startedAt: Date
    public var endsAt: Date
    /// "Ends at 1:20 PM" instead of "41m left"; tapping the label flips it (Trakt's behaviour).
    public var showsEndTime: Bool
    /// Set just before the activity ends, so its last frame says so.
    public var watched: Bool
    /// Set while the player is paused: progress stands still at this moment.
    public var pausedAt: Date?

    public init(startedAt: Date, endsAt: Date, showsEndTime: Bool, watched: Bool, pausedAt: Date? = nil) {
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.showsEndTime = showsEndTime
        self.watched = watched
        self.pausedAt = pausedAt
    }
}
