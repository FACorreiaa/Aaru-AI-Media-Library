import AaruAPI
import Algorithms
import Foundation
import Observation
import WidgetKit

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
    /// Tracked shows whose episodes are still loading (CAL-004), as after an import.
    private(set) var pendingShows = 0
    /// The last load or tick that failed. Shown until the next action.
    var problem: String?
    /// Applied to every day's episodes (CAL-003). The screen keeps it in `@AppStorage`.
    var filter = CalendarFilter()
    /// The episode whose sheet is open, by `cellID`; the sheet reads it live, so a tick shows.
    var openedID: String?
    /// iPhone: a Month day is open as a sheet, so the episode sheet opens from inside it, not
    /// from the screen under it (UX-068).
    var isDaySheetOpen = false

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
        loaded = .distantPast ..< .distantFuture
    }

    /// The episodes of one day: date-only ones first (they have no time), then by time.
    func entries(on date: Date) -> [CalendarEntry] {
        let key = CalendarDay(calendar.dateComponents([.year, .month, .day], from: date))
        return entries.filter { $0.day(in: calendar) == key && filter.matches($0) }.sorted { lhs, rhs in
            if lhs.airTimeKnown != rhs.airTimeKnown {
                return !lhs.airTimeKnown
            }
            return (lhs.airsAt, lhs.title.title, lhs.season, lhs.number)
                < (rhs.airsAt, rhs.title.title, rhs.season, rhs.number)
        }
    }

    /// The open sheet's episode, live.
    var opened: CalendarEntry? {
        openedID.flatMap { id in entries.first { $0.cellID == id } }
    }

    func open(_ entry: CalendarEntry) {
        openedID = entry.cellID
    }

    /// Missed (CAL-003): aired in the window and not watched, by show. Hide-watched is moot here.
    func missed(now: Date = .now) -> [MissedShow] {
        var filter = filter
        filter.hideWatched = false
        return MissedShow.catchUp(entries.filter(filter.matches), now: now)
    }

    // MARK: Loading

    /// Whether the last successful load covers `needed`. Views say "nothing airs" only when it
    /// does: entries left from another window are not this window's answer (UX-062).
    func covers(_ needed: Range<Date>) -> Bool {
        guard let loaded else { return false }
        return loaded.lowerBound <= needed.lowerBound && loaded.upperBound >= needed.upperBound
    }

    /// `needed` is not loaded and the last load failed: the view's error state, with Try again.
    func loadProblem(for needed: Range<Date>) -> String? {
        covers(needed) || isLoading ? nil : problem
    }

    /// Fetches `window` unless `needed` is already loaded.
    func ensure(_ needed: Range<Date>, fetching window: Range<Date>) async {
        if let loaded, loaded.lowerBound <= needed.lowerBound, loaded.upperBound >= needed.upperBound {
            return
        }
        await fetch(window)
    }

    /// CAL-004: asks again for the loaded window while shows are still loading their episodes,
    /// every ten seconds for at most five minutes. Ends when the caller's task is cancelled.
    func recheckWhilePending() async {
        let deadline = Date.now.addingTimeInterval(5 * 60)
        while pendingShows > 0, Date.now < deadline {
            do {
                try await Task.sleep(for: .seconds(10))
            } catch {
                return
            }
            guard let loaded else { return }
            await fetch(loaded)
        }
    }

    /// Replaces `entries` with `window`, in requests of at most `maxSpan` each.
    func fetch(_ window: Range<Date>) async {
        guard let api else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            var collected: [CalendarEntry] = []
            var waiting = 0
            var from = window.lowerBound
            while from < window.upperBound {
                let until = min(window.upperBound, from.addingTimeInterval(Self.maxSpan))
                switch try await api.getCalendar(query: .init(from: from, to: until)) {
                case let .ok(response):
                    let page = try response.body.json
                    collected += page.items
                    waiting = max(waiting, page.pendingShows ?? 0)
                case let .default(_, error):
                    problem = (try? error.body.json.message) ?? "The calendar could not be loaded."
                    return
                }
                from = until
            }
            entries = collected.uniqued(on: \.cellID)
            pendingShows = waiting
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
                // Widgets agree at once, then catch up on up next from the server (WID-001).
                WidgetSnapshotStore.setWatched(
                    libraryItemId: entry.libraryItemId, season: entry.season, number: entry.number, watched: watch
                )
                WidgetCenter.shared.reloadAllTimelines()
                Task { try? await WidgetSync.refresh(api: api) }
                #if os(iOS)
                    if watch {
                        await NowWatching.episodeWatched(
                            libraryItemId: entry.libraryItemId, season: entry.season, episode: entry.number
                        )
                    }
                #endif
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
        "\(entry.title.title) \(EpisodeCode.short(season: entry.season, number: entry.number)) was not saved."
    }
}
