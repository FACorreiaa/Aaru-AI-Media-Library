import Testing

@testable import AaruCore

/// Raw values are stored on the server and cached on clients. Changing one is a
/// migration, not a rename — these tests exist to make that break loudly.
@Suite
struct WireContractTests {
    @Test
    func libraryStatusRawValuesAreStable() {
        #expect(LibraryStatus.wishlist.rawValue == "wishlist")
        #expect(LibraryStatus.inProgress.rawValue == "in_progress")
        #expect(LibraryStatus.finished.rawValue == "finished")
        #expect(LibraryStatus.dropped.rawValue == "dropped")
        #expect(LibraryStatus.allCases.count == 4, "Status is consumption only; ownership is isOwned.")
    }

    @Test
    func mediaTypeRawValuesAreStable() {
        #expect(MediaType.allCases.map(\.rawValue) == ["movie", "show", "book"])
    }

    @Test
    func importSourceRawValuesAreStable() {
        #expect(
            ImportSource.allCases.map(\.rawValue) == [
                "trakt", "imdb_csv", "letterboxd_csv", "goodreads_csv", "cat_list", "cat_ics",
            ]
        )
    }

    @Test
    func importSourceDeclarationOrderIsTheMergeOrder() {
        #expect(ImportSource.trakt.mergeRank < ImportSource.imdbCSV.mergeRank)
        #expect(ImportSource.imdbCSV.mergeRank < ImportSource.letterboxdCSV.mergeRank)
        #expect(ImportSource.letterboxdCSV.mergeRank < ImportSource.goodreadsCSV.mergeRank)
        #expect(ImportSource.goodreadsCSV.mergeRank < ImportSource.catList.mergeRank)
        #expect(ImportSource.catList.mergeRank < ImportSource.catICS.mergeRank)
    }

    @Test
    func onlyFinishedStatesAreTerminal() {
        #expect(ImportJobState.queued.isTerminal == false)
        #expect(ImportJobState.running.isTerminal == false)
        #expect(ImportJobState.succeeded.isTerminal)
        #expect(ImportJobState.failed.isTerminal)
        #expect(ImportJobState.partial.isTerminal)
    }
}
