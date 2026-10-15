import Foundation
import Observation

/// APP-010: seven days of the user's own airing episodes, stepped a day at a time. Episodes and
/// ticks live in the shared `CalendarFeed`.
@MainActor
@Observable
final class WeekModel {
    /// The first of the seven visible days, at the start of that local day.
    private(set) var start: Date
    let feed: CalendarFeed

    var calendar: Calendar {
        feed.calendar
    }

    init(feed: CalendarFeed, today: Date = .now) {
        self.feed = feed
        start = Self.weekStart(of: today, in: feed.calendar)
    }

    /// For previews: a fixed week with entries already in place.
    convenience init(preview entries: [CalendarEntry], start: Date, calendar: Calendar = .aaru) {
        self.init(feed: CalendarFeed(preview: entries, calendar: calendar), today: start)
    }

    // MARK: Days

    var days: [Date] {
        (0 ..< 7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }

    var containsToday: Bool {
        days.contains(where: isToday)
    }

    func entries(on date: Date) -> [CalendarEntry] {
        feed.entries(on: date)
    }

    var pending: Set<String> {
        feed.pending
    }

    var hasLoaded: Bool {
        feed.hasLoaded
    }

    var isLoading: Bool {
        feed.isLoading
    }

    var isEmptyWeek: Bool {
        hasLoaded && days.allSatisfy { entries(on: $0).isEmpty }
    }

    func toggle(_ entry: CalendarEntry) async {
        await feed.toggle(entry)
    }

    // MARK: Stepping

    func step(days delta: Int) async {
        guard let moved = calendar.date(byAdding: .day, value: delta, to: start) else { return }
        start = moved
        await loadIfNeeded()
    }

    func goToToday() async {
        start = Self.weekStart(of: .now, in: calendar)
        await loadIfNeeded()
    }

    /// Moves the window by whole days so `date` is visible; used by the iPhone day pager.
    func reveal(_ date: Date) async {
        let first = calendar.startOfDay(for: date)
        guard let last = days.last else { return }
        if first < start {
            start = first
        } else if first > last, let shifted = calendar.date(byAdding: .day, value: -6, to: first) {
            start = shifted
        } else {
            return
        }
        await loadIfNeeded()
    }

    // MARK: Loading

    func load() async {
        guard let window else { return }
        await feed.fetch(window)
    }

    /// Fetches only when the visible days (plus a day each side, for date-only air dates near
    /// midnight) are not already loaded.
    func loadIfNeeded() async {
        guard let window,
              let from = calendar.date(byAdding: .day, value: -1, to: start),
              let until = calendar.date(byAdding: .day, value: 8, to: start)
        else { return }
        await feed.ensure(from ..< until, fetching: window)
    }

    /// A week either side of the visible one, so stepping a day rarely refetches.
    private var window: Range<Date>? {
        guard let from = calendar.date(byAdding: .day, value: -7, to: start),
              let until = calendar.date(byAdding: .day, value: 14, to: start)
        else { return nil }
        return from ..< until
    }

    static func weekStart(of date: Date, in calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }
}
