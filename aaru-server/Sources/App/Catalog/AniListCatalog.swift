import AaruCore
import Foundation

/// AniList adapter (CAT-007): the anime and manga catalog (MNG-001), over GraphQL. Reads need no
/// key. Each AniList anime entry is one season/cour, so its episodes are season 1.
struct AniListCatalog: CatalogSearching, EpisodeListing, MALBatchHydrating {
    static let endpoint = URL(string: "https://graphql.anilist.co")!

    let client: ProviderClient
    /// AniList asks API users to identify themselves; the same contact string as Open Library.
    var userAgent = AppConfig.defaultProviderUserAgent

    static let mediaFields = """
    id idMal type format status episodes duration chapters volumes genres
    title { romaji english native }
    startDate { year month day }
    coverImage { large }
    bannerImage
    externalLinks { site type }
    description(asHtml: false)
    """

    /// A manga's credits: the people who wrote and drew it become its byline.
    static let staffFields = "staff(perPage: 6, sort: [RELEVANCE, ROLE]) { edges { role node { name { full } } } }"

    /// AniList's own split: everything Aaru calls manga is its `MANGA` type, the rest is `ANIME`.
    static func aniListType(_ type: MediaType) -> String {
        type == .manga ? "MANGA" : "ANIME"
    }

    /// Fields for one kind: manga also asks for its credits.
    static func fields(_ type: MediaType) -> String {
        type == .manga ? "\(mediaFields) \(staffFields)" : mediaFields
    }

    func search(query: String, type: MediaType) async throws -> [CatalogHit] {
        // Manga search hides adult works, as Discover does for anime.
        let adult = type == .manga ? ", isAdult: false" : ""
        let body = try await post(SearchData.self, """
        query ($search: String) {
          Page(perPage: 20) {
            media(search: $search, type: \(Self.aniListType(type))\(adult), sort: SEARCH_MATCH) {
              \(Self.fields(type))
            }
          }
        }
        """, variables: ["search": .string(query)])
        return body.page.media.map(\.hit)
    }

    func hydrate(ids: ExternalIDs, type: MediaType) async throws -> CatalogTitle? {
        guard let media = try await media(for: ids, type: type) else { return nil }
        var hit = media.hit
        hit.ids = hit.ids.filling(from: ids)
        return CatalogTitle(
            hit: hit, status: media.titleStatus, runtimeMinutes: media.duration, genres: media.genres ?? []
        )
    }

    /// IMP-017: many MyAnimeList entries at once, 50 per request, keyed by MAL id. One request
    /// instead of 50 matters under AniList's 90-a-minute limit: a 2,000-entry export takes
    /// seconds, not 20 minutes. An id AniList does not know is simply missing from the result.
    /// MAL numbers anime and manga apart, so `type` says which list the ids come from.
    func hydrate(malIDs: [String], type: MediaType) async throws -> [String: CatalogTitle] {
        let ids = Array(Set(malIDs.compactMap { Int($0) })).sorted()
        var titles: [String: CatalogTitle] = [:]
        for start in stride(from: 0, to: ids.count, by: Self.batchSize) {
            let batch = Array(ids[start ..< min(start + Self.batchSize, ids.count)])
            let body = try await post(SearchData.self, """
            query ($ids: [Int]) {
              Page(perPage: \(Self.batchSize)) {
                media(idMal_in: $ids, type: \(Self.aniListType(type))) { \(Self.fields(type)) }
              }
            }
            """, variables: ["ids": .ints(batch)])
            for media in body.page.media {
                guard let mal = media.idMal else { continue }
                titles[String(mal)] = CatalogTitle(
                    hit: media.hit, status: media.titleStatus, runtimeMinutes: media.duration,
                    genres: media.genres ?? []
                )
            }
        }
        return titles
    }

    /// AniList's largest page.
    static let batchSize = 50

    func episodes(ids: ExternalIDs) async throws -> CatalogEpisodes? {
        guard let media = try await media(for: ids, type: .show, withSchedule: true) else { return nil }
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

    private func media(
        for ids: ExternalIDs,
        type: MediaType,
        withSchedule: Bool = false
    ) async throws -> AniListMedia? {
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
            query ($id: Int) {
              Media(\(selector), type: \(Self.aniListType(type))) { \(Self.fields(type)) \(schedule) }
            }
            """, variables: variables)
            return body.media
        } catch let error as ProviderError where error.kind == .notFound {
            return nil
        }
    }

    func post<T: Decodable>(_: T.Type, _ query: String, variables: [String: GraphQLValue]) async throws -> T {
        let payload = try JSONEncoder().encode(GraphQLRequest(query: query, variables: variables))
        let response = try await client.decode(
            GraphQLResponse<T>.self,
            OutboundRequest(
                method: "POST",
                url: Self.endpoint,
                headers: [
                    ("Content-Type", "application/json"), ("Accept", "application/json"), ("User-Agent", userAgent),
                ],
                body: payload
            )
        )
        guard let data = response.data else { throw ProviderError(provider: "anilist", kind: .notFound) }
        return data
    }

    /// AniList's own outage answers: a 401/403 saying the API is disabled, or a non-JSON page from
    /// the CDN in front of it. Reads need no key, so these are never a refused credential.
    static func classify(_ response: OutboundResponse) -> ProviderError.Kind? {
        guard response.status == 401 || response.status == 403 else { return nil }
        guard let body = try? JSONDecoder().decode(GraphQLErrors.self, from: response.body) else { return .unavailable }
        let disabled = body.errors?.contains { $0.message?.localizedCaseInsensitiveContains("disabled") == true }
        return disabled == true ? .unavailable : nil
    }
}

// MARK: - AniList wire shapes

private struct GraphQLErrors: Decodable {
    struct Message: Decodable { let message: String? }
    let errors: [Message]?
}

enum GraphQLValue: Encodable {
    case string(String)
    case int(Int)
    case ints([Int])

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .int(value): try container.encode(value)
        case let .ints(value): try container.encode(value)
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

struct SearchData: Decodable {
    struct Page: Decodable { let media: [AniListMedia] }
    let page: Page

    enum CodingKeys: String, CodingKey { case page = "Page" }
}

private struct MediaData: Decodable {
    let media: AniListMedia?

    enum CodingKeys: String, CodingKey { case media = "Media" }
}

/// One person's credit on a manga: "Story & Art", Eiichiro Oda.
struct AniListCredit: Decodable {
    struct Person: Decodable { let name: AniListName }

    let role: String?
    let node: Person
}

struct AniListName: Decodable {
    let full: String?
}

struct StreamingEpisode: Decodable, Sendable {
    let title: String?
}

struct AniListMedia: Decodable {
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

    struct Staff: Decodable { let edges: [AniListCredit] }

    let id: Int
    let idMal: Int?
    /// `ANIME` or `MANGA`.
    let type: String?
    let format: String?
    let status: String?
    let episodes: Int?
    let duration: Int?
    let chapters: Int?
    let volumes: Int?
    let staff: Staff?
    let genres: [String]?
    let title: Titles
    let startDate: StartDate?
    let coverImage: Cover?
    let bannerImage: String?
    let externalLinks: [ExternalLink]?
    let description: String?
    let airingSchedule: Schedule?
    let nextAiringEpisode: Airing?
    let streamingEpisodes: [StreamingEpisode]?

    var isManga: Bool {
        type == "MANGA"
    }

    var hit: CatalogHit {
        let display = title.english ?? title.romaji ?? title.native ?? "Untitled"
        var hit = CatalogHit(
            type: isManga ? .manga : format == "MOVIE" ? .movie : .show,
            title: display,
            originalTitle: title.native.flatMap { $0 == display ? nil : $0 },
            year: startDate?.year,
            posterURL: coverImage?.large.flatMap(URL.init(string:)),
            overview: description.map(AniListText.plain)?.nilIfBlank,
            byline: isManga ? authors : nil,
            ids: ExternalIDs(anilist: String(id), mal: idMal.map(String.init)),
            isAnime: !isManga,
            backdropURL: backdropURL,
            network: isManga ? nil : network,
            releaseDate: startDate?.text
        )
        if isManga {
            hit.chapterCount = chapters.flatMap { $0 > 0 ? $0 : nil }
            hit.volumeCount = volumes.flatMap { $0 > 0 ? $0 : nil }
        }
        return hit
    }

    /// Who wrote and drew it ("Story & Art", "Story", "Art", "Original Story"), in AniList's
    /// order, once each. Translators, letterers and editors are left out.
    var authors: String? {
        var names: [String] = []
        for edge in staff?.edges ?? [] {
            guard let role = edge.role, role.range(of: #"(?i)\b(story|art)\b"#, options: .regularExpression) != nil,
                  let name = edge.node.name.full?.nilIfBlank, !names.contains(name)
            else { continue }
            names.append(name)
        }
        return names.isEmpty ? nil : names.prefix(2).joined(separator: ", ")
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
