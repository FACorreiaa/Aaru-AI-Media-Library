import AaruCore
import Foundation
import Logging
import ServiceLifecycle

/// SCR-005: sends anime progress to connected MyAnimeList accounts. It reads the library's own
/// changes since each connection's cursor, so every write path (a tap, an import, a scrobble, an
/// undo, an agent) goes out the same way, and nothing has to remember to call it. Deletes are not
/// pushed: removing an anime from Aaru leaves it on MAL.
struct MALPusher: Sendable {
    let stores: Stores
    let connect: MALConnectService
    let api: MALAPI
    let logger: Logger
    var now: @Sendable () -> Date = { Date() }

    /// One entry's share of a show: its ticks, its episodes when known, and whether it is the
    /// show's first entry.
    struct Share: Sendable, Equatable {
        var ticks: Int
        var total: Int?
        var isFirst: Bool
    }

    /// One MAL entry an Aaru show stands for. `season` nil: an anime that is not a TMDB show,
    /// so every tick counts.
    struct Target: Sendable, Equatable {
        var malID: String
        var season: Int?
    }

    /// Pushes for every connection with library writes past its cursor. Returns entries sent.
    @discardableResult
    func runOnce() async throws -> Int {
        var sent = 0
        for due in try await stores.mal.pushesDue() {
            do {
                sent += try await push(due)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // The cursor stays put, so the next pass tries these writes again.
                logger.warning("MyAnimeList push failed", metadata: ["error": "\(error)"])
            }
        }
        return sent
    }

    func push(_ due: MALPushDue) async throws -> Int {
        let started = now()
        do {
            guard let token = try await connect.accessToken(userID: due.userID) else { return 0 }
            let sent = try await push(due, token: token, now: started)
            // Writes committing while this ran are read again next time, like the sync token.
            try await stores.mal.advanceCursor(
                userID: due.userID, cursor: started.addingTimeInterval(-LibraryService.syncOverlap)
            )
            return sent
        } catch let error as ProviderError where error.kind == .unauthorized {
            try await stores.mal.markRevoked(userID: due.userID, revokedAt: started)
            return 0
        }
    }

    private func push(_ due: MALPushDue, token: String, now: Date) async throws -> Int {
        let changes = try await stores.library.changes(userID: due.userID, since: due.cursor, now: now)
        let shows = changes.entries.filter { $0.title.type == .show }
        guard !shows.isEmpty else { return 0 }
        async let byTMDB = stores.animeMappings.mappings(tmdb: shows.compactMap(\.title.ids.tmdb))
        async let byAniList = stores.animeMappings.mappings(anilist: shows.compactMap(\.title.ids.anilist))
        let tmdbMappings = try await Dictionary(grouping: byTMDB) { $0.tmdb ?? "" }
        let anilistMappings = try await Dictionary(byAniList.map { ($0.anilist, $0) }) { first, _ in first }
        let planned = shows.compactMap { entry -> (LibraryEntry, [Target])? in
            let targets = Self.targets(
                entry.title,
                tmdbMappings: entry.title.ids.tmdb.flatMap { tmdbMappings[$0] } ?? [],
                anilistMapping: entry.title.ids.anilist.flatMap { anilistMappings[$0] }
            )
            return targets.isEmpty ? nil : (entry, targets)
        }
        guard !planned.isEmpty else { return 0 }
        async let watched = stores.library.watched(itemIDs: planned.map(\.0.item.id))
        async let known = stores.mal.entryStates(
            userID: due.userID, malIDs: planned.flatMap { $0.1.map(\.malID) }
        )
        let (ticks, states) = try await (watched, known)
        var sent = 0
        for (entry, targets) in planned {
            let episodes = try await stores.titles.episodes(entry.title.id)
            for (index, target) in targets.enumerated() {
                let inSeason = { (season: Int) in target.season.map { $0 == season } ?? (season > 0) }
                let count = (ticks[entry.item.id] ?? []).count(where: { inSeason($0.season) })
                let total = episodes.count(where: { inSeason($0.season) })
                let share = Share(ticks: count, total: total > 0 ? total : nil, isFirst: index == 0)
                guard let state = Self.state(
                    malID: target.malID, item: entry.item, share: share, known: states[target.malID]
                ), state != states[target.malID]
                else { continue }
                do {
                    try await api.updateListStatus(malID: target.malID, state, token: token)
                } catch let error as ProviderError where error.kind == .notFound || error.kind.isRefusal {
                    // MAL does not know this id (a stale mapping): skip it rather than block the rest.
                    logger.notice("MyAnimeList refused an entry", metadata: ["mal": "\(target.malID)"])
                    continue
                }
                let name = target.season.map { $0 > 1 ? "\(entry.title.title) · Season \($0)" : nil }
                try await stores.mal.saveEntryState(
                    state, title: name ?? entry.title.title, userID: due.userID
                )
                sent += 1
            }
        }
        return sent
    }

    /// The MAL entries a show stands for. A TMDB show splits by the anime mapping into one entry
    /// per season; a season several MAL entries map to (a split cour) is skipped, because Aaru
    /// cannot tell which of its ticks belong to which. Anything else uses its own MAL id.
    static func targets(_ title: Title, tmdbMappings: [AnimeMapping], anilistMapping: AnimeMapping?) -> [Target] {
        guard title.type == .show else { return [] }
        guard tmdbMappings.isEmpty else {
            let bySeason = Dictionary(grouping: tmdbMappings.filter { $0.mal != nil }) { $0.tmdbSeason ?? 1 }
            return bySeason.keys.sorted().compactMap { season in
                let ids = Set(bySeason[season]?.compactMap(\.mal) ?? [])
                return ids.count == 1 ? ids.first.map { Target(malID: $0, season: season) } : nil
            }
        }
        return (title.ids.mal ?? anilistMapping?.mal).map { [Target(malID: $0, season: nil)] } ?? []
    }

    /// What one MAL entry should say, or nil when Aaru has nothing to say about it (a later
    /// season nobody started). Only the first entry carries a show's plan or a drop with no ticks,
    /// so planning a show does not add every season to MAL. An entry the user put on hold on MAL
    /// stays on hold until Aaru's ticks move.
    static func state(malID: String, item: LibraryItem, share: Share, known: MALEntryState?) -> MALEntryState? {
        let (ticks, total, isFirst) = (share.ticks, share.total, share.isFirst)
        let score = item.rating.map { Int($0.value.rounded()) } ?? 0
        var state: MALEntryState
        switch item.status {
        case .finished:
            state = MALEntryState(malID: malID, status: .completed, episodes: total ?? ticks, score: score)
        case .dropped:
            guard ticks > 0 || isFirst else { return nil }
            state = MALEntryState(malID: malID, status: .dropped, episodes: ticks, score: score)
        case .wishlist:
            guard ticks > 0 || isFirst else { return nil }
            state = MALEntryState(malID: malID, status: .planToWatch, episodes: ticks, score: score)
        case .inProgress:
            if let total, ticks >= total {
                state = MALEntryState(malID: malID, status: .completed, episodes: total, score: score)
            } else if ticks > 0 || isFirst {
                state = MALEntryState(malID: malID, status: .watching, episodes: ticks, score: score)
            } else {
                return nil
            }
        }
        if let known, known.status == .onHold, state.status == .watching, state.episodes == known.episodes {
            state.status = .onHold
        }
        return state
    }
}

extension ProviderError.Kind {
    /// Any other 4xx: asking again gets the same answer.
    var isRefusal: Bool {
        if case .refused = self {
            return true
        }
        return false
    }
}

/// Runs the MyAnimeList push and read-back every 30 seconds in the API process, so a tick
/// reaches MAL within a minute and a read a client asked for starts within one. Reads that are
/// not due cost one query.
struct MALSyncService: Service {
    let pusher: MALPusher
    let puller: MALPuller
    let logger: Logger
    var interval: Duration = .seconds(30)

    /// The sync worker, when MyAnimeList is configured; none otherwise.
    static func services(
        stores: Stores, connect: MALConnectService, imports: ImportService, logger: Logger
    ) -> [any Service] {
        connect.api.map {
            [MALSyncService(
                pusher: MALPusher(stores: stores, connect: connect, api: $0, logger: logger),
                puller: MALPuller(stores: stores, connect: connect, imports: imports, api: $0, logger: logger),
                logger: logger
            )]
        } ?? []
    }

    func run() async throws {
        try await cancelWhenGracefulShutdown {
            while !Task.isCancelled {
                do {
                    let read = try await puller.runOnce()
                    if read > 0 {
                        logger.info("MyAnimeList entries read back", metadata: ["titles": "\(read)"])
                    }
                    let sent = try await pusher.runOnce()
                    if sent > 0 {
                        logger.info("MyAnimeList entries pushed", metadata: ["entries": "\(sent)"])
                    }
                } catch is CancellationError {
                    return
                } catch {
                    logger.error("MyAnimeList sync pass failed", metadata: ["error": "\(error)"])
                }
                try? await Task.sleep(for: interval)
            }
        }
    }
}
