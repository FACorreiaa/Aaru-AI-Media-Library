import AaruCore
import Configuration
import FluentSQL
import Foundation
import Hummingbird
import Logging
@testable import aaru

/// Postgres settings for tests: the docker-compose database unless overridden by env.
func testPostgresSettings() -> PostgresSettings {
    let env = ProcessInfo.processInfo.environment
    return PostgresSettings(
        host: env["POSTGRES_HOST"] ?? "127.0.0.1",
        port: env["POSTGRES_PORT"].flatMap(Int.init) ?? 5432,
        user: env["POSTGRES_USER"] ?? "hb",
        password: env["POSTGRES_PASSWORD"] ?? "testing123",
        database: env["POSTGRES_DATABASE"] ?? "hb",
        // Suites run in parallel and each opens its own pool: production's 10 per pool ran CI's
        // Postgres out of connections ("too many clients already") once the suite grew.
        poolSize: 2
    )
}

/// Migrates the test database once per test process. Suites run in parallel, and
/// concurrent `migrate()` calls race on the schema.
actor TestMigrations {
    static let shared = TestMigrations()
    private var done: Task<Void, any Error>?

    func ensureMigrated() async throws {
        if done == nil {
            done = Task {
                var logger = Logger(label: "aaru-tests")
                logger.logLevel = .warning
                let fluent = try await makeFluent(testPostgresSettings(), logger: logger)
                do {
                    try await fluent.migrate()
                    try await fluent.shutdown()
                } catch {
                    try? await fluent.shutdown()
                    throw error
                }
            }
        }
        try await done?.value
    }
}

/// Runs `body` against a migrated test database, then shuts Fluent down.
func withMigratedStores<T>(_ body: (Stores) async throws -> T) async throws -> T {
    try await TestMigrations.shared.ensureMigrated()
    var logger = Logger(label: "aaru-tests")
    logger.logLevel = .warning
    let fluent = try await makeFluent(testPostgresSettings(), logger: logger)
    do {
        let result = try await body(Stores.postgres(fluent.db()))
        try await fluent.shutdown()
        return result
    } catch {
        try? await fluent.shutdown()
        throw error
    }
}

/// A store that must not be touched by the test using it.
struct UntouchedStore: UserStore, SessionStore, MagicLinkStore, TitleStore, AnimeMappingStore, LibraryStore,
    ListStore, ShelfStore, ScheduleStore, ImportJobStore, TraktStore
{
    func find(ids _: ExternalIDs, type _: AaruCore.MediaType) async throws -> Title? {
        throw Touched()
    }

    func fillIDs(_: TitleID, from _: ExternalIDs) async throws {
        throw Touched()
    }

    func catalogState(_: TitleID) async throws -> TitleCatalogState? {
        throw Touched()
    }

    func saveEpisodes(_: TitleID, _: CatalogEpisodes, hydratedAt _: Date) async throws {
        throw Touched()
    }

    func episodes(_: TitleID) async throws -> [CatalogEpisode] {
        throw Touched()
    }

    func saveTracks(_: TitleID, _: [AlbumTrack], hydratedAt _: Date) async throws {
        throw Touched()
    }

    func tracks(_: TitleID) async throws -> [AlbumTrack] {
        throw Touched()
    }

    func mapping(anilist _: String) async throws -> AnimeMapping? {
        throw Touched()
    }

    func upsert(_: AnimeMapping) async throws {
        throw Touched()
    }

    struct Touched: Error {}

    func createUser(with _: AuthIdentity, displayName _: String?) async throws -> UserID {
        throw Touched()
    }

    func profile(_: UserID) async throws -> UserProfile? {
        throw Touched()
    }

    func deleteUser(_: UserID) async throws {
        throw Touched()
    }

    func count() async throws -> Int {
        throw Touched()
    }

    func create(userID _: UserID, tokenHash _: String, expiresAt _: Date) async throws {
        throw Touched()
    }

    /// Anonymous: no session resolves, so contract tests see the 401 path.
    func userID(forTokenHash _: String, now _: Date) async throws -> UserID? {
        nil
    }

    func delete(tokenHash _: String) async throws {
        throw Touched()
    }

    func create(email _: String, tokenHash _: String, codeHash _: String, expiresAt _: Date) async throws {
        throw Touched()
    }

    func consume(email _: String, codeHash _: String, maxAttempts _: Int, now _: Date) async throws -> Bool {
        throw Touched()
    }

    func consume(tokenHash _: String, now _: Date) async throws -> String? {
        throw Touched()
    }

    func user(for _: AuthIdentity.Provider, subject _: String) async throws -> UserID? {
        throw Touched()
    }

    func addIdentity(_: AuthIdentity, to _: UserID) async throws {
        throw Touched()
    }

    func insert(_: Title, status _: TitleStatus?, runtimeMinutes _: Int?, genres _: [String]) async throws {
        throw Touched()
    }

    func title(id _: TitleID) async throws -> Title? {
        throw Touched()
    }

    func item(id _: LibraryItemID, userID _: UserID) async throws -> LibraryItem? {
        throw Touched()
    }

    func item(userID _: UserID, titleID _: TitleID) async throws -> LibraryItem? {
        throw Touched()
    }

    func entry(id _: LibraryItemID, userID _: UserID, now _: Date) async throws -> LibraryEntry? {
        throw Touched()
    }

    func entries(userID _: UserID, filter _: LibraryFilter, after _: LibraryCursor?, limit _: Int, now _: Date)
        async throws -> (entries: [LibraryEntry], next: LibraryCursor?)
    {
        throw Touched()
    }

    func changes(userID _: UserID, since _: Date?, now _: Date) async throws
        -> (entries: [LibraryEntry], deleted: [LibraryItemID])
    {
        throw Touched()
    }

    func watched(itemID _: LibraryItemID) async throws -> Set<EpisodeKey> {
        throw Touched()
    }

    func actions(userID _: UserID, limit _: Int) async throws -> [ActionRecord] {
        throw Touched()
    }

    func undo(actionID _: UUID, userID _: UserID) async throws -> ActionRecord {
        throw Touched()
    }

    func list(id _: ListID, userID _: UserID) async throws -> AaruList? {
        throw Touched()
    }

    func titles(ids _: [TitleID]) async throws -> [Title] {
        throw Touched()
    }

    func calendar(userID _: UserID, from _: Date, until _: Date, now _: Date) async throws -> [CalendarEntry] {
        throw Touched()
    }

    func continueWatching(userID _: UserID, now _: Date, limit _: Int) async throws -> [ContinueEntry] {
        throw Touched()
    }

    func startWatching(userID _: UserID, limit _: Int) async throws -> [StartEntry] {
        throw Touched()
    }

    func unhydratedTrackedShows(userID _: UserID, limit _: Int) async throws -> [TitleID] {
        throw Touched()
    }

    func shelves(userID _: UserID) async throws -> [Shelf] {
        throw Touched()
    }

    func shelf(id _: UUID, userID _: UserID) async throws -> Shelf? {
        throw Touched()
    }

    func save(_: Shelf, userID _: UserID) async throws {
        throw Touched()
    }

    func delete(id _: UUID, userID _: UserID) async throws -> Bool {
        throw Touched()
    }

    func lists(userID _: UserID) async throws -> [AaruList] {
        throw Touched()
    }

    func insert(_: ImportJob) async throws {
        throw Touched()
    }

    func update(_: ImportJob) async throws {
        throw Touched()
    }

    func job(id _: ImportJobID, userID _: UserID) async throws -> ImportJob? {
        throw Touched()
    }

    func insert(_: ImportJob, rows _: [ImportRow]) async throws {
        throw Touched()
    }

    func jobs(userID _: UserID, limit _: Int) async throws -> [ImportJob] {
        throw Touched()
    }

    func claimNext(now _: Date, lease _: TimeInterval, userID _: UserID?) async throws -> ClaimedImportJob? {
        throw Touched()
    }

    func retry(_: ImportJobID, error _: String, notBefore _: Date, now _: Date) async throws {
        throw Touched()
    }

    func progress(_: ImportJobID, matched _: Int, lockedUntil _: Date) async throws {
        throw Touched()
    }

    func rows(jobID _: ImportJobID) async throws -> [PlannedRow] {
        throw Touched()
    }

    func savePlan(_: ImportJob, rows _: [PlannedRow]) async throws {
        throw Touched()
    }

    func delete(id _: ImportJobID, userID _: UserID) async throws -> Bool {
        throw Touched()
    }

    func appendRows(_: [ImportRow], jobID _: ImportJobID) async throws {
        throw Touched()
    }

    func createAuthRequest(stateHash _: String, request _: TraktAuthRequest, expiresAt _: Date) async throws {
        throw Touched()
    }

    func consumeAuthRequest(stateHash _: String, now _: Date) async throws -> TraktAuthRequest? {
        throw Touched()
    }

    func saveConnection(_: TraktConnectionRecord, userID _: UserID) async throws {
        throw Touched()
    }

    func connection(userID _: UserID) async throws -> TraktConnectionRecord? {
        throw Touched()
    }

    func deleteConnection(userID _: UserID) async throws {
        throw Touched()
    }
}

struct FixedHealth: DatabaseHealth {
    let reachable: Bool
    func isReachable() async -> Bool {
        reachable
    }
}

/// Stores with no database behind them; only `health` answers.
func fakeStores(databaseReachable: Bool = true) -> Stores {
    let untouched = UntouchedStore()
    return Stores(
        health: FixedHealth(reachable: databaseReachable),
        users: untouched,
        sessions: untouched,
        magicLinks: untouched,
        titles: untouched,
        animeMappings: untouched,
        library: untouched,
        lists: untouched,
        shelves: untouched,
        schedule: untouched,
        stats: untouched,
        importJobs: untouched,
        trakt: untouched,
        push: untouched,
        agentTokens: untouched,
        watchEvents: untouched,
        listens: untouched,
        plans: untouched,
        oauth: untouched,
        social: untouched,
        friendViews: untouched,
        interactions: untouched,
        groups: untouched,
        groupKinds: untouched,
        agent: untouched,
        concerts: untouched,
        gamification: untouched,
        tonight: untouched
    )
}

/// An Apple verifier that must not be called.
struct UntouchedAppleVerifier: AppleIdentityVerifying {
    func verify(identityToken _: String, rawNonce _: String) async throws -> AppleIdentity {
        throw UntouchedStore.Touched()
    }
}

/// Router over fake stores, for contract tests that need no database.
func fakeRouter(databaseReachable: Bool = true) throws -> Router<AppRequestContext> {
    let stores = fakeStores(databaseReachable: databaseReachable)
    let auth = AuthService(stores: stores, apple: UntouchedAppleVerifier(), magicLinks: nil)
    return try buildRouter(
        stores: stores,
        services: Services.make(stores: stores, catalogs: FakeCatalog.providers(FakeCatalog()), auth: auth)
    )
}

/// A unique-per-test external id, so tests sharing one database never collide.
func uniqueID(_ prefix: String = "t") -> String {
    "\(prefix)-\(UUID().uuidString.prefix(12))"
}

/// A user with a live session in the test database, for HTTP tests behind auth.
func signedInUser(_ stores: Stores) async throws -> (UserID, token: String) {
    let user = try await stores.users.createUser(
        with: AuthIdentity(provider: .email, subject: "\(UUID().uuidString)@test"),
        displayName: nil
    )
    let token = OpaqueToken.generate()
    try await stores.sessions.create(
        userID: user,
        tokenHash: OpaqueToken.hash(token),
        expiresAt: Date().addingTimeInterval(3600)
    )
    return (user, token)
}
