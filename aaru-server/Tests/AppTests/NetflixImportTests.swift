import AaruCore
import Foundation
import Testing
@testable import aaru

/// IMP-018: Netflix's viewing activity download, against stubs.
@Suite("Netflix import", .serialized)
struct NetflixImportTests {
    // MARK: Parser

    @Test("Titles: the first segment that reads as a season splits show from episode")
    func titles() {
        let cases: [(String, NetflixCSVParser.Entry)] = [
            ("Breaking Bad: Season 1: Pilot", .init(
                type: .show,
                title: "Breaking Bad",
                episode: NamedEpisode(season: 1, name: "Pilot")
            )),
            ("Baby Reindeer: Limited Series: Episode 3", .init(
                type: .show,
                title: "Baby Reindeer",
                episode: NamedEpisode(season: 1, name: "Episode 3")
            )),
            (
                "Stranger Things: Stranger Things 4: Chapter One: The Hellfire Club",
                .init(
                    type: .show,
                    title: "Stranger Things",
                    episode: NamedEpisode(season: 4, name: "Chapter One: The Hellfire Club")
                )
            ),
            ("Money Heist: Part 5: Episode 1", .init(
                type: .show,
                title: "Money Heist",
                episode: NamedEpisode(season: 5, name: "Episode 1")
            )),
            ("Star Wars: Andor: Season 2: One Year Later", .init(
                type: .show,
                title: "Star Wars: Andor",
                episode: NamedEpisode(
                    season: 2,
                    name: "One Year Later"
                )
            )),
            ("La Casa de Papel: Temporada 2: Episodio 3", .init(
                type: .show,
                title: "La Casa de Papel",
                episode: NamedEpisode(season: 2, name: "Episodio 3")
            )),
            ("Mission: Impossible - Fallout", .init(type: .movie, title: "Mission: Impossible - Fallout")),
            ("Glass Onion: A Knives Out Mystery", .init(type: .movie, title: "Glass Onion: A Knives Out Mystery")),
            ("Roma", .init(type: .movie, title: "Roma")),
        ]
        for (raw, expected) in cases {
            #expect(NetflixCSVParser.entry(raw) == expected, "\(raw)")
        }
    }

    @Test("Dates: month first unless a day passes 12; ISO and two-digit years read")
    func dates() throws {
        let iso = DateFormatter.iso8601Day
        let usOrder = NetflixCSVParser.DateOrder.of(["1/23/24", "2/3/24"])
        #expect(usOrder == .monthFirst)
        #expect(try iso.string(from: #require(NetflixCSVParser.day("1/23/24", order: usOrder))) == "2024-01-23")
        let euOrder = NetflixCSVParser.DateOrder.of(["03/02/2024", "23/01/2024"])
        #expect(euOrder == .dayFirst)
        #expect(try iso.string(from: #require(NetflixCSVParser.day("03/02/2024", order: euOrder))) == "2024-02-03")
        #expect(try iso.string(from: #require(NetflixCSVParser.day("2024-01-23", order: usOrder))) == "2024-01-23")
        #expect(try iso.string(from: #require(NetflixCSVParser.day("23.01.2024", order: euOrder))) == "2024-01-23")
        #expect(NetflixCSVParser.day("yesterday", order: usOrder) == nil)
    }

    @Test("Rows: one per show with its episodes, one per film; first watch year kept")
    func rows() throws {
        let rows = try NetflixCSVParser.parse(CSVTable("""
        Title,Date
        "Breaking Bad: Season 1: Gray Matter",3/2/21
        "Breaking Bad: Season 1: Pilot",3/1/21
        "Roma",6/5/23
        "Breaking Bad: Season 1: Pilot",12/30/20
        "Roma",1/5/19
        """))
        #expect(rows.map(\.title) == ["Breaking Bad", "Roma"])
        #expect(rows[0].type == .show && rows[0].status == .inProgress && rows[0].nameOnly == true)
        #expect(rows[0].namedEpisodes == [
            NamedEpisode(season: 1, name: "Gray Matter"), NamedEpisode(season: 1, name: "Pilot"),
        ])
        #expect(rows.map(\.notAfter) == [2020, 2019])
        #expect(rows[1].type == .movie && rows[1].status == .finished)
        #expect(rows[1].finishedAt.map(DateFormatter.iso8601Day.string) == "2023-06-05")
        #expect(rows[0].finishedAt == nil)
    }

    @Test("Format: detected by its two columns; the all-profiles download is refused")
    func format() throws {
        #expect(try ImportFormatDetector.detect("Title,Date\nRoma,1/5/19\n") == .netflixCSV)
        #expect(throws: ImportFormatError.self) {
            try NetflixCSVParser.parse(CSVTable("Profile Name,Start Time,Title\nAna,2024-01-01,Roma\n"))
        }
        #expect(throws: ImportFormatError.self) { try NetflixCSVParser.parse(CSVTable("Name,Year\nRoma,2018\n")) }
    }

    @Test("Episodes by name: same season first, else the one match in the show, never two")
    func episodeNames() {
        let episodes = [
            CatalogEpisode(season: 0, episode: 1, name: "Pilot"),
            CatalogEpisode(season: 1, episode: 1, name: "Pilot"),
            CatalogEpisode(season: 1, episode: 2, name: "Cat's in the Bag..."),
            CatalogEpisode(season: 2, episode: 1, name: "Seven Thirty-Seven"),
            CatalogEpisode(season: 3, episode: 1, name: "Untitled"),
            CatalogEpisode(season: 4, episode: 1, name: "Untitled"),
        ]
        func match(_ season: Int?, _ name: String) -> EpisodeKey? {
            EpisodeNameMatcher.match(NamedEpisode(season: season, name: name), in: episodes)
        }
        #expect(match(1, "Pilot") == (try? EpisodeKey(season: 1, episode: 1)))
        #expect(match(1, "Cat’s in the Bag…") == (try? EpisodeKey(season: 1, episode: 2)))
        #expect(match(1, "Seven Thirty-Seven") == (try? EpisodeKey(season: 2, episode: 1)), "Netflix's season 1")
        #expect(match(nil, "Pilot") == (try? EpisodeKey(season: 1, episode: 1)), "specials need season 0")
        #expect(match(2, "Untitled") == nil)
        #expect(match(1, "Not an episode") == nil)
    }

    // MARK: Matching

    func importer(_ env: LibraryHarness) -> ImportService {
        ImportService(
            stores: env.stores,
            resolver: TitleResolver(stores: env.stores, catalogs: FakeCatalog.providers(env.fake))
        )
    }

    @discardableResult
    func stub(_ env: LibraryHarness, _ type: MediaType, _ name: String, year: Int) -> CatalogHit {
        let hit = CatalogHit(
            type: type, title: name, originalTitle: nil, year: year, posterURL: nil, overview: nil,
            byline: nil, ids: ExternalIDs(tmdb: uniqueID("tmdb")), isAnime: false
        )
        env.fake.stubTitle(CatalogTitle(hit: hit, status: type == .show ? .returning : nil, runtimeMinutes: nil))
        return hit
    }

    @Test("A file plans shows with named episodes ticked and films finished; remakes stay unmatched")
    func matching() async throws {
        try await LibraryHarness.run { env in
            let (show, film, remade, later) = (
                uniqueID("Show"),
                uniqueID("Film"),
                uniqueID("Remade"),
                uniqueID("Later")
            )
            let showHit = stub(env, .show, show, year: 2015)
            try env.fake.stubEpisodes(#require(showHit.ids.tmdb), CatalogEpisodes(status: .returning, episodes: [
                CatalogEpisode(season: 1, episode: 1, name: "Arrival"),
                CatalogEpisode(season: 1, episode: 2, name: "Departure"),
                CatalogEpisode(season: 2, episode: 1, name: "Return"),
            ]))
            env.fake.stubSearch(show, [showHit])
            let filmHit = stub(env, .movie, film, year: 2019)
            env.fake.stubSearch(film, [filmHit])
            env.fake.stubSearch(remade, [stub(env, .movie, remade, year: 1990), stub(env, .movie, remade, year: 2016)])
            let original = stub(env, .movie, later, year: 2001)
            env.fake.stubSearch(later, [original, stub(env, .movie, later, year: 2024)])

            let service = importer(env)
            let job = try await service.createCSVImport(
                userID: env.userID,
                source: .netflixCSV,
                filename: nil,
                text: """
                Title,Date
                "\(show): Season 1: Arrival",1/2/22
                "\(show): Season 1: Return",1/3/22
                "\(show): Season 1: Not On TMDB",1/4/22
                "\(film)",5/6/22
                "\(remade)",5/7/22
                "\(later)",5/8/22
                """
            )
            while try await service.runNext(for: env.userID) {}
            let planned = try await env.stores.importJobs.rows(jobID: job.id)
            #expect(planned.map(\.outcome) == [.create, .create, .unmatched, .create])
            #expect(planned[2].reason == "Several films are called “\(remade)”. Pick the right one by hand.")
            #expect(planned[0].row.namedEpisodes == nil)
            #expect(try planned[0].row.watched == [
                EpisodeKey(season: 1, episode: 1),
                EpisodeKey(season: 2, episode: 1),
            ])
            _ = try await service.apply(job.id, userID: env.userID)
            try await expectApplied(env, show: showHit, film: filmHit, original: original)
        }
    }

    func expectApplied(
        _ env: LibraryHarness,
        show showHit: CatalogHit,
        film filmHit: CatalogHit,
        original: CatalogHit
    ) async throws {
        do {
            let showTitle = try #require(try await env.stores.titles.find(ids: showHit.ids, type: .show))
            let showItem = try #require(try await env.stores.library.item(userID: env.userID, titleID: showTitle.id))
            #expect(showItem.status == .inProgress)
            #expect(try await env.stores.library.watched(itemID: showItem.id).count == 2)
            let filmTitle = try #require(try await env.stores.titles.find(ids: filmHit.ids, type: .movie))
            #expect(try await env.stores.library.item(userID: env.userID, titleID: filmTitle.id)?.status == .finished)
            let laterTitle = try #require(try await env.stores.titles.find(ids: original.ids, type: .movie))
            #expect(
                try await env.stores.library.item(userID: env.userID, titleID: laterTitle.id) != nil,
                "the 2024 remake came out after it was watched in 2022"
            )
        }
    }
}

private extension DateFormatter {
    static let iso8601Day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
