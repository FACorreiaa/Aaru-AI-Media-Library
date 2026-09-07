import Testing

@testable import AaruCore

@Suite
struct ExternalIDsTests {
    @Test
    func emptyIsEmpty() {
        #expect(ExternalIDs().isEmpty)
        #expect(ExternalIDs(tmdb: "603").isEmpty == false)
    }

    @Test
    func fillingNeverOverwritesAnEstablishedIdentifier() {
        let fromTrakt = ExternalIDs(tmdb: "603", trakt: "481")
        let fromLetterboxd = ExternalIDs(tmdb: "999", imdb: "tt0133093")

        let merged = fromTrakt.filling(from: fromLetterboxd)

        #expect(merged.tmdb == "603", "The earlier source keeps its value.")
        #expect(merged.trakt == "481")
        #expect(merged.imdb == "tt0133093", "The later source fills what was empty.")
    }

    @Test
    func matchesRequiresAgreementOnAProviderBothSidesKnow() {
        let a = ExternalIDs(tmdb: "603", imdb: "tt0133093")
        let b = ExternalIDs(imdb: "tt0133093")
        let c = ExternalIDs(imdb: "tt0234215")

        #expect(a.matches(b))
        #expect(a.matches(c) == false)
        #expect(ExternalIDs().matches(ExternalIDs()) == false, "Two unknowns are not a match.")
        #expect(a.matches(ExternalIDs(trakt: "481")) == false, "No shared provider is no match.")
    }

    @Test
    func knownListsOnlyPopulatedProviders() {
        let ids = ExternalIDs(tmdb: "603", isbn: nil, openLibrary: "OL123W")
        #expect(ids.known.map(\.provider) == ["tmdb", "openLibrary"])
    }
}
