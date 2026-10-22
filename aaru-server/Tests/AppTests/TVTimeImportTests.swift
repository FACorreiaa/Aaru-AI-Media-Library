import AaruCore
import Foundation
import Testing
@testable import aaru

/// IMP-012: TV Time's exports, against stubs. The files are written from the column layouts the
/// public TV Time converters document (Trakt's importer fixtures, TvTimeToTrakt, rewatch); every
/// id, name and date in them is made up.
@Suite("TV Time import", .serialized)
struct TVTimeImportTests {
    // MARK: Layouts

    static let seriesEpisodesHeader = "series_tvdb_id,series_imdb_id,series_uuid,title,season,episode,tvdb_id,"
        + "is_watched,watched_at,rewatch_count,special"
    static let seriesHeader = "uuid,tvdb_id,imdb_id,title,status,created_at"
    static let moviesHeader = "uuid,tvdb_id,imdb_id,title,year,created_at,watched_at,is_watched,rewatch_count"
    static let v2Header = "created_at,user_id,key,updated_at,uuid,is_archived,is_followed,s_id,is_for_later,"
        + "runtime,s_no,ep_no,ep_id,series_name,season_number,episode_number"
    static let v1Header = "watch_count,uuid,type,series_name,type-uuid-n,updated_at,user_id,created_at,series_id,"
        + "release_date,alpha_range_key,movie_name,entity_type,season_number,episode_number,episode_id,"
        + "watch_date_range_key"
    static let followedHeader = "user_id,tv_show_id,notification_type,notification_offset,created_at,updated_at,"
        + "active,diffusion,folder_id,archived,tv_show_name"
    static let seenHeader = "ts,show_name,episode_id,episode_season_number,episode_number,episode_name"

    @Test("Each TV Time file is told by its columns, and auto detects it")
    func layouts() throws {
        let cases: [(String, TVTimeCSVParser.Layout)] = [
            (Self.seriesEpisodesHeader, .seriesEpisodes),
            (Self.seriesHeader, .series),
            (Self.moviesHeader, .movies),
            (Self.v2Header, .trackingV2),
            (Self.v1Header, .trackingV1),
            (Self.followedHeader, .followedShows),
            (Self.seenHeader, .seenEpisodes),
        ]
        for (header, layout) in cases {
            #expect(TVTimeCSVParser.layout(Set(CSVTable(header).headers)) == layout, "\(layout)")
            #expect(try ImportFormatDetector.detect(header + "\n") == .tvTimeCSV, "\(layout)")
        }
        #expect(throws: ImportFormatError.self) {
            try TVTimeCSVParser.parse(CSVTable("list_id,list_name,item_type,tvdb_id,uuid,name,custom_order\n"))
        }
        #expect(throws: ImportFormatError.self) { try ImportFormatDetector.detect("PK\u{03}\u{04}\u{14}\0") }
        #expect(try ImportFormatDetector.detect("Title,Year,IMDb ID\nDark,2017,tt5753856\n") == .genericCSV)
    }

    @Test("Dates: TV Time's three layouts read in UTC; 0001-01-01 is no date")
    func dates() {
        let seconds = { (raw: String) in TVTimeCSVParser.date(raw)?.timeIntervalSince1970 }
        #expect(seconds("2019-10-04 03:43:42") == 1_570_160_622)
        #expect(seconds("2019-10-04T03:43:42Z") == 1_570_160_622)
        #expect(seconds("2019-10-04T03:43:42.067614Z") == 1_570_160_622)
        #expect(seconds("2019-10-04") == 1_570_190_400)
        #expect(TVTimeCSVParser.date("0001-01-01") == nil)
        #expect(TVTimeCSVParser.date("") == nil)
    }

    // MARK: Export my data

    @Test("Series episodes: one row per show with its watched episodes; nothing watched is planned")
    func seriesEpisodes() throws {
        let rows = try TVTimeCSVParser.parse(CSVTable("""
        \(Self.seriesEpisodesHeader)
        900001,,u-1,Glasshouse,1,2,7000002,true,2021-05-02 20:00:00,0,false
        900001,,u-1,Glasshouse,1,1,7000001,true,2021-05-01 20:00:00,1,false
        900001,,u-1,Glasshouse,2,1,7000003,false,,0,false
        900001,,u-1,Glasshouse,1,1,7000001,true,2022-01-01 20:00:00,1,false
        900002,tt0900002,u-2,Harbour Lights,1,1,7000010,false,,0,false
        ,,u-3,,1,1,,true,2021-01-01 00:00:00,0,false
        """))
        #expect(rows.map(\.title) == ["Glasshouse", "Harbour Lights"])
        #expect(rows[0].ids == ExternalIDs(tvdb: "900001"))
        #expect(try rows[0].watched == [EpisodeKey(season: 1, episode: 1), EpisodeKey(season: 1, episode: 2)])
        #expect(rows[0].status == nil, "ticks make it in progress when planned")
        #expect(rows[0].notAfter == 2021)
        #expect(rows[0].nameOnly == true)
        #expect(rows[1].ids == ExternalIDs(imdb: "tt0900002", tvdb: "900002"))
        #expect(rows[1].watched == nil && rows[1].status == .wishlist)
    }

    @Test("Series: TV Time's status words map onto Aaru's; unknown words say nothing")
    func series() throws {
        let rows = try TVTimeCSVParser.parse(CSVTable("""
        \(Self.seriesHeader)
        u-1,900011,,Northbound,continuing,2018-12-18T12:39:15Z
        u-2,900012,,Paper Moons,up_to_date,2025-03-20T10:15:42.067614Z
        u-3,900013,-1,Quiet Hours,not_started_yet,2018-09-08T10:16:19Z
        u-4,900014,,Red Tide,stopped,2019-01-01T00:00:00Z
        u-5,900015,,Salt Road,something_new,2019-01-01T00:00:00Z
        """))
        #expect(rows.map(\.status) == [.inProgress, .inProgress, .wishlist, .dropped, nil])
        #expect(rows[2].ids == ExternalIDs(tvdb: "900013"), "-1 is no IMDb id")
    }

    @Test("Movies: watched ones finished on their date, the rest planned; no id needs a year")
    func movies() throws {
        let rows = try TVTimeCSVParser.parse(CSVTable("""
        \(Self.moviesHeader)
        u-1,130001,tt0130001,The Long Field,2020,2022-03-18T00:03:26Z,2022-03-18T00:03:26Z,true,0
        u-2,130002,-1,Tin Lanterns,2017,2019-09-10T08:01:29Z,,false,0
        u-3,130003,,Nameless,,2019-09-10T08:01:29Z,,false,0
        u-4,130001,tt0130001,The Long Field,2020,2023-01-01T00:00:00Z,2023-01-01T00:00:00Z,true,1
        """))
        #expect(rows.map(\.title) == ["The Long Field", "Tin Lanterns"])
        #expect(rows[0].ids == ExternalIDs(imdb: "tt0130001", tvdb: "130001"))
        #expect(rows[0].status == .finished)
        #expect(rows[0].finishedAt == TVTimeCSVParser.date("2022-03-18T00:03:26Z"))
        #expect(rows[1].ids.isEmpty && rows[1].year == 2017 && rows[1].status == .wishlist)
        #expect(rows[1].finishedAt == nil)
    }

    // MARK: GDPR export

    @Test("Tracking v2: plays tick episodes; follow flags plan or drop the rest")
    func trackingV2() throws {
        let rows = try TVTimeCSVParser.parse(CSVTable("""
        \(Self.v2Header)
        2021-11-12 17:11:33,0,tracking-stats,2026-06-04 14:04:56,,,,,,,,,,,,
        2024-11-02 11:53:58,0,watch-episode-aaa-111,2024-11-02 11:53:58,,,,900021,,2520,1,5,9000001,Treason Bay,,
        2016-08-10 16:48:22,0,watch-episode-aaa-112,2016-08-10 16:48:22,,,,900021,,,,,9000002,Treason Bay,1,4
        2017-01-01 10:00:00,0,rewatch-episode-aaa-113,2017-01-01 10:00:00,,,,900021,,,1,5,9000001,Treason Bay,,
        2020-01-01 10:00:00,0,user-series-900021,2020-01-01 10:00:00,u-1,false,true,900021,false,,,,,Treason Bay,,
        2020-01-01 10:00:00,0,user-series-900022,2020-01-01 10:00:00,u-2,false,false,900022,true,,,,,Umber,,
        2020-01-01 10:00:00,0,user-series-900023,2020-01-01 10:00:00,u-3,true,true,900023,false,,,,,Vantage,,
        2020-01-01 10:00:00,0,user-series-900024,2020-01-01 10:00:00,u-4,false,false,900024,false,,,,,Unfollowed,,
        """))
        #expect(rows.map(\.title) == ["Treason Bay", "Umber", "Vantage"])
        #expect(try rows[0].watched == [EpisodeKey(season: 1, episode: 4), EpisodeKey(season: 1, episode: 5)])
        #expect(rows[0].status == nil && rows[0].notAfter == 2016)
        #expect(rows[1].status == .wishlist, "watch later")
        #expect(rows[2].status == .dropped, "archived")
    }

    @Test("Tracking v1: movies only, by their English slug; no release date means name only")
    func trackingV1() throws {
        let rows = try TVTimeCSVParser.parse(CSVTable("""
        \(Self.v1Header)
        1,m-1,watch,,watch-m-1-0,,0,2022-04-10,,2017-10-12,watch-alpha-june,June,movie,,,,watch-date-1649590015
        ,m-2,towatch,,towatch-m-2-0,,0,2022-04-11 11:26:55,,0001-01-01,towatch-alpha-sky-sailors,하늘 선원,movie,,,,
        1,m-2,watch,,watch-m-2-0,,0,2023-02-01 11:26:55,,0001-01-01,watch-alpha-sky-sailors,하늘 선원,movie,,,,
        1,e-1,watch,Treason Bay,watch-e-1-0,,0,2021-10-10 11:49:11,,,,,episode,1,1,9000003,
        """))
        #expect(rows.map(\.title) == ["June", "sky sailors"])
        #expect(rows[0].year == 2017 && rows[0].status == .finished && rows[0].nameOnly == nil)
        #expect(rows[0].finishedAt == Date(timeIntervalSince1970: 1_649_590_015))
        #expect(rows[1].year == nil && rows[1].nameOnly == true && rows[1].notAfter == 2023)
        #expect(rows[1].status == .finished, "watched after it was on the list")
    }

    @Test("Followed shows and seen episodes")
    func followedAndSeen() throws {
        let followed = try TVTimeCSVParser.parse(CSVTable("""
        \(Self.followedHeader)
        1,900031,2,1440,2021-03-15 20:42:59,,0,,,0,Willow Creek
        1,900032,2,1440,2021-03-15 20:42:59,,0,,,1,Xanadu Line
        """))
        #expect(followed.map(\.status) == [.wishlist, .dropped])
        #expect(followed[0].ids == ExternalIDs(tvdb: "900031"))

        let seen = try TVTimeCSVParser.parse(CSVTable("""
        \(Self.seenHeader)
        1633866551,Yarrow,9000041,1,2,Second
        1570160622,Yarrow,9000040,1,1,First
        """))
        #expect(seen.count == 1 && seen[0].ids.isEmpty && seen[0].nameOnly == true)
        #expect(try seen[0].watched == [EpisodeKey(season: 1, episode: 1), EpisodeKey(season: 1, episode: 2)])
        #expect(seen[0].notAfter == 2019)
    }

    // MARK: Matching

    func importer(_ env: LibraryHarness) -> ImportService {
        ImportService(
            stores: env.stores,
            resolver: TitleResolver(stores: env.stores, catalogs: FakeCatalog.providers(env.fake))
        )
    }

    func numericID() -> String {
        String(Int.random(in: 10_000_000 ... 99_999_999))
    }

    @discardableResult
    func stub(_ env: LibraryHarness, _ type: MediaType, _ name: String, year: Int, ids: ExternalIDs) -> CatalogHit {
        let hit = CatalogHit(
            type: type, title: name, originalTitle: nil, year: year, posterURL: nil, overview: nil,
            byline: nil, ids: ids.filling(from: ExternalIDs(tmdb: uniqueID("tmdb"))), isAnime: false
        )
        env.fake.stubTitle(CatalogTitle(hit: hit, status: type == .show ? .returning : nil, runtimeMinutes: nil))
        return hit
    }

    func run(_ service: ImportService, _ env: LibraryHarness, _ text: String) async throws -> [PlannedRow] {
        let job = try await service.createCSVImport(
            userID: env.userID, source: .tvTimeCSV, filename: "tvtime.csv", text: text
        )
        while try await service.runNext(for: env.userID) {}
        let planned = try await env.stores.importJobs.rows(jobID: job.id)
        _ = try await service.apply(job.id, userID: env.userID)
        return planned
    }

    @Test("Shows match by TVDB id, an id TMDB lacks by exact name; re-running adds nothing; never backward")
    func matching() async throws {
        try await LibraryHarness.run { env in
            let (known, legacy, lost) = (uniqueID("Known"), uniqueID("Legacy"), uniqueID("Lost"))
            let (knownTVDB, legacyTVDB, lostTVDB) = (numericID(), numericID(), numericID())
            let knownHit = stub(env, .show, known, year: 2015, ids: ExternalIDs(tvdb: knownTVDB))
            // TMDB knows this show under another TVDB id than the one TV Time kept.
            let legacyHit = stub(env, .show, legacy, year: 2010, ids: ExternalIDs(tvdb: numericID()))
            env.fake.stubSearch(legacy, [legacyHit])
            let service = importer(env)

            let episodes = """
            \(Self.seriesEpisodesHeader)
            \(knownTVDB),,u-1,\(known),1,1,1,true,2020-01-01 20:00:00,0,false
            \(knownTVDB),,u-1,\(known),1,2,2,true,2020-01-02 20:00:00,0,false
            \(legacyTVDB),,u-2,\(legacy),1,1,3,true,2020-01-03 20:00:00,0,false
            \(lostTVDB),,u-3,\(lost),1,1,4,true,2020-01-04 20:00:00,0,false
            """
            let first = try await run(service, env, episodes)
            #expect(first.map(\.outcome) == [.create, .create, .unmatched])

            let knownTitle = try #require(try await env.stores.titles.find(ids: knownHit.ids, type: .show))
            let knownItem = try #require(
                try await env.stores.library.item(userID: env.userID, titleID: knownTitle.id)
            )
            #expect(knownItem.status == .inProgress)
            #expect(try await env.stores.library.watched(itemID: knownItem.id).count == 2)
            let legacyTitle = try #require(try await env.stores.titles.find(ids: legacyHit.ids, type: .show))
            #expect(try await env.stores.library.item(userID: env.userID, titleID: legacyTitle.id) != nil)

            let again = try await run(service, env, episodes)
            #expect(again.map(\.outcome) == [.skip, .skip, .unmatched], "re-running creates nothing new")

            // The series file says the show was never started: an import never moves it back.
            let series = try await run(service, env, """
            \(Self.seriesHeader)
            u-1,\(knownTVDB),,\(known),not_started_yet,2019-01-01T00:00:00Z
            """)
            #expect(series.map(\.outcome) == [.skip])
            #expect(try await env.stores.library.item(userID: env.userID, titleID: knownTitle.id)?
                .status == .inProgress)
        }
    }

    @Test("Movies match by IMDb id, or by name and year")
    func movieMatching() async throws {
        try await LibraryHarness.run { env in
            let (byID, byName) = (uniqueID("ById"), uniqueID("ByName"))
            let imdb = "tt\(numericID())"
            let idHit = stub(env, .movie, byID, year: 2020, ids: ExternalIDs(imdb: imdb))
            let nameHit = stub(env, .movie, byName, year: 2017, ids: ExternalIDs())
            env.fake.stubSearch(byName, [nameHit])
            let planned = try await run(importer(env), env, """
            \(Self.moviesHeader)
            u-1,\(numericID()),\(imdb),\(byID),2020,2022-03-18T00:03:26Z,2022-03-18T00:03:26Z,true,0
            u-2,\(numericID()),-1,\(byName),2017,2019-09-10T08:01:29Z,,false,0
            """)
            #expect(planned.map(\.outcome) == [.create, .create])
            let idTitle = try #require(try await env.stores.titles.find(ids: idHit.ids, type: .movie))
            let idItem = try #require(try await env.stores.library.item(userID: env.userID, titleID: idTitle.id))
            #expect(idItem.status == .finished)
            #expect(idItem.finishedAt == TVTimeCSVParser.date("2022-03-18T00:03:26Z"))
            let nameTitle = try #require(try await env.stores.titles.find(ids: nameHit.ids, type: .movie))
            #expect(try await env.stores.library.item(userID: env.userID, titleID: nameTitle.id)?.status == .wishlist)
        }
    }
}
