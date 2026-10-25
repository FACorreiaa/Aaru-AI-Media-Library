import Foundation

/// One day on Schedule's date strip, in the viewer's calendar and time zone.
struct SportDay: Hashable, Identifiable {
    /// The start of the local day.
    let date: Date
    /// "2026-10-24": the local day, as the schedule asks for it.
    let key: String
    /// Days from today: -3 … 7.
    let offset: Int
    let timeZone: TimeZone

    var id: String {
        key
    }

    var isToday: Bool {
        offset == 0
    }

    private var style: Date.FormatStyle {
        Date.FormatStyle(timeZone: timeZone)
    }

    /// "Today", else "Sat".
    var weekday: String {
        isToday ? "Today" : date.formatted(style.weekday(.abbreviated))
    }

    /// "24".
    var dayNumber: String {
        date.formatted(style.day())
    }

    /// "Today, Saturday 24 October", for VoiceOver.
    var spoken: String {
        let full = date.formatted(style.weekday(.wide).day().month(.wide))
        return isToday ? "Today, \(full)" : full
    }

    /// `back` days before today to `ahead` days after it, in `calendar`'s zone.
    static func strip(
        around now: Date, calendar: Calendar = .current, back: Int = 3, ahead: Int = 7
    ) -> [SportDay] {
        let today = calendar.startOfDay(for: now)
        return (-back ... ahead).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return SportDay(
                date: date, key: key(for: date, calendar: calendar), offset: offset, timeZone: calendar.timeZone
            )
        }
    }

    /// "2026-10-24": the day `date` falls on in `calendar`.
    static func key(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// The words on a score line: the live clock, the kick-off, the result.
enum SportLabels {
    /// "67′" for a minute ("45+2′" too), "HT" or "Q3" as given, "Live" when the provider sends none.
    static func clock(_ progress: String?) -> String {
        let text = (progress ?? "").trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return "Live" }
        let isMinute = text.allSatisfy { $0.isNumber || $0 == "+" } && text.first?.isNumber == true
        return isMinute ? "\(text)′" : text
    }

    /// The status column: the live clock, the local kick-off ("20:45"), Final, Postponed, Cancelled.
    static func status(
        _ status: SportEventStatus, progress: String?, startsAt: Date?, timeZone: TimeZone = .current
    ) -> String {
        switch status {
        case .live: clock(progress)
        case .finished: "Final"
        case .postponed: "Postponed"
        case .cancelled: "Cancelled"
        case .scheduled: startsAt.map { time($0, timeZone: timeZone) } ?? "TBA"
        }
    }

    /// "2 – 1", or nil until both sides have a score.
    static func score(home: Int?, away: Int?) -> String? {
        guard let home, let away else { return nil }
        return "\(home) – \(away)"
    }

    /// "20:45" or "8:45 PM", in the viewer's zone and locale.
    static func time(_ date: Date, timeZone: TimeZone = .current) -> String {
        date.formatted(Date.FormatStyle(timeZone: timeZone).hour().minute())
    }

    /// "Today", "Tomorrow", "Yesterday", else "Sat 25 Oct": the local day of `date`, or of the
    /// UTC `day` when the exact start is unknown.
    static func dayLabel(_ date: Date?, day: String, now: Date = .now, calendar: Calendar = .current) -> String {
        guard let date else {
            let style = Date.FormatStyle(timeZone: .gmt).weekday(.abbreviated).day().month(.abbreviated)
            return utcDay(day).map { $0.formatted(style) } ?? day
        }
        let today = calendar.startOfDay(for: now)
        let offset = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day
        switch offset {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        default:
            return date.formatted(
                Date.FormatStyle(timeZone: calendar.timeZone).weekday(.abbreviated).day().month(.abbreviated)
            )
        }
    }

    /// "Today, 20:45", "Sat 25 Oct, 20:45", or the day alone when the time is unknown.
    static func kickoff(_ date: Date?, day: String, now: Date = .now, calendar: Calendar = .current) -> String {
        let dayText = dayLabel(date, day: day, now: now, calendar: calendar)
        guard let date else { return dayText }
        return "\(dayText), \(time(date, timeZone: calendar.timeZone))"
    }

    private static func utcDay(_ day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }
}

extension SportEvent {
    /// A UFC or WWE card: a name and a poster, no home and away.
    var isCard: Bool {
        home == nil && away == nil
    }

    var scoreText: String? {
        SportLabels.score(home: home?.score, away: away?.score)
    }

    var statusText: String {
        SportLabels.status(status, progress: progress, startsAt: startsAt)
    }

    /// Live, or past its start and not yet marked live (for up to three hours), so the next
    /// refresh should bring its score.
    func isLiveOrDue(now: Date = .now) -> Bool {
        if status == .live {
            return true
        }
        guard status == .scheduled, let startsAt else { return false }
        return startsAt <= now && now.timeIntervalSince(startsAt) < 3 * 60 * 60
    }

    /// "Arsenal 2, Chelsea 1, 67′" or "UFC 310, Today, 03:00", for VoiceOver.
    var spoken: String {
        var parts: [String] = []
        if let home, let away {
            parts.append([home.name, home.score.map(String.init)].compactMap(\.self).joined(separator: " "))
            parts.append([away.name, away.score.map(String.init)].compactMap(\.self).joined(separator: " "))
        } else {
            parts.append(name)
        }
        switch status {
        case .live: parts.append("live, \(SportLabels.clock(progress))")
        case .scheduled: parts.append(SportLabels.kickoff(startsAt, day: day))
        default: parts.append(statusText)
        }
        if isFavorite {
            parts.append("a favorite")
        }
        return parts.joined(separator: ", ")
    }
}

/// When Sports fetches again: about four seconds after a response that is still `pending` (a
/// few times at most), every 90 seconds while something shown is live, otherwise not at all.
struct SportsRefresh {
    struct Snapshot: Equatable {
        var pending: Bool
        var live: Bool

        init(pending: Bool, live: Bool) {
            self.pending = pending
            self.live = live
        }

        init(_ favorites: SportFavorites, now: Date = .now) {
            pending = favorites.items.contains(where: \.pending)
            live = favorites.items.contains { item in
                !item.live.isEmpty || item.next?.isLiveOrDue(now: now) == true
            }
        }

        init(_ schedule: SportSchedule, now: Date = .now) {
            pending = schedule.pending
            live = schedule.groups.contains { $0.events.contains { $0.isLiveOrDue(now: now) } }
        }
    }

    static let pendingDelay: Duration = .seconds(4)
    static let liveDelay: Duration = .seconds(90)
    static let pendingRetries = 4

    private(set) var pendingTries = 0
    private var lastLive = false

    /// The wait before the next fetch, or nil to stop. A failed fetch (nil) keeps the last
    /// known live state, so a blip does not end the refresh during a match.
    mutating func next(after snapshot: Snapshot?) -> Duration? {
        let live = snapshot?.live ?? lastLive
        lastLive = live
        if snapshot?.pending == true, pendingTries < Self.pendingRetries {
            pendingTries += 1
            return Self.pendingDelay
        }
        if snapshot?.pending == false {
            pendingTries = 0
        }
        return live ? Self.liveDelay : nil
    }
}

/// "Where to watch" countries: ISO 3166-1 alpha-2 codes, named in the viewer's language.
enum WatchCountry {
    static func name(_ code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }

    /// The device's region, offered first; never saved until picked.
    static var suggested: String? {
        guard let code = Locale.current.region?.identifier, isCountryCode(code) else { return nil }
        return code
    }

    /// Every country code the system knows, by name.
    static let all: [String] = Locale.Region.isoRegions
        .map(\.identifier)
        .filter(isCountryCode)
        .sorted { name($0).localizedStandardCompare(name($1)) == .orderedAscending }

    private static func isCountryCode(_ code: String) -> Bool {
        code.count == 2 && code.allSatisfy { $0.isASCII && $0.isUppercase }
    }
}
