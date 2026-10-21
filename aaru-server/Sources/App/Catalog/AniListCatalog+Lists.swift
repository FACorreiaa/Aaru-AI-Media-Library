import AaruCore
import Foundation

// MARK: Lists (IMP-014)

extension AniListCatalog: AniListListReading {
    func animeRows(userName: String) async throws -> [ImportRow] {
        let body = try await post(ListData.self, """
        query ($name: String) {
          MediaListCollection(userName: $name, type: ANIME) {
            lists { entries {
              status progress score(format: POINT_10_DECIMAL)
              completedAt { year month day }
              media { id idMal format episodes title { romaji english } startDate { year } }
            } }
          }
        }
        """, variables: ["name": .string(userName)])
        return body.collection.lists.flatMap(\.entries).map { entry in
            let media = entry.media
            let finished = entry.completedAt.flatMap { date -> Date? in
                guard let year = date.year, let month = date.month, let day = date.day else { return nil }
                return Date.catalogDay(String(format: "%04d-%02d-%02d", year, month, day))
            }
            let status = AnimeListImport.status(entry.status)
            let isMovie = media.format == "MOVIE"
            return ImportRow(
                sourceKey: "anilist:\(media.id)",
                type: isMovie ? .movie : .show,
                title: media.title.english ?? media.title.romaji ?? "Untitled",
                year: media.startDate?.year,
                ids: ExternalIDs(anilist: String(media.id), mal: media.idMal.map(String.init)),
                status: status,
                rating: AnimeListImport.rating(entry.score),
                finishedAt: finished,
                lists: [],
                watched: AnimeListImport.progress(
                    entry.progress ?? 0, total: media.episodes, status: status, isMovie: isMovie
                )
            )
        }
    }
}

private struct ListData: Decodable {
    struct Collection: Decodable { let lists: [ListGroup] }
    struct ListGroup: Decodable { let entries: [ListEntry] }

    let collection: Collection

    enum CodingKeys: String, CodingKey {
        case collection = "MediaListCollection"
    }
}

private struct ListEntry: Decodable {
    struct FuzzyDate: Decodable { let year, month, day: Int? }

    let status: String
    let progress: Int?
    let score: Double?
    let completedAt: FuzzyDate?
    let media: ListMedia
}

private struct ListMedia: Decodable {
    struct Titles: Decodable { let romaji, english: String? }
    struct Start: Decodable { let year: Int? }

    let id: Int
    let idMal: Int?
    let format: String?
    let episodes: Int?
    let title: Titles
    let startDate: Start?
}
