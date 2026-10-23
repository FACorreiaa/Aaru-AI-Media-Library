import AaruCore
import Foundation
import Testing
@testable import aaru

/// IMP-006/007/008: the export layouts, with the quirks real exports have. No database.
@Suite("CSV import parsers")
struct ImportParserTests {
    @Test("CSV: quoted commas, doubled quotes, CRLF and a BOM")
    func csvQuoting() {
        let table = CSVTable("\u{FEFF}Title,Note\r\n\"Dune, Part One\",\"He said \"\"hi\"\"\"\r\nPlain,x\r\n")
        #expect(table.headers == ["Title", "Note"])
        #expect(table.records.map { $0["Title"] } == ["Dune, Part One", "Plain"])
        #expect(table.records.first?["Note"] == "He said \"hi\"")
    }

    @Test("Goodreads: =\"\" ISBNs, shelf to status, stars doubled, custom shelves become lists")
    func goodreads() throws {
        let csv = #"""
        Book Id,Title,Author,ISBN,ISBN13,My Rating,Exclusive Shelf,Bookshelves,Date Read,Original Publication Year
        1,Dune,Frank Herbert,"=""0441172717""","=""9780441172719""",4,read,"favorites, read, sci-fi",2024/03/01,1965
        2,No ISBN Book,Some Author,"=""""","=""""",0,to-read,to-read,,2001
        3,Reading Now,An Author,,,0,currently-reading,currently-reading,,2010
        """#
        let rows = try CSVImportParser.parse(csv, source: .goodreadsCSV, filename: nil)
        #expect(rows.count == 3)
        #expect(rows[0].ids.isbn == "9780441172719")
        #expect(rows[0].status == .finished)
        #expect(rows[0].rating == 8)
        #expect(rows[0].lists == ["favorites", "sci-fi"], "read is the exclusive shelf, not a list")
        #expect(rows[0].finishedAt != nil)
        #expect(rows[1].ids.isbn == nil, "an empty =\"\" ISBN is no ISBN")
        #expect(rows[1].author == "Some Author", "title + author is the fallback")
        #expect(rows[1].status == .wishlist)
        #expect(rows[1].rating == nil, "0 stars means not rated")
        #expect(rows[2].status == .inProgress)
    }

    @Test("Goodreads (IMP-020): series suffix, did-not-finish shelves, review or private notes, owned copies")
    func goodreadsMore() throws {
        let csv = #"""
        Book Id,Title,Author,Exclusive Shelf,Bookshelves,My Review,Private Notes,Owned Copies
        1,"Leviathan Wakes (The Expanse, #1)",James S.A. Corey,dnf,dnf,"Slow.<br/>Gave up &amp; moved on.",Hidden,1
        2,"Dune (Deluxe Edition)",Frank Herbert,Did Not Finish,did-not-finish,,"Private, only",0
        3,"Small Gods (Discworld, #13; Omnieni #1)",Terry Pratchett,abandoned,,<p> </p>,,
        4,Plain,Someone,Dropped,,,,x
        5,Shelved,Someone,favorites,favorites,,,
        """#
        let rows = try CSVImportParser.parse(csv, source: .goodreadsCSV, filename: nil)
        #expect(rows.map(\.title) == ["Leviathan Wakes", "Dune (Deluxe Edition)", "Small Gods", "Plain", "Shelved"])
        #expect(rows.map(\.status) == [.dropped, .dropped, .dropped, .dropped, nil])
        #expect(rows[0].lists == ["dnf"], "a custom exclusive shelf is still a list")
        #expect(rows[0].notes == "Slow.\nGave up & moved on.", "the review wins over private notes")
        #expect(rows[1].notes == "Private, only")
        #expect(rows[2].notes == nil, "a review with nothing in it is no notes")
        #expect(rows.map(\.isOwned) == [true, nil, nil, nil, nil], "only a count above 0 says owned")
    }

    @Test("Goodreads: only a bracket that numbers the book in a series leaves the title")
    func goodreadsSeriesSuffix() {
        #expect(CSVImportParser.withoutSeries("The Way of Kings (The Stormlight Archive, #1)") == "The Way of Kings")
        #expect(CSVImportParser.withoutSeries("Mistborn (Mistborn, #0.5)") == "Mistborn")
        #expect(CSVImportParser.withoutSeries("Omnibus (Series #1-3)") == "Omnibus")
        #expect(CSVImportParser.withoutSeries("Catch-22 (50th Anniversary)") == "Catch-22 (50th Anniversary)")
        #expect(CSVImportParser.withoutSeries("(#1)") == "(#1)", "a title that is only the bracket stays")
        #expect(CSVImportParser.plainText("3 < 4 &lt;b&gt;") == "3 < 4 <b>", "only real tags go")
    }

    @Test("IMDb: tconst is the id, episodes are refused with a reason, the watchlist is a wishlist")
    func imdb() throws {
        let ratings = #"""
        Const,Your Rating,Date Rated,Title,Title Type,Year
        tt0133093,9,2024-01-02,The Matrix,Movie,1999
        tt0944947,10,2024-01-03,Game of Thrones,TV Series,2011
        tt1480055,8,2024-01-04,Winter Is Coming,TV Episode,2011
        """#
        let rows = try CSVImportParser.parse(ratings, source: .imdbCSV, filename: "ratings.csv")
        #expect(rows.map(\.type) == [.movie, .show, .movie])
        #expect(rows[0].ids.imdb == "tt0133093")
        #expect(rows[0].status == .finished)
        #expect(rows[0].rating == 9)
        #expect(rows[2].unsupported != nil)
        let watchlist = "Position,Const,Title,Title Type,Year\n1,tt0133093,The Matrix,Movie,1999\n"
        #expect(try CSVImportParser.parse(watchlist, source: .imdbCSV, filename: nil).first?.status == .wishlist)
    }

    @Test("Letterboxd: half stars double onto 1–10, the watchlist file is a wishlist")
    func letterboxd() throws {
        let diary = #"""
        Date,Name,Year,Letterboxd URI,Rating,Watched Date
        2024-02-01,Heat,1995,https://boxd.it/abc,4.5,2024-01-31
        2024-02-02,Crash,2004,https://boxd.it/def,0.5,
        """#
        let rows = try CSVImportParser.parse(diary, source: .letterboxdCSV, filename: "diary.csv")
        #expect(rows.map(\.rating) == [9, 1])
        #expect(rows[0].status == .finished)
        #expect(rows[0].ids.isEmpty, "no id: title + year resolution")
        let watchlist = "Date,Name,Year,Letterboxd URI\n2024-02-01,Heat,1995,https://boxd.it/abc\n"
        let wish = try CSVImportParser.parse(watchlist, source: .letterboxdCSV, filename: "watchlist.csv")
        #expect(wish.first?.status == .wishlist)
    }

    @Test("A file uploaded as the wrong source fails with a readable message")
    func wrongColumns() {
        let goodreads = "Title,Author,Exclusive Shelf\nDune,Frank Herbert,read\n"
        #expect(throws: ImportFormatError.self) {
            _ = try CSVImportParser.parse(goodreads, source: .imdbCSV, filename: nil)
        }
        do {
            _ = try CSVImportParser.parse(goodreads, source: .letterboxdCSV, filename: nil)
        } catch let error as ImportFormatError {
            #expect(error.message.contains("Letterboxd") && error.message.contains("Name"))
        } catch {
            Issue.record("unexpected \(error)")
        }
    }
}
