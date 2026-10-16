import Foundation

/// What the widgets render (WID-001): written by the app into the App Group after every Home load
/// and every tick, read by the widget extension. Widgets hold no library state of their own.
/// Plain values only, so the snapshot never depends on the API's generated types.
struct WidgetSnapshot: Codable, Sendable, Equatable {
    /// Continue watching: an in-progress show's next episode.
    struct NextEpisode: Codable, Sendable, Equatable, Identifiable {
        var libraryItemId: String
        var title: String
        var season: Int
        var number: Int
        var episodeName: String?
        var runtimeMinutes: Int?
        var remainingCount: Int
        var remainingMinutes: Int
        var isFinale: Bool
        var posterURL: URL?
        var backdropURL: URL?

        var id: String {
            libraryItemId
        }
    }

    /// One airing episode of a tracked show (CAL-001).
    struct Airing: Codable, Sendable, Equatable, Identifiable {
        var libraryItemId: String
        var title: String
        var season: Int
        var number: Int
        var episodeName: String?
        var airsAt: Date
        /// False: `airsAt` is midnight UTC of a date-only air date. Show the day, never a time.
        var airTimeKnown: Bool
        var network: String?
        var kind: AiringKind
        var watched: Bool

        var id: String {
            "\(libraryItemId)-\(season)-\(number)"
        }

        var episodeCode: String {
            String(format: "S%02dE%02d", season, number)
        }

        /// The day it airs: an exact time on the viewer's calendar, a date-only air date in UTC
        /// (the Calendar screen's rule).
        func day(in calendar: Calendar) -> DayKey {
            DayKey((airTimeKnown ? calendar : WidgetSnapshot.utc).dateComponents([.year, .month, .day], from: airsAt))
        }
    }

    /// A calendar day independent of time zone.
    struct DayKey: Hashable, Comparable, Sendable {
        let year: Int
        let month: Int
        let day: Int

        init(_ components: DateComponents) {
            year = components.year ?? 0
            month = components.month ?? 0
            day = components.day ?? 0
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
        }
    }

    var upNext: [NextEpisode]
    /// From the Monday of this week to two weeks out, in air order.
    var airings: [Airing]
    var writtenAt: Date

    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    /// The viewer's calendar with Monday-first weeks, like the Calendar screen.
    static var weekCalendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    /// Unwatched episodes still to come at `now`, earliest first. An exact time counts until it
    /// airs; a date-only episode counts for its whole day.
    func upcoming(at now: Date, calendar: Calendar = WidgetSnapshot.weekCalendar) -> [Airing] {
        let today = DayKey(calendar.dateComponents([.year, .month, .day], from: now))
        return airings.filter { airing in
            guard !airing.watched else { return false }
            return airing.airTimeKnown ? airing.airsAt > now : airing.day(in: calendar) >= today
        }
    }
}

/// CAL-001's episode kind, for badges and colours.
enum AiringKind: String, Codable, Sendable {
    case premiere, finale, regular
}

/// The snapshot file in the App Group container. Missing or unreadable means "not set up yet".
enum WidgetSnapshotStore {
    private static var url: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)?
            .appendingPathComponent("widget-snapshot.json")
    }

    static func load() -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let url else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Sign-out: widgets must not keep showing the last user's shows.
    static func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// A tick made elsewhere, applied wherever the episode appears so widgets agree with the app
    /// before the next full write.
    static func setWatched(libraryItemId: String, season: Int, number: Int, watched: Bool) {
        guard var snapshot = load() else { return }
        for index in snapshot.airings.indices {
            let airing = snapshot.airings[index]
            if airing.libraryItemId == libraryItemId, airing.season == season, airing.number == number {
                snapshot.airings[index].watched = watched
            }
        }
        save(snapshot)
    }

    /// The Up Next widget's optimistic step: the row moves to the next episode in the season, or
    /// drops out when that was the last one left. Returns the snapshot before, to restore.
    @discardableResult
    static func advance(libraryItemId: String) -> WidgetSnapshot? {
        guard let before = load(),
              let index = before.upNext.firstIndex(where: { $0.libraryItemId == libraryItemId })
        else { return nil }
        var snapshot = before
        var row = snapshot.upNext[index]
        if row.remainingCount <= 1 {
            snapshot.upNext.remove(at: index)
        } else {
            row.remainingMinutes = max(0, row.remainingMinutes - (row.runtimeMinutes ?? 0))
            row.remainingCount -= 1
            row.number += 1
            row.episodeName = nil
            row.isFinale = false
            snapshot.upNext[index] = row
        }
        save(snapshot)
        return before
    }
}

/// Deep links from widgets into the app: `aaru://title/{libraryItemId}`.
enum WidgetLink {
    static let scheme = "aaru"

    static func title(_ libraryItemId: String) -> URL? {
        URL(string: "\(scheme)://title/\(libraryItemId)")
    }

    /// The library item id in a title link, or nil for any other URL.
    static func libraryItemId(in url: URL) -> String? {
        guard url.scheme == scheme, url.host() == "title",
              let id = url.pathComponents.dropFirst().first, !id.isEmpty
        else { return nil }
        return id
    }
}
