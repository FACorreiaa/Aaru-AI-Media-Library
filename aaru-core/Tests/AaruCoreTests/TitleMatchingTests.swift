import Testing
@testable import AaruCore

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

struct CrossTypeMatchingTests {
    @Test
    func aSharedTmdbNumberAcrossMovieAndShowIsNotAMatch() {
        let movie = MediaRef(type: .movie, ids: ExternalIDs(tmdb: "1399"), title: "Game of Thrones", year: 2011)
        let show = MediaRef(type: .show, ids: ExternalIDs(tmdb: "1399"), title: "Game of Thrones", year: 2011)
        #expect(MatchKey.canMerge(movie, show) == false)
    }

    @Test
    func animeIdsMatchAndFill() {
        let fromAniList = ExternalIDs(anilist: "21", mal: "21")
        let fromMAL = ExternalIDs(mal: "21", anidb: "69")
        #expect(fromAniList.matches(fromMAL))
        #expect(fromAniList.filling(from: fromMAL) == ExternalIDs(anilist: "21", mal: "21", anidb: "69"))
        #expect(fromAniList.known.map(\.provider) == ["anilist", "mal"])
    }
}

/// IMP-020: a book one year off matches only with its author, and only books.
struct BookYearToleranceTests {
    let goodreads = MediaRef(type: .book, title: "Leviathan Wakes", year: 2011)

    @Test
    func oneYearOffMatchesWithTheSameAuthor() {
        let hit = MediaRef(type: .book, title: "Leviathan Wakes", year: 2012)
        #expect(MatchKey.canMergeBook(goodreads, author: "James S.A. Corey", hit, byline: "James S. A. Corey"))
        #expect(MatchKey.canMergeBook(goodreads, author: "James S.A. Corey", hit, byline: "Someone, James S. A. Corey"))
        #expect(MatchKey.canMerge(goodreads, hit) == false, "plain matching stays exact")
    }

    @Test
    func noAuthorOrAnotherAuthorDoesNotMatch() {
        let hit = MediaRef(type: .book, title: "Leviathan Wakes", year: 2012)
        #expect(MatchKey.canMergeBook(goodreads, author: "Someone Else", hit, byline: "James S. A. Corey") == false)
        #expect(MatchKey.canMergeBook(goodreads, author: nil, hit, byline: "James S. A. Corey") == false)
        #expect(MatchKey.canMergeBook(goodreads, author: "James S.A. Corey", hit, byline: nil) == false)
        #expect(MatchKey.sameAuthor("James Corey", byline: "James S. A. Corey") == false)
        #expect(MatchKey.sameAuthor("", byline: "") == false)
    }

    @Test
    func twoYearsOffOrNoYearOrAnotherTitleDoesNotMatch() {
        let far = MediaRef(type: .book, title: "Leviathan Wakes", year: 2013)
        let noYear = MediaRef(type: .book, title: "Leviathan Wakes", year: nil)
        let other = MediaRef(type: .book, title: "Caliban's War", year: 2012)
        for hit in [far, noYear, other] {
            #expect(MatchKey
                .canMergeBook(goodreads, author: "James S.A. Corey", hit, byline: "James S. A. Corey") == false)
        }
    }

    @Test
    func otherKindsAreNeverLoosened() {
        let film = MediaRef(type: .movie, title: "Dune", year: 2021)
        let nextYear = MediaRef(type: .movie, title: "Dune", year: 2022)
        #expect(MatchKey.canMergeBook(film, author: "Denis Villeneuve", nextYear, byline: "Denis Villeneuve") == false)
    }
}
