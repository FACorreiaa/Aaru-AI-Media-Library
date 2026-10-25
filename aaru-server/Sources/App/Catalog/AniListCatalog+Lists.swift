import AaruCore
import Foundation

// MARK: Lists (IMP-014)

extension AniListCatalog: AniListListReading {
    /// The anime list, then the manga list (MNG-002). A user with only one of them is fine.
    func listRows(userName: String) async throws -> [ImportRow] {
        try await rows(userName: userName, type: .show) + rows(userName: userName, type: .manga)
    }

    private func rows(userName: String, type: MediaType) async throws -> [ImportRow] {
        let body = try await post(ListData.self, """
        query ($name: String) {
          MediaListCollection(userName: $name, type: \(Self.aniListType(type))) {
            lists { entries {
              status progress progressVolumes score(format: POINT_10_DECIMAL)
              completedAt { year month day }
              media { id idMal format episodes chapters volumes title { romaji english } startDate { year } }
            } }
          }
        }
        """, variables: ["name": .string(userName)])
        return body.collection.lists.flatMap(\.entries).map { entry in
            type == .manga ? Self.mangaRow(entry) : Self.animeRow(entry)
        }
    }

    private static func animeRow(_ entry: ListEntry) -> ImportRow {
        let media = entry.media
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
            finishedAt: entry.finished,
            lists: [],
            watched: AnimeListImport.progress(
                entry.progress ?? 0, total: media.episodes, status: status, isMovie: isMovie
            ),
            knowsOnHold: true
        )
    }

    /// AniList's `progress` on a manga is chapters; `progressVolumes` is volumes.
    private static func mangaRow(_ entry: ListEntry) -> ImportRow {
        let media = entry.media
        let status = AnimeListImport.status(entry.status)
        return ImportRow(
            sourceKey: "anilist:\(media.id)",
            type: .manga,
            title: media.title.english ?? media.title.romaji ?? "Untitled",
            year: media.startDate?.year,
            ids: ExternalIDs(anilist: String(media.id), mal: media.idMal.map(String.init)),
            status: status,
            rating: AnimeListImport.rating(entry.score),
            finishedAt: entry.finished,
            lists: [],
            mangaChapter: AnimeListImport.read(entry.progress ?? 0, total: media.chapters, status: status),
            mangaVolume: AnimeListImport.read(entry.progressVolumes ?? 0, total: media.volumes, status: status),
            knowsOnHold: true
        )
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
    let progressVolumes: Int?
    let score: Double?
    let completedAt: FuzzyDate?
    let media: ListMedia

    var finished: Date? {
        guard let year = completedAt?.year, let month = completedAt?.month, let day = completedAt?.day
        else { return nil }
        return Date.catalogDay(String(format: "%04d-%02d-%02d", year, month, day))
    }
}

private struct ListMedia: Decodable {
    struct Titles: Decodable { let romaji, english: String? }
    struct Start: Decodable { let year: Int? }

    let id: Int
    let idMal: Int?
    let format: String?
    let episodes: Int?
    let chapters: Int?
    let volumes: Int?
    let title: Titles
    let startDate: Start?
}
