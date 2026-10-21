import Foundation

/// Where an import's rows came from.
///
/// The declaration order is the merge order: when a user connects several sources,
/// apply them in this order and let later sources fill only empty fields.
public enum ImportSource: String, Codable, Hashable, Sendable, CaseIterable {
    case trakt
    /// A Stremio account's library and watch history, read once through a link code (IMP-016).
    case stremio
    case imdbCSV = "imdb_csv"
    case letterboxdCSV = "letterboxd_csv"
    case goodreadsCSV = "goodreads_csv"
    case catList = "cat_list"
    case catICS = "cat_ics"
    /// Netflix's viewing activity download, one profile (IMP-018). Names only, so after every
    /// source that carries ids.
    case netflixCSV = "netflix_csv"
    /// One CSV from TV Time's export, the in-app one or the GDPR one (IMP-012).
    case tvTimeCSV = "tvtime_csv"
    /// MyAnimeList's XML list export (IMP-013).
    case malXML = "mal_xml"
    /// A public AniList list, read by username (IMP-014).
    case anilist
    /// Any other site's CSV, read by its column names. Last in the merge order: it fills gaps only.
    case genericCSV = "csv"

    /// Position in the merge order, lowest first.
    public var mergeRank: Int {
        ImportSource.allCases.firstIndex(of: self) ?? ImportSource.allCases.count
    }
}

/// Lifecycle of one import run.
public enum ImportJobState: String, Codable, Hashable, Sendable, CaseIterable {
    case queued
    case running
    /// Rows are matched and a plan is ready; nothing is written until the user approves it.
    case planned
    case succeeded
    case failed
    /// Finished, but some rows could not be matched.
    case partial

    public var isTerminal: Bool {
        switch self {
        case .queued, .running, .planned: false
        case .succeeded, .failed, .partial: true
        }
    }
}

/// What an import run did. Unmatched rows are counted, never silently dropped.
public struct ImportStats: Codable, Hashable, Sendable {
    public var created: Int
    public var updated: Int
    public var skipped: Int
    public var unmatched: Int

    public init(created: Int = 0, updated: Int = 0, skipped: Int = 0, unmatched: Int = 0) {
        self.created = created
        self.updated = updated
        self.skipped = skipped
        self.unmatched = unmatched
    }

    public var total: Int {
        created + updated + skipped + unmatched
    }
}

/// One run of a Trakt, CSV, or CAT ingest.
///
/// Imports are one-way into Aaru. Re-running an import updates in place via
/// `(userID, titleID)`; it does not duplicate items.
public struct ImportJob: Codable, Hashable, Sendable, Identifiable {
    public var id: ImportJobID
    public var userID: UserID
    public var source: ImportSource
    public var state: ImportJobState
    public var stats: ImportStats
    public var errorSummary: String?
    /// The uploaded file's name, for file imports. The file itself is never kept.
    public var filename: String?
    public var createdAt: Date
    public var updatedAt: Date
    /// The rows read from the file or provider, and how many the worker has matched so far.
    public var rowsTotal: Int
    public var rowsMatched: Int

    public init(
        id: ImportJobID = ImportJobID(),
        userID: UserID,
        source: ImportSource,
        state: ImportJobState = .queued,
        stats: ImportStats = ImportStats(),
        errorSummary: String? = nil,
        filename: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        rowsTotal: Int = 0,
        rowsMatched: Int = 0
    ) {
        self.id = id
        self.userID = userID
        self.source = source
        self.state = state
        self.stats = stats
        self.errorSummary = errorSummary
        self.filename = filename
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.rowsTotal = rowsTotal
        self.rowsMatched = rowsMatched
    }
}
