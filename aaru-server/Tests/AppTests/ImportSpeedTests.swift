import AaruCore
import Foundation
import Testing
@testable import aaru

/// IMP-017: big exports match in batches and in parallel, and say how far they are.
@Suite("Import speed and progress (IMP-017)", .serialized)
struct ImportSpeedTests {
    /// A MAL export of `ids`, each a TV entry the user plans to watch.
    static func malExport(_ ids: [String]) -> String {
        let entries = ids.map { id in
            """
            <anime>
              <series_animedb_id>\(id)</series_animedb_id>
              <series_title><![CDATA[Show \(id)]]></series_title>
              <series_type>TV</series_type>
              <series_episodes>12</series_episodes>
              <my_watched_episodes>0</my_watched_episodes>
              <my_score>0</my_score>
              <my_status>Plan to Watch</my_status>
            </anime>
            """
        }
        return "<?xml version=\"1.0\"?><myanimelist>\(entries.joined())</myanimelist>"
    }

    static func anime(mal: String) -> CatalogTitle {
        CatalogTitle(
            hit: CatalogHit(
                type: .show, title: "Show \(mal)", originalTitle: nil, year: 2020, posterURL: nil, overview: nil,
                byline: nil, ids: ExternalIDs(anilist: "al\(mal)", mal: mal), isAnime: true
            ),
            status: .ended, runtimeMinutes: 24
        )
    }

    @Test("AniList answers MAL ids 50 at a time, keyed by MAL id; unknown ids are just missing")
    func aniListBatches() async throws {
        let stub = StubTransport { request in
            let ids = (try? JSONDecoder().decode(BatchBody.self, from: request.body ?? Data()))?.variables.ids ?? []
            let media = ids.filter { $0 != 7 }.map { id in
                #"{"id":\#(id + 100_000),"idMal":\#(id),"format":"TV","title":{"romaji":"Show \#(id)"}}"#
            }
            let json = #"{"data":{"Page":{"media":[\#(media.joined(separator: ","))]}}}"#
            return OutboundResponse(status: 200, body: Data(json.utf8))
        }
        let catalog = AniListCatalog(client: ProviderClient(
            name: "anilist", transport: stub, pacer: RequestPacer(requestsPerSecond: 1000, burst: 100)
        ))
        let ids = (1 ... 120).map(String.init)
        let titles = try await catalog.hydrate(malIDs: ids + ["5", "x"], type: .show)

        #expect(stub.requests.count == 3, "120 ids, 50 per request")
        #expect(titles.count == 119)
        #expect(titles["7"] == nil)
        #expect(titles["42"]?.hit.ids == ExternalIDs(anilist: "100042", mal: "42"))
        let body = try #require(stub.requests.first?.body.flatMap { String(bytes: $0, encoding: .utf8) })
        #expect(body.contains("idMal_in"))
    }

    @Test("A MAL export resolves one AniList batch per 50 rows, keeps row order, ends with full progress")
    func malImportBatchedWithProgress() async throws {
        try await LibraryHarness.run { env in
            let base = Int.random(in: 1_000_000 ..< 9_000_000)
            let known = (0 ..< 59).map { String(base + $0) }
            let unknown = String(base + 99)
            for mal in known {
                env.fake.stubTitle(Self.anime(mal: mal))
            }
            let service = ImportService(
                stores: env.stores,
                resolver: TitleResolver(stores: env.stores, catalogs: FakeCatalog.providers(env.fake))
            )
            let job = try await service.createCSVImport(
                userID: env.userID, source: .malXML, filename: "animelist.xml",
                text: Self.malExport(known + [unknown])
            )
            #expect(job.rowsTotal == 60, "the upload's answer already counts the rows")
            #expect(try await service.detail(job.id, userID: env.userID).job.rowsTotal == 60)

            #expect(try await service.runNext(for: env.userID))

            let (planned, rows) = try await service.detail(job.id, userID: env.userID)
            #expect(planned.state == .planned)
            #expect(planned.rowsMatched == 60 && planned.rowsTotal == 60)
            #expect(planned.stats.created == 59 && planned.stats.unmatched == 1)
            #expect(env.fake.callCount("hydrateMAL") == 2, "60 rows: a chunk of 50 and a chunk of 10")
            #expect(env.fake.callCount("hydrate") == 0, "no per-entry AniList calls")
            for row in rows where row.outcome == .create {
                let titleID = try #require(row.titleID)
                let title = try #require(try await env.stores.titles.title(id: titleID))
                #expect(title.ids.mal == row.row.ids.mal, "each row keeps its own match")
            }
            #expect(rows.last?.outcome == .unmatched)
        }
    }

    @Test("Matching reports progress as each chunk of 50 finishes, ending at every row")
    func progressReports() async throws {
        try await LibraryHarness.run { env in
            let base = Int.random(in: 1_000_000 ..< 9_000_000)
            let ids = (0 ..< 60).map { String(base + $0) }
            for mal in ids {
                env.fake.stubTitle(Self.anime(mal: mal))
            }
            let service = ImportService(
                stores: env.stores,
                resolver: TitleResolver(stores: env.stores, catalogs: FakeCatalog.providers(env.fake))
            )
            let rows = try MALListParser.parse(Self.malExport(ids)).enumerated().map { index, row in
                PlannedRow(index: index, row: row, outcome: .pending, reason: nil, titleID: nil)
            }
            let reports = Reports()
            _ = try await service.plan(rows, userID: env.userID) { await reports.add($0) }
            let values = await reports.values
            #expect(values.count == 2, "a chunk of 50 and a chunk of 10")
            #expect(values.last == 60 && values == values.sorted())
        }
    }
}

/// The variables of an AniList batch request.
private struct BatchBody: Decodable {
    struct Variables: Decodable { let ids: [Int] }
    let variables: Variables
}

private actor Reports {
    var values: [Int] = []
    func add(_ value: Int) {
        values.append(value)
    }
}
