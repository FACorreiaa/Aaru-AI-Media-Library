import AaruCore
import FluentSQL
import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
@testable import aaru

/// IMP-009 and IMP-010: Pogdesign CAT by pasted list, iCal file, or iCal link, against stubs.
@Suite("Pogdesign CAT import", .serialized)
struct CATImportTests {
    // MARK: Parsers

    @Test("List: one show per line, bullets dropped, (YYYY) read as the year, repeats folded")
    func list() throws {
        let rows = try CATListParser.parse("""
        Severance
        - The Bear
        3. Brothers (2026)

        • severance
        Slow Horses\r
        """)
        #expect(rows.map(\.title) == ["Severance", "The Bear", "Brothers", "Slow Horses"])
        #expect(rows.map(\.year) == [nil, nil, 2026, nil])
        #expect(rows.map(\.nameOnly) == [true, true, nil, true])
        #expect(rows.allSatisfy { $0.type == .show && $0.status == .wishlist && $0.watched == nil })
    }

    @Test("List: a line too long to be a name is listed as unmatched; too many lines is refused")
    func listLimits() throws {
        let rows = try CATListParser.parse("Severance\n" + String(repeating: "x", count: 300))
        #expect(rows.count == 2 && rows[1].unsupported != nil)
        let many = (0 ... CATImport.maxLines).map { "Show \($0)" }.joined(separator: "\n")
        #expect(throws: ImportFormatError.self) { try CATListParser.parse(many) }
    }

    static func calendar(_ summaries: [String]) -> String {
        let events = summaries.enumerated().map { index, summary in
            "BEGIN:VEVENT\r\nUID:\(index)@pogdesign\r\nDTSTART;VALUE=DATE:20261021\r\nSUMMARY:\(summary)\r\nEND:VEVENT"
        }
        return (["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//CAT//EN"] + events + ["END:VCALENDAR"])
            .joined(separator: "\r\n") + "\r\n"
    }

    @Test("ICS: 200 events across 15 shows become 15 rows")
    func calendarCollapses() throws {
        let summaries = (0 ..< 200).map { index in
            "Show \(index % 15): S\(index / 15 + 1)E\(index % 9 + 1) - Episode \(index)"
        }
        let rows = try CATCalendarParser.parse(Self.calendar(summaries))
        #expect(rows.count == 15)
        #expect(Set(rows.map(\.title)) == Set((0 ..< 15).map { "Show \($0)" }))
        #expect(rows.allSatisfy { $0.status == .wishlist && $0.unsupported == nil })
    }

    @Test("ICS: folded lines and escapes are read; an unreadable summary is surfaced once")
    func calendarFolding() throws {
        let text = """
        BEGIN:VCALENDAR\r
        BEGIN:VEVENT\r
        SUMMARY;LANGUAGE=en:Law & Order\\, Special Victims Unit: S27E\r
         03 - Part One\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        SUMMARY:Doctor Who (2023) - 2x05\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        SUMMARY:Season premiere night\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        SUMMARY:Season premiere night\r
        END:VEVENT\r
        END:VCALENDAR\r
        """
        let rows = try CATCalendarParser.parse(text)
        #expect(rows.map(\.title) == ["Law & Order, Special Victims Unit", "Doctor Who", "Season premiere night"])
        #expect(rows[1].year == 2023)
        #expect(rows[2].unsupported == "Couldn't read a show name from “Season premiere night”.")
    }

    @Test("ICS: each show keeps its first episode and that event's day")
    func calendarAirings() throws {
        let text = """
        BEGIN:VCALENDAR\r
        BEGIN:VEVENT\r
        DTSTART:20261026T000000\r
        SUMMARY:The Simpsons S38E04 - \\nTreehouse of Horror XXXVII\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        DTSTART:20261102T010000\r
        SUMMARY:The Simpsons S38E05 - \\nThe Kosmic Kruiser\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        SUMMARY:Doctor Who - 2x05\r
        DTSTART;VALUE=DATE:20261031\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        SUMMARY:Tracker S03E04\r
        END:VEVENT\r
        END:VCALENDAR\r
        """
        let rows = try CATCalendarParser.parse(text)
        #expect(rows.map(\.title) == ["The Simpsons", "Doctor Who", "Tracker"])
        #expect(rows.map(\.airing) == [
            ImportAiring(season: 38, episode: 4, day: "2026-10-26"),
            ImportAiring(season: 2, episode: 5, day: "2026-10-31"),
            nil,
        ])
    }

    @Test("Detection: a calendar is CAT's; a list is never mistaken for one")
    func detection() throws {
        #expect(try ImportFormatDetector.detect("\u{FEFF}BEGIN:VCALENDAR\r\nEND:VCALENDAR") == .catICS)
        #expect(throws: ImportFormatError.self) { try CATCalendarParser.parse("Severance\nThe Bear") }
    }

    @Test("Link: only CAT's own iCal link, rewritten to generate_ics")
    func links() throws {
        let url = try CATCalendarFeed.calendarURL(" https://www.pogdesign.co.uk/cat/download_ics/abc123DEF \n")
        #expect(url.absoluteString == "https://www.pogdesign.co.uk/cat/generate_ics/abc123DEF")
        #expect(try CATCalendarFeed.calendarURL("https://pogdesign.co.uk/cat/generate_ics/k-1/").host() ==
            "www.pogdesign.co.uk")
        for bad in [
            "http://www.pogdesign.co.uk/cat/download_ics/abc",
            "https://evil.example/cat/download_ics/abc",
            "https://www.pogdesign.co.uk.evil.example/cat/download_ics/abc",
            "https://www.pogdesign.co.uk/cat/show-select",
            "https://www.pogdesign.co.uk/cat/download_ics/abc/../../x",
            "https://www.pogdesign.co.uk:8443/cat/download_ics/abc",
            "https://user@www.pogdesign.co.uk/cat/download_ics/abc",
            "not a link",
        ] {
            #expect(throws: AppError.self, "\(bad)") { try CATCalendarFeed.calendarURL(bad) }
        }
    }

    // MARK: Matching

    func importer(_ env: LibraryHarness, feed: CATCalendarFeed? = nil) -> ImportService {
        ImportService(
            stores: env.stores,
            resolver: TitleResolver(stores: env.stores, catalogs: FakeCatalog.providers(env.fake)),
            catFeed: feed
        )
    }

    /// A show the fake TMDB finds by `name` and can hydrate.
    @discardableResult
    func stubShow(_ env: LibraryHarness, _ name: String, year: Int = 2020) -> CatalogHit {
        let hit = CatalogHit(
            type: .show, title: name, originalTitle: nil, year: year, posterURL: nil, overview: nil,
            byline: nil, ids: ExternalIDs(tmdb: uniqueID("tmdb")), isAnime: false
        )
        env.fake.stubTitle(CatalogTitle(hit: hit, status: .returning, runtimeMinutes: nil))
        return hit
    }

    @Test("A unique name is created as wishlist; a shared name or no hit is unmatched; nothing moves back")
    func matching() async throws {
        try await LibraryHarness.run { env in
            let (unique, shared, owned, missing) = (
                uniqueID("Unique"),
                uniqueID("Shared"),
                uniqueID("Owned"),
                uniqueID("Missing")
            )
            let uniqueHit = stubShow(env, unique)
            env.fake.stubSearch(unique, [uniqueHit])
            env.fake.stubSearch(shared, [stubShow(env, shared, year: 2005), stubShow(env, shared, year: 2019)])
            let ownedHit = stubShow(env, owned)
            env.fake.stubSearch(owned, [ownedHit])
            _ = try await env.add("show", tmdb: #require(ownedHit.ids.tmdb), status: "in_progress")
            let service = importer(env)

            let job = try await service.createCATImport(
                userID: env.userID, text: [unique, shared, owned, missing].joined(separator: "\n")
            )
            #expect(job.source == .catList)
            while try await service.runNext(for: env.userID) {}
            let planned = try await env.stores.importJobs.rows(jobID: job.id)
            #expect(planned.map(\.outcome) == [.create, .unmatched, .skip, .unmatched])
            #expect(planned[1].reason == "Several shows are called “\(shared)”. Pick the right one by hand.")
            _ = try await service.apply(job.id, userID: env.userID)

            let created = try #require(try await env.stores.titles.find(ids: uniqueHit.ids, type: .show))
            let item = try #require(try await env.stores.library.item(userID: env.userID, titleID: created.id))
            #expect(item.status == .wishlist)
            #expect(try await env.stores.library.watched(itemID: item.id).isEmpty)
            let ownedTitle = try #require(try await env.stores.titles.find(ids: ownedHit.ids, type: .show))
            #expect(try await env.stores.library.item(userID: env.userID, titleID: ownedTitle.id)?.status ==
                .inProgress)
        }
    }

    @Test("ICS: of two shows with one name, the one airing that episode that day is the match")
    func airingTiebreak() async throws {
        try await LibraryHarness.run { env in
            let (remade, bothAir) = (uniqueID("Remade"), uniqueID("BothAir"))
            func episodes(_ hit: CatalogHit, airs day: String) throws {
                try env.fake.stubEpisodes(#require(hit.ids.tmdb), CatalogEpisodes(status: .returning, episodes: [
                    CatalogEpisode(season: 2, episode: 3, airsAt: Date.catalogDay(day)),
                ]))
            }
            let (original, remake) = (stubShow(env, remade, year: 2005), stubShow(env, remade, year: 2025))
            try episodes(original, airs: "2006-03-01")
            try episodes(remake, airs: "2026-10-20")
            env.fake.stubSearch(remade, [original, remake])
            let (first, second) = (stubShow(env, bothAir, year: 2010), stubShow(env, bothAir, year: 2024))
            try episodes(first, airs: "2026-10-21")
            try episodes(second, airs: "2026-10-22")
            env.fake.stubSearch(bothAir, [first, second])
            let service = importer(env)
            let job = try await service.createCATImport(
                userID: env.userID, text: Self.calendar(["\(remade) S02E03", "\(bothAir) S02E03"])
            )
            while try await service.runNext(for: env.userID) {}
            let planned = try await env.stores.importJobs.rows(jobID: job.id)
            #expect(planned.map(\.outcome) == [.create, .unmatched])
            #expect(try await planned[0].titleID == env.stores.titles.find(ids: remake.ids, type: .show)?.id)
            #expect(planned[1].reason == "Several shows are called “\(bothAir)”. Pick the right one by hand.")
        }
    }

    @Test("POST /v1/imports/cat takes a pasted list or a calendar file")
    func route() async throws {
        try await LibraryHarness.run { env in
            func post(_ text: String, _ type: String) async throws -> [String: Any] {
                try await env.client.execute(
                    uri: "/v1/imports/cat", method: .post,
                    headers: [.authorization: "Bearer \(env.token)", .contentType: type],
                    body: ByteBuffer(string: text)
                ) { response in
                    #expect(response.status == .accepted)
                    return try LibraryHarness.Reply(status: response.status, body: Data(buffer: response.body)).json()
                }
            }
            let list = try await post("Severance\nThe Bear", "text/plain")["source"] as? String
            let calendar = try await post(Self.calendar(["Severance: S02E01"]), "text/calendar")["source"] as? String
            #expect(list == "cat_list")
            #expect(calendar == "cat_ics")
        }
    }

    // MARK: The link

    @Test("Link: the calendar is read once from generate_ics and the link is not kept")
    func feed() async throws {
        try await LibraryHarness.run { env in
            let key = uniqueID("catkey")
            let calendar = Self.calendar(["Severance: S02E01", "Severance: S02E02", "The Bear: S04E01"])
            let transport = StubTransport { _ in OutboundResponse(status: 200, body: Data(calendar.utf8)) }
            var client = ProviderClient(
                name: "pogdesign", transport: transport, pacer: RequestPacer(requestsPerSecond: 1000, burst: 100)
            )
            client.sleep = { _ in }
            let service = importer(env, feed: CATCalendarFeed(client: client))

            let job = try await service.createCATFeedImport(
                userID: env.userID, link: "https://www.pogdesign.co.uk/cat/download_ics/\(key)"
            )
            #expect(job.source == .catICS && job.filename == nil)
            #expect(transport.requests.map(\.url.absoluteString) == [
                "https://www.pogdesign.co.uk/cat/generate_ics/\(key)",
            ])
            #expect(try await env.stores.importJobs.rows(jobID: job.id).map(\.row.title) == ["Severance", "The Bear"])
            #expect(try await Self.rowsMentioning(key) == 0, "the link's key is never stored")

            transport.respond { _ in OutboundResponse(status: 200, body: Data("<html>Log in</html>".utf8)) }
            await #expect(throws: AppError.self, "a page that is not a calendar") {
                try await service.createCATFeedImport(
                    userID: env.userID, link: "https://www.pogdesign.co.uk/cat/download_ics/\(key)"
                )
            }
        }
    }

    static func rowsMentioning(_ text: String) async throws -> Int? {
        try await withSQL { sql in
            try await sql.raw("""
            SELECT ((SELECT count(*) FROM import_rows WHERE row::text LIKE \(bind: "%\(text)%"))
                 + (SELECT count(*) FROM import_jobs WHERE to_jsonb(import_jobs)::text LIKE \(bind: "%\(text)%")))::int
                 AS count
            """).first(decoding: StremioImportTests.Count.self)?.count
        }
    }
}

// MARK: A real export

extension CATImportTests {
    /// Trimmed from a real CAT export (2026-10-21). The header's PRODID, which carries the user's
    /// CAT key and email, is replaced.
    static let realExport = """
    BEGIN:VCALENDAR\r
    VERSION:2.0\r
    CALSCALE:GREGORIAN\r
    X-WR-CALDESC:Calendar for TV from Pogdesign\r
    X-WR-CALNAME:TV Shows\r
    X-WR-TIMEZONE:Europe/Lisbon\r
    PRODID:-//Pogdesign//TV//EN\r
    METHOD:PUBLISH\r
    BEGIN:VEVENT\r
    DTSTART:20261026T000000\r
    DTEND:20261026T003000\r
    SUMMARY:The Simpsons S38E04 - \\nTreehouse of Horror XXXVII\r
    URL:https://www.pogdesign.co.uk/cat/The-Simpsons-summary\r
    UID:THESIMPSONS_38_4\r
    CATEGORIES: The Simpsons Episodes, TV Shows\r
    END:VEVENT\r
    BEGIN:VEVENT\r
    DTSTART:20261026T010000\r
    DTEND:20261026T020000\r
    SUMMARY:Tracker S04E04 - \\nPurification\r
    DESCRIPTION:When a woman disappears after helping a terrified teenage\r
      runaway\\, Colter uncovers a disturbing case of abuse and\r
      embarks on a desperate search to save them both.\r
    URL:https://www.pogdesign.co.uk/cat/Tracker-summary\r
    UID:TRACKER_4_4\r
    END:VEVENT\r
    BEGIN:VEVENT\r
    DTSTART:20261102T020000\r
    SUMMARY:Tracker S04E05 - \\nNeed to Know\r
    UID:TRACKER_4_5\r
    END:VEVENT\r
    BEGIN:VEVENT\r
    DTSTART:20261022T010000\r
    SUMMARY:Scrubs (2026) S02E05 - \\nMy Best Friend&#039\\;s Birthday\r
    URL:https://www.pogdesign.co.uk/cat/Scrubs-2026-summary\r
    UID:SCRUBS2026_2_5\r
    END:VEVENT\r
    BEGIN:VEVENT\r
    DTSTART:20261022T045900\r
    SUMMARY:Brothers (2026) S01E06 - \\nThe Dance\r
    UID:BROTHERS2026_1_6\r
    END:VEVENT\r
    END:VCALENDAR\r
    """

    @Test("A real CAT export: one row per show, CAT's (2026) as the year, each with its first airing")
    func realExportRows() throws {
        let rows = try CATCalendarParser.parse(Self.realExport)
        #expect(rows.map(\.title) == ["The Simpsons", "Tracker", "Scrubs", "Brothers"])
        #expect(rows.map(\.year) == [nil, nil, 2026, 2026])
        #expect(rows.map(\.nameOnly) == [true, true, nil, nil])
        #expect(rows.map(\.airing) == [
            ImportAiring(season: 38, episode: 4, day: "2026-10-26"),
            ImportAiring(season: 4, episode: 4, day: "2026-10-26"),
            ImportAiring(season: 2, episode: 5, day: "2026-10-22"),
            ImportAiring(season: 1, episode: 6, day: "2026-10-22"),
        ])
        #expect(try ImportFormatDetector.detect(Self.realExport) == .catICS)
    }
}
