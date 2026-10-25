import AaruCore
import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
@testable import aaru

/// Importing any site's CSV, and `source=auto` picking the right parser.
@Suite("Generic CSV and format detection", .serialized)
struct GenericImportTests {
    @Test("auto: MAL-format XML, the three named CSVs, and anything else as a generic CSV")
    func detection() throws {
        #expect(try ImportFormatDetector
            .detect("\u{FEFF}<?xml version=\"1.0\"?><myanimelist></myanimelist>") == .malXML)
        #expect(try ImportFormatDetector.detect("Const,Your Rating,Title,Title Type\n") == .imdbCSV)
        #expect(try ImportFormatDetector.detect("Date,Name,Year,Letterboxd URI\n") == .letterboxdCSV)
        #expect(try ImportFormatDetector.detect("Book Id,Title,Exclusive Shelf\n") == .goodreadsCSV)
        #expect(try ImportFormatDetector.detect("Name,Year,Watched\n") == .genericCSV)
        #expect(throws: ImportFormatError.self) { try ImportFormatDetector.detect("<rss><channel/></rss>") }
    }

    @Test("Generic CSV: columns by common names, ids, type, status words, 5-star ratings doubled")
    func parse() throws {
        let rows = try GenericCSVParser.parse(CSVTable("""
        Title,Release Date,Media Type,IMDb ID,TMDB ID,Status,My Rating,Watched At
        Arrival,2016-11-11,Movie,tt2543164,329865,Completed,4.5,2024-02-01
        Severance,2022,TV Show,,95396,Watching,5,
        Some Book,2001,,,,Want to Read,,
        ,,,,,,,
        """))
        #expect(rows.count == 3, "a row with neither a title nor an id is skipped")
        #expect(rows[0].type == .movie && rows[0].year == 2016 && rows[0].ids.imdb == "tt2543164")
        #expect(rows[0].ids.tmdb == "329865" && rows[0].status == .finished && rows[0].rating == 9)
        #expect(rows[0].finishedAt == Date.catalogDay("2024-02-01"))
        #expect(rows[1].type == .show && rows[1].status == .inProgress && rows[1].rating == 10)
        #expect(rows[2].status == .wishlist && rows[2].rating == nil)
        #expect(throws: ImportFormatError.self) { try GenericCSVParser.parse(CSVTable("Foo,Bar\n1,2")) }
    }

    @Test("LIB-007: on hold and paused read as on hold, the word Aaru's own export writes")
    func onHoldWords() {
        #expect(GenericCSVParser.status("On hold") == .onHold)
        #expect(GenericCSVParser.status("on-hold") == .onHold)
        #expect(GenericCSVParser.status("Paused") == .onHold)
        #expect(GenericCSVParser.status(AccountExport.statusWord(.onHold)) == .onHold)
        for status in LibraryStatus.allCases {
            #expect(GenericCSVParser.status(AccountExport.statusWord(status)) == status, "\(status) round-trips")
        }
    }

    @Test("Ratings: 0–5 doubles, 0–10 stays, percentages divide by ten")
    func ratingScales() {
        #expect(GenericCSVParser.ratingScale([3, 4.5]) == 2)
        #expect(GenericCSVParser.ratingScale([7, 10]) == 1)
        #expect(GenericCSVParser.ratingScale([85, 60]) == 0.1)
    }

    @Test("source=auto on a generic CSV queues a `csv` job")
    func autoUpload() async throws {
        try await LibraryHarness.run { env in
            let reply = try await env.client.execute(
                uri: "/v1/imports/csv?source=auto&filename=simkl.csv",
                method: .post,
                headers: [.authorization: "Bearer \(env.token)", .contentType: "text/csv"],
                body: ByteBuffer(string: "Title,Year,Type\nArrival,2016,movie\n")
            ) { LibraryHarness.Reply(status: $0.status, body: Data(buffer: $0.body)) }
            #expect(reply.status == .accepted)
            #expect(try reply.json()["source"] as? String == "csv")
        }
    }
}
