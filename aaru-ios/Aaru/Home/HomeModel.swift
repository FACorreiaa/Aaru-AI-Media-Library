import AaruAPI
import AaruCore
import Foundation
import Observation

typealias ContinueEntry = Components.Schemas.ContinueEntry
typealias StartEntry = Components.Schemas.StartEntry
typealias UnfinishedEntry = Components.Schemas.UnfinishedEntry
typealias LibraryCounts = Components.Schemas.LibraryCounts
typealias DiscoverRow = Components.Schemas.DiscoverRow
typealias DiscoverRowKind = Components.Schemas.DiscoverRowKind

/// Home (APP-009, APP-013): Continue watching, Start watching, Unfinished and the status counts
/// from `/v1/up-next`; the albums being listened to from the shelf (MUS-001); the next two weeks of airings from
/// `/v1/calendar`; this month's numbers
/// from `/v1/me/stats`; then Discover's public rows from `/v1/discover` (DISC-001); and what a
/// player is playing now from `/v1/me/now-playing` (SCR-008, SCR-009), polled while Home is open. Each part
/// loads on its own, so one failing keeps the rest. The last good load is cached so Home opens
/// offline.
@MainActor
@Observable
final class HomeModel {
    private(set) var continueWatching: [ContinueEntry] = []
    private(set) var startWatching: [StartEntry] = []
    /// Unwatched episodes of tracked shows airing from today on, in air order.
    private(set) var upcoming: [CalendarEntry] = []
    private(set) var unfinished: [UnfinishedEntry] = []
    private(set) var counts: LibraryCounts?
    private(set) var weekStats: Stats?
    /// Trending and this-season rows, the same for everyone. Below the user's own rows, and
    /// all a new account sees.
    private(set) var discover: [DiscoverRow] = []
    /// What players report playing now (SCR-008, SCR-009), above Tonight, in the Live
    /// Activity's order. Empty when nothing plays.
    private(set) var nowPlaying: [NowPlayingItem] = []
    /// Discover hits being added right now, by hit id.
    var adding: Set<String> = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    /// The first load failed and nothing is on screen: Home shows the error state, not a spinner
    /// (UX-063). Cleared by the next load that lands.
    private(set) var loadFailed = false
    private(set) var pending: Set<String> = []
    /// Agent requests waiting for the user (OUT-004), pinned above the rows.
    private(set) var plans: [AgentPlan] = []
    /// The airings behind "Airing soon", for the episode sheet a card opens (UX-092). Fetched once,
    /// for the same window the widgets use.
    let airingFeed: CalendarFeed
    /// Tonight as the server ranks it (AG-005).
    let tonightFeed: TonightFeed
    /// The last load or check that failed. Shown until the next action.
    var problem: String?

    /// Previews only: the Listening row without a shelf behind it.
    @ObservationIgnored private var previewListening: [LibraryRow]?

    @ObservationIgnored let api: Client?
    @ObservationIgnored let library: LibraryModel?
    @ObservationIgnored private let cache: HomeCache?
    @ObservationIgnored let calendar: Calendar
    @ObservationIgnored let now: () -> Date
    /// What the cache holds, updated part by part as loads land.
    @ObservationIgnored private var snapshot: HomeCache.Snapshot?
    /// The library revision the last load started at: a write after it means Home is stale.
    @ObservationIgnored private var loadedRevision: Int?
    /// A shelf change arrived while a load was running; run once more when it ends.
    @ObservationIgnored private var reloadQueued = false

    /// Cards in the Calendar row; the full list is one tap away.
    nonisolated static let upcomingLimit = 12
    /// Cards in Continue watching; "All N" opens the Watching page past it.
    nonisolated static let continueLimit = 12

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
        airingFeed = CalendarFeed(api: api, library: library, calendar: calendar)
        tonightFeed = TonightFeed(api: api, cache: cache, timeZone: calendar.timeZone)
        if let snapshot = cache?.load() {
            self.snapshot = snapshot
            apply(snapshot)
        }
        discover = cache?.loadDiscover() ?? []
    }

    /// For previews: rows already in place, nothing to fetch.
    convenience init(
        preview snapshot: HomeCache.Snapshot,
        discover: [DiscoverRow] = [],
        listening: [LibraryRow] = [],
        nowPlaying: [NowPlayingItem] = [],
        now: Date = .now
    ) {
        self.init(api: nil, library: nil, cache: nil, now: { now })
        apply(snapshot)
        self.discover = discover
        self.nowPlaying = nowPlaying
        previewListening = listening
        hasLoaded = true
    }

    /// What Start watching shows: albums have their own row, Listening (UX-052).
    var startable: [StartEntry] {
        startWatching.filter { $0.title.mediaKind != .music }
    }

    /// Nothing of the user's own: no rows from the library. Discover's rows may still be there.
    var isEmpty: Bool {
        continueWatching.isEmpty && startWatching.isEmpty && upcoming.isEmpty && unfinished.isEmpty
            && listening.isEmpty && reading.isEmpty
    }

    /// MUS-001: albums marked Listening, most recently touched first. Read from the shelf, so an
    /// album set to Listening shows here at once, offline too.
    var listening: [LibraryRow] {
        previewListening ?? library?.rows(kind: .music, status: .inProgress) ?? []
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

    /// Every part at once. Any one failing keeps whatever is on screen for it; Discover failing
    /// never touches the user's own rows.
    func load() async {
        guard let api, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        repeat {
            reloadQueued = false
            loadedRevision = library?.revision ?? 0
            async let discoverRows = Self.fetchDiscover(api)
            async let stats: Void = loadWeekStats(api)
            async let tonight: Void = tonightFeed.load()
            let coreLoaded = await loadCore(api)
            await (stats, tonight)
            if let rows = await discoverRows {
                discover = rows
                cache?.saveDiscover(rows)
            }
            if let snapshot, let cache {
                cache.save(snapshot)
                if coreLoaded {
                    // Previews pass no cache; only the real Home feeds the widgets (WID-001).
                    WidgetSync.publish(WidgetSync.snapshot(
                        upNext: snapshot.upNext,
                        airing: snapshot.airing,
                        listening: listening.compactMap { library?.entry($0.id) },
                        now: now()
                    ))
                }
            }
        } while reloadQueued
    }

    /// What is playing now. A failure keeps the last answer: the card's clock runs on from it.
    /// On iPhone it also starts "Now playing" when no activity runs, and saves its art.
    func loadNowPlaying() async {
        guard let api, case let .ok(response) = try? await api.getNowPlaying(),
              let reply = try? response.body.json
        else { return }
        nowPlaying = reply.playing
        #if os(iOS)
            await NowWatchingStart.follow(nowPlaying)
        #endif
    }

    /// Library items playing now: Tonight and Continue watching leave them out.
    var playingItemIds: Set<String> {
        Set(nowPlaying.compactMap(\.libraryItemId))
    }

    private nonisolated static func fetchDiscover(_ api: Client) async -> [DiscoverRow]? {
        guard case let .ok(response) = try? await api.getDiscover() else { return nil }
        return try? response.body.json.rows
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
                if hasLoaded || !isEmpty {
                    problem = "Home could not be refreshed."
                } else {
                    loadFailed = true
                }
                return false
            }
            var next = try HomeCache.Snapshot(
                upNext: upNextResponse.body.json,
                airing: airingResponse.body.json.items
            )
            next.weekStats = snapshot?.weekStats
            snapshot = next
            apply(next)
            hasLoaded = true
            loadFailed = false
            problem = nil
            return true
        } catch {
            if hasLoaded || !isEmpty {
                problem = "Offline. Showing Home from the last load."
            } else {
                // Nothing to show: the error state says it, not a banner under a spinner.
                loadFailed = true
            }
            return false
        }
    }

    /// The last 7 days' numbers (GAM-006d). A failure leaves the strip as it was and says
    /// nothing: the strip is a summary, not something the user asked for.
    private func loadWeekStats(_ api: Client) async {
        let query = Operations.GetStats.Input.Query(span: .last7, tz: calendar.timeZone.identifier)
        guard case let .ok(response) = try? await api.getStats(query: query),
              let stats = try? response.body.json
        else { return }
        weekStats = stats
        snapshot?.weekStats = stats
    }

    private func apply(_ snapshot: HomeCache.Snapshot) {
        continueWatching = snapshot.upNext.continueWatching
        startWatching = snapshot.upNext.startWatching
        unfinished = snapshot.upNext.unfinished ?? []
        counts = snapshot.upNext.counts
        weekStats = snapshot.weekStats
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
}

extension HomeModel {
    /// Tonight's season tick (PROG-006). Nothing moves until the server answers; then Home reloads.
    func markSeasonWatched(_ entry: ContinueEntry) async {
        let id = entry.libraryItemId
        guard let library, !pending.contains(id) else { return }
        problem = nil
        pending.insert(id)
        defer { pending.remove(id) }
        problem = await library.markSeasonWatched(id, season: entry.next.season, api: api)
        if problem == nil {
            await shelfChanged()
        }
    }

    private static func notSaved(_ entry: ContinueEntry) -> String {
        "\(entry.title.title) \(EpisodeCode.short(season: entry.next.season, number: entry.next.number)) was not saved."
    }
}

// MARK: Requests and airings

extension HomeModel {
    /// Requests waiting for an answer. A failure leaves the list as it was; the next load tries again.
    func loadPlans() async {
        guard let api, case let .ok(response)? = try? await api.listPlans(query: .init(status: .pending)) else {
            return
        }
        plans = (try? response.body.json.items) ?? plans
    }

    /// A request was answered here or in a sheet (UX-082). Its card stays, now saying what
    /// happened (with History for an applied one), until the next load leaves it out; an applied
    /// one changed the library, so the rows load again.
    func planDecided(_ plan: AgentPlan) async {
        guard let index = plans.firstIndex(where: { $0.id == plan.id }) else { return }
        plans[index] = plan
        if plan.status == .applied {
            await load()
        }
    }

    /// Opens an "Airing soon" card's episode sheet, fetching the window first if it is not here.
    /// False when the calendar does not have the airing (offline, or outside the window): the
    /// card then opens the show instead.
    func openAiring(_ entry: CalendarEntry) async -> Bool {
        if !airingFeed.entries.contains(where: { $0.cellID == entry.cellID }) {
            await airingFeed.fetch(WidgetSync.window(now: now(), calendar: calendar))
        }
        guard airingFeed.entries.contains(where: { $0.cellID == entry.cellID }) else { return false }
        airingFeed.open(entry)
        return true
    }
}
