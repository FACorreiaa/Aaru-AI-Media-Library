import AaruCore
import Foundation

/// TMDB adapter (CAT-002): search and detail for movies and shows, external ids, and
/// season/episode lists. Poster URLs are referenced, never downloaded. No TMDB field
/// name leaves this file.
struct TMDBCatalog: CatalogSearching, EpisodeListing, MultiSearching {
    static let baseURL = URL(string: "https://api.themoviedb.org/3")!
    static let imageBase = "https://image.tmdb.org/t/p/w500"
    /// Backdrops render as wide banners, never full-screen: w780 is enough at 3x.
    static let backdropBase = "https://image.tmdb.org/t/p/w780"
    /// Episode stills render as row thumbnails and in the episode sheet: w300 covers both.
    static let stillBase = "https://image.tmdb.org/t/p/w300"
    /// Search results are enriched with IMDb ids up to this many hits.
    static let enrichLimit = 10

    let client: ProviderClient
    /// A v3 API key (sent as `api_key`) or a v4 read token (sent as a Bearer header).
    let apiKey: String

    // MARK: Search

    func search(query: String, type: MediaType) async throws -> [CatalogHit] {
        let kind = try Self.kind(for: type)
        let page = try await get(SearchPage.self, "search/\(kind)", ["query": query, "include_adult": "false"])
        let hits = page.results.compactMap { $0.hit(type: type) }
        return try await withImdbIDs(hits)
    }

    /// CAT-019: films and shows in one query. People and adult titles are dropped.
    func searchMulti(query: String) async throws -> [CatalogHit] {
        let page = try await get(SearchPage.self, "search/multi", ["query": query, "include_adult": "false"])
        return try await withImdbIDs(page.results.compactMap(\.mixedHit))
    }

    /// Fills `imdb` on the top hits from each title's external ids, concurrently and paced.
    private func withImdbIDs(_ hits: [CatalogHit]) async throws -> [CatalogHit] {
        try await withThrowingTaskGroup(of: (Int, String?).self) { group in
            for (index, hit) in hits.prefix(Self.enrichLimit).enumerated() {
                guard let tmdb = hit.ids.tmdb, let kind = try? Self.kind(for: hit.type) else { continue }
                group.addTask {
                    let ids = try? await get(ExternalIDsBody.self, "\(kind)/\(tmdb)/external_ids", [:])
                    return (index, ids?.imdbId?.nilIfBlank)
                }
            }
            var enriched = hits
            for try await (index, imdb) in group {
                enriched[index].ids.imdb = imdb
            }
            return enriched
        }
    }

    // MARK: Detail

    func hydrate(ids: ExternalIDs, type: MediaType) async throws -> CatalogTitle? {
        let kind = try Self.kind(for: type)
        guard let tmdb = try await tmdbID(for: ids, kind: kind) else { return nil }
        do {
            let detail = try await get(Detail.self, "\(kind)/\(tmdb)", ["append_to_response": "external_ids"])
            guard var hit = detail.hit(type: type) else { return nil }
            hit.ids = hit.ids.filling(from: ids)
            return CatalogTitle(hit: hit, status: detail.titleStatus, runtimeMinutes: detail.runtime)
        } catch let error as ProviderError where error.kind == .notFound {
            return nil
        }
    }

    /// The TMDB id directly, or found through IMDb / TVDB ids.
    private func tmdbID(for ids: ExternalIDs, kind: String) async throws -> String? {
        if let tmdb = ids.tmdb {
            return tmdb
        }
        let lookups: [(String?, String)] = [(ids.imdb, "imdb_id"), (ids.tvdb, "tvdb_id")]
        for case let (value?, source) in lookups {
            let found = try await get(FindResult.self, "find/\(value)", ["external_source": source])
            let match = kind == "movie" ? found.movieResults.first : found.tvResults.first
            if let id = match?.id {
                return String(id)
            }
        }
        return nil
    }

    // MARK: Episodes

    func episodes(ids: ExternalIDs) async throws -> CatalogEpisodes? {
        guard let tmdb = try await tmdbID(for: ids, kind: "tv") else { return nil }
        let show: Detail
        do {
            show = try await get(Detail.self, "tv/\(tmdb)", [:])
        } catch let error as ProviderError where error.kind == .notFound {
            return nil
        }
        let seasonNumbers = (show.seasons ?? []).map(\.seasonNumber)
        let episodes = try await withThrowingTaskGroup(of: [CatalogEpisode].self) { group in
            for number in seasonNumbers {
                group.addTask {
                    let season = try await get(SeasonBody.self, "tv/\(tmdb)/season/\(number)", [:])
                    return season.episodes.map { episode in
                        CatalogEpisode(
                            season: episode.seasonNumber,
                            episode: episode.episodeNumber,
                            name: episode.name?.nilIfBlank,
                            airsAt: Date.catalogDay(episode.airDate),
                            runtimeMinutes: episode.runtime ?? show.episodeRunTime?.first,
                            tmdbEpisodeID: episode.id.map(String.init),
                            overview: episode.overview?.nilIfBlank,
                            stillURL: episode.stillPath.flatMap { URL(string: TMDBCatalog.stillBase + $0) }
                        )
                    }
                }
            }
            var all: [CatalogEpisode] = []
            for try await season in group {
                all += season
            }
            return all.sorted { ($0.season, $0.episode) < ($1.season, $1.episode) }
        }
        return CatalogEpisodes(
            status: show.titleStatus, episodes: episodes, backdropURL: show.backdropURL, network: show.network
        )
    }

    // MARK: Plumbing

    private static func kind(for type: MediaType) throws -> String {
        switch type {
        case .movie: return "movie"
        case .show: return "tv"
        case .book: throw ProviderError(provider: "tmdb", kind: .notFound)
        }
    }

    private func get<T: Decodable>(_: T.Type, _ path: String, _ query: [String: String]) async throws -> T {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        var items = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var headers = [("Accept", "application/json")]
        if apiKey.contains(".") {
            headers.append(("Authorization", "Bearer \(apiKey)"))
        } else {
            items.append(URLQueryItem(name: "api_key", value: apiKey))
        }
        components?.queryItems = items
        guard let url = components?.url else { throw ProviderError(provider: "tmdb", kind: .malformed) }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try await client.decode(T.self, OutboundRequest(url: url, headers: headers), decoder: decoder)
    }
}

// MARK: - Discover (DISC-001)

extension TMDBCatalog: DiscoverListing {
    /// TV genres a "what to watch" row leaves out: news, soap, talk.
    static let offRowGenres: Set<Int> = [10763, 10766, 10767]
    /// "New shows" premiered within this window.
    static let newShowWindow: TimeInterval = 90 * 24 * 60 * 60

    var discoverLists: Set<DiscoverList> {
        [.tvTrending, .tvOnAir, .tvNew, .moviesTrending, .moviesInTheaters]
    }

    func list(_ list: DiscoverList, now: Date) async throws -> [CatalogHit] {
        let type: MediaType
        let path: String
        var query = ["include_adult": "false"]
        switch list {
        case .tvTrending: (type, path) = (.show, "trending/tv/week")
        case .tvOnAir: (type, path) = (.show, "tv/on_the_air")
        case .tvNew:
            (type, path) = (.show, "discover/tv")
            query["first_air_date.gte"] = Self.day(now.addingTimeInterval(-Self.newShowWindow))
            query["first_air_date.lte"] = Self.day(now)
            query["sort_by"] = "popularity.desc"
            // Popularity alone surfaces shows nobody has rated yet.
            query["vote_count.gte"] = "10"
        case .moviesTrending: (type, path) = (.movie, "trending/movie/week")
        case .moviesInTheaters: (type, path) = (.movie, "movie/now_playing")
        default: throw ProviderError(provider: "tmdb", kind: .notFound)
        }
        let page = try await get(SearchPage.self, path, query)
        return page.results.compactMap { entry -> CatalogHit? in
            guard let hit = entry.hit(type: type) else { return nil }
            guard type == .show else { return hit }
            // Anime rows come from AniList, the anime catalog.
            let genres = Set(entry.genreIds ?? [])
            return hit.isAnime || !genres.isDisjoint(with: Self.offRowGenres) ? nil : hit
        }
    }

    private static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - TMDB wire shapes (private to this adapter)

private struct SearchPage: Decodable {
    let results: [Detail]
}

private struct ExternalIDsBody: Decodable {
    let imdbId: String?
    let tvdbId: Int?
}

private struct FindResult: Decodable {
    struct Entry: Decodable { let id: Int }
    let movieResults: [Entry]
    let tvResults: [Entry]
}

private struct SeasonBody: Decodable {
    struct Episode: Decodable {
        let id: Int?
        let seasonNumber: Int
        let episodeNumber: Int
        let name: String?
        let overview: String?
        let airDate: String?
        let runtime: Int?
        let stillPath: String?
    }

    let episodes: [Episode]
}

/// Movie and TV detail/search entries share this shape; fields absent on one kind are nil.
private struct Detail: Decodable {
    struct SeasonSummary: Decodable { let seasonNumber: Int }

    let id: Int
    let title: String?
    let name: String?
    let originalTitle: String?
    let originalName: String?
    let releaseDate: String?
    let firstAirDate: String?
    let posterPath: String?
    let backdropPath: String?
    let networks: [Network]?
    let overview: String?
    let genreIds: [Int]?
    let genres: [Genre]?
    let originalLanguage: String?
    let status: String?
    let runtime: Int?
    let episodeRunTime: [Int]?
    let seasons: [SeasonSummary]?
    let externalIds: ExternalIDsBody?
    let imdbId: String?
    /// `search/multi` only: `movie`, `tv` or `person`.
    let mediaType: String?
    let adult: Bool?

    struct Genre: Decodable { let id: Int }
    struct Network: Decodable { let name: String }

    var backdropURL: URL? {
        backdropPath.flatMap { URL(string: TMDBCatalog.backdropBase + $0) }
    }

    /// The first network TMDB lists is the original broadcaster or streamer.
    var network: String? {
        networks?.first?.name.nilIfBlank
    }

    /// A mixed-list entry as a film or show; people and adult titles are nil.
    var mixedHit: CatalogHit? {
        guard adult != true else { return nil }
        switch mediaType {
        case "movie": return hit(type: .movie)
        case "tv": return hit(type: .show)
        default: return nil
        }
    }

    func hit(type: MediaType) -> CatalogHit? {
        guard let display = (title ?? name)?.nilIfBlank else { return nil }
        let genreIDs = genreIds ?? genres?.map(\.id) ?? []
        return CatalogHit(
            type: type,
            title: display,
            originalTitle: (originalTitle ?? originalName).flatMap { $0 == display ? nil : $0 },
            year: catalogYear(releaseDate ?? firstAirDate),
            posterURL: posterPath.flatMap { URL(string: TMDBCatalog.imageBase + $0) },
            overview: overview?.nilIfBlank,
            byline: nil,
            ids: ExternalIDs(
                tmdb: String(id),
                imdb: (externalIds?.imdbId ?? imdbId)?.nilIfBlank,
                tvdb: externalIds?.tvdbId.map(String.init)
            ),
            // Japanese animation. AniList is the anime catalog; this flags TMDB hits.
            isAnime: genreIDs.contains(16) && originalLanguage == "ja",
            backdropURL: backdropURL,
            network: network,
            releaseDate: catalogDate(releaseDate?.nilIfBlank ?? firstAirDate)
        )
    }

    var titleStatus: TitleStatus? {
        switch status {
        case "Returning Series", "In Production": .returning
        case "Planned", "Pilot", "Post Production", "Rumored": .upcoming
        case "Ended": .ended
        case "Canceled": .canceled
        default: nil
        }
    }
}
