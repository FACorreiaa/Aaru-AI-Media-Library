import AaruCore
import Configuration
import Foundation
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

/// Runs `body` against a migrated test database, then shuts Fluent down.
func withMigratedStores<T>(_ body: (Stores) async throws -> T) async throws -> T {
    var logger = Logger(label: "aaru-tests")
    logger.logLevel = .warning
    let fluent = try await makeFluent(testPostgresSettings(), logger: logger)
    do {
        try await fluent.migrate()
        let result = try await body(Stores.postgres(fluent.db()))
        try await fluent.shutdown()
        return result
    } catch {
        try? await fluent.shutdown()
        throw error
    }
}

/// A store that must not be touched by the test using it.
struct UntouchedStore: UserStore, TitleStore, LibraryStore, ListStore, ImportJobStore {
    struct Touched: Error {}

    func createUser(with _: AuthIdentity) async throws -> UserID {
        throw Touched()
    }

    func user(for _: AuthIdentity.Provider, subject _: String) async throws -> UserID? {
        throw Touched()
    }

    func insert(_: Title) async throws {
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
        titles: untouched,
        library: untouched,
        lists: untouched,
        importJobs: untouched
    )
}

/// A date Postgres stores without loss (whole seconds).
func wholeSecondNow() -> Date {
    Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
}
