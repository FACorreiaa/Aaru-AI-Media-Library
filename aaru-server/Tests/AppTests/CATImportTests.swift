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
