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
        database: env["POSTGRES_DATABASE"] ?? "hb"
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
    ListStore, ImportJobStore
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

    func saveEpisodes(_: TitleID, _: [CatalogEpisode], status _: TitleStatus?, hydratedAt _: Date) async throws {
        throw Touched()
    }

    func episodes(_: TitleID) async throws -> [CatalogEpisode] {
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

    func create(email _: String, tokenHash _: String, expiresAt _: Date) async throws {
        throw Touched()
    }

    func consume(tokenHash _: String, now _: Date) async throws -> String? {
        throw Touched()
    }

    func user(for _: AuthIdentity.Provider, subject _: String) async throws -> UserID? {
        throw Touched()
    }

    func insert(_: Title, status _: TitleStatus?, runtimeMinutes _: Int?) async throws {
        throw Touched()
    }

    func title(id _: TitleID) async throws -> Title? {
        throw Touched()
    }

    func insert(_: LibraryItem) async throws {
        throw Touched()
    }

    func item(id _: LibraryItemID, userID _: UserID) async throws -> LibraryItem? {
        throw Touched()
    }

    func create(_: AaruList) async throws {
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
        importJobs: untouched
    )
}

/// A date Postgres stores without loss (whole seconds).
func wholeSecondNow() -> Date {
    Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
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
    return try buildRouter(
        stores: stores,
        auth: AuthService(stores: stores, apple: UntouchedAppleVerifier(), magicLinks: nil),
        catalog: CatalogService(stores: stores, catalogs: FakeCatalog.providers(FakeCatalog()))
    )
}

/// Answers every outbound request with a canned response and counts calls.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    // @unchecked: test-only; `lock` guards every mutable field.
    private let lock = NSLock()
    private var handler: @Sendable (OutboundRequest) -> OutboundResponse
    private var recorded: [OutboundRequest] = []

    init(_ handler: @escaping @Sendable (OutboundRequest) -> OutboundResponse) {
        self.handler = handler
    }

    /// Changes the canned response for later requests.
    func respond(_ handler: @escaping @Sendable (OutboundRequest) -> OutboundResponse) {
        lock.withLock { self.handler = handler }
    }

    var requests: [OutboundRequest] {
        lock.withLock { recorded }
    }

    func send(_ request: OutboundRequest) async throws -> OutboundResponse {
        lock.withLock {
            recorded.append(request)
            return handler(request)
        }
    }
}

/// Runs raw SQL against the test database (assertions only; app code uses stores).
func withSQL<T>(_ body: (any SQLDatabase) async throws -> T) async throws -> T {
    var logger = Logger(label: "aaru-tests")
    logger.logLevel = .warning
    let fluent = try await makeFluent(testPostgresSettings(), logger: logger)
    do {
        guard let sql = fluent.db() as? any SQLDatabase else { throw MigrationNeedsSQL() }
        let result = try await body(sql)
        try await fluent.shutdown()
        return result
    } catch {
        try? await fluent.shutdown()
        throw error
    }
}

/// Every table with a `user_id` column (plus `users` itself), with the number of rows
/// that still reference `userID`. Empty means the user is gone everywhere.
func rowsReferencing(_ userID: UserID) async throws -> [String: Int] {
    struct Column: Decodable { let tableName: String }
    struct Count: Decodable { let count: Int }
    return try await withSQL { sql in
        let tables = try await sql.raw("""
        SELECT table_name FROM information_schema.columns
        WHERE table_schema = 'public' AND column_name = 'user_id'
        """).all(decoding: Column.self, keyDecodingStrategy: .convertFromSnakeCase).map(\.tableName)
        var counts: [String: Int] = [:]
        for table in tables + ["users"] {
            let column = table == "users" ? "id" : "user_id"
            let count = try await sql.raw("""
            SELECT count(*)::int AS count FROM \(ident: table) WHERE \(ident: column) = \(bind: userID.rawValue)
            """).first(decoding: Count.self)?.count ?? 0
            if count > 0 {
                counts[table] = count
            }
        }
        return counts
    }
}

/// A catalog provider with canned answers and call counts. Never reaches the network.
final class FakeCatalog: CatalogSearching, EpisodeListing, @unchecked Sendable {
    // @unchecked: test-only; `lock` guards every mutable field.
    private let lock = NSLock()
    private var searchResults: [String: [CatalogHit]] = [:]
    private var titles: [CatalogTitle] = []
    private var episodeLists: [String: CatalogEpisodes] = [:]
    private var calls: [String: Int] = [:]
    private var failure: (any Error)?

    static func providers(_ catalog: FakeCatalog) -> CatalogProviders {
        CatalogProviders(tmdb: catalog, anilist: catalog, openLibrary: catalog)
    }

    func fail(with error: (any Error)?) {
        lock.withLock { failure = error }
    }

    func stubSearch(_ query: String, _ hits: [CatalogHit]) {
        lock.withLock { searchResults[query] = hits }
    }

    func stubTitle(_ title: CatalogTitle) {
        lock.withLock { titles.append(title) }
    }

    /// Keyed by the show's tmdb or anilist id.
    func stubEpisodes(_ key: String, _ episodes: CatalogEpisodes) {
        lock.withLock { episodeLists[key] = episodes }
    }

    func callCount(_ name: String) -> Int {
        lock.withLock { calls[name, default: 0] }
    }

    private func record(_ name: String) throws {
        try lock.withLock {
            calls[name, default: 0] += 1
            if let failure {
                throw failure
            }
        }
    }

    func search(query: String, type _: AaruCore.MediaType) async throws -> [CatalogHit] {
        try record("search")
        return lock.withLock { searchResults[query] ?? [] }
    }

    func hydrate(ids: ExternalIDs, type: AaruCore.MediaType) async throws -> CatalogTitle? {
        try record("hydrate")
        // Simulate provider latency so concurrent resolutions overlap.
        try await Task.sleep(for: .milliseconds(5))
        return lock.withLock {
            titles.first { $0.hit.type == type && $0.hit.ids.matches(ids) }
        }
    }

    func episodes(ids: ExternalIDs) async throws -> CatalogEpisodes? {
        try record("episodes")
        return lock.withLock { ids.tmdb.flatMap { episodeLists[$0] } ?? ids.anilist.flatMap { episodeLists[$0] } }
    }
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
