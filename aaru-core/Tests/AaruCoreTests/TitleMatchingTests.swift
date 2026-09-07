import Testing

@testable import AaruCore

@Suite
struct TitleMatchingTests {
    @Test
    func normalizeLowercasesFoldsAndCollapses() {
        #expect(MatchKey.normalize("Amélie") == "amelie")
        #expect(MatchKey.normalize("WALL·E") == "wall e")
        #expect(MatchKey.normalize("  Spirited   Away  ") == "spirited away")
        #expect(MatchKey.normalize("Se7en") == "se7en")
    }

    @Test
    func normalizeDropsOneLeadingArticle() {
        #expect(MatchKey.normalize("The Office") == "office")
        #expect(MatchKey.normalize("A Ghost Story") == "ghost story")
        #expect(MatchKey.normalize("An Education") == "education")
        #expect(MatchKey.normalize("The The Thing") == "the thing", "Only the first article goes.")
    }

    @Test
    func normalizeKeepsATitleThatIsOnlyAnArticle() {
        #expect(MatchKey.normalize("The") == "the")
    }

    @Test
    func matchingIdentifiersMergeRegardlessOfName() {
        let a = MediaRef(type: .movie, ids: ExternalIDs(imdb: "tt0133093"), title: "The Matrix", year: 1999)
        let b = MediaRef(type: .movie, ids: ExternalIDs(imdb: "tt0133093"), title: "Matrix", year: nil)
        #expect(MatchKey.canMerge(a, b))
    }

    @Test
    func similarNamesAloneDoNotMerge() {
        let a = MediaRef(type: .movie, title: "The Matrix", year: 1999)
        let b = MediaRef(type: .movie, title: "The Matrix", year: 2021)
        #expect(MatchKey.canMerge(a, b) == false, "Different years are different works.")

        let show = MediaRef(type: .show, title: "Fargo", year: 2014)
        let movie = MediaRef(type: .movie, title: "Fargo", year: 2014)
        #expect(MatchKey.canMerge(show, movie) == false, "Type is part of identity.")
    }

    @Test
    func nameAndYearMergeWhenOneSideHasNoYear() {
        let a = MediaRef(type: .movie, title: "The Matrix", year: 1999)
        let b = MediaRef(type: .movie, title: "Matrix, The", year: nil)
        #expect(MatchKey.canMerge(a, b) == false, "Punctuation-shifted titles are not normalized to each other.")

        let c = MediaRef(type: .movie, title: "the matrix", year: nil)
        #expect(MatchKey.canMerge(a, c))
    }
}
