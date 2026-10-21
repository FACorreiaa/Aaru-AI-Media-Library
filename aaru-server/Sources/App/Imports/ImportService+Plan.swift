import AaruCore
import Foundation

/// Planning and approval. Rows for the same title (two AniList seasons of one TMDB show, a film
/// listed twice) merge into the first: it carries every tick, the furthest status, the first
/// rating. The approval re-decides from the library as it is then, so a stale plan never
/// overwrites.
extension ImportService {
    // MARK: Plan

    /// Matches every row and decides what the approval would do with it.
    func plan(_ rows: [PlannedRow], userID: UserID) async throws -> [PlannedRow] {
        var planned: [PlannedRow] = []
        for row in rows {
            try await planned.append(match(row))
        }
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

    /// Resolves one row to a title, or says why it could not.
    private func match(_ planned: PlannedRow) async throws -> PlannedRow {
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
