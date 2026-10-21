import AaruCore
import Foundation
import Testing
@testable import aaru

/// An AniList outage does not hold a whole MyAnimeList export hostage: the job retries first,
/// and its last try plans every row AniList is not needed for.
@Suite("Imports during an AniList outage", .serialized)
struct ImportOutageTests {
    @Test("Early tries wait for AniList; the last try matches mapped anime through TMDB and names the rest")
    func plansAroundAniList() async throws {
        try await LibraryHarness.run { env in
            let base = Int.random(in: 1_000_000 ..< 9_000_000)
            let mapped = String(base)
            let lonely = String(base + 1)
            let tmdbID = "\(base)"
            try await env.stores.animeMappings.upsert(
                AnimeMapping(anilist: "\(base + 5_000_000)", mal: mapped, tmdb: tmdbID, tmdbSeason: 1)
            )
            let tmdb = FakeCatalog()
            tmdb.stubTitle(CatalogTitle(
                hit: CatalogHit(
                    type: .show, title: "Show \(mapped)", originalTitle: nil, year: 2020, posterURL: nil,
                    overview: nil, byline: nil, ids: ExternalIDs(tmdb: tmdbID), isAnime: true
                ),
                status: .ended, runtimeMinutes: 24
            ))
            let anilist = FakeCatalog()
            anilist.fail(with: ProviderError(provider: "anilist", kind: .unauthorized))
            let service = ImportService(
                stores: env.stores,
                resolver: TitleResolver(
                    stores: env.stores, catalogs: CatalogProviders(tmdb: tmdb, anilist: anilist, openLibrary: tmdb)
                )
            )
            let job = try await service.createCSVImport(
                userID: env.userID, source: .malXML, filename: "animelist.xml",
                text: ImportSpeedTests.malExport([mapped, lonely])
            )

            #expect(try await service.runNext(for: env.userID))
            let waiting = try await service.detail(job.id, userID: env.userID).job
            #expect(waiting.state == .queued, "a first try waits for AniList to come back")
            #expect(waiting.errorSummary == "AniList could not be reached while matching titles.")

            let rows = try await service.detail(job.id, userID: env.userID).rows
            let planned = try await service.plan(rows, userID: env.userID, withoutAniListIfDown: true)
            #expect(planned[0].outcome == .create, "a mapped anime resolves through TMDB")
            #expect(planned[1].outcome == .unmatched)
            #expect(planned[1].reason?.contains("AniList was not answering") == true)
            #expect(anilist.callCount("hydrate") == 0, "rows after the failed batch do not ask again")
        }
    }
}
