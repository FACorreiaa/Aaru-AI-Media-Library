import AaruCore
import Foundation
import Testing
@testable import aaru

@Suite("Show episode refresh (JOB-001 refresh kind)", .serialized)
struct CatalogRefreshTests {
    static let day: TimeInterval = 86400

    private struct TitleRow: Decodable {
        let titleId: UUID
    }

    private struct StateRow: Decodable {
        let episodesHydratedAt: Date?
        let episodesAttemptedAt: Date?
    }

    private func titleID(_ itemID: String) async throws -> TitleID {
        try await withSQL { sql in
            let row = try await sql
                .raw("SELECT title_id FROM library_items WHERE id = \(bind: UUID(uuidString: itemID)!)")
                .first(decoding: TitleRow.self, keyDecodingStrategy: .convertFromSnakeCase)
            return try TitleID(#require(row).titleId)
        }
    }

    private func setState(_ id: TitleID, hydratedAt: Date?, attemptedAt: Date? = nil) async throws {
        try await withSQL { sql in
            try await sql.raw("""
            UPDATE titles SET episodes_hydrated_at = \(bind: hydratedAt), episodes_attempted_at = \(bind: attemptedAt)
            WHERE id = \(bind: id.rawValue)
            """).run()
        }
    }

    private func state(_ id: TitleID) async throws -> StateRow {
        try await withSQL { sql in
            try #require(try await sql.raw("""
            SELECT episodes_hydrated_at, episodes_attempted_at FROM titles WHERE id = \(bind: id.rawValue)
            """).first(decoding: StateRow.self, keyDecodingStrategy: .convertFromSnakeCase))
        }
    }

    @Test("A pass loads never-loaded shows, refreshes stale ones, skips fresh ones and backs off on failure")
    func pass() async throws {
        try await LibraryHarness.run { env in
            let now = Date()
            let fresh = try await titleID(env.add("show", tmdb: env.stubShow("Fresh", status: .ended)))
            let stale = try await titleID(env.add("show", tmdb: env.stubShow("Stale", status: .ended)))
            let imported = try await titleID(env.add("show", tmdb: env.stubShow("Imported", status: .ended)))
            let gone = try await titleID(env.add("show", tmdb: env.stubShow("Gone", status: .ended)))
            let dropped = try await titleID(env.add(
                "show",
                tmdb: env.stubShow("Dropped", status: .ended),
                status: "dropped"
            ))
            try await setState(stale, hydratedAt: now.addingTimeInterval(-40 * Self.day))
            try await setState(imported, hydratedAt: nil)
            try await setState(dropped, hydratedAt: nil)
            // Its last refresh attempt failed ten minutes ago.
            try await setState(
                gone,
                hydratedAt: now.addingTimeInterval(-40 * Self.day),
                attemptedAt: now.addingTimeInterval(-600)
            )

            let due = try await env.stores.titles.staleTrackedShows(
                now: now, retryAfter: now.addingTimeInterval(-CatalogRefresher.retryAfter), limit: 100_000
            )
            #expect(due.contains(stale) && due.contains(imported))
            #expect(!due.contains(gone), "attempted within the hour: backs off")
            #expect(!due.contains(fresh), "inside its window")
            #expect(!due.contains(dropped), "not tracked")
            #expect(try #require(due.firstIndex(of: imported)) < due.firstIndex(of: stale)!, "never-loaded first")

            var refresher = CatalogRefresher(
                stores: env.stores,
                catalog: CatalogService(stores: env.stores, catalogs: FakeCatalog.providers(env.fake))
            )
            refresher.now = { now }
            refresher.passLimit = 100_000
            _ = try await refresher.runOnce()

            #expect(try await state(imported).episodesHydratedAt != nil)
            #expect(try await env.stores.titles.episodes(imported).count == 6)
            #expect(try await state(stale).episodesHydratedAt! > now.addingTimeInterval(-Self.day))
            #expect(try await state(imported).episodesAttemptedAt == now, "every attempt is stamped")

            let again = try await env.stores.titles.staleTrackedShows(
                now: now, retryAfter: now.addingTimeInterval(-CatalogRefresher.retryAfter), limit: 100_000
            )
            #expect(!again.contains(imported) && !again.contains(stale))
            let later = now.addingTimeInterval(CatalogRefresher.retryAfter)
            let afterBackoff = try await env.stores.titles.staleTrackedShows(
                now: later, retryAfter: later.addingTimeInterval(-CatalogRefresher.retryAfter), limit: 100_000
            )
            #expect(afterBackoff.contains(gone), "retried once the hour is up")
        }
    }

    @Test("A show with an episode airing within 30 days is stale after a day")
    func airingWindow() async throws {
        try await LibraryHarness.run { env in
            let now = Date()
            let airing = try await titleID(env.add("show", tmdb: env.stubShow(
                "Airing", status: .returning, unaired: true, now: now
            )))
            try await setState(airing, hydratedAt: now.addingTimeInterval(-2 * Self.day))
            let due = try await env.stores.titles.staleTrackedShows(
                now: now, retryAfter: now.addingTimeInterval(-CatalogRefresher.retryAfter), limit: 100_000
            )
            #expect(due.contains(airing))
        }
    }
}
