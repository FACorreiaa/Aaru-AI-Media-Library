import AaruAPI
import Foundation
import Observation

typealias CalendarEntry = Components.Schemas.CalendarEntry

/// One calendar day, independent of time zone: the key both calendar views group episodes by.
struct CalendarDay: Hashable, Comparable {
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
    func day(in calendar: Calendar) -> CalendarDay {
        let reader = airTimeKnown ? calendar : CalendarFeed.utcCalendar
        return CalendarDay(reader.dateComponents([.year, .month, .day], from: airsAt))
    }
}

extension Calendar {
    /// The viewer's calendar, but weeks start on Monday everywhere, as CAT's and Stremio's do.
    static var aaru: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }
}

/// The episodes both calendar views read (CAL-001), and the one place a calendar tick is written.
/// Week and month share it, so switching views reuses whatever is already loaded.
@MainActor
@Observable
final class CalendarFeed {
    private(set) var entries: [CalendarEntry] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var pending: Set<String> = []
    /// The last load or tick that failed. Shown until the next action.
    var problem: String?

    @ObservationIgnored private let api: Client?
    @ObservationIgnored private let library: LibraryModel?
    @ObservationIgnored let calendar: Calendar
    /// The UTC window `entries` covers.
    @ObservationIgnored private var loaded: Range<Date>?

    nonisolated static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    /// CAL-001's longest range per request.
    nonisolated static let maxSpan: TimeInterval = 42 * 86400

    init(api: Client?, library: LibraryModel?, calendar: Calendar = .aaru) {
        self.api = api
        self.library = library
        self.calendar = calendar
    }

    /// For previews: entries already in place, nothing to fetch.
    convenience init(preview entries: [CalendarEntry], calendar: Calendar = .aaru) {
        self.init(api: nil, library: nil, calendar: calendar)
        self.entries = entries
        hasLoaded = true
    }

    /// The episodes of one day: date-only ones first (they have no time), then by time.
    func entries(on date: Date) -> [CalendarEntry] {
        let key = CalendarDay(calendar.dateComponents([.year, .month, .day], from: date))
        return entries.filter { $0.day(in: calendar) == key }.sorted { lhs, rhs in
            if lhs.airTimeKnown != rhs.airTimeKnown {
                return !lhs.airTimeKnown
            }
            return (lhs.airsAt, lhs.title.title, lhs.season, lhs.number)
                < (rhs.airsAt, rhs.title.title, rhs.season, rhs.number)
        }
    }

    // MARK: Loading

    /// Fetches `window` unless `needed` is already loaded.
    func ensure(_ needed: Range<Date>, fetching window: Range<Date>) async {
        if let loaded, loaded.lowerBound <= needed.lowerBound, loaded.upperBound >= needed.upperBound {
            return
        }
        await fetch(window)
    }

    /// Replaces `entries` with `window`, in requests of at most `maxSpan` each.
    func fetch(_ window: Range<Date>) async {
        guard let api else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            var collected: [CalendarEntry] = []
            var from = window.lowerBound
            while from < window.upperBound {
                let until = min(window.upperBound, from.addingTimeInterval(Self.maxSpan))
                switch try await api.getCalendar(query: .init(from: from, to: until)) {
                case let .ok(response):
                    collected += try response.body.json.items
                case let .default(_, error):
                    problem = (try? error.body.json.message) ?? "The calendar could not be loaded."
                    return
                }
                from = until
            }
            var seen: Set<String> = []
            entries = collected.filter { seen.insert($0.cellID).inserted }
            loaded = window
            hasLoaded = true
            problem = nil
        } catch {
            problem = hasLoaded
                ? "Offline. Showing the calendar from the last load."
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
}
