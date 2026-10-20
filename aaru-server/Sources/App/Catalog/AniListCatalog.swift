import AaruCore
import Foundation

/// AniList adapter (CAT-007): the anime catalog, over GraphQL. Reads need no key.
/// Each AniList entry is one season/cour, so its episodes are season 1.
struct AniListCatalog: CatalogSearching, EpisodeListing, DiscoverFeeds {
    static let endpoint = URL(string: "https://graphql.anilist.co")!

    let client: ProviderClient

    private static let mediaFields = """
    id idMal format status episodes duration
    title { romaji english native }
    startDate { year month day }
    coverImage { large }
    bannerImage
    externalLinks { site type }
    description(asHtml: false)
    """

    func search(query: String, type _: MediaType) async throws -> [CatalogHit] {
        let body = try await post(SearchData.self, """
        query ($search: String) {
          Page(perPage: 20) { media(search: $search, type: ANIME, sort: SEARCH_MATCH) { \(Self.mediaFields) } }
        }
        """, variables: ["search": .string(query)])
        return body.page.media.map(\.hit)
    }

    /// CAT-020: one season's anime by popularity. Adult entries are never asked for.
    func discover(_ feed: DiscoverFeed) async throws -> [CatalogHit] {
        guard case let .animeSeason(season) = feed else { throw ProviderError(provider: "anilist", kind: .notFound) }
        let body = try await post(SearchData.self, """
        query ($season: MediaSeason, $year: Int) {
          Page(perPage: 20) {
            media(season: $season, seasonYear: $year, type: ANIME, isAdult: false, sort: POPULARITY_DESC) {
              \(Self.mediaFields)
            }
          }
        }
        """, variables: ["season": .string(season.name.rawValue.uppercased()), "year": .int(season.year)])
        return body.page.media.map(\.hit)
    }

    func hydrate(ids: ExternalIDs, type _: MediaType) async throws -> CatalogTitle? {
        guard let media = try await media(for: ids) else { return nil }
        var hit = media.hit
        hit.ids = hit.ids.filling(from: ids)
        return CatalogTitle(hit: hit, status: media.titleStatus, runtimeMinutes: media.duration)
    }

    func episodes(ids: ExternalIDs) async throws -> CatalogEpisodes? {
        guard let media = try await media(for: ids, withSchedule: true) else { return nil }
        let aired = media.airingSchedule?.nodes ?? []
        var airsAt: [Int: Date] = Dictionary(
            aired.map { ($0.episode, Date(timeIntervalSince1970: TimeInterval($0.airingAt))) },
            uniquingKeysWith: { first, _ in first }
        )
        if let next = media.nextAiringEpisode {
            airsAt[next.episode] = Date(timeIntervalSince1970: TimeInterval(next.airingAt))
        }
        // Known episode count, or as far as the schedule reaches for a show still airing.
        let count = max(media.episodes ?? 0, airsAt.keys.max() ?? 0)
        guard count > 0 else { return CatalogEpisodes(status: media.titleStatus, episodes: []) }
        let names = Self.episodeNames(media.streamingEpisodes ?? [], count: count)
        let episodes = (1 ... count).map { number in
            CatalogEpisode(
                season: 1,
                episode: number,
                name: names[number],
                airsAt: airsAt[number],
                runtimeMinutes: media.duration,
                tmdbEpisodeID: nil,
                airTimeKnown: airsAt[number] != nil
            )
        }
        return CatalogEpisodes(
            status: media.titleStatus, episodes: episodes, backdropURL: media.backdropURL, network: media.network
        )
    }

    /// AniList has no per-episode titles, but its streaming links are titled "Episode 3 - Name".
    /// Only names are kept (the thumbnails are the streaming site's art), and only when the
    /// number is inside the show's range; anything else is left unnamed, never guessed.
    static func episodeNames(_ links: [StreamingEpisode], count: Int) -> [Int: String] {
        var names: [Int: String] = [:]
        for link in links {
            guard let title = link.title,
                  let match = title.wholeMatch(of: /(?i)episode\s+(\d+)\s*[-–:]\s*(.+)/),
                  let number = Int(match.1), (1 ... count).contains(number), names[number] == nil
            else { continue }
            let name = String(match.2).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                names[number] = name
            }
        }
        return names
    }

    // MARK: Plumbing

    private func media(for ids: ExternalIDs, withSchedule: Bool = false) async throws -> Media? {
        let schedule = withSchedule
            ? """
            airingSchedule(notYetAired: false, perPage: 50) { nodes { episode airingAt } }
            nextAiringEpisode { episode airingAt }
            streamingEpisodes { title }
            """
            : ""
        let selector: String
        let variables: [String: GraphQLValue]
        if let anilist = ids.anilist.flatMap(Int.init) {
            selector = "id: $id"
            variables = ["id": .int(anilist)]
        } else if let mal = ids.mal.flatMap(Int.init) {
            selector = "idMal: $id"
            variables = ["id": .int(mal)]
        } else {
            return nil
        }
        do {
            let body = try await post(MediaData.self, """
            query ($id: Int) { Media(\(selector), type: ANIME) { \(Self.mediaFields) \(schedule) } }
            """, variables: variables)
            return body.media
        } catch let error as ProviderError where error.kind == .notFound {
            return nil
        }
    }

    private func post<T: Decodable>(_: T.Type, _ query: String, variables: [String: GraphQLValue]) async throws -> T {
        let payload = try JSONEncoder().encode(GraphQLRequest(query: query, variables: variables))
        let response = try await client.decode(
            GraphQLResponse<T>.self,
            OutboundRequest(
                method: "POST",
                url: Self.endpoint,
                headers: [("Content-Type", "application/json"), ("Accept", "application/json")],
                body: payload
            )
        )
        guard let data = response.data else { throw ProviderError(provider: "anilist", kind: .notFound) }
        return data
    }
}

// MARK: - AniList wire shapes

private enum GraphQLValue: Encodable {
    case string(String)
    case int(Int)

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .int(value): try container.encode(value)
        }
    }
}

private struct GraphQLRequest: Encodable {
    let query: String
    let variables: [String: GraphQLValue]
}

private struct GraphQLResponse<T: Decodable>: Decodable {
    let data: T?
}

private struct SearchData: Decodable {
    struct Page: Decodable { let media: [Media] }
    let page: Page

    enum CodingKeys: String, CodingKey { case page = "Page" }
}

private struct MediaData: Decodable {
    let media: Media?

    enum CodingKeys: String, CodingKey { case media = "Media" }
}

struct StreamingEpisode: Decodable, Sendable {
    let title: String?
}

private struct Media: Decodable {
    struct Titles: Decodable {
        let romaji: String?
        let english: String?
        let native: String?
    }

    struct StartDate: Decodable {
        let year: Int?
        let month: Int?
        let day: Int?

        /// `YYYY-MM-DD` when AniList knows the full date.
        var text: String? {
            guard let year, let month, let day else { return nil }
            return String(format: "%04d-%02d-%02d", year, month, day)
        }
    }

    struct Cover: Decodable { let large: String? }
    struct ExternalLink: Decodable {
        let site: String
        let type: String?
    }

    struct Airing: Decodable {
        let episode: Int
        let airingAt: Int
    }

    struct Schedule: Decodable { let nodes: [Airing] }

    let id: Int
    let idMal: Int?
    let format: String?
    let status: String?
    let episodes: Int?
    let duration: Int?
    let title: Titles
    let startDate: StartDate?
    let coverImage: Cover?
    let bannerImage: String?
    let externalLinks: [ExternalLink]?
    let description: String?
    let airingSchedule: Schedule?
    let nextAiringEpisode: Airing?
    let streamingEpisodes: [StreamingEpisode]?

    var hit: CatalogHit {
        let display = title.english ?? title.romaji ?? title.native ?? "Untitled"
        return CatalogHit(
            type: format == "MOVIE" ? .movie : .show,
            title: display,
            originalTitle: title.native.flatMap { $0 == display ? nil : $0 },
            year: startDate?.year,
            posterURL: coverImage?.large.flatMap(URL.init(string:)),
            overview: description.map(AniListText.plain)?.nilIfBlank,
            byline: nil,
            ids: ExternalIDs(anilist: String(id), mal: idMal.map(String.init)),
            isAnime: true,
            backdropURL: backdropURL,
            network: network,
            releaseDate: startDate?.text
        )
    }

    var backdropURL: URL? {
        bannerImage.flatMap(URL.init(string:))
    }

    /// Anime has no broadcaster in AniList's model; the first streaming link is what a viewer
    /// needs ("Crunchyroll").
    var network: String? {
        externalLinks?.first { $0.type == "STREAMING" }?.site.nilIfBlank
    }

    var titleStatus: TitleStatus? {
        switch status {
        case "RELEASING", "HIATUS": .returning
        case "NOT_YET_RELEASED": .upcoming
        case "FINISHED": .ended
        case "CANCELLED": .canceled
        default: nil
        }
    }
}

enum AniListText {
    /// AniList sends `<br>` and `<i>` even with `asHtml: false`. Clients get plain text.
    static func plain(_ html: String) -> String {
        var text = html.replacingOccurrences(
            of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, character) in [
            ("&amp;", "&"), ("&quot;", "\""), ("&#039;", "'"), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"),
            ("&nbsp;", " "),
        ] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        text = text.replacingOccurrences(of: "[ \\t]+\n", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

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
