import AaruCore
import Foundation

/// File imports (IMP-001, IMP-004, IMP-005): upload → a leased job matches every row and
/// builds a plan → the user approves → the plan is written as one journaled, undoable action.
/// Nothing touches the library before the approval (DESIGN.md: first-run imports always plan).
struct ImportService: Sendable {
    /// Uploads larger than this are refused before they are read in full.
    static let maxUploadBytes = 5 * 1024 * 1024
    static let maxAttempts = 3
    static let lease: TimeInterval = 30 * 60

    let stores: Stores
    let resolver: TitleResolver
    var now: @Sendable () -> Date = { Date() }

    // MARK: Requests

    /// Parses the file now (fast, bounded) and queues the matching (slow, provider calls).
    func createCSVImport(
        userID: UserID,
        source: ImportSource,
        filename: String?,
        text: String
    ) async throws -> ImportJob {
        let rows: [ImportRow]
        do {
            rows = try CSVImportParser.parse(text, source: source, filename: filename)
        } catch let error as ImportFormatError {
            throw AppError(
                status: .unprocessableContent, code: "validation_failed", message: error.message,
                details: ["file": error.message]
            )
        }
        guard !rows.isEmpty else {
            throw AppError(
                status: .unprocessableContent, code: "validation_failed",
                message: "That file has no rows to import.", details: ["file": "No rows."]
            )
        }
        let job = ImportJob(
            userID: userID, source: source, filename: filename, createdAt: now(), updatedAt: now()
        )
        try await stores.importJobs.insert(job, rows: rows)
        return job
    }

    func jobs(userID: UserID) async throws -> [ImportJob] {
        try await stores.importJobs.jobs(userID: userID, limit: 50)
    }

    func detail(_ id: ImportJobID, userID: UserID) async throws -> (job: ImportJob, rows: [PlannedRow]) {
        guard let job = try await stores.importJobs.job(id: id, userID: userID) else { throw AppError.notFound() }
        return try await (job, stores.importJobs.rows(jobID: id))
    }

    func delete(_ id: ImportJobID, userID: UserID) async throws {
        guard let job = try await stores.importJobs.job(id: id, userID: userID) else { throw AppError.notFound() }
        guard job.state != .running else {
            throw AppError(
                status: .conflict, code: "import_running",
                message: "This import is being matched right now. Try again when it has a plan."
            )
        }
        _ = try await stores.importJobs.delete(id: id, userID: userID)
    }

    // MARK: The worker's step

    /// Leases one job and plans it. Returns false when there was nothing to do.
    @discardableResult
    func runNext() async throws -> Bool {
        guard let claimed = try await stores.importJobs.claimNext(now: now(), lease: Self.lease) else { return false }
        var job = claimed.job
        do {
            let rows = try await plan(stores.importJobs.rows(jobID: job.id), userID: job.userID)
            job.state = .planned
            job.stats = Self.stats(rows)
            job.errorSummary = nil
            job.updatedAt = now()
            try await stores.importJobs.savePlan(job, rows: rows)
        } catch {
            let summary = Self.summary(of: error)
            if claimed.attempts < Self.maxAttempts {
                // Back off: 30 s, then 60 s. A provider outage usually passes.
                let wait = TimeInterval(30 * claimed.attempts)
                try await stores.importJobs.retry(
                    job.id, error: summary, notBefore: now().addingTimeInterval(wait), now: now()
                )
            } else {
                job.state = .failed
                job.errorSummary = summary
                job.updatedAt = now()
                try await stores.importJobs.update(job)
            }
        }
        return true
    }

    /// Matches every row and decides what the approval would do with it.
    private func plan(_ rows: [PlannedRow], userID: UserID) async throws -> [PlannedRow] {
        var seen: Set<TitleID> = []
        var planned: [PlannedRow] = []
        for var row in rows {
            if let reason = row.row.unsupported {
                row.outcome = .unmatched
                row.reason = reason
                planned.append(row)
                continue
            }
            do {
                let title = try await resolver.resolve(row.row.mediaRef, searchHint: row.row.author)
                row.titleID = title.id
                if seen.contains(title.id) {
                    row.outcome = .skip
                    row.reason = "Repeats an earlier row."
                } else {
                    seen.insert(title.id)
                    let decision = try await decide(row.row, titleID: title.id, userID: userID)
                    row.outcome = decision.outcome
                    row.reason = decision.reason
                }
            } catch ResolutionError.notFound {
                row.outcome = .unmatched
                row.reason = "No catalog entry matches “\(row.row.title)”\(row.row.year.map { " (\($0))" } ?? "")."
            } catch ResolutionError.ambiguous {
                row.outcome = .unmatched
                row.reason = "More than one catalog entry matches. Pick the right one by hand."
            } catch is ValidationError {
                row.outcome = .unmatched
                row.reason = "Not enough to match: the row needs an id or a year."
            }
            planned.append(row)
        }
        return planned
    }

    private struct Decision {
        var outcome: ImportOutcome
        var reason: String?
        var fields: ItemFields?
        var itemID: LibraryItemID?
    }

    /// Fill-empty only (IMP-004): an import never overwrites a status, rating or date the
    /// library already has. It only adds what is missing.
    private func decide(_ row: ImportRow, titleID: TitleID, userID: UserID) async throws -> Decision {
        guard let item = try await stores.library.item(userID: userID, titleID: titleID) else {
            let status = row.status ?? .wishlist
            let fields = ItemFields(
                status: status, rating: Self.rating(row.rating), notes: nil, isOwned: false,
                finishedAt: status == .finished ? row.finishedAt : nil, bookPage: nil, bookPercent: nil
            )
            return Decision(outcome: .create, fields: fields)
        }
        guard let entry = try await stores.library.entry(id: item.id, userID: userID, now: now()) else {
            return Decision(outcome: .skip, reason: "Already on your shelf.")
        }
        var fields = ItemFields(
            status: item.status, rating: item.rating?.value, notes: item.notes, isOwned: item.isOwned,
            finishedAt: item.finishedAt, bookPage: entry.bookProgress?.page, bookPercent: entry.bookProgress?.percent
        )
        var filled: [String] = []
        if fields.rating == nil, let rating = Self.rating(row.rating) {
            fields.rating = rating
            filled.append("rating")
        }
        if fields.finishedAt == nil, fields.status == .finished, let finished = row.finishedAt {
            fields.finishedAt = finished
            filled.append("finish date")
        }
        guard !filled.isEmpty else {
            return Decision(outcome: .skip, reason: "Already on your shelf; nothing new to add.")
        }
        return Decision(
            outcome: .update, reason: "Adds the \(filled.joined(separator: " and ")).", fields: fields, itemID: item.id
        )
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
        var seen: Set<TitleID> = []
        for index in rows.indices {
            guard let titleID = rows[index].titleID, rows[index].outcome != .unmatched else { continue }
            for list in rows[index].row.lists {
                listMembers[list, default: []].append(titleID)
            }
            // A repeat of an earlier row adds nothing (its list membership is already counted).
            guard seen.insert(titleID).inserted else { continue }
            if let write = try await write(for: &rows[index], titleID: titleID, userID: userID) {
                ops.append(write)
            }
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

    /// Decides one row again (the library may have changed since the plan) and returns its write.
    private func write(
        for row: inout PlannedRow,
        titleID: TitleID,
        userID: UserID
    ) async throws -> LibraryOp? {
        let decision = try await decide(row.row, titleID: titleID, userID: userID)
        row.outcome = decision.outcome
        row.reason = decision.reason
        switch (decision.outcome, decision.fields, decision.itemID) {
        case let (.create, fields?, _):
            let snapshot = ItemSnapshot(
                id: LibraryItemID(),
                titleID: titleID,
                fields: fields,
                addedAt: now(),
                watched: []
            )
            return .insertItem(snapshot)
        case let (.update, fields?, itemID?):
            return .setFields(itemID, fields)
        default:
            return nil
        }
    }

    /// Goodreads custom shelves become lists: one per shelf name, reusing a list of that name.
    private func listOps(_ members: [String: [TitleID]], userID: UserID) async throws -> [LibraryOp] {
        guard !members.isEmpty else { return [] }
        let existing = try await stores.lists.lists(userID: userID)
        return members.sorted { $0.key < $1.key }.map { name, titles in
            if let list = existing.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                var merged = list.titleIDs
                for title in titles where !merged.contains(title) {
                    merged.append(title)
                }
                return .setListMembers(list.id, merged)
            }
            var unique: [TitleID] = []
            for title in titles where !unique.contains(title) {
                unique.append(title)
            }
            return .insertList(ListSnapshot(id: ListID(), name: name, createdAt: now(), members: unique))
        }
    }
}

extension ImportService {
    // MARK: Helpers

    static func stats(_ rows: [PlannedRow]) -> ImportStats {
        ImportStats(
            created: rows.count { $0.outcome == .create },
            updated: rows.count { $0.outcome == .update },
            skipped: rows.count { $0.outcome == .skip },
            unmatched: rows.count { $0.outcome == .unmatched }
        )
    }

    static func rating(_ value: Double?) -> Double? {
        value.flatMap { try? Rating($0) }?.value
    }

    private static func summary(_ source: ImportSource, stats: ImportStats) -> String {
        let name = switch source {
        case .imdbCSV: "IMDb"
        case .letterboxdCSV: "Letterboxd"
        case .goodreadsCSV: "Goodreads"
        case .trakt: "Trakt"
        case .catList, .catICS: "Pogdesign CAT"
        }
        return "Imported \(stats.created) new and updated \(stats.updated) from \(name)"
    }

    private static func summary(of error: any Error) -> String {
        if let provider = error as? ProviderError {
            return "\(provider.provider) could not be reached while matching titles."
        }
        return "Matching stopped: \(String(describing: error).prefix(200))"
    }
}
