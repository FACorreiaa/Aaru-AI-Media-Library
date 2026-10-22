import AaruCore
import Foundation

/// Unmatched-row triage (IMP-011): the person searches the catalog and picks the title a row
/// meant. Before approval the pick joins the plan; after it, the row is written at once, like a
/// tap, as its own undoable action. Either way the source's status, rating and ticks come with
/// it, merged like any import row: fill empty, move forward, never past a status set by hand.
extension ImportService {
    func resolveRow(
        _ id: ImportJobID,
        index: Int,
        to ref: MediaRef,
        userID: UserID
    ) async throws -> (job: ImportJob, row: PlannedRow) {
        guard var job = try await stores.importJobs.job(id: id, userID: userID) else { throw AppError.notFound() }
        guard job.state == .planned || job.state == .partial || job.state == .succeeded else {
            throw AppError(
                status: .conflict, code: "import_not_planned",
                message: "This import has no plan yet. Try again when its rows are matched."
            )
        }
        var rows = try await stores.importJobs.rows(jobID: id)
        guard let position = rows.firstIndex(where: { $0.index == index }) else { throw AppError.notFound() }
        guard rows[position].outcome == .unmatched else {
            throw AppError(status: .conflict, code: "import_row_matched", message: "This row is already matched.")
        }
        let title = try await resolver.resolve(ref)
        var row = rows[position]
        row.titleID = title.id
        row.row.type = title.type
        row.row.unsupported = nil
        if let names = row.row.namedEpisodes {
            let keys = try await resolver.episodes(of: title, named: names)
            row.row.watched = keys.isEmpty ? row.row.watched : (row.row.watched ?? []) + keys
            row.row.namedEpisodes = nil
        }
        row.outcome = .pending
        rows[position] = row

        if job.state == .planned {
            rows = try await decided(rows, userID: userID)
            job.stats = Self.stats(rows)
            job.updatedAt = now()
            try await stores.importJobs.savePlan(job, rows: rows)
            return (job, rows[position])
        }

        try await write(&row, job: job, userID: userID)
        rows[position] = row
        job.stats = Self.stats(rows)
        job.state = job.stats.unmatched > 0 ? .partial : .succeeded
        job.updatedAt = now()
        try await stores.importJobs.savePlan(job, rows: [row])
        return (job, row)
    }

    /// One row of an approved import, decided against the library as it is now and written as
    /// one journaled action.
    private func write(_ row: inout PlannedRow, job: ImportJob, userID: UserID) async throws {
        guard let titleID = row.titleID else { return }
        let context = try await mergeContext([row], userID: userID)
        let merged = Self.merged(Self.seasonRows([row], context: context))
        var ops: [LibraryOp] = []
        if merged.listOnly == true {
            row.outcome = .skip
            row.reason = "On a list only; added to the list, not your library."
        } else {
            ops += writes(for: &row, merged: merged, titleID: titleID, item: context.states[titleID])
        }
        let members = Dictionary(uniqueKeysWithValues: Set(row.row.lists).map { ($0, [titleID]) })
        ops += try await listOps(members, userID: userID)
        guard !ops.isEmpty else { return }
        try await stores.library.apply(
            .batch(ops), userID: userID, actor: .user, kind: "import",
            summary: "Matched “\(row.row.title)” from \(Self.sourceName(job.source)) by hand"
        )
    }
}
