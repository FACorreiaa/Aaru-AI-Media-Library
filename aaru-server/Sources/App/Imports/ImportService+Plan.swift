import AaruCore
import Foundation

/// Planning and approval. Rows for the same title (two AniList seasons of one TMDB show, a film
/// listed twice) merge into the first: it carries every tick, the furthest status, the first
/// rating. The approval re-decides from the library as it is then, so a stale plan never
/// overwrites.
extension ImportService {
    // MARK: Plan

    /// Rows per chunk: one AniList page, so a MyAnimeList export costs one request per chunk.
    static let chunkSize = 50
    /// Chunks in flight. AniList answers a page in a second or two; three at once keep its pacer,
    /// not its latency, the limit.
    static let chunksInFlight = 3
    /// Rows matched at once inside a chunk. Each is a few short queries (and a TMDB call for a
    /// new title), so this stays small enough to leave request handlers their connections.
    static let rowsInFlight = 4

    /// Matches every row and decides what the approval would do with it. `progress` hears how many
    /// rows are matched as each chunk finishes (and renews the job's lease). With
    /// `withoutAniListIfDown` (a job's last try), an AniList outage leaves only the rows that need
    /// AniList unmatched, instead of failing the import.
    func plan(
        _ rows: [PlannedRow],
        userID: UserID,
        withoutAniListIfDown: Bool = false,
        progress: @Sendable (Int) async throws -> Void = { _ in }
    ) async throws -> [PlannedRow] {
        let chunks = stride(from: 0, to: rows.count, by: Self.chunkSize).map { start in
            Array(rows[start ..< min(start + Self.chunkSize, rows.count)])
        }
        var matched = 0
        var planned = try await Self.boundedMap(chunks, limit: Self.chunksInFlight) { chunk in
            try await matchChunk(chunk, withoutAniListIfDown: withoutAniListIfDown)
        } finished: { chunk in
            matched += chunk.count
            try await progress(matched)
        }.flatMap(\.self)
        for (titleID, indices) in Self.groups(planned) {
            let merged = try await Self.merged(seasonRows(indices.map { planned[$0] }))
            for index in indices.dropFirst() {
                planned[index].outcome = .skip
                planned[index].reason = "Merged into an earlier row."
            }
            let first = indices[0]
            if merged.listOnly == true {
                planned[first].outcome = .skip
                planned[first].reason = "On a list only; added to the list, not your library."
            } else {
                let decision = try await decide(merged, titleID: titleID, userID: userID)
                planned[first].outcome = decision.outcome
                planned[first].reason = decision.reason
            }
        }
        return planned
    }

    /// One chunk: AniList's answers for its MyAnimeList-only rows in one request, then each row.
    private func matchChunk(_ chunk: [PlannedRow], withoutAniListIfDown: Bool) async throws -> [PlannedRow] {
        let refs = chunk.compactMap { row in row.row.unsupported == nil ? row.row.mediaRef : nil }
        let resolver: TitleResolver
        do {
            resolver = try await self.resolver.prefetchingMAL(refs)
        } catch let error as ProviderError where withoutAniListIfDown && error.isAniListOutage {
            resolver = self.resolver.withoutAniList(error)
        }
        return try await Self.boundedMap(chunk, limit: Self.rowsInFlight) { row in
            try await match(row, with: resolver, withoutAniListIfDown: withoutAniListIfDown)
        }
    }

    /// `transform` over `items`, at most `limit` at once, the results in the items' order.
    /// `finished` hears each result as it lands, on the calling task.
    static func boundedMap<Item: Sendable, Result: Sendable>(
        _ items: [Item],
        limit: Int,
        _ transform: @escaping @Sendable (Item) async throws -> Result,
        finished: (Result) async throws -> Void = { _ in }
    ) async throws -> [Result] {
        var results = [Result?](repeating: nil, count: items.count)
        try await withThrowingTaskGroup(of: (Int, Result).self) { group in
            var next = 0
            func start() {
                guard next < items.count else { return }
                let index = next
                next += 1
                group.addTask { try await (index, transform(items[index])) }
            }
            for _ in 0 ..< limit {
                start()
            }
            while let (index, result) = try await group.next() {
                results[index] = result
                try await finished(result)
                start()
            }
        }
        return results.compactMap(\.self)
    }

    /// Resolves one row to a title, or says why it could not.
    private func match(
        _ planned: PlannedRow, with resolver: TitleResolver, withoutAniListIfDown: Bool
    ) async throws -> PlannedRow {
        var row = planned
        if let reason = row.row.unsupported {
            row.outcome = .unmatched
            row.reason = reason
            return row
        }
        let nameOnly = row.row.nameOnly == true && row.row.year == nil && row.row.ids.isEmpty
        do {
            row.titleID = if nameOnly {
                try await resolver.resolveShow(named: row.row.title).id
            } else {
                try await resolver.resolve(row.row.mediaRef, searchHint: row.row.author).id
            }
        } catch ResolutionError.notFound {
            row.outcome = .unmatched
            row.reason = "No catalog entry matches “\(row.row.title)”\(row.row.year.map { " (\($0))" } ?? "")."
        } catch ResolutionError.ambiguous {
            row.outcome = .unmatched
            row.reason = nameOnly
                ? "Several shows are called “\(row.row.title)”. Pick the right one by hand."
                : "More than one catalog entry matches. Pick the right one by hand."
        } catch is ValidationError {
            row.outcome = .unmatched
            row.reason = "Not enough to match: the row needs an id or a year."
        } catch let error as ProviderError where withoutAniListIfDown && error.isAniListOutage {
            row.outcome = .unmatched
            row.reason = "AniList was not answering, so this could not be matched. "
                + "Import the file again later to add it."
        }
        return row
    }

    // MARK: Approval

    /// Writes the plan as one journaled action, so a whole import undoes in one tap.
    func apply(_ id: ImportJobID, userID: UserID) async throws -> ImportJob {
        guard var job = try await stores.importJobs.job(id: id, userID: userID) else { throw AppError.notFound() }
        guard job.state == .planned else {
            throw AppError(
                status: .conflict, code: "import_not_planned",
                message: job.state.isTerminal ? "This import was already applied." : "This import has no plan yet."
            )
        }
        var rows = try await stores.importJobs.rows(jobID: id)
        var ops: [LibraryOp] = []
        var listMembers: [String: [TitleID]] = [:]
        for row in rows where row.outcome != .unmatched {
            guard let titleID = row.titleID else { continue }
            for list in row.row.lists {
                listMembers[list, default: []].append(titleID)
            }
        }
        for (titleID, indices) in Self.groups(rows) {
            let merged = try await Self.merged(seasonRows(indices.map { rows[$0] }))
            // A list-only title joins its list without joining the library.
            guard merged.listOnly != true else { continue }
            ops += try await writes(for: &rows[indices[0]], merged: merged, titleID: titleID, userID: userID)
        }
        ops += try await listOps(listMembers, userID: userID)
        job.stats = Self.stats(rows)
        if !ops.isEmpty {
            try await stores.library.apply(
                .batch(ops), userID: userID, actor: .user, kind: "import",
                summary: Self.summary(job.source, stats: job.stats)
            )
        }
        job.state = job.stats.unmatched > 0 ? .partial : .succeeded
        job.updatedAt = now()
        try await stores.importJobs.savePlan(job, rows: rows)
        return job
    }

    /// Decides one title again (the library may have changed since the plan) and returns its writes.
    private func writes(
        for row: inout PlannedRow,
        merged: ImportRow,
        titleID: TitleID,
        userID: UserID
    ) async throws -> [LibraryOp] {
        let decision = try await decide(merged, titleID: titleID, userID: userID)
        row.outcome = decision.outcome
        row.reason = decision.reason
        switch (decision.outcome, decision.fields, decision.itemID) {
        case let (.create, fields?, _):
            return [.insertItem(ItemSnapshot(
                id: LibraryItemID(), titleID: titleID, fields: fields, addedAt: now(), watched: decision.watch
            ))]
        case let (.update, fields?, itemID?):
            var ops: [LibraryOp] = decision.fieldsChanged ? [.setFields(itemID, fields)] : []
            if !decision.watch.isEmpty {
                ops.append(.setEpisodes(itemID, watch: decision.watch, unwatch: []))
            }
            return ops
        default:
            return []
        }
    }
}
