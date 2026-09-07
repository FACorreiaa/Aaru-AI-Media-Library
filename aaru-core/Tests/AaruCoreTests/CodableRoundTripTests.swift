import Foundation
import Testing

@testable import AaruCore

/// Encodes then decodes a value and returns the result, so a test can assert the
/// round trip preserved everything.
private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
    let encoder = JSONEncoder()
    let data = try encoder.encode(value)
    return try JSONDecoder().decode(T.self, from: data)
}

@Suite
struct CodableRoundTripTests {
    @Test
    func titleSurvivesRoundTrip() throws {
        let title = Title(
            type: .show,
            title: "Severance",
            originalTitle: "Severance",
            year: 2022,
            synopsis: "Work/life balance, enforced.",
            posterURL: URL(string: "https://image.tmdb.org/t/p/w500/poster.jpg"),
            ids: ExternalIDs(tmdb: "95396", imdb: "tt11280740"),
            seasons: [
                Season(
                    number: 1,
                    name: "Season 1",
                    episodes: [Episode(key: try EpisodeKey(season: 1, episode: 1), name: "Good News About Hell")]
                )
            ]
        )
        #expect(try roundTrip(title) == title)
    }

    @Test
    func libraryItemSurvivesRoundTrip() throws {
        let item = LibraryItem(
            userID: UserID(),
            titleID: TitleID(),
            status: .inProgress,
            isOwned: true,
            rating: try Rating(8.5),
            notes: "Rewatch before season 3.",
            progress: .show(
                ShowProgress(
                    watched: [try EpisodeKey(season: 1, episode: 1), try EpisodeKey(season: 1, episode: 2)],
                    currentSeason: 1,
                    currentEpisode: 3
                )
            )
        )
        let decoded = try roundTrip(item)
        #expect(decoded.status == .inProgress)
        #expect(decoded.isOwned)
        #expect(decoded.rating == item.rating)
        #expect(decoded.progress?.show?.watched == item.progress?.show?.watched)
    }

    @Test
    func bookProgressSurvivesRoundTrip() throws {
        let progress = Progress.book(try BookProgress(page: 120, percent: 34.5))
        let decoded = try roundTrip(progress)
        #expect(decoded.book?.page == 120)
        #expect(decoded.book?.percent == 34.5)
        #expect(decoded.show == nil)
    }

    @Test
    func listAndImportJobSurviveRoundTrip() throws {
        let list = AaruList(userID: UserID(), name: "Comfort rewatches", titleIDs: [TitleID(), TitleID()])
        #expect(try roundTrip(list) == list)

        let job = ImportJob(
            userID: UserID(),
            source: .letterboxdCSV,
            state: .partial,
            stats: ImportStats(created: 40, updated: 2, skipped: 1, unmatched: 7),
            errorSummary: "7 rows had no TMDB match."
        )
        #expect(try roundTrip(job) == job)
    }

    @Test
    func mediaRefSurvivesRoundTrip() throws {
        let ref = MediaRef(type: .book, ids: ExternalIDs(isbn: "9780571364893"), title: "Piranesi", year: 2020)
        #expect(try roundTrip(ref) == ref)
    }

    @Test
    func identifiersEncodeAsBareUUIDStrings() throws {
        let id = TitleID()
        let data = try JSONEncoder().encode(id)
        #expect(String(decoding: data, as: UTF8.self) == "\"\(id.rawValue.uuidString)\"")
        #expect(try JSONDecoder().decode(TitleID.self, from: data) == id)
    }
}
