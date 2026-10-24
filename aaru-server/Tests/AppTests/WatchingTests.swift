import AaruCore
import Foundation
import Testing
@testable import aaru

/// APP-018: the anime backlog (in progress, imported status, no tick made in Aaru) and
/// `GET /v1/library/watching`.
@Suite("Watching and the anime backlog (APP-018)", .serialized)
struct WatchingTests {
    static let day: TimeInterval = 86400

    /// A show whose season 1 episodes air at these offsets (in days) from now.
    func stubShow(
        _ env: LibraryHarness, _ name: String, anime: Bool, days: [Double], status: TitleStatus = .returning
    ) -> String {
        let tmdb = uniqueID("tmdb")
        env.fake.stubTitle(CatalogTitle(
            hit: CatalogHit(
                type: .show, title: name, originalTitle: nil, year: 2026, posterURL: nil, overview: nil,
                byline: nil, ids: ExternalIDs(tmdb: tmdb), isAnime: anime
            ),
            status: status, runtimeMinutes: nil
        ))
        let now = Date()
        env.fake.stubEpisodes(tmdb, CatalogEpisodes(status: status, episodes: days.enumerated().map { index, offset in
            CatalogEpisode(
                season: 1, episode: index + 1, name: "\(name) \(index + 1)",
                airsAt: now.addingTimeInterval(offset * Self.day), runtimeMinutes: 25, tmdbEpisodeID: nil
            )
        }))
        return tmdb
    }

    /// Imports one show in progress with these episodes ticked, as a MAL export would; returns the item id.
    func importShow(_ env: LibraryHarness, tmdb: String, watched: [Int]) async throws -> String {
        let row = try ImportRow(
            type: .show, title: "Row", ids: ExternalIDs(tmdb: tmdb), status: .inProgress, rating: nil,
            finishedAt: nil, lists: [], watched: watched.map { try EpisodeKey(season: 1, episode: $0) }
        )
        let job = ImportJob(userID: env.userID, source: .malXML, createdAt: .distantPast)
        try await env.stores.importJobs.insert(job, rows: [row])
        let service = ImportService(
            stores: env.stores, resolver: TitleResolver(stores: env.stores, catalogs: FakeCatalog.providers(env.fake))
        )
        for _ in 0 ..< 50 {
            let state = try await env.stores.importJobs.job(id: job.id, userID: env.userID)?.state
            guard state == .queued || state == .running, try await service.runNext(for: env.userID) else { break }
        }
        _ = try await service.apply(job.id, userID: env.userID)
        let title = try #require(try await env.stores.titles.find(ids: ExternalIDs(tmdb: tmdb), type: .show))
        return try #require(try await env.stores.library.item(userID: env.userID, titleID: title.id)).id.description
    }

    func entry(_ env: LibraryHarness, _ id: String) async throws -> [String: Any] {
        try await env.send(.get, "/v1/library/items/\(id)").json()
    }

    @Test("An imported anime with no tick made in Aaru is in the backlog until the first live tick")
    func importedAnime() async throws {
        try await LibraryHarness.run { env in
            let id = try await importShow(env, tmdb: stubShow(env, "Frieren", anime: true, days: [-30, -23, -16]),
                                          watched: [1])
            var body = try await entry(env, id)
            #expect(body["inBacklog"] as? Bool == true)
            #expect(body["lastWatchedAt"] == nil, "an imported tick is not a live one")

            _ = try await env.send(.put, "/v1/library/items/\(id)/episodes/1/2", json: ["watched": true])
            body = try await entry(env, id)
            #expect(body["inBacklog"] as? Bool == false)
            #expect(body["lastWatchedAt"] is String)
            #expect(body["status"] as? String == "in_progress", "the status never moves")
        }
    }

    @Test("An anime set to watching by hand, an imported show and a later import never count as backlog")
    func notBacklog() async throws {
        try await LibraryHarness.run { env in
            let byHand = try await env.add(
                "show", tmdb: stubShow(env, "Dandadan", anime: true, days: [-9, -2]), status: "in_progress"
            )
            #expect(try await entry(env, byHand)["inBacklog"] as? Bool == false)

            let tv = try await importShow(env, tmdb: stubShow(env, "Severance", anime: false, days: [-30, -23]),
                                          watched: [1])
            #expect(try await entry(env, tv)["inBacklog"] as? Bool == false)

            // Started in Aaru, then the same title imported again: still active.
            let tmdb = stubShow(env, "Mushishi", anime: true, days: [-60, -53, -46])
            let started = try await importShow(env, tmdb: tmdb, watched: [])
            _ = try await env.send(.put, "/v1/library/items/\(started)/episodes/1/1", json: ["watched": true])
            _ = try await importShow(env, tmdb: tmdb, watched: [1, 2])
            #expect(try await entry(env, started)["inBacklog"] as? Bool == false)
        }
    }

    @Test("Watching joins the show's status, next airing and what is left; plans to watch stay out")
    func watching() async throws {
        try await LibraryHarness.run { env in
            // Three aired, one next week: two left after ticking the first.
            let airing = try await env.add(
                "show", tmdb: stubShow(env, "Severance", anime: false, days: [-30, -23, -16, 7]),
                status: "in_progress"
            )
            _ = try await env.send(.put, "/v1/library/items/\(airing)/episodes/1/1", json: ["watched": true])
            // Caught up: the next episode has not aired.
            let caughtUp = try await env.add(
                "show", tmdb: stubShow(env, "Andor", anime: false, days: [-9, 5]), status: "in_progress"
            )
            _ = try await env.send(.put, "/v1/library/items/\(caughtUp)/episodes/1/1", json: ["watched": true])
            let film = try await env.add("movie", tmdb: env.stubMovie("Arrival"), status: "in_progress")
            _ = try await env.add("show", tmdb: stubShow(env, "Later", anime: false, days: [-9]))
            let backlog = try await importShow(env, tmdb: stubShow(env, "Gintama", anime: true, days: [-90]),
                                               watched: [])

            let items = try #require(try await env.send(.get, "/v1/library/watching").json()["items"]
                as? [[String: Any]])
            let byID = Dictionary(uniqueKeysWithValues: items.compactMap { item -> (String, [String: Any])? in
                guard let id = (item["entry"] as? [String: Any])?["id"] as? String else { return nil }
                return (id, item)
            })
            #expect(Set(byID.keys) == [airing, caughtUp, film, backlog], "no wishlist, no other kinds")

            let row = try #require(byID[airing])
            #expect(row["showStatus"] as? String == "returning")
            #expect((row["nextAiring"] as? [String: Any])?["number"] as? Int == 4)
            #expect(row["nextName"] as? String == "Severance 2")
            #expect(row["remainingCount"] as? Int == 2)
            #expect(row["remainingMinutes"] as? Int == 50)

            let waiting = try #require(byID[caughtUp])
            #expect((waiting["nextAiring"] as? [String: Any])?["number"] as? Int == 2)
            #expect(waiting["nextName"] == nil && waiting["remainingCount"] == nil)

            #expect((byID[backlog]?["entry"] as? [String: Any])?["inBacklog"] as? Bool == true)
            #expect(byID[film]?["showStatus"] == nil)

            let (other, _) = try await signedInUser(env.stores)
            #expect(try await env.services.schedule.watching(userID: other).isEmpty)
        }
    }
}
