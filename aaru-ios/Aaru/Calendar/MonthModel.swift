import Foundation
import Observation

/// The month calendar (DESIGN.md §7, Stremio's layout): the Monday-start weeks covering one month,
/// a selected day, and an agenda from that day on. Episodes and ticks live in `CalendarFeed`.
@MainActor
@Observable
final class MonthModel {
    /// The first day of the visible month, at the start of that local day.
    private(set) var month: Date
    /// The day the agenda starts from.
    var selection: Date
    let feed: CalendarFeed

    var calendar: Calendar {
        feed.calendar
    }

    init(feed: CalendarFeed, today: Date = .now) {
        self.feed = feed
        month = Self.monthStart(of: today, in: feed.calendar)
        selection = feed.calendar.startOfDay(for: today)
    }

    /// For previews: a fixed month with entries already in place.
    convenience init(preview entries: [CalendarEntry], today: Date = .now, calendar: Calendar = .aaru) {
        self.init(feed: CalendarFeed(preview: entries, calendar: calendar), today: today)
    }

    // MARK: Grid

    /// Monday before (or on) the 1st through the Sunday after (or on) the last day: 4 to 6 weeks.
    var gridDays: [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end),
              let gridEnd = calendar.date(byAdding: .day, value: 7, to: WeekModel.weekStart(of: lastDay, in: calendar))
        else { return [] }
        let gridStart = WeekModel.weekStart(of: interval.start, in: calendar)
        let count = calendar.dateComponents([.day], from: gridStart, to: gridEnd).day ?? 35
        return (0 ..< count).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    /// "MON" … "SUN", following the calendar's first weekday.
    var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    func isInMonth(_ day: Date) -> Bool {
        calendar.isDate(day, equalTo: month, toGranularity: .month)
    }

    func isPast(_ day: Date) -> Bool {
        day < calendar.startOfDay(for: .now)
    }

    func isToday(_ day: Date) -> Bool {
        calendar.isDateInToday(day)
    }

    func isSelected(_ day: Date) -> Bool {
        calendar.isDate(day, inSameDayAs: selection)
    }

    var showsToday: Bool {
        isInMonth(.now) && isToday(selection)
    }

    func entries(on day: Date) -> [CalendarEntry] {
        feed.entries(on: day)
    }

    /// The selected day and every later day of the grid that has an episode.
    var agenda: [(day: Date, entries: [CalendarEntry])] {
        let from = calendar.startOfDay(for: selection)
        return gridDays.filter { $0 >= from }.compactMap { day in
            let entries = entries(on: day)
            return entries.isEmpty ? nil : (day, entries)
        }
    }

    /// This month's grid has loaded (not just some other window's).
    var isLoaded: Bool {
        window.map(feed.covers) ?? false
    }

    /// This month has not loaded and its load failed.
    var loadProblem: String? {
        window.flatMap(feed.loadProblem(for:))
    }

    var isEmptyMonth: Bool {
        isLoaded && feed.pendingShows == 0 && gridDays.filter(isInMonth).allSatisfy { entries(on: $0).isEmpty }
    }

    /// "October", or "October 2027" outside the current year. `offset` names a neighbour.
    func title(offset: Int = 0) -> String {
        let date = calendar.date(byAdding: .month, value: offset, to: month) ?? month
        let sameYear = calendar.isDate(date, equalTo: .now, toGranularity: .year)
        return date.formatted(sameYear ? .dateTime.month(.wide) : .dateTime.month(.wide).year())
    }

    // MARK: Stepping

    func select(_ day: Date) {
        selection = calendar.startOfDay(for: day)
    }

    func step(months delta: Int) async {
        guard let moved = calendar.date(byAdding: .month, value: delta, to: month) else { return }
        month = moved
        selection = isInMonth(.now) ? calendar.startOfDay(for: .now) : moved
        await loadIfNeeded()
    }

    func goToToday() async {
        month = Self.monthStart(of: .now, in: calendar)
        selection = calendar.startOfDay(for: .now)
        await loadIfNeeded()
    }

    // MARK: Loading

    func load() async {
        guard let window else { return }
        await feed.fetch(window)
    }

    func loadIfNeeded() async {
        guard let window else { return }
        await feed.ensure(window, fetching: window)
    }

    /// The grid's days, widened so a date-only episode (midnight UTC of its date) on either edge
    /// is inside whatever the viewer's offset from UTC. The feed splits anything over 42 days.
    private var window: Range<Date>? {
        let days = gridDays
        guard let first = days.first, let last = days.last,
              let end = calendar.date(byAdding: .day, value: 1, to: last)
        else { return nil }
        let utc = CalendarFeed.utcCalendar
        let utcFirst = utc.date(from: calendar.dateComponents([.year, .month, .day], from: first)) ?? first
        let utcEnd = utc.date(from: calendar.dateComponents([.year, .month, .day], from: end)) ?? end
        return min(first, utcFirst) ..< max(end, utcEnd)
    }

    static func monthStart(of date: Date, in calendar: Calendar) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }
}
