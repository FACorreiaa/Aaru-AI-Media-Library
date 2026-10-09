import AaruCore
import FluentSQL
import Foundation
import Logging
@testable import aaru

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
