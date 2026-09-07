import Testing

@testable import AaruCore

@Suite
struct ValidationTests {
    @Test
    func titleRejectsBlankNamesAndImpossibleYears() {
        #expect(throws: ValidationError.emptyTitle) {
            try Title(type: .movie, title: "   ").validate()
        }
        #expect(throws: ValidationError.invalidYear(1600)) {
            try Title(type: .movie, title: "Nosferatu", year: 1600).validate()
        }
        #expect(throws: Never.self) {
            try Title(type: .movie, title: "Nosferatu", year: 1922).validate()
        }
    }

    @Test
    func listRejectsABlankName() {
        #expect(throws: ValidationError.emptyListName) {
            try AaruList(userID: UserID(), name: " ").validate()
        }
    }

    @Test
    func mediaRefNeedsSomethingToResolveAgainst() {
        #expect(MediaRef(type: .movie).isResolvable == false)
        #expect(MediaRef(type: .movie, title: "Heat").isResolvable == false, "A name with no year is not enough.")
        #expect(MediaRef(type: .movie, title: "Heat", year: 1995).isResolvable)
        #expect(MediaRef(type: .movie, ids: ExternalIDs(tmdb: "949")).isResolvable)
        #expect(MediaRef(titleID: TitleID(), type: .movie).isResolvable)

        #expect(throws: ValidationError.unresolvableMediaRef) {
            try MediaRef(type: .book).validate()
        }
    }

    @Test
    func episodeKeyRejectsImpossibleCoordinates() {
        #expect(throws: ValidationError.invalidEpisodeNumber(season: 1, episode: 0)) {
            try EpisodeKey(season: 1, episode: 0)
        }
        #expect(throws: Never.self) {
            try EpisodeKey(season: 0, episode: 1)  // specials
        }
    }

    @Test
    func bookProgressRejectsImpossiblePositions() {
        #expect(throws: ValidationError.invalidBookProgress) { try BookProgress(page: -1) }
        #expect(throws: ValidationError.invalidBookProgress) { try BookProgress(percent: 101) }
        #expect(throws: Never.self) { try BookProgress(page: 0, percent: 0) }
    }

    @Test
    func showProgressReportsTheFurthestEpisode() throws {
        let progress = ShowProgress(watched: [
            try EpisodeKey(season: 1, episode: 9),
            try EpisodeKey(season: 2, episode: 1),
            try EpisodeKey(season: 1, episode: 10),
        ])
        #expect(progress.watchedCount == 3)
        #expect(progress.furthestWatched == (try EpisodeKey(season: 2, episode: 1)))
    }
}
