import AaruCore
import Foundation
import Logging

/// SCR-010: reads connected MyAnimeList lists back into Aaru, the one two-way exception. MAL has
/// no webhooks, so a list is read when a client opens Aaru (at most every 10 minutes) and every
/// 6 hours. Entries MAL changed after the cursor go through the import merge: they fill gaps and
/// move a status forward, never back, never out of dropped, never past a status set by hand.
/// Aaru's own pushes come back equal to what it last agreed with MAL and are dropped.
struct MALPuller: Sendable {
    let stores: Stores
    let connect: MALConnectService
    let imports: ImportService
    let api: MALAPI
    let logger: Logger
    var now: @Sendable () -> Date = { Date() }

    static let interval: TimeInterval = 6 * 3600
    /// The whole list is read once a week, for entries removed on MAL.
    static let fullReadInterval: TimeInterval = 7 * 86400
    /// Connections read per pass, one after another on the shared MAL pacer.
    static let perPass = 10
    /// A changed-entries read rarely passes its first page; a full read takes MAL's largest.
    static let pageSize = 100
    static let fullPageSize = 1000
    /// No list is read past this many entries.
    static let maxEntries = 20000

    /// Reads every connection due. Returns the titles added or updated.
    @discardableResult
    func runOnce() async throws -> Int {
        let started = now()
        let due = try await stores.mal.claimPulls(
            now: started, staleBefore: started.addingTimeInterval(-Self.interval),
            fullBefore: started.addingTimeInterval(-Self.fullReadInterval), limit: Self.perPass
        )
        var changed = 0
        for one in due {
            do {
                changed += try await pull(one)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // The cursor stays put: the next read sees these entries again.
                logger.warning("MyAnimeList read failed", metadata: ["error": "\(error)"])
            }
        }
        return changed
    }

    func pull(_ due: MALPullDue) async throws -> Int {
        let started = now()
        do {
            guard let token = try await connect.accessToken(userID: due.userID) else {
                logger.notice("MyAnimeList read skipped: no usable token")
                return 0
            }
            let entries = try await read(due, token: token)
            let changed = entries.filter { $0.listStatus.updatedAt > due.cursor }
            let known = try await stores.mal.entryStates(
                userID: due.userID, malIDs: changed.map { String($0.node.id) }
            )
            let fresh = changed.filter { entry in
                Self.state(entry).map { $0 != known[$0.malID] } ?? true
            }
            let planned = try await imports.applyFromMAL(fresh.map(Self.row), userID: due.userID)
            let applied = planned.count { $0.outcome == .create || $0.outcome == .update }
            log(due, read: entries.count, changed: changed.count, planned: planned)
            for entry in fresh {
                guard let state = Self.state(entry) else { continue }
                try await stores.mal.saveEntryState(state, title: entry.node.title, userID: due.userID)
            }
            if due.fullRead {
                try await stores.mal.markRemoved(
                    userID: due.userID, listed: entries.map { String($0.node.id) }, now: started
                )
            }
            try await stores.mal.finishPull(
                userID: due.userID, cursor: changed.map(\.listStatus.updatedAt).max() ?? due.cursor,
                fullReadAt: due.fullRead ? started : nil
            )
            return applied
        } catch let error as ProviderError where error.kind == .unauthorized {
            try await stores.mal.markRevoked(userID: due.userID, revokedAt: started)
            return 0
        }
    }

    /// What one read saw and did, so a change on MAL that never reaches the library can be traced:
    /// counts always, and each entry that wrote nothing, by MAL id and outcome. No user, title or
    /// reason text: a reason can quote the title.
    /// `skip` means the merge found nothing to move forward; `unmatched`, no catalog title.
    private func log(_ due: MALPullDue, read: Int, changed: Int, planned: [PlannedRow]) {
        logger.info("MyAnimeList list read", metadata: [
            "entries": "\(read)", "changed": "\(changed)", "fresh": "\(planned.count)",
            "applied": "\(planned.count { $0.outcome == .create || $0.outcome == .update })",
            "cursor": "\(due.cursor.formatted(.iso8601))", "full": "\(due.fullRead)",
        ])
        for row in planned where row.outcome == .skip || row.outcome == .unmatched {
            logger.notice("MyAnimeList entry not applied", metadata: [
                "mal": "\(row.row.ids.mal ?? "")", "outcome": "\(row.outcome.rawValue)",
            ])
        }
    }

    /// The list newest change first, until the first entry not newer than the cursor; a full read
    /// takes every page.
    private func read(_ due: MALPullDue, token: String) async throws -> [MALListEntry] {
        let limit = due.fullRead ? Self.fullPageSize : Self.pageSize
        var entries: [MALListEntry] = []
        while entries.count < Self.maxEntries {
            let page = try await api.animeList(token: token, offset: entries.count, limit: limit)
            entries += page.data
            guard page.paging?.next != nil, let last = page.data.last else { break }
            if !due.fullRead, last.listStatus.updatedAt <= due.cursor {
                break
            }
        }
        return entries
    }

    /// The entry as MAL holds it, to compare with what Aaru last agreed. Nil for a status Aaru
    /// does not know.
    static func state(_ entry: MALListEntry) -> MALEntryState? {
        entry.listStatus.status.flatMap(MALListStatus.init(rawValue:)).map {
            MALEntryState(
                malID: String(entry.node.id), status: $0, episodes: entry.listStatus.numEpisodesWatched ?? 0,
                score: entry.listStatus.score ?? 0
            )
        }
    }

    /// The entry as an import row, read as IMP-013 reads MAL's export.
    static func row(_ entry: MALListEntry) -> ImportRow {
        let (node, list) = (entry.node, entry.listStatus)
        let isMovie = node.mediaType == "movie"
        let status = list.status.flatMap { AnimeListImport.status($0.replacingOccurrences(of: "_", with: "")) }
        return ImportRow(
            sourceKey: "mal:\(node.id)",
            type: isMovie ? .movie : .show,
            title: node.title,
            ids: ExternalIDs(mal: String(node.id)),
            status: status,
            rating: AnimeListImport.rating(list.score.map(Double.init)),
            finishedAt: list.finishDate.flatMap(Date.catalogDay),
            lists: [],
            watched: AnimeListImport.progress(
                list.numEpisodesWatched ?? 0, total: node.numEpisodes, status: status, isMovie: isMovie
            ),
            knowsOnHold: true
        )
    }
}

extension ImportService {
    /// SCR-010: entries read back from MyAnimeList, matched, merged and written at once as one
    /// journaled action, so Undo takes it back. There is no plan to approve: the user connected
    /// MAL to keep the two lists in step, and the merge only fills gaps and moves forward.
    /// Returns every row with its outcome: created and updated were written.
    func applyFromMAL(_ rows: [ImportRow], userID: UserID) async throws -> [PlannedRow] {
        guard !rows.isEmpty else { return [] }
        let pending = rows.enumerated().map { PlannedRow(index: $0.offset, row: $0.element, outcome: .pending) }
        var planned = try await plan(pending, userID: userID)
        let ops = try await writes(for: &planned, userID: userID)
        guard !ops.isEmpty else { return planned }
        try await stores.library.apply(
            .batch(ops), userID: userID, actor: .user, kind: "import",
            summary: Self.summary(.malXML, stats: Self.stats(planned))
        )
        return planned
    }
}
