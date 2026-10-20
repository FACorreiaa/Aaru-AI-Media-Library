import AaruAPI
import Foundation
import Observation

typealias ContinueEntry = Components.Schemas.ContinueEntry
typealias StartEntry = Components.Schemas.StartEntry
typealias DiscoverRow = Components.Schemas.DiscoverRow

/// Home (APP-009): Continue watching and Start watching from `/v1/up-next`, and the next two
/// weeks of airings from `/v1/calendar`, then Discover's public rows from `/v1/discover`
/// (DISC-001). The last good load is cached so Home opens offline.
@MainActor
@Observable
final class HomeModel {
    private(set) var continueWatching: [ContinueEntry] = []
    private(set) var startWatching: [StartEntry] = []
    /// Unwatched episodes of tracked shows airing from today on, in air order.
    private(set) var upcoming: [CalendarEntry] = []
    /// Trending and this-season rows, the same for everyone. Below the user's own rows, and
    /// all a new account sees.
    private(set) var discover: [DiscoverRow] = []
    /// Discover hits being added right now, by hit id.
    private(set) var adding: Set<String> = []
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
            apply(snapshot)
        }
        discover = cache?.loadDiscover() ?? []
    }

    /// For previews: rows already in place, nothing to fetch.
    convenience init(preview snapshot: HomeCache.Snapshot, discover: [DiscoverRow] = [], now: Date = .now) {
        self.init(api: nil, library: nil, cache: nil, now: { now })
        apply(snapshot)
        self.discover = discover
        hasLoaded = true
    }

    var isEmpty: Bool {
        continueWatching.isEmpty && startWatching.isEmpty && upcoming.isEmpty
    }

    // MARK: Loading

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load()
    }

    /// Every read at once. Any failing keeps whatever is on screen; Discover failing never
    /// touches the user's own rows.
    func load() async {
        guard let api, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        async let discoverRows = Self.fetchDiscover(api)
        await loadOwnRows(api)
        if let rows = await discoverRows {
            discover = rows
            cache?.saveDiscover(rows)
        }
    }

    private nonisolated static func fetchDiscover(_ api: Client) async -> [DiscoverRow]? {
        guard case let .ok(response) = try? await api.getDiscover() else { return nil }
        return try? response.body.json.rows
    }

    private func loadOwnRows(_ api: Client) async {
        // The widgets' window: from this week's Monday (or yesterday — a date-only air date is
        // midnight UTC, "yesterday" west of Greenwich) to two weeks out. Home keeps only today on.
        let window = WidgetSync.window(now: now(), calendar: calendar)
        do {
            async let upNextOutput = api.getUpNext()
            async let calendarOutput = api.getCalendar(query: .init(from: window.lowerBound, to: window.upperBound))
            let (upNext, airing) = try await (upNextOutput, calendarOutput)
            guard case let .ok(upNextResponse) = upNext, case let .ok(airingResponse) = airing else {
                problem = "Home could not be loaded."
                return
            }
            let snapshot = try HomeCache.Snapshot(
                upNext: upNextResponse.body.json,
                airing: airingResponse.body.json.items
            )
            apply(snapshot)
            if let cache {
                cache.save(snapshot)
                // Previews pass no cache; only the real Home feeds the widgets (WID-001).
                WidgetSync.publish(WidgetSync.snapshot(upNext: snapshot.upNext, airing: snapshot.airing, now: now()))
            }
            hasLoaded = true
            problem = nil
        } catch {
            problem = hasLoaded || !isEmpty
                ? "Offline. Showing Home from the last load."
                : "Aaru could not reach the server."
        }
    }

    private func apply(_ snapshot: HomeCache.Snapshot) {
        continueWatching = snapshot.upNext.continueWatching
        startWatching = snapshot.upNext.startWatching
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

    // MARK: Discover

    /// The library item a Discover hit opens: the server's mark, else a match on the shelf
    /// (it may have been added since the rows loaded).
    func libraryItemID(_ hit: CatalogHit) -> String? {
        hit.libraryItemId ?? library?.entry(matching: hit)?.id
    }

    /// Adds a Discover hit with a status, as search does. The card turns into a link to it.
    func add(_ hit: CatalogHit, status: LibraryStatus) async {
        guard let api, !adding.contains(hit.id) else { return }
        problem = nil
        adding.insert(hit.id)
        defer { adding.remove(hit.id) }
        let ref = Components.Schemas.MediaRef(_type: hit._type, ids: hit.ids, title: hit.title, year: hit.year)
        do {
            switch try await api.addLibraryItem(body: .json(.init(mediaRef: ref, status: status))) {
            case let .ok(response):
                let entry = try response.body.json
                library?.upsert(entry)
                mark(hit, libraryItemID: entry.id)
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "\(hit.title) could not be added."
            }
        } catch {
            problem = "\(hit.title) was not added. Aaru could not reach the server."
        }
    }

    private func mark(_ hit: CatalogHit, libraryItemID: String) {
        for row in discover.indices {
            for item in discover[row].items.indices where discover[row].items[item].id == hit.id {
                discover[row].items[item].libraryItemId = libraryItemID
            }
        }
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
                library?.upsert(forShelf)
                #if os(iOS)
                    await NowWatching.episodeWatched(
                        libraryItemId: id, season: entry.next.season, episode: entry.next.number
                    )
                #endif
                await load()
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
