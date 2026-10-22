import AaruCore
import Foundation
import Testing
@testable import aaru

@Suite("Whole show watched (PROG-005) and profile stats (GAM-006b)", .serialized)
struct ShowWatchedTests {
    func progress(_ reply: [String: Any]) -> (watched: Int?, aired: Int?) {
        let progress = reply["progress"] as? [String: Any]
        return (progress?["watchedCount"] as? Int, progress?["airedCount"] as? Int)
    }

    @Test("PROG-005: an ended show finishes in one action, undated, and one undo puts it back")
    func endedShow() async throws {
        try await LibraryHarness.run { env in
            let id = try await env.add("show", tmdb: env.stubShow("Severance", status: .ended))
            _ = try await env.send(.put, "/v1/library/items/\(id)/episodes/1/1", json: ["watched": true])
            let before = try await env.actionCount()

            let reply = try await env.send(.post, "/v1/library/items/\(id)/watched").json()
            let entry = try #require(reply["entry"] as? [String: Any])
            #expect(entry["status"] as? String == "finished")
            #expect(progress(entry).watched == 6)
            #expect(reply["episodes"] as? Int == 5)
            #expect(try await env.actionCount() == before + 1)

            // Not today's activity: only the one real tick counts this week.
            let week = try await env.send(.get, "/v1/me/stats?span=last7").json()
            #expect((week["totals"] as? [String: Any])?["episodesWatched"] as? Int == 1)
            // The profile counts all six.
            let profile = try await env.send(.get, "/v1/me/profile/stats").json()
            #expect(profile["episodesWatched"] as? Int == 6)
            #expect(profile["minutesWatched"] as? Int == 270)
            #expect((profile["shows"] as? [String: Any])?["finished"] as? Int == 1)

            let action = try #require((reply["action"] as? [String: Any])?["id"] as? String)
            #expect(try await env.send(.post, "/v1/actions/\(action)/undo").status == .ok)
            let undone = try await env.send(.get, "/v1/library/items/\(id)").json()
            #expect(undone["status"] as? String == "in_progress")
            #expect(progress(undone).watched == 1)
        }
    }

    @Test("PROG-005: a running show ticks aired episodes only and stays in progress; again is a no-op")
    func runningShow() async throws {
        try await LibraryHarness.run { env in
            let id = try await env.add("show", tmdb: env.stubShow("Airing", status: .returning, unaired: true))
            let reply = try await env.send(.post, "/v1/library/items/\(id)/watched").json()
            let entry = try #require(reply["entry"] as? [String: Any])
            #expect(entry["status"] as? String == "in_progress")
            #expect(progress(entry).watched == 5)
            #expect(progress(entry).aired == 5)

            let count = try await env.actionCount()
            let again = try await env.send(.post, "/v1/library/items/\(id)/watched").json()
            #expect(again["action"] == nil)
            #expect(again["episodes"] as? Int == 0)
            #expect(try await env.actionCount() == count)
        }
    }

    @Test("PROG-005: PATCH finished on a show is the whole show watched, with the other fields in the same action")
    func patchFinished() async throws {
        try await LibraryHarness.run { env in
            let id = try await env.add("show", tmdb: env.stubShow("Dark", status: .ended))
            let before = try await env.actionCount()
            let reply = try await env.send(.patch, "/v1/library/items/\(id)", json: ["status": "finished", "rating": 9])
                .json()
            #expect(reply["status"] as? String == "finished")
            #expect(reply["rating"] as? Double == 9)
            #expect(progress(reply).watched == 6)
            #expect(try await env.actionCount() == before + 1)

            let running = try await env.add("show", tmdb: env.stubShow("Running", status: .returning))
            let caughtUp = try await env.send(.patch, "/v1/library/items/\(running)", json: ["status": "finished"])
                .json()
            #expect(caughtUp["status"] as? String == "in_progress")
            #expect(progress(caughtUp).watched == 6)
        }
    }

    @Test("PROG-005: adding a show as watched ticks it in the add; films are not shows")
    func addAsWatched() async throws {
        try await LibraryHarness.run { env in
            let ended = try await env.add("show", tmdb: env.stubShow("Ended", status: .ended), status: "finished")
            let entry = try await env.send(.get, "/v1/library/items/\(ended)").json()
            #expect(entry["status"] as? String == "finished")
            #expect(progress(entry).watched == 6)

            let running = try await env.add(
                "show",
                tmdb: env.stubShow("Running", status: .returning),
                status: "finished"
            )
            #expect(try await env.send(.get, "/v1/library/items/\(running)")
                .json()["status"] as? String == "in_progress")

            let movie = try await env.add("movie", tmdb: env.stubMovie("Heat"))
            #expect(try await env.send(.post, "/v1/library/items/\(movie)/watched").status == .unprocessableContent)
        }
    }

    @Test("GAM-006b: profile counts per kind, ratings over every rated item; an empty library is zeros")
    func profile() async throws {
        try await LibraryHarness.run { env in
            let empty = try await env.send(.get, "/v1/me/profile/stats").json()
            #expect(empty["minutesWatched"] as? Int == 0)
            #expect((empty["topGenres"] as? [Any])?.isEmpty == true)
            #expect(empty["memberSince"] != nil)

            let film = try await env.add("movie", tmdb: env.stubMovie("Heat"), status: "finished")
            _ = try await env.send(.patch, "/v1/library/items/\(film)", json: ["rating": 8])
            let show = try await env.add("show", tmdb: env.stubShow("Dark", status: .returning), status: "in_progress")
            _ = try await env.send(.patch, "/v1/library/items/\(show)", json: ["rating": 6])
            _ = try await env.send(.post, "/v1/library/items/\(show)/seasons/1/watched")

            let profile = try await env.send(.get, "/v1/me/profile/stats").json()
            #expect(profile["minutesWatched"] as? Int == 100 + 3 * 45)
            #expect((profile["movies"] as? [String: Any])?["finished"] as? Int == 1)
            #expect((profile["shows"] as? [String: Any])?["inProgress"] as? Int == 1)
            let ratings = try #require(profile["ratings"] as? [String: Any])
            #expect(ratings["count"] as? Int == 2)
            #expect(ratings["mean"] as? Double == 7)
            let top = try #require((profile["mostWatched"] as? [[String: Any]])?.first)
            #expect((top["title"] as? [String: Any])?["title"] as? String == "Dark")
        }
    }
}
