import Testing
@testable import AaruCore

struct ISBNTests {
    @Test
    func isbn10AndItsIsbn13AreTheSameKey() {
        #expect(ISBN.normalize("0-441-17271-7") == "9780441172719") // Dune, ISBN-10
        #expect(ISBN.normalize("978-0-441-17271-9") == "9780441172719") // Dune, ISBN-13
    }

    @Test
    func toleratesGoodreadsWrappingAndAnXCheckDigit() {
        #expect(ISBN.normalize(#"="0441172717""#) == "9780441172719")
        #expect(ISBN.normalize("080442957X") == "9780804429573")
    }

    @Test
    func rejectsBadChecksumsAndShapes() {
        #expect(ISBN.normalize("0441172718") == nil)
        #expect(ISBN.normalize("9780441172710") == nil)
        #expect(ISBN.normalize("") == nil)
        #expect(ISBN.normalize("12345") == nil)
    }
}
