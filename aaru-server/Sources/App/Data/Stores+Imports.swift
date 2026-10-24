import AaruCore
import Foundation

/// A job the worker leased, and how many times it has been tried (this attempt included).
struct ClaimedImportJob: Sendable {
    var job: ImportJob
    var attempts: Int
}

protocol ImportJobStore: Sendable {
    func insert(_ job: ImportJob) async throws
    /// A new job with its parsed rows, in one transaction.
    func insert(_ job: ImportJob, rows: [ImportRow]) async throws
    /// Rows fetched by the worker (Trakt), for a job created without any.
    func appendRows(_ rows: [ImportRow], jobID: ImportJobID) async throws
    func update(_ job: ImportJob) async throws
    func job(id: ImportJobID, userID: UserID) async throws -> ImportJob?
    /// Newest first.
    func jobs(userID: UserID, limit: Int) async throws -> [ImportJob]
    /// Leases the oldest runnable job (JOB-001): queued and due, or `running` with an expired
    /// lease because its worker died. Two workers never lease the same job.
    /// `userID` keeps the claim to one user's jobs (tests running in parallel use it).
    func claimNext(now: Date, lease: TimeInterval, userID: UserID?) async throws -> ClaimedImportJob?
    /// Puts a failed attempt back in the queue, not before `notBefore`.
    func retry(_ id: ImportJobID, error: String, notBefore: Date, now: Date) async throws
    /// Hands a running job back to the queue at once without counting the attempt: the worker
    /// stopped (shutdown), the job did not fail.
    func release(_ id: ImportJobID, now: Date) async throws
    /// The worker's heartbeat while matching: rows matched so far, and a lease pushed forward so a
    /// long import is never taken for a dead one.
    func progress(_ id: ImportJobID, matched: Int, lockedUntil: Date) async throws
    func rows(jobID: ImportJobID) async throws -> [PlannedRow]
    /// Stores each row's outcome and the job's new state and stats, and releases the lease.
    func savePlan(_ job: ImportJob, rows: [PlannedRow]) async throws
    /// Removes a job and its rows. Library items it created stay; undo is the journal's job.
    func delete(id: ImportJobID, userID: UserID) async throws -> Bool
    /// A Stremio link code the user is approving (IMP-016). Expired ones are swept here.
    func createStremioLink(code: String, userID: UserID, expiresAt: Date, now: Date) async throws
    /// When the user's code stops being valid; nil when it is not theirs or is gone.
    func stremioLinkExpiry(code: String, userID: UserID) async throws -> Date?
    /// Single use: true when this call removed the code, so two polls never import twice.
    func consumeStremioLink(code: String, userID: UserID) async throws -> Bool
}

// Batched reads an import plan and the account export make once instead of per row. The
// defaults loop over the single-item calls, so stores without a batched query still conform.

/// One library item as an import sees it (IMP-004).
struct ImportItemState: Sendable, Equatable {
    var itemID: LibraryItemID
    /// `statusByHand` stays nil here, so a write built from these fields leaves the flag alone.
    var fields: ItemFields
    var statusByHand: Bool
    var watched: Set<EpisodeKey>
}

extension LibraryStore {
    /// Item by item, for stores without a batched read.
    func watched(itemIDs: [LibraryItemID]) async throws -> [LibraryItemID: Set<EpisodeKey>] {
        var result: [LibraryItemID: Set<EpisodeKey>] = [:]
        for id in itemIDs {
            result[id] = try await watched(itemID: id)
        }
        return result
    }

    /// Title by title, for stores without a batched read.
    func importStates(userID: UserID, titleIDs: [TitleID]) async throws -> [TitleID: ImportItemState] {
        var result: [TitleID: ImportItemState] = [:]
        for titleID in titleIDs {
            guard let item = try await item(userID: userID, titleID: titleID),
                  let entry = try await entry(id: item.id, userID: userID, now: Date())
            else { continue }
            result[titleID] = try await ImportItemState(
                itemID: item.id,
                fields: ItemFields(
                    status: item.status, rating: item.rating?.value, notes: item.notes, isOwned: item.isOwned,
                    finishedAt: item.finishedAt, bookPage: entry.bookProgress?.page,
                    bookPercent: entry.bookProgress?.percent, mangaChapter: entry.mangaProgress?.chapter,
                    mangaVolume: entry.mangaProgress?.volume
                ),
                statusByHand: statusSetByHand(itemID: item.id),
                watched: watched(itemID: item.id)
            )
        }
        return result
    }
}

extension AnimeMappingStore {
    /// Id by id, for stores without a batched read.
    func mappings(mal ids: [String]) async throws -> [String: AnimeMapping] {
        var result: [String: AnimeMapping] = [:]
        for id in Set(ids) {
            result[id] = try await mapping(mal: id)
        }
        return result
    }
}

extension ImportJobStore {
    /// For stores without a release: a retry due now (the attempt still counts).
    func release(_ id: ImportJobID, now: Date) async throws {
        try await retry(id, error: "Interrupted.", notBefore: now, now: now)
    }
}
