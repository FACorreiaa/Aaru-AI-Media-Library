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
    func create(email: String, tokenHash: String, expiresAt: Date) async throws
    /// Atomically marks the link used and returns its email. Nil when the link is
    /// unknown, expired, or already used — a link signs in once.
    func consume(tokenHash: String, now: Date) async throws -> String?
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
    func saveEpisodes(_ id: TitleID, _ episodes: [CatalogEpisode], status: TitleStatus?, hydratedAt: Date) async throws
    func episodes(_ id: TitleID) async throws -> [CatalogEpisode]
    /// The titles with these ids, in the order given; unknown ids are skipped.
    func titles(ids: [TitleID]) async throws -> [Title]
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
}

/// The library and its journal. Every write goes through `apply`, which runs the op,
/// records its inverse in `actions`, and commits both or neither (AUD-001, X-007).
protocol LibraryStore: Sendable {
    /// Applies `op` for `userID` in one transaction and journals its inverse.
    /// Throws `StoreConflict` on a duplicate (user, title) and `AppError.notFound` when an
    /// op names an item the user does not own.
    @discardableResult
    func apply(_ op: LibraryOp, userID: UserID, actor: Actor, kind: String, summary: String) async throws
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

protocol ImportJobStore: Sendable {
    func insert(_ job: ImportJob) async throws
    func update(_ job: ImportJob) async throws
    func job(id: ImportJobID, userID: UserID) async throws -> ImportJob?
}

/// Everything handlers may touch, injected once at boot.
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
    var importJobs: any ImportJobStore
}
