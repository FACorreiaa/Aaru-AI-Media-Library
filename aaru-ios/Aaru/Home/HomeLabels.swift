import Foundation

// MARK: Labels

extension HomeModel {
    /// "Dropped", or "Paused 6 weeks" for a show left alone since `since`.
    func unfinishedLabel(_ entry: UnfinishedEntry) -> String {
        switch entry.reason {
        case .dropped: return "Dropped"
        case .stalled:
            let days = calendar.dateComponents([.day], from: entry.since, to: now()).day ?? 0
            let weeks = max(1, days / 7)
            return weeks == 1 ? "Paused 1 week" : "Paused \(weeks) weeks"
        }
    }

    /// "Today · New", "In 3 hours", "Tomorrow", "In 2 days". Hours only for exact air times.
    func airingLabel(_ entry: CalendarEntry) -> String {
        Self.airingLabel(airsAt: entry.airsAt, airTimeKnown: entry.airTimeKnown, now: now(), calendar: calendar)
    }

    /// The same words for any airing, such as a list row's next episode (LST-003).
    nonisolated static func airingLabel(airsAt: Date, airTimeKnown: Bool, now current: Date, calendar: Calendar)
        -> String
    {
        if airTimeKnown, airsAt > current {
            let minutes = Int(airsAt.timeIntervalSince(current) / 60)
            if minutes < 60 {
                return "In \(max(1, minutes)) min"
            }
            if minutes < 12 * 60 {
                let hours = minutes / 60
                return hours == 1 ? "In 1 hour" : "In \(hours) hours"
            }
        }
        let today = calendar.startOfDay(for: current)
        // A date-only air date is midnight UTC of that date, so it is read in UTC.
        let reader = airTimeKnown ? calendar : CalendarFeed.utcCalendar
        let day = reader.dateComponents([.year, .month, .day], from: airsAt)
        guard let airDate = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day))
        else { return "" }
        let days = calendar.dateComponents([.day], from: today, to: airDate).day ?? 0
        switch days {
        case ..<1: return "Today · New"
        case 1: return "Tomorrow"
        default: return "In \(days) days"
        }
    }
}

/// "57m", "1h", "8h 40m".
func durationLabel(minutes: Int) -> String {
    let hours = minutes / 60
    let rest = minutes % 60
    switch (hours, rest) {
    case (0, _): return "\(rest)m"
    case (_, 0): return "\(hours)h"
    default: return "\(hours)h \(rest)m"
    }
}
