import AaruAPI
import Foundation
import Observation

typealias CalendarEntry = Components.Schemas.CalendarEntry

/// One calendar day, independent of time zone: the key the grid groups episodes by.
struct WeekDay: Hashable, Comparable {
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

extension CalendarEntry {
    /// Stable per episode: one library item airs each episode once.
    var cellID: String {
        "\(libraryItemId)-\(season)-\(number)"
    }

    /// The day the episode airs. A date-only air date is midnight UTC of that date, so it is
    /// read in UTC; an exact time is read on the viewer's own calendar.
    func day(in calendar: Calendar) -> WeekDay {
        let reader = airTimeKnown ? calendar : WeekModel.utcCalendar
        return WeekDay(reader.dateComponents([.year, .month, .day], from: airsAt))
    }
}

/// APP-010: seven days of the user's own airing episodes (CAL-001), stepped a day at a time, with
/// a tick per episode that writes the same route as title detail.
@MainActor
@Observable
final class WeekModel {
    /// The first of the seven visible days, at the start of that local day.
    private(set) var start: Date
    private(set) var entries: [CalendarEntry] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var pending: Set<String> = []
    /// The last load or tick that failed. Shown until the next action.
    var problem: String?

    @ObservationIgnored private let api: Client?
    @ObservationIgnored private let library: LibraryModel?
    @ObservationIgnored let calendar: Calendar
    /// The UTC window `entries` covers. Wider than the seven days, so stepping a day rarely
    /// refetches and date-only episodes near midnight are never cut off.
    @ObservationIgnored private var loaded: Range<Date>?

    nonisolated static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    init(api: Client?, library: LibraryModel?, calendar: Calendar = .current, today: Date = .now) {
        self.api = api
        self.library = library
        self.calendar = calendar
        start = Self.weekStart(of: today, in: calendar)
    }

    /// For previews: a fixed week with entries already in place.
    convenience init(preview entries: [CalendarEntry], start: Date, calendar: Calendar = .current) {
        self.init(api: nil, library: nil, calendar: calendar, today: start)
        self.entries = entries
        hasLoaded = true
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

    /// The episodes of one visible day: date-only ones first (they have no time), then by time.
    func entries(on date: Date) -> [CalendarEntry] {
        let key = WeekDay(calendar.dateComponents([.year, .month, .day], from: date))
        return entries.filter { $0.day(in: calendar) == key }.sorted { lhs, rhs in
            if lhs.airTimeKnown != rhs.airTimeKnown {
                return !lhs.airTimeKnown
            }
            return (lhs.airsAt, lhs.title.title, lhs.season, lhs.number)
                < (rhs.airsAt, rhs.title.title, rhs.season, rhs.number)
        }
    }

    var isEmptyWeek: Bool {
        hasLoaded && days.allSatisfy { entries(on: $0).isEmpty }
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
        await fetch(around: start)
    }

    private func loadIfNeeded() async {
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return }
        let margin: TimeInterval = 86400
        if let loaded, loaded.lowerBound <= start.addingTimeInterval(-margin),
           loaded.upperBound >= end.addingTimeInterval(margin)
        {
            return
        }
        await fetch(around: start)
    }

    /// One call for a week either side of the visible one: 21 days, inside CAL-001's 35-day cap.
    private func fetch(around start: Date) async {
        guard let api,
              let from = calendar.date(byAdding: .day, value: -7, to: start),
              let until = calendar.date(byAdding: .day, value: 14, to: start)
        else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            switch try await api.getCalendar(query: .init(from: from, to: until)) {
            case let .ok(response):
                entries = try response.body.json.items
                loaded = from ..< until
                hasLoaded = true
                problem = nil
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "The week could not be loaded."
            }
        } catch {
            problem = hasLoaded
                ? "Offline. Showing the week from the last load."
                : "Aaru could not reach the server."
        }
    }

    // MARK: Ticking

    /// Optimistic, like title detail: the tick moves now and rolls back if the server says no.
    func toggle(_ entry: CalendarEntry) async {
        let id = entry.cellID
        guard let api, !pending.contains(id) else { return }
        let watch = !entry.watched
        problem = nil
        setWatched(id, watch)
        pending.insert(id)
        defer { pending.remove(id) }
        do {
            let output = try await api.setEpisodeWatched(
                path: .init(id: entry.libraryItemId, season: entry.season, episode: entry.number),
                body: .json(.init(watched: watch))
            )
            switch output {
            case let .ok(response):
                var forShelf = try response.body.json
                forShelf.watchedEpisodes = nil
                library?.upsert(forShelf)
            case let .default(_, error):
                setWatched(id, !watch)
                problem = (try? error.body.json.message) ?? Self.notSaved(entry)
            }
        } catch {
            setWatched(id, !watch)
            problem = Self.notSaved(entry) + " Aaru could not reach the server."
        }
    }

    private func setWatched(_ id: String, _ watched: Bool) {
        guard let index = entries.firstIndex(where: { $0.cellID == id }) else { return }
        entries[index].watched = watched
    }

    private static func notSaved(_ entry: CalendarEntry) -> String {
        "\(entry.title.title) S\(entry.season) E\(entry.number) was not saved."
    }

    static func weekStart(of date: Date, in calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }
}
