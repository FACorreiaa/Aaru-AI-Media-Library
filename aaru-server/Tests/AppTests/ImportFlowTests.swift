import AaruCore
import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
@testable import aaru

/// IMP-001/004/005 and JOB-001 end to end: upload, plan in the worker, approve, undo.
@Suite("Imports", .serialized)
struct ImportFlowTests {
    func upload(
        _ env: LibraryHarness,
        _ csv: String,
        source: String,
        filename: String = "export.csv"
    ) async throws -> LibraryHarness.Reply {
        try await env.client.execute(
            uri: "/v1/imports/csv?source=\(source)&filename=\(filename)",
            method: .post,
            headers: [.authorization: "Bearer \(env.token)", .contentType: "text/csv"],
            body: ByteBuffer(string: csv)
        ) { LibraryHarness.Reply(status: $0.status, body: Data(buffer: $0.body)) }
    }

    func importer(_ env: LibraryHarness, now: @escaping @Sendable () -> Date = { Date() }) -> ImportService {
        var service = ImportService(
            stores: env.stores,
            resolver: TitleResolver(stores: env.stores, catalogs: FakeCatalog.providers(env.fake))
        )
        service.now = now
        return service
    }

    /// Runs the worker until this job leaves the queue. Other tests' jobs may be ahead of it.
    func plan(_ env: LibraryHarness, _ id: String, service: ImportService? = nil) async throws -> [String: Any] {
        let service = service ?? importer(env)
        for _ in 0 ..< 50 {
            let job = try await env.send(.get, "/v1/imports/\(id)").json()
            let state = (job["job"] as? [String: Any])?["state"] as? String
            if state != "queued", state != "running" {
                return job
            }
            guard try await service.runNext(for: env.userID) else { break }
        }
        return try await env.send(.get, "/v1/imports/\(id)").json()
    }

    func book(_ title: String, isbn: String, year: Int) -> CatalogTitle {
        CatalogTitle(
            hit: CatalogHit(
                type: .book, title: title, originalTitle: nil, year: year, posterURL: nil, overview: nil,
                byline: "An Author", ids: ExternalIDs(isbn: isbn, openLibrary: uniqueID("OL")), isAnime: false
            ),
            status: nil, runtimeMinutes: nil
        )
    }

    func isbn13() throws -> String {
        let nine = String(format: "%09d", Int.random(in: 0 ..< 1_000_000_000))
        return try #require(ISBN.normalize(nine + isbn10Check(nine)))
    }

    @Test("A Goodreads import plans first, writes nothing until approved, then undoes as one action")
    func goodreadsPlanApplyUndo() async throws {
        try await LibraryHarness.run { env in
            let isbn = try isbn13()
            env.fake.stubTitle(book("Dune", isbn: isbn, year: 1965))
            let shelf = uniqueID("shelf")
            let csv = #"""
            Book Id,Title,Author,ISBN13,My Rating,Exclusive Shelf,Bookshelves,Original Publication Year
            1,Dune,Frank Herbert,"=""\#(isbn)""",4,read,"\#(shelf), read",1965
            2,A Book Nobody Has,Nobody,"=""""",0,to-read,to-read,1999
            3,Dune,Frank Herbert,"=""\#(isbn)""",4,read,read,1965
            """#
            let created = try await upload(env, csv, source: "goodreads")
            #expect(created.status == .accepted)
            let id = try #require(created.json()["id"] as? String)

            let planned = try await plan(env, id)
            let job = try #require(planned["job"] as? [String: Any])
            #expect(job["state"] as? String == "planned")
            let outcomes = (planned["rows"] as? [[String: Any]])?.compactMap { $0["outcome"] as? String }
            #expect(outcomes == ["create", "unmatched", "skip"])
            let unmatched = try #require((planned["rows"] as? [[String: Any]])?[1])
            #expect(unmatched["title"] as? String == "A Book Nobody Has")
            #expect((unmatched["reason"] as? String)?.isEmpty == false)

            let before = try await env.send(.get, "/v1/library/sync").json()
            #expect((before["items"] as? [Any])?.isEmpty == true, "nothing is written before approval")

            let applied = try await env.send(.post, "/v1/imports/\(id)/apply").json()
            #expect(applied["state"] as? String == "partial", "one row stayed unmatched")
            #expect((applied["stats"] as? [String: Int])?["created"] == 1)

            let library = try await env.send(.get, "/v1/library/sync").json()
            let item = try #require((library["items"] as? [[String: Any]])?.first)
            #expect(item["status"] as? String == "finished")
            #expect(item["rating"] as? Double == 8)
            let lists = try await env.send(.get, "/v1/lists").json()
            #expect((lists["items"] as? [[String: Any]])?.contains { $0["name"] as? String == shelf } == true)

            let actions = try await env.send(.get, "/v1/actions?limit=1").json()
            let action = try #require((actions["items"] as? [[String: Any]])?.first)
            #expect(action["kind"] as? String == "import")
            #expect(try await env.send(.post, "/v1/actions/\(action["id"] as? String ?? "")/undo").status == .ok)
            let undone = try await env.send(.get, "/v1/library/sync").json()
            #expect((undone["items"] as? [Any])?.isEmpty == true, "one undo removes the whole import")

            #expect(try await env.send(.post, "/v1/imports/\(id)/apply").status == .conflict, "applies once")
        }
    }

    @Test("IMP-004: an import fills empty fields and never overwrites a rating the library has")
    func fillEmptyOnly() async throws {
        try await LibraryHarness.run { env in
            let (rated, unrated) = try (isbn13(), isbn13())
            env.fake.stubTitle(book("Rated", isbn: rated, year: 2000))
            env.fake.stubTitle(book("Unrated", isbn: unrated, year: 2001))
            for isbn in [rated, unrated] {
                _ = try await env.send(.post, "/v1/library/items", json: [
                    "mediaRef": ["type": "book", "ids": ["isbn": isbn]], "status": "finished",
                ])
            }
            let ratedID = try #require(
                try (await env.send(.get, "/v1/library/sync").json()["items"] as? [[String: Any]])?
                    .first { ($0["title"] as? [String: Any])?["title"] as? String == "Rated" }?["id"] as? String
            )
            _ = try await env.send(.patch, "/v1/library/items/\(ratedID)", json: ["rating": 6])

            let csv = #"""
            Title,Author,ISBN13,My Rating,Exclusive Shelf
            Rated,A,"=""\#(rated)""",5,read
            Unrated,A,"=""\#(unrated)""",5,read
            """#
            let id = try #require(try await upload(env, csv, source: "goodreads").json()["id"] as? String)
            let planned = try await plan(env, id)
            #expect((planned["rows"] as? [[String: Any]])?.compactMap { $0["outcome"] as? String } == [
                "skip",
                "update",
            ])
            _ = try await env.send(.post, "/v1/imports/\(id)/apply")
            let items = try #require(try await env.send(.get, "/v1/library/sync").json()["items"] as? [[String: Any]])
            let ratings = Dictionary(uniqueKeysWithValues: items.map {
                (($0["title"] as? [String: Any])?["title"] as? String ?? "", $0["rating"] as? Double)
            })
            #expect(ratings["Rated"] == 6, "the library's rating stays")
            #expect(ratings["Unrated"] == 10, "an empty rating is filled")
        }
    }

    @Test("JOB-001: a job whose worker died is leased again once its lease runs out")
    func expiredLeaseIsReclaimed() async throws {
        try await LibraryHarness.run { env in
            let job = ImportJob(userID: env.userID, source: .goodreadsCSV, createdAt: .distantPast)
            try await env.stores.importJobs.insert(job, rows: [])
            let start = Date()
            // Lease every runnable job, as a worker would before crashing.
            var first: ClaimedImportJob?
            while let claimed = try await env.stores.importJobs.claimNext(now: start, lease: 60, userID: env.userID) {
                if claimed.job.id == job.id {
                    first = claimed; break
                }
            }
            #expect(first?.attempts == 1)
            #expect(
                try await env.stores.importJobs.claimNext(
                    now: start.addingTimeInterval(30),
                    lease: 60,
                    userID: env.userID
                )?.job.id
                    != job.id,
                "still leased"
            )
            var again: ClaimedImportJob?
            while let claimed = try await env.stores.importJobs
                .claimNext(now: start.addingTimeInterval(61), lease: 60, userID: env.userID)
            {
                if claimed.job.id == job.id {
                    again = claimed; break
                }
            }
            #expect(again?.attempts == 2, "the dead worker's job runs again")
        }
    }

    @Test("JOB-001: a job released at shutdown runs again at once, without spending an attempt")
    func releasedJobIsClaimedAgain() async throws {
        try await LibraryHarness.run { env in
            let job = ImportJob(userID: env.userID, source: .goodreadsCSV, createdAt: .distantPast)
            try await env.stores.importJobs.insert(job, rows: [])
            let start = Date()
            var first: ClaimedImportJob?
            while let claimed = try await env.stores.importJobs.claimNext(now: start, lease: 60, userID: env.userID) {
                if claimed.job.id == job.id {
                    first = claimed; break
                }
            }
            #expect(first?.attempts == 1)
            try await env.stores.importJobs.release(job.id, now: start)
            var again: ClaimedImportJob?
            while let claimed = try await env.stores.importJobs.claimNext(now: start, lease: 60, userID: env.userID) {
                if claimed.job.id == job.id {
                    again = claimed; break
                }
            }
            #expect(again?.attempts == 1, "the lease is given back before it runs out")
        }
    }

    @Test("JOB-001: a job that keeps failing lands in failed with a summary, after retries")
    func failingJobFails() async throws {
        try await LibraryHarness.run { env in
            let clock = TestClock(Date())
            let service = importer(env, now: { clock.now })
            let csv = try "Title,Author,ISBN13,My Rating,Exclusive Shelf\nX,A,\"=\"\"\(isbn13())\"\"\",0,read\n"
            let id = try #require(try await upload(env, csv, source: "goodreads").json()["id"] as? String)
            env.fake.fail(with: ProviderError(provider: "openlibrary", kind: .unavailable))
            var state: String?
            for _ in 0 ..< 60 {
                _ = try await service.runNext(for: env.userID)
                clock.advance(by: 120)
                state = try await (env.send(.get, "/v1/imports/\(id)").json()["job"] as? [String: Any])?["state"]
                    as? String
                if state == "failed" {
                    break
                }
            }
            env.fake.fail(with: nil)
            let job = try #require(try await env.send(.get, "/v1/imports/\(id)").json()["job"] as? [String: Any])
            #expect(state == "failed")
            #expect((job["errorSummary"] as? String)?.contains("Open Library") == true)
        }
    }

    @Test("IMP-005: an oversized upload is refused, and a file with the wrong columns says why")
    func uploadLimits() async throws {
        try await LibraryHarness.run { env in
            let huge = String(repeating: "a", count: ImportService.maxUploadBytes + 1)
            #expect(try await upload(env, huge, source: "imdb").status == .contentTooLarge)
            let wrong = try await upload(env, "Title,Author,Exclusive Shelf\nDune,F,read\n", source: "imdb")
            #expect(wrong.status == .unprocessableContent)
            #expect(wrong.text.contains("IMDb"))
        }
    }
}
