import AaruCore
import Foundation

// MARK: Listening history (MUS-004)

/// A listening import's plays wait in `import_listens` until the user applies them, then go to the
/// listening log as `import` listens of the job. A listen is not a library write, so nothing is
/// journaled: undoing the job deletes its listens. They count in Insights and the Recap on their
/// own day, earn no points, and count toward music badges (decisions 2026-10-27).
extension ImportService {
    /// A Spotify history file holds years of plays; library exports stay at 5 MB.
    static let maxListenUploadBytes = 24 * 1024 * 1024
    /// One listening file is parsed at a time, so two large uploads never share the server's memory.
    static let listenFileGate = SerialGate()

    /// Parses the file now and stages its plays; the worker counts which are new.
    func createListenFileImport(userID: UserID, source: ImportSource?, filename: String?, data: Data) async throws
        -> ImportJob
    {
        let page: ListenHistoryPage
        let resolved: ImportSource
        do {
            (resolved, page) = try await Self.listenFileGate.run {
                let resolved = try source ?? ListenFileDetector.detect(data)
                return try (resolved, ListenFileDetector.parse(data, source: resolved, now: now()))
            }
        } catch let error as ImportFormatError {
            throw Self.invalid(["file": error.message])
        }
        guard !page.listens.isEmpty else {
            throw Self.invalid(["file": "That file has no music plays to import."])
        }
        let job = ImportJob(
            userID: userID, source: resolved, stats: ImportStats(ignored: page.ignored), filename: filename,
            createdAt: now(), updatedAt: now(), rowsTotal: page.listens.count
        )
        try await stores.importJobs.insert(job)
        try await stores.listens.stage(page.listens, jobID: job.id, from: 0)
        return job
    }

    /// A Last.fm or ListenBrainz import job. The worker reads the account; the username is kept in
    /// the job's `filename`, which is what the import list shows.
    func createListenAccountImport(userID: UserID, source: ImportSource, username: String) async throws -> ImportJob {
        guard listenHistory[source] != nil else {
            throw AppError(
                status: .serviceUnavailable, code: "\(source.rawValue)_unavailable",
                message: "\(source.displayName) import is not set up on this server yet."
            )
        }
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: ["@"])
        let control = name.contains { $0.isNewline || $0.asciiValue.map { $0 < 32 } == true }
        guard (1 ... 64).contains(name.count), !control else {
            throw Self.invalid(["username": "Enter your \(source.displayName) username."])
        }
        let job = ImportJob(userID: userID, source: source, filename: name, createdAt: now(), updatedAt: now())
        try await stores.importJobs.insert(job)
        return job
    }

    /// The worker's plan for a listening import: an account is read into staging first, renewing
    /// the lease each page; then the staged plays are split into new and already in the log.
    /// Always true: the job was worked on.
    func planListens(_ job: inout ImportJob) async throws -> Bool {
        defer { Self.count(job) }
        if job.source == .lastFM || job.source == .listenBrainz {
            guard try await fetchListens(&job) else { return true }
        }
        guard job.rowsTotal > 0 else {
            try await fail(&job, "That import has no plays left. Import the file again.")
            return true
        }
        let fresh = try await stores.listens.countNew(jobID: job.id, userID: job.userID)
        job.stats.created = fresh
        job.stats.skipped = job.rowsTotal - fresh
        job.state = .planned
        job.errorSummary = nil
        job.updatedAt = now()
        try await stores.importJobs.progress(
            job.id, matched: job.rowsTotal, lockedUntil: now().addingTimeInterval(Self.lease)
        )
        try await stores.importJobs.update(job)
        return true
    }

    /// Reads the account's history into staging. False when the job failed for good: an unknown
    /// user, private listening, or nothing to read.
    private func fetchListens(_ job: inout ImportJob) async throws -> Bool {
        let service = job.source.displayName
        guard let reader = listenHistory[job.source], let name = job.filename else {
            try await fail(&job, "\(service) import is not available right now.")
            return false
        }
        let jobID = job.id
        try await stores.listens.clearStaged(jobID: jobID)
        let since = try await stores.listens.newestImported(userID: job.userID, source: job.source, account: name)
        var staged = 0
        var ignored = 0
        do {
            try await reader.read(user: name, since: since, now: now()) { page in
                try await stores.listens.stage(page.listens, jobID: jobID, from: staged)
                staged += page.listens.count
                ignored += page.ignored
                try await stores.importJobs.progress(
                    jobID, matched: staged, lockedUntil: now().addingTimeInterval(Self.lease)
                )
            }
        } catch let error as ProviderError where error.kind == .notFound {
            try await fail(&job, "\(service) has no user “\(name)”. Check the username, then import again.")
            return false
        } catch let error as ProviderError where error.kind == .refused(LastFMHistory.privateListening) {
            try await fail(
                &job,
                "\(name) hides their recent listening on Last.fm. Turn off “Hide recent listening” in Last.fm's "
                    + "privacy settings, then import again."
            )
            return false
        }
        guard staged > 0 else {
            try await fail(
                &job, since == nil ? "\(name) has no listens on \(service) yet." :
                    "Nothing new on \(service) since your last import of \(name)."
            )
            return false
        }
        job.rowsTotal = staged
        job.stats.ignored = ignored
        return true
    }

    /// Writes the new plays to the listening log. No points, however recent: a backlog is not a
    /// day's listening.
    func applyListens(_ job: ImportJob) async throws -> ImportJob {
        var job = job
        let written = try await stores.listens.applyStaged(jobID: job.id, userID: job.userID)
        job.stats.created = written
        job.stats.skipped = max(0, job.rowsTotal - written)
        job.state = .succeeded
        job.updatedAt = now()
        try await stores.importJobs.update(job)
        await GamificationService(stores: stores, now: now).listensImported(job.userID)
        return job
    }

    /// Undoes an applied listening import in one step: its listens, the music badges only they held,
    /// and the job itself go.
    func undoListens(_ id: ImportJobID, userID: UserID) async throws {
        guard let job = try await stores.importJobs.job(id: id, userID: userID) else { throw AppError.notFound() }
        guard job.source.isListens else {
            throw AppError(
                status: .conflict, code: "import_not_listens",
                message: "This import changed your library. Undo it from its action instead."
            )
        }
        guard job.state == .succeeded else {
            throw AppError(
                status: .conflict, code: "import_not_applied",
                message: "This import was not applied, so there is nothing to undo. Delete it instead."
            )
        }
        _ = try await stores.listens.deleteImported(jobID: id, userID: userID)
        _ = try await stores.importJobs.delete(id: id, userID: userID)
        await GamificationService(stores: stores, now: now).listensUndone(userID)
    }

    private static func invalid(_ details: [String: String]) -> AppError {
        AppError(
            status: .unprocessableContent, code: "validation_failed",
            message: details.values.sorted().joined(separator: " "), details: details
        )
    }
}

/// Lets one caller at a time through; the rest wait their turn, first come first served.
actor SerialGate {
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func run<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        await enter()
        defer { leave() }
        return try await body()
    }

    private func enter() async {
        guard busy else {
            busy = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func leave() {
        if waiting.isEmpty {
            busy = false
        } else {
            waiting.removeFirst().resume()
        }
    }
}
