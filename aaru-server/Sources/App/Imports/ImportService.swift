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
    /// Trakt connect and its reader. Nil when Trakt is not configured.
    var trakt: TraktImport?
    /// Public AniList lists (IMP-014). Nil when the catalog is a test fake.
    var anilistLists: (any AniListListReading)?
    /// Stremio's account API and Cinemeta, for history imports (IMP-016). Nil in most tests.
    var stremio: StremioAccount?
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
            rows = try Self.parse(text, source: source, filename: filename)
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

    /// Leases one job and plans it. Returns false when there was nothing to do. The worker passes
    /// no user; tests pass theirs so parallel suites never take each other's jobs.
    @discardableResult
    func runNext(for userID: UserID? = nil) async throws -> Bool {
        guard let claimed = try await stores.importJobs.claimNext(now: now(), lease: Self.lease, userID: userID)
        else { return false }
        var job = claimed.job
        do {
            var stored = try await stores.importJobs.rows(jobID: job.id)
            if stored.isEmpty, job.source == .trakt || job.source == .anilist {
                let fetched = job.source == .trakt ? try await fetchTrakt(&job) : try await fetchAniList(&job)
                guard let fetched else { return true }
                try await stores.importJobs.appendRows(fetched, jobID: job.id)
                stored = try await stores.importJobs.rows(jobID: job.id)
            }
            if job.source == .stremio {
                stored = try await expandStremioWatched(stored)
            }
            let rows = try await plan(stored, userID: job.userID)
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

    /// Goodreads custom shelves become lists: one per shelf name, reusing a list of that name.
    func listOps(_ members: [String: [TitleID]], userID: UserID) async throws -> [LibraryOp] {
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

    static func summary(_ source: ImportSource, stats: ImportStats) -> String {
        let name = switch source {
        case .imdbCSV: "IMDb"
        case .letterboxdCSV: "Letterboxd"
        case .goodreadsCSV: "Goodreads"
        case .trakt: "Trakt"
        case .stremio: "Stremio"
        case .catList, .catICS: "Pogdesign CAT"
        case .malXML: "MyAnimeList"
        case .anilist: "AniList"
        case .genericCSV: "CSV"
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

// MARK: Trakt (IMP-003)

extension ImportService {
    /// A Trakt import job. Its rows are read from Trakt by the worker, not now.
    func createTraktImport(userID: UserID) async throws -> ImportJob {
        guard let trakt, try await trakt.connect.status(userID: userID).connected else {
            throw AppError(status: .conflict, code: "trakt_not_connected", message: "Connect Trakt first.")
        }
        let job = ImportJob(userID: userID, source: .trakt, createdAt: now(), updatedAt: now())
        try await stores.importJobs.insert(job, rows: [])
        return job
    }

    /// Reads the user's Trakt library. A revoked connection fails the job at once (no retry) and
    /// forgets the dead tokens, so Settings shows "Connect Trakt" again. Trakt's account answers
    /// (420 over a limit, 423 locked) fail at once too: retrying gets the same answer.
    func fetchTrakt(_ job: inout ImportJob) async throws -> [ImportRow]? {
        let failure: String
        do {
            guard let trakt, let token = try await trakt.connect.accessToken(userID: job.userID) else {
                try await fail(&job, "Trakt is not connected. Connect it in Settings, then import again.")
                return nil
            }
            return try await trakt.importer.rows(token: token)
        } catch let error as ProviderError where error.kind == .unauthorized {
            try await stores.trakt.deleteConnection(userID: job.userID)
            failure = "Trakt access was revoked or expired. Connect Trakt again, then import."
        } catch let error as ProviderError where error.kind == .refused(420) {
            failure = "Your Trakt account is over one of Trakt's limits, so Trakt refused the import."
        } catch let error as ProviderError where error.kind == .refused(423) {
            failure = "Trakt has locked this account. Sort it out on trakt.tv, then import again."
        }
        try await fail(&job, failure)
        return nil
    }

    private func fail(_ job: inout ImportJob, _ summary: String) async throws {
        job.state = .failed
        job.errorSummary = summary
        job.updatedAt = now()
        try await stores.importJobs.update(job)
    }
}

/// What a Trakt import needs: the connection (for a fresh token) and the reader.
struct TraktImport: Sendable {
    var connect: TraktConnectService
    var importer: TraktImporter
}
