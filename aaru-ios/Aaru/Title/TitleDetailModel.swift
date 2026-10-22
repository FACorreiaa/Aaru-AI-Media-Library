import AaruAPI
import AaruCore
import Foundation
import Observation

typealias TitleDetail = Components.Schemas.TitleDetail
typealias LibraryItemPatch = Components.Schemas.LibraryItemPatch
typealias Episode = Components.Schemas.Episode

struct EpisodeKey: Hashable, Comparable, Identifiable {
    let season: Int
    let number: Int

    init(season: Int, number: Int) {
        self.season = season
        self.number = number
    }

    init(_ episode: Episode) {
        self.init(season: episode.season, number: episode.number)
    }

    var id: Self {
        self
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.season, lhs.number) < (rhs.season, rhs.number)
    }
}

/// APP-005: one library item and its title. Every write is optimistic, reconciles with the
/// server's answer, and rolls back visibly when the server says no.
@MainActor
@Observable
final class TitleDetailModel {
    private(set) var entry: LibraryEntry
    private(set) var title: TitleDetail?
    private(set) var watched: Set<EpisodeKey> = []
    private(set) var pending: Set<EpisodeKey> = []
    private(set) var isSaving = false
    /// `GET /v1/titles/{id}` failed, so there are no seasons to show. Cleared by the next `load()`.
    private(set) var loadFailed = false
    /// The last write that failed and was rolled back. Shown until the next action.
    var problem: String?

    @ObservationIgnored let api: Client?
    @ObservationIgnored private let library: LibraryModel
    /// The undo toast, from the view's environment. Nil in previews.
    @ObservationIgnored var toasts: ToastCenter?

    /// `title` is for previews: the detail already loaded, nothing to fetch.
    init(entry: LibraryEntry, api: Client?, library: LibraryModel, title: TitleDetail? = nil) {
        self.entry = entry
        self.api = api
        self.library = library
        self.title = title
    }

    var isShow: Bool {
        entry.title._type == .show
    }

    func load() async {
        guard let api else { return }
        loadFailed = false
        async let item = api.getLibraryItem(path: .init(id: entry.id))
        async let detail = api.getTitle(path: .init(id: entry.title.id))
        do {
            if case let .ok(response) = try await item {
                try apply(response.body.json)
            }
        } catch {
            problem = "Aaru could not reach the server."
        }
        // Without the title there is nothing to tick: say so instead of spinning.
        do {
            if case let .ok(response) = try await detail {
                title = try response.body.json
            } else {
                loadFailed = title == nil
            }
        } catch {
            loadFailed = title == nil
        }
    }

    // MARK: Seasons

    /// Seasons in order, specials (season 0) last.
    var orderedSeasons: [Components.Schemas.Season] {
        (title?.seasons ?? []).sorted {
            ($0.number == 0 ? Int.max : $0.number) < ($1.number == 0 ? Int.max : $1.number)
        }
    }

    /// The first aired episode not yet watched, specials aside. Nil when caught up.
    var nextEpisode: EpisodeKey? {
        let now = Date()
        return orderedSeasons.filter { $0.number > 0 }.flatMap(\.episodes)
            .first { ($0.airsAt ?? .distantPast) <= now && !self.watched.contains(EpisodeKey($0)) }
            .map(EpisodeKey.init)
    }

    func episode(_ key: EpisodeKey) -> Episode? {
        title?.seasons?.first { $0.number == key.season }?.episodes.first { $0.number == key.number }
    }

    /// The episode `offset` steps away in season-map order, or nil past either end.
    func episode(_ key: EpisodeKey, offset: Int) -> EpisodeKey? {
        let keys = orderedSeasons.flatMap(\.episodes).map(EpisodeKey.init)
        guard let index = keys.firstIndex(of: key), keys.indices.contains(index + offset) else { return nil }
        return keys[index + offset]
    }

    /// Unaired episodes cannot be ticked; one already ticked can still be unticked.
    func canToggle(_ episode: Episode) -> Bool {
        hasAired(episode) || watched.contains(EpisodeKey(episode))
    }

    func hasAired(_ episode: Episode) -> Bool {
        (episode.airsAt ?? .distantPast) <= Date()
    }

    // MARK: Episodes

    func toggle(_ key: EpisodeKey) async {
        guard let api, !pending.contains(key) else { return }
        let watch = !watched.contains(key)
        problem = nil
        // Optimistic: the tick moves now; the server's answer decides.
        if watch {
            watched.insert(key)
        } else {
            watched.remove(key)
        }
        pending.insert(key)
        defer { pending.remove(key) }
        do {
            let output = try await api.setEpisodeWatched(
                path: .init(id: entry.id, season: key.season, episode: key.number),
                body: .json(.init(watched: watch))
            )
            switch output {
            case let .ok(response):
                try commit(response.body.json)
                // The widgets' up next and week follow every tick (WID-001).
                Task { try? await WidgetSync.refresh(api: api) }
                #if os(iOS)
                    if watch {
                        await NowWatching.episodeWatched(
                            libraryItemId: entry.id, season: key.season, episode: key.number
                        )
                    }
                #endif
            case let .default(_, error):
                rollback(key, to: !watch, message: (try? error.body.json.message))
            }
        } catch {
            rollback(key, to: !watch, message: nil)
        }
    }

    #if os(iOS)
        /// Starts the "Now watching" Live Activity for one episode (WID-005).
        func startWatching(_ episode: Components.Schemas.Episode) async {
            problem = await NowWatchingStart.start(NowWatchingAttributes(
                libraryItemId: entry.id, title: entry.title.title, season: episode.season, episode: episode.number,
                episodeName: episode.name, posterURL: entry.title.posterUrl,
                runtimeMinutes: NowWatchingStart.runtime(episode.runtimeMinutes ?? title?.runtimeMinutes)
            ))
        }
    #endif

    func markSeasonWatched(_ season: Int) async {
        guard let api else { return }
        let before = watched
        let aired = airedEpisodes(in: season)
        problem = nil
        watched.formUnion(aired)
        pending.formUnion(aired)
        defer { pending.subtract(aired) }
        do {
            switch try await api.markSeasonWatched(path: .init(id: entry.id, season: season)) {
            case let .ok(response):
                try commit(response.body.json)
                #if os(iOS)
                    await NowWatching.seasonWatched(libraryItemId: entry.id, season: season)
                #endif
            case let .default(_, error):
                watched = before
                problem = (try? error.body.json.message) ?? "Season \(season) could not be marked. Try again."
            }
        } catch {
            watched = before
            problem = "Season \(season) could not be marked. Aaru could not reach the server."
        }
    }

    /// PROG-005: Watched on a show ticks every aired episode as one action, which the toast can
    /// undo. The server decides the status: an ended or canceled show becomes Watched, a running
    /// one stays Watching, caught up, and the picker settles on whichever it says.
    func markShowWatched() async {
        let before = (entry, watched)
        let aired = Set(orderedSeasons.filter { $0.number > 0 }.flatMap(\.episodes).filter(hasAired)
            .map(EpisodeKey.init))
        problem = nil
        watched.formUnion(aired)
        entry.status = endsAtFinale ? .finished : .inProgress
        pending.formUnion(aired)
        isSaving = true
        defer {
            pending.subtract(aired)
            isSaving = false
        }
        switch await library.markShowWatched(entry.id, api: api) {
        case let .success(result):
            apply(result.entry)
            // The toast can outlive this page: the undo runs either way, the reload only while open.
            toasts?.showWatched(result) { [weak self, library, api] actionID in
                let problem = await library.undo(actionID, api: api)
                if problem == nil {
                    await self?.load()
                }
                return problem
            }
        case let .failure(failure):
            (entry, watched) = before
            problem = failure.message
        }
    }

    /// An ended or canceled show finishes when every episode is ticked; a running one, or one
    /// whose detail has not loaded, is the server's call. Optimistic only.
    private var endsAtFinale: Bool {
        guard let status = title?.status else { return true }
        return status == .ended || status == .canceled
    }

    /// "Caught up · next Oct 30": a running show with every aired episode watched, and its next
    /// air date when the catalog has one. Nil for anything else.
    var caughtUpLine: String? {
        guard isShow, entry.status != .finished, let progress = entry.progress, progress.airedCount > 0,
              progress.watchedCount >= progress.airedCount
        else { return nil }
        if let status = title?.status, status == .ended || status == .canceled {
            return nil
        }
        let now = Date()
        let next = orderedSeasons.filter { $0.number > 0 }.flatMap(\.episodes)
            .filter { ($0.airsAt ?? .distantPast) > now }
            .min { ($0.airsAt ?? .distantFuture) < ($1.airsAt ?? .distantFuture) }
        guard let next, let airsAt = next.airsAt else { return "Caught up" }
        // A date-only air date is midnight UTC of that date, so it is read in UTC.
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        if !next.airTimeKnown {
            style.timeZone = .gmt
        }
        return "Caught up · next \(airsAt.formatted(style))"
    }

    func airedEpisodes(in season: Int) -> Set<EpisodeKey> {
        let now = Date()
        let episodes = title?.seasons?.first { $0.number == season }?.episodes ?? []
        return Set(episodes.filter { ($0.airsAt ?? .distantPast) <= now }.map(EpisodeKey.init))
    }

    // MARK: Item fields

    func update(_ patch: LibraryItemPatch, optimistic: (inout LibraryEntry) -> Void) async {
        guard let api else { return }
        // A show set to Watched goes through the whole-show mark, so it gets an action to undo.
        if isShow, patch.status == .finished, entry.status != .finished {
            await markShowWatched()
            return
        }
        let before = entry
        problem = nil
        optimistic(&entry)
        isSaving = true
        defer { isSaving = false }
        do {
            switch try await api.updateLibraryItem(path: .init(id: entry.id), body: .json(patch)) {
            case let .ok(response):
                try commit(response.body.json)
                // An album moving in or out of Listening changes the Listening widget (MUS-001).
                if patch.status != nil, entry.title._type == .album {
                    Task { try? await WidgetSync.refresh(api: api) }
                }
            case let .default(_, error):
                entry = before
                problem = (try? error.body.json.message) ?? "That change was not saved."
            }
        } catch {
            entry = before
            problem = "That change was not saved. Aaru could not reach the server."
        }
    }

    /// Removes the item from the library (UX-061). The server journals it, so History can undo
    /// it. False, with `problem` set, when the server said no.
    func remove() async -> Bool {
        problem = nil
        if let failure = await library.remove(entry.id, api: api) {
            problem = failure
            return false
        }
        return true
    }

    // MARK: Reconcile

    /// The server's answer is the truth: it replaces the optimistic state and the shelf's row.
    private func commit(_ response: LibraryEntry) {
        apply(response)
        var forShelf = response
        forShelf.watchedEpisodes = nil
        library.upsert(forShelf)
    }

    private func apply(_ response: LibraryEntry) {
        entry = response
        if let episodes = response.watchedEpisodes {
            watched = Set(episodes.map { EpisodeKey(season: $0.season, number: $0.number) })
        }
    }

    private func rollback(_ key: EpisodeKey, to wasWatched: Bool, message: String?) {
        if wasWatched {
            watched.insert(key)
        } else {
            watched.remove(key)
        }
        let code = EpisodeCode.short(season: key.season, number: key.number)
        problem = message ?? "\(code) was not saved. Aaru could not reach the server."
    }
}
