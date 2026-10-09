import AaruCore
import Foundation

/// AniList adapter (CAT-007): the anime catalog, over GraphQL. Reads need no key.
/// Each AniList entry is one season/cour, so its episodes are season 1.
struct AniListCatalog: CatalogSearching, EpisodeListing {
    static let endpoint = URL(string: "https://graphql.anilist.co")!

    let client: ProviderClient

    private static let mediaFields = """
    id idMal format status episodes duration
    title { romaji english native }
    startDate { year }
    coverImage { large }
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
        let episodes = (1 ... count).map { number in
            CatalogEpisode(
                season: 1,
                episode: number,
                name: nil,
                airsAt: airsAt[number],
                runtimeMinutes: media.duration,
                tmdbEpisodeID: nil
            )
        }
        return CatalogEpisodes(status: media.titleStatus, episodes: episodes)
    }

    // MARK: Plumbing

    private func media(for ids: ExternalIDs, withSchedule: Bool = false) async throws -> Media? {
        let schedule = withSchedule
            ? """
            airingSchedule(notYetAired: false, perPage: 50) { nodes { episode airingAt } }
            nextAiringEpisode { episode airingAt }
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

private struct Media: Decodable {
    struct Titles: Decodable {
        let romaji: String?
        let english: String?
        let native: String?
    }

    struct StartDate: Decodable { let year: Int? }
    struct Cover: Decodable { let large: String? }
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
    let description: String?
    let airingSchedule: Schedule?
    let nextAiringEpisode: Airing?

    var hit: CatalogHit {
        let display = title.english ?? title.romaji ?? title.native ?? "Untitled"
        return CatalogHit(
            type: format == "MOVIE" ? .movie : .show,
            title: display,
            originalTitle: title.native.flatMap { $0 == display ? nil : $0 },
            year: startDate?.year,
            posterURL: coverImage?.large.flatMap(URL.init(string:)),
            overview: description?.nilIfBlank,
            byline: nil,
            ids: ExternalIDs(anilist: String(id), mal: idMal.map(String.init)),
            isAnime: true
        )
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
