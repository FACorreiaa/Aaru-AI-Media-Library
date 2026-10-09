import AaruCore
import Foundation
import Testing
@testable import aaru

@Suite("Library and journal (M4)", .serialized)
struct LibraryTests {
    @Test("LIB-001: posting the same MediaRef twice returns the same item")
    func addIsIdempotent() async throws {
        try await LibraryHarness.run { env in
            let tmdb = env.stubMovie("Dune")
            let first = try await env.add("movie", tmdb: tmdb)
            let second = try await env.add("movie", tmdb: tmdb)
            #expect(first == second)
            #expect(try await env.actionCount() == 1, "the repeat add writes nothing")
        }
    }

    @Test("LIB-002: filters return only the caller's matching rows; pages are stable while rows change")
    func filtersAndPagination() async throws {
        try await LibraryHarness.run { env in
            var ids: [String] = []
            for index in 0 ..< 5 {
                try await ids.append(env.add("movie", tmdb: env.stubMovie("Movie \(index)")))
            }
            let show = try await env.add("show", tmdb: env.stubShow("Show", status: .returning), status: "in_progress")

            let filtered = try await env.send(.get, "/v1/library/items?status=in_progress&type=show").json()
            #expect((filtered["items"] as? [[String: Any]])?.compactMap { $0["id"] as? String } == [show])

            // Another user's library is invisible.
            let (_, otherToken) = try await signedInUser(env.stores)
            let other = try await env.send(.get, "/v1/library/items", token: otherToken).json()
            #expect((other["items"] as? [Any])?.isEmpty == true)

            // Page through movies two at a time while a row is updated mid-way.
            var seen: [String] = []
            var cursor: String?
            repeat {
                let uri = "/v1/library/items?type=movie&limit=2" + (cursor.map { "&cursor=\($0)" } ?? "")
                let page = try await env.send(.get, uri).json()
                seen += (page["items"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
                cursor = (page["page"] as? [String: Any])?["nextCursor"] as? String
                if seen.count == 2 {
                    _ = try await env.send(.patch, "/v1/library/items/\(ids[0])", json: ["isOwned": true])
                }
            } while cursor != nil
            #expect(Set(seen).count == seen.count, "no duplicates across pages")
            #expect(Set(ids.dropFirst()).isSubset(of: Set(seen)), "no unchanged row skipped")
        }
    }

    @Test("LIB-003: ratings validate, owned leaves status alone, finished stamps a date, others get 404")
    func patchRules() async throws {
        try await LibraryHarness.run { env in
            let id = try await env.add("movie", tmdb: env.stubMovie("Heat"))
            let bad = try await env.send(.patch, "/v1/library/items/\(id)", json: ["rating": 11])
            #expect(bad.status == .unprocessableContent)
            #expect(bad.text.contains("rating"))
            #expect(try await env.send(.patch, "/v1/library/items/\(id)", json: ["rating": 7.3])
                .status == .unprocessableContent)

            let owned = try await env.send(.patch, "/v1/library/items/\(id)", json: ["isOwned": true]).json()
            #expect(owned["status"] as? String == "wishlist")
            #expect(owned["isOwned"] as? Bool == true)

            let finished = try await env.send(
                .patch,
                "/v1/library/items/\(id)",
                json: ["status": "finished", "rating": 8.5]
            )
            .json()
            #expect(finished["finishedAt"] != nil)
            #expect(finished["rating"] as? Double == 8.5)

            let (_, otherToken) = try await signedInUser(env.stores)
            #expect(try await env.send(.patch, "/v1/library/items/\(id)", json: ["isOwned": false], token: otherToken)
                .status == .notFound)
            #expect(try await env.send(.get, "/v1/library/items/\(id)", token: otherToken).status == .notFound)
        }
    }

    @Test("LIB-004: a delete on one device reaches another that asks only for changes")
    func syncDeletes() async throws {
        try await LibraryHarness.run { env in
            let keep = try await env.add("movie", tmdb: env.stubMovie("Keep"))
            let drop = try await env.add("movie", tmdb: env.stubMovie("Drop"))
            let first = try await env.send(.get, "/v1/library/sync").json()
            #expect(Set((first["items"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }) == [keep, drop])
            let token = try #require(first["token"] as? String)

            #expect(try await env.send(.delete, "/v1/library/items/\(drop)").status == .noContent)
            let next = try await env.send(.get, "/v1/library/sync?since=\(token)").json()
            #expect((next["deleted"] as? [String]) == [drop.lowercased()] || (next["deleted"] as? [String]) == [drop])
        }
    }

    @Test("AUD-001: one journal row per write, none for a failed write")
    func journal() async throws {
        try await LibraryHarness.run { env in
            let id = try await env.add("show", tmdb: env.stubShow("Severance", status: .returning))
            #expect(try await env.actionCount() == 1)
            _ = try await env.send(.patch, "/v1/library/items/\(id)", json: ["rating": 9])
            #expect(try await env.actionCount() == 2)
            _ = try await env.send(.post, "/v1/library/items/\(id)/seasons/1/watched")
            #expect(try await env.actionCount() == 3, "a season of episodes is one action")
            #expect(try await env.send(.patch, "/v1/library/items/\(id)", json: ["rating": 42])
                .status == .unprocessableContent)
            #expect(try await env.actionCount() == 3, "a rejected write leaves no row")
        }
    }

    @Test("AUD-002: undoing a season mark restores the prior state exactly; undoing twice is 409")
    func undoSeason() async throws {
        try await LibraryHarness.run { env in
            let id = try await env.add("show", tmdb: env.stubShow("Andor", status: .returning))
            _ = try await env.send(.put, "/v1/library/items/\(id)/episodes/1/2", json: ["watched": true])
            _ = try await env.send(.post, "/v1/library/items/\(id)/seasons/1/watched")
            let marked = try await env.send(.get, "/v1/library/items/\(id)").json()
            #expect((marked["progress"] as? [String: Any])?["watchedCount"] as? Int == 3)

            let actions = try await env.send(.get, "/v1/actions?limit=1").json()
            let actionID = try #require((actions["items"] as? [[String: Any]])?.first?["id"] as? String)
            #expect(try await env.send(.post, "/v1/actions/\(actionID)/undo").status == .ok)

            let watched = try await env.stores.library.watched(itemID: #require(LibraryItemID(uuidString: id)))
            #expect(
                try watched == [EpisodeKey(season: 1, episode: 2)],
                "the episode watched before the bulk mark stays"
            )
            #expect(try await env.send(.post, "/v1/actions/\(actionID)/undo").status == .conflict)
        }
    }

    @Test("AUD-002: undoing a delete brings the item back with its progress")
    func undoDelete() async throws {
        try await LibraryHarness.run { env in
            let id = try await env.add("show", tmdb: env.stubShow("Lost", status: .ended))
            _ = try await env.send(.put, "/v1/library/items/\(id)/episodes/1/1", json: ["watched": true])
            _ = try await env.send(.delete, "/v1/library/items/\(id)")
            let actionID = try #require(
                try (await env.send(.get, "/v1/actions?limit=1").json()["items"] as? [[String: Any]])?
                    .first?["id"] as? String
            )
            _ = try await env.send(.post, "/v1/actions/\(actionID)/undo")
            let restored = try await env.send(.get, "/v1/library/items/\(id)").json()
            #expect((restored["progress"] as? [String: Any])?["watchedCount"] as? Int == 1)
        }
    }
}

@Suite("TV progress (M5)", .serialized)
struct ProgressTests {
    @Test("PROG-001: an episode not in the show is 422; ticking twice is idempotent")
    func tickRules() async throws {
        try await LibraryHarness.run { env in
            let id = try await env.add("show", tmdb: env.stubShow("Dark", status: .ended))
            #expect(try await env.send(.put, "/v1/library/items/\(id)/episodes/9/9", json: ["watched": true])
                .status == .unprocessableContent)
            for _ in 0 ..< 2 {
                let reply = try await env.send(.put, "/v1/library/items/\(id)/episodes/1/1", json: ["watched": true])
                #expect(try (reply.json()["progress"] as? [String: Any])?["watchedCount"] as? Int == 1)
            }
        }
    }

    @Test("PROG-002: a season mark leaves unaired episodes alone")
    func seasonSkipsUnaired() async throws {
        try await LibraryHarness.run { env in
            let id = try await env.add(
                "show",
                tmdb: env.stubShow("Airing", status: .returning, seasons: 1, unaired: true)
            )
            let reply = try await env.send(.post, "/v1/library/items/\(id)/seasons/1/watched").json()
            let progress = try #require(reply["progress"] as? [String: Any])
            #expect(progress["watchedCount"] as? Int == 2)
            #expect(progress["airedCount"] as? Int == 2)
        }
    }

    @Test("PROG-003: first tick starts a show; an ended show finishes; a running show never auto-finishes")
    func statusTransitions() async throws {
        try await LibraryHarness.run { env in
            let ended = try await env.add("show", tmdb: env.stubShow("Ended", status: .ended, seasons: 1))
            let first = try await env.send(.put, "/v1/library/items/\(ended)/episodes/1/1", json: ["watched": true])
                .json()
            #expect(first["status"] as? String == "in_progress")
            let done = try await env.send(.post, "/v1/library/items/\(ended)/seasons/1/watched").json()
            #expect(done["status"] as? String == "finished")

            let running = try await env.add("show", tmdb: env.stubShow("Running", status: .returning, seasons: 1))
            let caughtUp = try await env.send(.post, "/v1/library/items/\(running)/seasons/1/watched").json()
            #expect(caughtUp["status"] as? String == "in_progress")
            let progress = try #require(caughtUp["progress"] as? [String: Any])
            #expect(progress["nextEpisode"] == nil)
        }
    }

    @Test("PROG-004: book progress is a page or a percent, validated, never both")
    func bookProgress() async throws {
        try await LibraryHarness.run { env in
            let isbn = try #require(ISBN.normalize(String(format: "%09d", Int.random(in: 0 ..< 999_999_999)) + "0") ??
                ISBN.normalize("0441172717"))
            let olid = uniqueID("OL")
            env.fake.stubTitle(CatalogTitle(
                hit: CatalogHit(
                    type: .book, title: "A Book", originalTitle: nil, year: 1965, posterURL: nil, overview: nil,
                    byline: nil, ids: ExternalIDs(isbn: isbn, openLibrary: olid), isAnime: false
                ),
                status: nil, runtimeMinutes: nil
            ))
            let added = try await env.send(.post, "/v1/library/items", json: [
                "mediaRef": ["type": "book", "ids": ["openLibrary": olid]],
            ])
            let id = try #require(try added.json()["id"] as? String)
            #expect(try await env.send(.patch, "/v1/library/items/\(id)", json: ["bookPercent": 150]).status
                == .unprocessableContent)
            #expect(try await env.send(.patch, "/v1/library/items/\(id)", json: ["bookPage": 10, "bookPercent": 5])
                .status
                == .unprocessableContent)
            _ = try await env.send(.patch, "/v1/library/items/\(id)", json: ["bookPage": 120])
            let percent = try await env.send(.patch, "/v1/library/items/\(id)", json: ["bookPercent": 40]).json()
            let progress = try #require(percent["bookProgress"] as? [String: Any])
            #expect(progress["percent"] as? Double == 40)
            #expect(progress["page"] == nil, "setting one clears the other")
        }
    }
}
