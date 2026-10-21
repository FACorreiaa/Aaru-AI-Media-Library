import AaruCore
import Foundation
import Testing
@testable import aaru

/// IMP-004 across sources (2026-10-20): a later import fills gaps and moves a status forward,
/// never backward, never out of dropped, never past a status the user chose; anime from MAL lands
/// on the TMDB show a Trakt import made; AniList seasons tick the TMDB seasons they map to.
@Suite("Import merge", .serialized)
struct ImportMergeTests {
    func service(_ env: LibraryHarness) -> ImportService {
        ImportService(
            stores: env.stores,
            resolver: TitleResolver(stores: env.stores, catalogs: FakeCatalog.providers(env.fake))
        )
    }

    /// Plans and approves one import of these rows; returns the plan as approved.
    @discardableResult
    func runImport(_ env: LibraryHarness, _ source: ImportSource, _ rows: [ImportRow]) async throws -> [PlannedRow] {
        let job = ImportJob(userID: env.userID, source: source, createdAt: .distantPast)
        try await env.stores.importJobs.insert(job, rows: rows)
        let service = service(env)
        for _ in 0 ..< 50 {
            let state = try await env.stores.importJobs.job(id: job.id, userID: env.userID)?.state
            guard state == .queued || state == .running, try await service.runNext(for: env.userID) else { break }
        }
        _ = try await service.apply(job.id, userID: env.userID)
        return try await env.stores.importJobs.rows(jobID: job.id)
    }

    func movie(_ env: LibraryHarness, _ name: String) -> ExternalIDs {
        let ids = ExternalIDs(tmdb: uniqueID("m"), imdb: uniqueID("tt"))
        env.fake.stubTitle(CatalogTitle(
            hit: CatalogHit(
                type: .movie, title: name, originalTitle: nil, year: 2020, posterURL: nil, overview: nil,
                byline: nil, ids: ids, isAnime: false
            ),
            status: nil, runtimeMinutes: 100
        ))
        return ids
    }

    func show(_ env: LibraryHarness, _ name: String) -> String {
        let tmdb = uniqueID("s")
        env.fake.stubTitle(CatalogTitle(
            hit: CatalogHit(
                type: .show, title: name, originalTitle: nil, year: 2020, posterURL: nil, overview: nil,
                byline: nil, ids: ExternalIDs(tmdb: tmdb), isAnime: true
            ),
            status: .ended, runtimeMinutes: 24
        ))
        return tmdb
    }

    func row(
        _ type: MediaType,
        _ ids: ExternalIDs,
        status: LibraryStatus?,
        rating: Double? = nil,
        finishedAt: Date? = nil,
        watched: [EpisodeKey]? = nil
    ) -> ImportRow {
        ImportRow(
            type: type, title: "Row", ids: ids, status: status, rating: rating, finishedAt: finishedAt, lists: [],
            watched: watched
        )
    }

    func episodes(_ season: Int, _ range: ClosedRange<Int>) throws -> [EpisodeKey] {
        try range.map { try EpisodeKey(season: season, episode: $0) }
    }

    func item(_ env: LibraryHarness, _ ids: ExternalIDs, _ type: MediaType) async throws -> LibraryItem {
        let title = try #require(try await env.stores.titles.find(ids: ids, type: type))
        return try #require(try await env.stores.library.item(userID: env.userID, titleID: title.id))
    }

    @Test("The same import twice changes nothing the second time")
    func sameSourceTwice() async throws {
        try await LibraryHarness.run { env in
            let film = movie(env, "Twice")
            let rows = [row(.movie, film, status: .finished, rating: 8)]
            try await runImport(env, .letterboxdCSV, rows)
            let again = try await runImport(env, .letterboxdCSV, rows)
            #expect(again.map(\.outcome) == [.skip])
            let items = try await env.stores.library.entries(
                userID: env.userID, filter: LibraryFilter(), after: nil, limit: 50, now: Date()
            )
            #expect(items.entries.count == 1)
        }
    }

    @Test("A wishlist title from one source is finished by a later source that watched it")
    func wishlistMovesForward() async throws {
        try await LibraryHarness.run { env in
            let film = movie(env, "Forward")
            let watched = Date(timeIntervalSince1970: 1_700_000_000)
            try await runImport(env, .imdbCSV, [row(.movie, film, status: .wishlist)])
            let plan = try await runImport(
                env, .letterboxdCSV, [row(.movie, film, status: .finished, rating: 7, finishedAt: watched)]
            )
            #expect(plan.first?.outcome == .update)
            #expect(plan.first?.reason == "Moves it to Watched and adds the rating and finish date.")
            let item = try await item(env, film, .movie)
            #expect(item.status == .finished && item.finishedAt == watched && item.rating?.value == 7)
        }
    }

    @Test("A later import never moves a status backward, and never out of dropped")
    func neverBackwardNorOutOfDropped() async throws {
        try await LibraryHarness.run { env in
            let (done, dropped) = (movie(env, "Done"), movie(env, "Dropped"))
            try await runImport(env, .letterboxdCSV, [
                row(.movie, done, status: .finished), row(.movie, dropped, status: .dropped),
            ])
            let plan = try await runImport(env, .imdbCSV, [
                row(.movie, done, status: .wishlist), row(.movie, dropped, status: .finished),
            ])
            #expect(plan.map(\.outcome) == [.skip, .skip])
            #expect(try await item(env, done, .movie).status == .finished)
            #expect(try await item(env, dropped, .movie).status == .dropped)
        }
    }

    @Test("A status the user chose stays; a plain wishlist add may still move forward")
    func handSetStatusStays() async throws {
        try await LibraryHarness.run { env in
            let (chosen, added) = (movie(env, "Chosen"), movie(env, "Added"))
            for ids in [chosen, added] {
                _ = try await env.send(.post, "/v1/library/items", json: [
                    "mediaRef": ["type": "movie", "ids": ["tmdb": ids.tmdb ?? ""]], "status": "wishlist",
                ])
            }
            let chosenItem = try await item(env, chosen, .movie)
            _ = try await env.send(.patch, "/v1/library/items/\(chosenItem.id.rawValue)", json: [
                "status": "in_progress",
            ])
            try await runImport(env, .letterboxdCSV, [
                row(.movie, chosen, status: .finished), row(.movie, added, status: .finished),
            ])
            #expect(try await item(env, chosen, .movie).status == .inProgress, "the user's choice stays")
            #expect(try await item(env, added, .movie).status == .finished, "a wishlist add moves on")
        }
    }

    @Test("Undoing the user's status change clears the flag, so an import may move it again")
    func undoRestoresTheFlag() async throws {
        try await LibraryHarness.run { env in
            let film = movie(env, "Undone")
            try await runImport(env, .imdbCSV, [row(.movie, film, status: .wishlist)])
            let id = try await item(env, film, .movie).id
            _ = try await env.send(.patch, "/v1/library/items/\(id.rawValue)", json: ["status": "in_progress"])
            #expect(try await env.stores.library.statusSetByHand(itemID: id))
            let edit = try #require(try await env.stores.library.actions(userID: env.userID, limit: 1).first)
            #expect(try await env.send(.post, "/v1/actions/\(edit.id.uuidString)/undo").status == .ok)
            #expect(try await !env.stores.library.statusSetByHand(itemID: id))
        }
    }

    @Test("A MAL row lands on the TMDB show a Trakt import created, not a second title")
    func malAfterTraktIsOneTitle() async throws {
        try await LibraryHarness.run { env in
            let tmdb = show(env, "Frieren")
            let mal = uniqueID("mal")
            try await env.stores.animeMappings.upsert(AnimeMapping(
                anilist: uniqueID("al"), mal: mal, tmdb: tmdb, tmdbSeason: 1
            ))
            try await runImport(env, .trakt, [
                row(.show, ExternalIDs(tmdb: tmdb), status: .inProgress, watched: episodes(1, 1 ... 2)),
            ])
            let plan = try await runImport(env, .malXML, [
                row(.show, ExternalIDs(mal: mal), status: .finished, watched: episodes(1, 1 ... 4)),
            ])
            #expect(plan.first?.outcome == .update)
            let entries = try await env.stores.library.entries(
                userID: env.userID, filter: LibraryFilter(), after: nil, limit: 50, now: Date()
            )
            #expect(entries.entries.count == 1, "one show, not a TMDB copy and an AniList copy")
            let item = try await item(env, ExternalIDs(tmdb: tmdb), .show)
            #expect(item.status == .finished)
            #expect(try await env.stores.library.watched(itemID: item.id).count == 4)
        }
    }

    @Test("Two AniList seasons of one TMDB show tick seasons 1 and 2 on one item")
    func anilistSeasonsTickTheirSeason() async throws {
        try await LibraryHarness.run { env in
            let tmdb = show(env, "Mob")
            let (first, second) = (uniqueID("al"), uniqueID("al"))
            try await env.stores.animeMappings.upsert(AnimeMapping(anilist: first, tmdb: tmdb, tmdbSeason: 1))
            try await env.stores.animeMappings.upsert(AnimeMapping(anilist: second, tmdb: tmdb, tmdbSeason: 2))
            let plan = try await runImport(env, .anilist, [
                row(.show, ExternalIDs(anilist: first), status: .finished, watched: episodes(1, 1 ... 3)),
                row(.show, ExternalIDs(anilist: second), status: .inProgress, watched: episodes(1, 1 ... 2)),
            ])
            #expect(plan.map(\.outcome) == [.create, .skip])
            #expect(plan.last?.reason == "Merged into an earlier row.")
            let item = try await item(env, ExternalIDs(tmdb: tmdb), .show)
            let ticked = try await env.stores.library.watched(itemID: item.id)
            #expect(try ticked == Set(episodes(1, 1 ... 3) + episodes(2, 1 ... 2)))
        }
    }
}
