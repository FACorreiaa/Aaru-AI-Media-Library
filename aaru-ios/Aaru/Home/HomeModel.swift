import AaruAPI
import Foundation
import Observation

typealias ContinueEntry = Components.Schemas.ContinueEntry
typealias StartEntry = Components.Schemas.StartEntry
typealias UnfinishedEntry = Components.Schemas.UnfinishedEntry
typealias LibraryCounts = Components.Schemas.LibraryCounts

/// Home (APP-009, APP-013): Continue watching, Start watching, Unfinished and the status counts
/// from `/v1/up-next`; the next two weeks of airings from `/v1/calendar`; this month's numbers
/// from `/v1/me/stats`; and Discover's new shows. Each part loads on its own, so one failing keeps
/// the rest. The last good load is cached so Home opens offline.
@MainActor
@Observable
final class HomeModel {
    private(set) var continueWatching: [ContinueEntry] = []
    private(set) var startWatching: [StartEntry] = []
    /// Unwatched episodes of tracked shows airing from today on, in air order.
    private(set) var upcoming: [CalendarEntry] = []
    private(set) var unfinished: [UnfinishedEntry] = []
    private(set) var counts: LibraryCounts?
    private(set) var monthStats: Stats?
    private(set) var newShows: [CatalogHit] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var pending: Set<String> = []
    /// The last load or check that failed. Shown until the next action.
    var problem: String?

    @ObservationIgnored private let api: Client?
    @ObservationIgnored private let library: LibraryModel?
    @ObservationIgnored private let cache: HomeCache?
    @ObservationIgnored let calendar: Calendar
    @ObservationIgnored private let now: () -> Date
    /// What the cache holds, updated part by part as loads land.
    @ObservationIgnored private var snapshot: HomeCache.Snapshot?
    /// The library revision the last load started at: a write after it means Home is stale.
    @ObservationIgnored private var loadedRevision: Int?
    /// A shelf change arrived while a load was running; run once more when it ends.
    @ObservationIgnored private var reloadQueued = false

    /// Cards in the New shows teaser; the rest are on Discover.
    nonisolated static let teaserLimit = 10

    /// Cards in the Calendar row; the full list is one tap away.
    nonisolated static let upcomingLimit = 12

    init(
        api: Client?,
        library: LibraryModel?,
        cache: HomeCache? = HomeCache(),
        calendar: Calendar = .aaru,
        now: @escaping () -> Date = Date.init
    ) {
        self.api = api
        self.library = library
        self.cache = cache
        self.calendar = calendar
        self.now = now
        if let snapshot = cache?.load() {
            self.snapshot = snapshot
            apply(snapshot)
        }
    }

    /// For previews: rows already in place, nothing to fetch.
    convenience init(preview snapshot: HomeCache.Snapshot, now: Date = .now) {
        self.init(api: nil, library: nil, cache: nil, now: { now })
        apply(snapshot)
        hasLoaded = true
    }

    /// Nothing of the user's own: no rows from the library. The teaser may still be there.
    var hasNoShelfRows: Bool {
        continueWatching.isEmpty && startWatching.isEmpty && upcoming.isEmpty && unfinished.isEmpty
    }

    var isEmpty: Bool {
        hasNoShelfRows && newShows.isEmpty
    }

    // MARK: Loading

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load()
    }

    /// The library changed (an add, a tick, a sync). Refetches unless a load already started after
    /// the change; one arriving mid-load runs once more when that load ends. Before the first
    /// load has been tried there is nothing to refresh: that load is on its way.
    func shelfChanged() async {
        guard let library, let loadedRevision, library.revision != loadedRevision else { return }
        if isLoading {
            reloadQueued = true
            return
        }
        await load()
    }

    /// Every part at once. Any one failing keeps whatever is on screen for it.
    func load() async {
        guard let api, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        repeat {
            reloadQueued = false
            loadedRevision = library?.revision ?? 0
            async let core: Bool = loadCore(api)
            async let stats: Void = loadMonthStats(api)
            async let teaser: Void = loadNewShows(api)
            let coreLoaded = await core
            _ = await (stats, teaser)
            if let snapshot, let cache {
                cache.save(snapshot)
                if coreLoaded {
                    // Previews pass no cache; only the real Home feeds the widgets (WID-001).
                    WidgetSync.publish(WidgetSync.snapshot(
                        upNext: snapshot.upNext,
                        airing: snapshot.airing,
                        now: now()
                    ))
                }
            }
        } while reloadQueued
    }

    /// Up next and the calendar together: the rows that are the user's own. False when they failed.
    private func loadCore(_ api: Client) async -> Bool {
        // The widgets' window: from this week's Monday (or yesterday — a date-only air date is
        // midnight UTC, "yesterday" west of Greenwich) to two weeks out. Home keeps only today on.
        let window = WidgetSync.window(now: now(), calendar: calendar)
        do {
            async let upNextOutput = api.getUpNext()
            async let calendarOutput = api.getCalendar(query: .init(from: window.lowerBound, to: window.upperBound))
            let (upNext, airing) = try await (upNextOutput, calendarOutput)
            guard case let .ok(upNextResponse) = upNext, case let .ok(airingResponse) = airing else {
                problem = "Home could not be loaded."
                return false
            }
            var next = try HomeCache.Snapshot(
                upNext: upNextResponse.body.json,
                airing: airingResponse.body.json.items
            )
            next.monthStats = snapshot?.monthStats
            next.newShows = snapshot?.newShows
            snapshot = next
            apply(next)
            hasLoaded = true
            problem = nil
            return true
        } catch {
            problem = hasLoaded || !isEmpty
                ? "Offline. Showing Home from the last load."
                : "Aaru could not reach the server."
            return false
        }
    }

    /// This month's numbers. A failure leaves the strip as it was and says nothing: the strip is
    /// a summary, not something the user asked for.
    private func loadMonthStats(_ api: Client) async {
        let parts = calendar.dateComponents([.year, .month], from: now())
        let query = Operations.GetStats.Input.Query(
            year: parts.year, month: parts.month, tz: calendar.timeZone.identifier
        )
        guard case let .ok(response) = try? await api.getStats(query: query),
              let stats = try? response.body.json
        else { return }
        monthStats = stats
        snapshot?.monthStats = stats
    }

    /// Discover's new shows for the teaser. A failure keeps the last ones.
    private func loadNewShows(_ api: Client) async {
        guard case let .ok(response) = try? await api.getDiscover(query: .init(section: .newShows)),
              let feed = try? response.body.json,
              let section = feed.sections.first(where: { $0.id == .newShows })
        else { return }
        newShows = Array(section.items.prefix(Self.teaserLimit))
        snapshot?.newShows = newShows
    }

    private func apply(_ snapshot: HomeCache.Snapshot) {
        continueWatching = snapshot.upNext.continueWatching
        startWatching = snapshot.upNext.startWatching
        unfinished = snapshot.upNext.unfinished ?? []
        counts = snapshot.upNext.counts
        monthStats = snapshot.monthStats
        newShows = snapshot.newShows ?? []
        let today = CalendarDay(calendar.dateComponents([.year, .month, .day], from: now()))
        upcoming = snapshot.airing
            .filter { !$0.watched && $0.day(in: calendar) >= today }
            .sorted { lhs, rhs in
                let (left, right) = (lhs.day(in: calendar), rhs.day(in: calendar))
                if left != right {
                    return left < right
                }
                if lhs.airTimeKnown != rhs.airTimeKnown {
                    return !lhs.airTimeKnown
                }
                return (lhs.airsAt, lhs.title.title) < (rhs.airsAt, rhs.title.title)
            }
            .prefix(Self.upcomingLimit)
            .map(\.self)
    }

    // MARK: Checking

    /// Marks the card's next episode watched. The card moves on at once (to the following episode,
    /// or off the row when that was the last aired one), then Home refetches for the real next.
    func markNextWatched(_ entry: ContinueEntry) async {
        let id = entry.libraryItemId
        guard let api, !pending.contains(id) else { return }
        let before = continueWatching
        problem = nil
        advance(id)
        pending.insert(id)
        defer { pending.remove(id) }
        do {
            let output = try await api.setEpisodeWatched(
                path: .init(id: id, season: entry.next.season, episode: entry.next.number),
                body: .json(.init(watched: true))
            )
            switch output {
            case let .ok(response):
                var forShelf = try response.body.json
                forShelf.watchedEpisodes = nil
                // Refetches for the real next card; HomeScreen's revision observer then finds
                // this load already started and does not run a second one.
                library?.upsert(forShelf)
                #if os(iOS)
                    await NowWatching.episodeWatched(
                        libraryItemId: id, season: entry.next.season, episode: entry.next.number
                    )
                #endif
                await shelfChanged()
            case let .default(_, error):
                continueWatching = before
                problem = (try? error.body.json.message) ?? Self.notSaved(entry)
            }
        } catch {
            continueWatching = before
            problem = Self.notSaved(entry) + " Aaru could not reach the server."
        }
    }

    #if os(iOS)
        /// Starts the "Now watching" Live Activity for the card's next episode (WID-005).
        func startWatching(_ entry: ContinueEntry) async {
            problem = await NowWatchingStart.start(NowWatchingAttributes(
                libraryItemId: entry.libraryItemId, title: entry.title.title, season: entry.next.season,
                episode: entry.next.number, episodeName: entry.nextName, posterURL: entry.title.posterUrl,
                runtimeMinutes: NowWatchingStart.runtime(entry.nextRuntimeMinutes)
            ))
        }
    #endif

    /// The optimistic step: next episode in the same season, one fewer left.
    private func advance(_ id: String) {
        guard let index = continueWatching.firstIndex(where: { $0.libraryItemId == id }) else { return }
        var card = continueWatching[index]
        guard card.remainingCount > 1 else {
            continueWatching.remove(at: index)
            return
        }
        card.remainingMinutes = max(0, card.remainingMinutes - (card.nextRuntimeMinutes ?? 0))
        card.remainingCount -= 1
        card.next.number += 1
        card.nextName = nil
        card.isFinale = false
        continueWatching[index] = card
    }

    private static func notSaved(_ entry: ContinueEntry) -> String {
        "\(entry.title.title) S\(entry.next.season) E\(entry.next.number) was not saved."
    }

    // MARK: Labels

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
        let current = now()
        if entry.airTimeKnown, entry.airsAt > current {
            let minutes = Int(entry.airsAt.timeIntervalSince(current) / 60)
            if minutes < 60 {
                return "In \(max(1, minutes)) min"
            }
            if minutes < 12 * 60 {
                let hours = minutes / 60
                return hours == 1 ? "In 1 hour" : "In \(hours) hours"
            }
        }
        let today = calendar.startOfDay(for: current)
        let day = entry.day(in: calendar)
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
