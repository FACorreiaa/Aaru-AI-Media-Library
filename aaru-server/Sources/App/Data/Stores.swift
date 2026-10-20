import AaruCore
import Foundation

// The data layer boundary (SRV-003). Request handlers see only these protocols;
// Fluent and SQL stay behind them. Methods arrive with the ticket that needs them —
// these are what the M1 migrations must prove, nothing speculative.

/// A write broke a uniqueness rule the database enforces.
struct StoreConflict: Error, Sendable {
    let message: String
}

/// How a user signed in. One user may have several.
struct AuthIdentity: Sendable, Hashable {
    enum Provider: String, Sendable {
        case apple
        case email
        case google
    }

    var provider: Provider
    var subject: String
    var email: String?
}

protocol DatabaseHealth: Sendable {
    /// True when the database answers a trivial query. Never throws, never leaks detail.
    func isReachable() async -> Bool
}

protocol UserStore: Sendable {
    /// Creates a user with its first identity, or throws `StoreConflict` if the identity exists.
    func createUser(with identity: AuthIdentity, displayName: String?) async throws -> UserID
    func user(for provider: AuthIdentity.Provider, subject: String) async throws -> UserID?
    /// Links another sign-in to an existing user. `StoreConflict` when it already belongs to someone.
    func addIdentity(_ identity: AuthIdentity, to user: UserID) async throws
    func profile(_ id: UserID) async throws -> UserProfile?
    /// Deletes the user and, by cascade, every row that belongs to them, plus the
    /// magic links sent to their email identities (AUTH-004).
    func deleteUser(_ id: UserID) async throws
}

struct UserProfile: Sendable, Equatable {
    var id: UserID
    var displayName: String?
    var providers: [AuthIdentity.Provider]
}

protocol SessionStore: Sendable {
    func create(userID: UserID, tokenHash: String, expiresAt: Date) async throws
    /// The session's user, or nil when the token is unknown or expired.
    func userID(forTokenHash tokenHash: String, now: Date) async throws -> UserID?
    func delete(tokenHash: String) async throws
}

protocol MagicLinkStore: Sendable {
    func create(email: String, tokenHash: String, codeHash: String, expiresAt: Date) async throws
    /// Atomically marks the link used and returns its email. Nil when the link is
    /// unknown, expired, or already used — a link signs in once.
    func consume(tokenHash: String, now: Date) async throws -> String?
    /// The same, by the emailed code. A wrong code counts against every live link for the
    /// email; a link with `maxAttempts` wrong codes no longer accepts its code.
    func consume(email: String, codeHash: String, maxAttempts: Int, now: Date) async throws -> Bool
}

protocol TitleStore: Sendable {
    /// Throws `StoreConflict` when another title already holds one of its external ids.
    func insert(_ title: Title, status: TitleStatus?, runtimeMinutes: Int?) async throws
    func title(id: TitleID) async throws -> Title?
    /// The title of this type holding any of these ids. TMDB/Trakt ids are type-scoped.
    func find(ids: ExternalIDs, type: MediaType) async throws -> Title?
    /// Fill-empty-only. An id another title already holds is skipped, never merged.
    func fillIDs(_ id: TitleID, from ids: ExternalIDs) async throws
    func catalogState(_ id: TitleID) async throws -> TitleCatalogState?
    /// Upserts episodes by (season, episode) and records the show's status and when it
    /// was hydrated. Never deletes: progress refers to episodes by number.
    func saveEpisodes(_ id: TitleID, _ fresh: CatalogEpisodes, hydratedAt: Date) async throws
    func episodes(_ id: TitleID) async throws -> [CatalogEpisode]
    /// The titles with these ids, in the order given; unknown ids are skipped.
    func titles(ids: [TitleID]) async throws -> [Title]
    /// Shows someone tracks (wishlist or in progress) whose episodes were never loaded or are
    /// past their staleness window, never-loaded first. Shows attempted since `retryAfter`
    /// are skipped so a failing provider is not hammered.
    func staleTrackedShows(now: Date, retryAfter: Date, limit: Int) async throws -> [TitleID]
    /// Records an episode refresh attempt, successful or not.
    func markEpisodesAttempted(_ id: TitleID, at: Date) async throws
}

extension TitleStore {
    func insert(_ title: Title) async throws {
        try await insert(title, status: nil, runtimeMinutes: nil)
    }
}

struct TitleCatalogState: Sendable, Equatable {
    var status: TitleStatus?
    var runtimeMinutes: Int?
    var episodesHydratedAt: Date?
}

/// A community mapping from an AniList entry to TMDB (CAT-009). Catalog data, no user.
struct AnimeMapping: Sendable, Equatable {
    var anilist: String
    var mal: String?
    var anidb: String?
    var tvdb: String?
    var tmdb: String?
    var tmdbSeason: Int?
}

protocol AnimeMappingStore: Sendable {
    func mapping(anilist: String) async throws -> AnimeMapping?
    func upsert(_ mapping: AnimeMapping) async throws
    /// Upserts in batches inside one transaction; re-running with the same rows changes nothing.
    func upsertMany(_ mappings: [AnimeMapping]) async throws
}

/// The library and its journal. Every write goes through `apply`, which runs the op,
/// records its inverse in `actions`, and commits both or neither (AUD-001, X-007).
protocol LibraryStore: Sendable {
    /// Applies `op` for `userID` in one transaction and journals its inverse.
    /// Throws `StoreConflict` on a duplicate (user, title) and `AppError.notFound` when an
    /// op names an item the user does not own.
    @discardableResult
    func apply(_ op: LibraryOp, userID: UserID, caller: Caller, kind: String, summary: String) async throws
        -> ActionRecord
    func item(id: LibraryItemID, userID: UserID) async throws -> LibraryItem?
    func item(userID: UserID, titleID: TitleID) async throws -> LibraryItem?
    func entry(id: LibraryItemID, userID: UserID, now: Date) async throws -> LibraryEntry?
    func entries(
        userID: UserID,
        filter: LibraryFilter,
        after: LibraryCursor?,
        limit: Int,
        now: Date
    ) async throws -> (entries: [LibraryEntry], next: LibraryCursor?)
    /// Items changed after `since` (all when nil), ids deleted after it, and the token to
    /// pass next time.
    func changes(userID: UserID, since: Date?, now: Date) async throws
        -> (entries: [LibraryEntry], deleted: [LibraryItemID])
    func watched(itemID: LibraryItemID) async throws -> Set<EpisodeKey>
    func actions(userID: UserID, limit: Int) async throws -> [ActionRecord]
    /// Applies the action's inverse and journals that as a new `undo` action. Throws
    /// `ActionConflict` if it was already undone or its target no longer matches.
    func undo(actionID: UUID, userID: UserID) async throws -> ActionRecord
}

extension LibraryStore {
    @discardableResult
    func apply(_ op: LibraryOp, userID: UserID, actor: Actor, kind: String, summary: String) async throws
        -> ActionRecord
    {
        try await apply(op, userID: userID, caller: Caller(actor: actor), kind: kind, summary: summary)
    }
}

/// List reads. List writes are `LibraryOp`s through `LibraryStore.apply`.
protocol ListStore: Sendable {
    func lists(userID: UserID) async throws -> [AaruList]
    func list(id: ListID, userID: UserID) async throws -> AaruList?
}

/// A shelf: a saved query over the library (SHF-001). Never membership (X-008).
struct Shelf: Sendable, Equatable {
    var id: UUID
    var name: String
    var filter: LibraryFilter
    var isPinned: Bool
    var createdAt: Date
}

protocol ShelfStore: Sendable {
    func shelves(userID: UserID) async throws -> [Shelf]
    func shelf(id: UUID, userID: UserID) async throws -> Shelf?
    func save(_ shelf: Shelf, userID: UserID) async throws
    func delete(id: UUID, userID: UserID) async throws -> Bool
}

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
    func rows(jobID: ImportJobID) async throws -> [PlannedRow]
    /// Stores each row's outcome and the job's new state and stats, and releases the lease.
    func savePlan(_ job: ImportJob, rows: [PlannedRow]) async throws
    /// Removes a job and its rows. Library items it created stay; undo is the journal's job.
    func delete(id: ImportJobID, userID: UserID) async throws -> Bool
}

/// A user's Trakt connection, tokens still sealed.
struct TraktConnectionRecord: Sendable, Equatable {
    var sealedAccessToken: String
    var sealedRefreshToken: String
    var expiresAt: Date
    var username: String?
    var connectedAt: Date
}

/// One PKCE sign-in in flight.
struct TraktAuthRequest: Sendable, Equatable {
    var userID: UserID
    var codeVerifier: String
    var returnTo: String
}

protocol TraktStore: Sendable {
    func createAuthRequest(stateHash: String, request: TraktAuthRequest, expiresAt: Date) async throws
    /// Single use: returns the request and deletes it. Nil when unknown or expired.
    func consumeAuthRequest(stateHash: String, now: Date) async throws -> TraktAuthRequest?
    func saveConnection(_ connection: TraktConnectionRecord, userID: UserID) async throws
    func connection(userID: UserID) async throws -> TraktConnectionRecord?
    func deleteConnection(userID: UserID) async throws
}

/// Which APNs gateway a device's token belongs to.
enum PushEnvironment: String, Codable, Sendable {
    case sandbox
    case production
}

struct PushDevice: Sendable, Equatable {
    var token: String
    var environment: PushEnvironment
    /// The app's bundle id: Release and Beta are separate topics.
    var topic: String
}

/// An episode that aired for a user who asked to hear about it, not yet announced.
struct DueAiring: Sendable, Equatable {
    var userID: UserID
    var titleID: TitleID
    var title: String
    var season: Int
    var episode: Int
    var episodeName: String?
}

protocol PushStore: Sendable {
    /// A token belongs to one user: registering it again moves it.
    func register(_ device: PushDevice, userID: UserID) async throws
    func unregister(token: String, userID: UserID) async throws
    /// Apple said the token is dead (uninstalled app, revoked permission).
    func forget(token: String) async throws
    func devices(userID: UserID) async throws -> [PushDevice]
    func airingEnabled(userID: UserID) async throws -> Bool
    /// Turning it on records when, so only episodes airing afterwards are announced.
    func setAiring(_ enabled: Bool, userID: UserID, now: Date) async throws
    /// Aired in `(since, now]`, for in-progress shows, not watched, not announced, user opted in.
    func dueAirings(now: Date, since: Date) async throws -> [DueAiring]
    /// Claims an announcement. False when another run already sent it.
    func claim(_ airing: DueAiring) async throws -> Bool
}

/// Everything handlers may touch, injected once at boot.
/// What an agent token may do (OUT-001). A token never has more than a signed-in session.
enum AgentScope: String, Codable, Sendable, CaseIterable {
    case libraryRead = "library:read"
    case libraryWrite = "library:write"
    case scrobbleWrite = "scrobble:write"
}

/// Which outside caller a token is for. Only Stremio exists until OUT-004.
enum AgentTokenKind: String, Codable, Sendable {
    case stremio
}

/// One agent token as its owner sees it. The secret is never stored, only its SHA-256.
struct AgentToken: Sendable, Equatable {
    var id: UUID
    var name: String
    var kind: AgentTokenKind
    var scopes: Set<AgentScope>
    var createdAt: Date
    var lastUsedAt: Date?
}

protocol AgentTokenStore: Sendable {
    func create(_ token: AgentToken, tokenHash: String, userID: UserID) async throws
    /// Tokens not revoked, newest first.
    func tokens(userID: UserID) async throws -> [AgentToken]
    /// True when the user's token existed and was live.
    func revoke(id: UUID, userID: UserID, now: Date) async throws -> Bool
    /// The live token with this hash and its owner; nil when unknown, revoked or expired.
    func token(forHash hash: String, now: Date) async throws -> (token: AgentToken, userID: UserID)?
    func touch(id: UUID, at: Date) async throws
}

struct Stores: Sendable {
    var health: any DatabaseHealth
    var users: any UserStore
    var sessions: any SessionStore
    var magicLinks: any MagicLinkStore
    var titles: any TitleStore
    var animeMappings: any AnimeMappingStore
    var library: any LibraryStore
    var lists: any ListStore
    var shelves: any ShelfStore
    var schedule: any ScheduleStore
    var stats: any StatsStore
    var importJobs: any ImportJobStore
    var trakt: any TraktStore
    var push: any PushStore
    var agentTokens: any AgentTokenStore
    var watchEvents: any WatchEventStore
}
