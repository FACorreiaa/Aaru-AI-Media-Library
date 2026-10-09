import AaruCore
import Foundation
import Testing
@testable import aaru

/// Needs Postgres: `cd aaru-server && docker compose up -d`.
@Suite("Database (M1 migrations)", .serialized)
struct DatabaseTests {
    @Test("SRV-004: migrations are re-runnable")
    func migrationsRerun() async throws {
        try await withMigratedStores { _ in }
        try await withMigratedStores { _ in }
    }

    @Test("SRV-004: one identity maps to one user")
    func identityIsUnique() async throws {
        try await withMigratedStores { stores in
            let identity = AuthIdentity(provider: .apple, subject: UUID().uuidString, email: nil)
            let userID = try await stores.users.createUser(with: identity)
            #expect(try await stores.users.user(for: .apple, subject: identity.subject) == userID)
            await #expect(throws: StoreConflict.self) {
                _ = try await stores.users.createUser(with: identity)
            }
        }
    }

    @Test("SRV-005: a non-null external id is unique at the database level; nulls are not")
    func externalIDsAreUnique() async throws {
        try await withMigratedStores { stores in
            let tmdb = "srv005-\(UUID().uuidString)"
            try await stores.titles.insert(Title(type: .movie, title: "A", ids: ExternalIDs(tmdb: tmdb)))
            await #expect(throws: StoreConflict.self) {
                try await stores.titles.insert(Title(type: .movie, title: "B", ids: ExternalIDs(tmdb: tmdb)))
            }
            // TMDB numbers movies and shows separately.
            try await stores.titles.insert(Title(type: .show, title: "C", ids: ExternalIDs(tmdb: tmdb)))
            // Two titles with no tmdb id both insert.
            try await stores.titles.insert(Title(type: .movie, title: "D"))
            try await stores.titles.insert(Title(type: .movie, title: "D"))
        }
    }

    @Test("SRV-005: a title round-trips")
    func titleRoundTrip() async throws {
        try await withMigratedStores { stores in
            let title = Title(
                type: .show,
                title: "The Paper",
                year: 2025,
                posterURL: URL(string: "https://image.tmdb.org/t/p/w500/x.jpg"),
                ids: ExternalIDs(tmdb: "rt-\(UUID().uuidString)", imdb: "tt-\(UUID().uuidString)")
            )
            try await stores.titles.insert(title)
            #expect(try await stores.titles.title(id: title.id) == title)
        }
    }

    @Test("SRV-006: a second library item for the same user and title is rejected by the index")
    func libraryItemIsUnique() async throws {
        try await withMigratedStores { stores in
            let user = try await stores.users.createUser(with: .init(provider: .email, subject: UUID().uuidString))
            let title = Title(type: .movie, title: "Dune")
            try await stores.titles.insert(title)
            let item = try LibraryItem(
                userID: user,
                titleID: title.id,
                status: .wishlist,
                rating: Rating(8.5),
                addedAt: wholeSecondNow(),
                updatedAt: wholeSecondNow()
            )
            try await stores.library.insert(item)
            #expect(try await stores.library.item(id: item.id, userID: user) == item)
            await #expect(throws: StoreConflict.self) {
                try await stores.library.insert(LibraryItem(userID: user, titleID: title.id, status: .finished))
            }
            // Another user cannot read it.
            #expect(try await stores.library.item(id: item.id, userID: UserID()) == nil)
        }
    }

    @Test("SRV-006: lists keep member order and default to private")
    func listRoundTrip() async throws {
        try await withMigratedStores { stores in
            let user = try await stores.users.createUser(with: .init(provider: .email, subject: UUID().uuidString))
            let first = Title(type: .book, title: "Dune")
            let second = Title(type: .book, title: "Children of Dune")
            try await stores.titles.insert(first)
            try await stores.titles.insert(second)
            let list = AaruList(
                userID: user,
                name: "Arrakis",
                titleIDs: [second.id, first.id],
                createdAt: wholeSecondNow(),
                updatedAt: wholeSecondNow()
            )
            try await stores.lists.create(list)
            #expect(try await stores.lists.lists(userID: user) == [list])
        }
    }

    @Test("SRV-007: an import job round-trips without losing a field")
    func importJobRoundTrip() async throws {
        try await withMigratedStores { stores in
            let user = try await stores.users.createUser(with: .init(provider: .email, subject: UUID().uuidString))
            var job = ImportJob(
                userID: user,
                source: .letterboxdCSV,
                createdAt: wholeSecondNow(),
                updatedAt: wholeSecondNow()
            )
            try await stores.importJobs.insert(job)
            #expect(try await stores.importJobs.job(id: job.id, userID: user) == job)

            job.state = .partial
            job.stats = ImportStats(created: 3, updated: 1, skipped: 2, unmatched: 4)
            job.errorSummary = "4 rows unmatched"
            job.updatedAt = wholeSecondNow().addingTimeInterval(5)
            try await stores.importJobs.update(job)
            #expect(try await stores.importJobs.job(id: job.id, userID: user) == job)
        }
    }
}
