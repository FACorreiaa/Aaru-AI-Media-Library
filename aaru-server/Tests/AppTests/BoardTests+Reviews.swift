import AaruCore
import Foundation
import Testing
@testable import aaru

@Suite("Board reviews and spoilers (BOARD-001)", .serialized)
struct BoardReviewTests {
    private func review(
        _ env: LibraryHarness, type: String, tmdb: String, rating: Double?, token: String? = nil
    ) async throws -> LibraryHarness.Reply {
        var json: [String: Any] = ["body": "thoughts", "title": ["type": type, "ids": ["tmdb": tmdb]]]
        if let rating {
            json["rating"] = rating
        }
        return try await env.send(.post, "/v1/board/posts", json: json, token: token)
    }

    private func item(_ env: LibraryHarness, _ id: String) async throws -> [String: Any] {
        try await env.send(.get, "/v1/library/items/\(id)").json()
    }

    @Test("BOARD-001: a review of a new title adds it as Watched with the rating")
    func newTitle() async throws {
        try await LibraryHarness.run { env in
            _ = try await claimHandle(env)
            let tmdb = env.stubMovie("Dune")
            let posted = try await review(env, type: "movie", tmdb: tmdb, rating: 9)
            #expect(posted.status == .created, "\(posted.text)")

            let page = try await env.send(.get, "/v1/library/items").json()
            let items = try #require(page["items"] as? [[String: Any]])
            let mine = try #require(items.first { ($0["title"] as? [String: Any])?["title"] as? String == "Dune" })
            #expect(mine["status"] as? String == "finished")
            #expect(mine["rating"] as? Double == 9)

            let actions = try await env.send(.get, "/v1/actions").json()["items"] as? [[String: Any]] ?? []
            let kinds = actions.compactMap { $0["kind"] as? String }
            #expect(kinds.contains("add") && kinds.contains("update"))
        }
    }

    @Test("BOARD-001: a review of a title in progress keeps its status")
    func keepsStatus() async throws {
        try await LibraryHarness.run { env in
            _ = try await claimHandle(env)
            let tmdb = env.stubShow("Severance", status: .returning)
            let id = try await env.add("show", tmdb: tmdb, status: "in_progress")
            #expect(try await review(env, type: "show", tmdb: tmdb, rating: 7).status == .created)
            let entry = try await item(env, id)
            #expect(entry["status"] as? String == "in_progress")
            #expect(entry["rating"] as? Double == 7)
        }
    }

    @Test("BOARD-001: no rating means no library write; a bad rating fails")
    func noWrite() async throws {
        try await LibraryHarness.run { env in
            _ = try await claimHandle(env)
            let tmdb = env.stubMovie("Heat")
            #expect(try await review(env, type: "movie", tmdb: tmdb, rating: nil).status == .created)
            let page = try await env.send(.get, "/v1/library/items").json()
            #expect((page["items"] as? [Any])?.isEmpty == true)
            #expect(try await review(env, type: "movie", tmdb: tmdb, rating: 11).status == .unprocessableContent)
        }
    }

    @Test("BOARD-001: spoilers veil friends who are behind")
    func veil() async throws {
        try await LibraryHarness.run { env in
            let mine = try await claimHandle(env)
            let ana = try await friend(env, of: mine)
            let ben = try await friend(env, of: mine)
            let tmdb = env.stubShow("Andor", status: .returning, seasons: 2, perSeason: 6)
            let watcher = GroupKindTests()
            _ = try await watcher.watch(env, tmdb: tmdb, (1 ... 5).map { (1, $0) })
            _ = try await watcher.watch(env, tmdb: tmdb, [(1, 1), (1, 2)], token: ana.token)
            let benItem = try await watcher.watch(env, tmdb: tmdb, [(1, 1)], token: ben.token)
            let done = try await env.send(
                .patch, "/v1/library/items/\(benItem)", json: ["status": "finished"], token: ben.token
            )
            #expect(done.status == .ok, "\(done.text)")

            let posted = try await review(env, type: "show", tmdb: tmdb, rating: nil)
            #expect(posted.status == .created, "\(posted.text)")
            let json = try posted.json()
            #expect((json["spoiler"] as? [String: Any])?["episode"] as? Int == 5)
            #expect(json["veiled"] as? Bool == false)
            let id = try #require(json["id"] as? String)

            for (token, expected) in [(ana.token, true), (ben.token, false), (nil, false)] as [(String?, Bool)] {
                let feed = try await env.send(.get, "/v1/board", token: token).json()
                let row = try #require((feed["items"] as? [[String: Any]])?.first { $0["id"] as? String == id })
                #expect(row["veiled"] as? Bool == expected)
                let single = try await env.send(.get, "/v1/board/posts/\(id)", token: token).json()
                #expect(single["veiled"] as? Bool == expected)
            }
        }
    }
}
