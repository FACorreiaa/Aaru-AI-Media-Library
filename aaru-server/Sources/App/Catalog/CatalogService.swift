import AaruCore
import Foundation

/// The search scopes a client can ask for. `anime` is AniList; `all` is films, shows and anime
/// together (books stay out); the others map to their `MediaType`.
enum SearchScope: String, Sendable {
    case all, movie, show, anime, book
}

/// Search hits, and whether a provider failed so the hits are only part of the answer.
struct CatalogSearchResult: Sendable, Equatable {
    var hits: [CatalogHit]
    var incomplete = false
    /// Why the hits are partial, when a provider is down, in words a client can show.
    var notice: String?

    static let aniListDown = "AniList is down right now, so anime results come from TMDB and may be missing some."
}

/// A title as the detail route returns it: the catalog row plus show state.
struct TitleDetail: Sendable {
    var title: Title
    var status: TitleStatus?
    var runtimeMinutes: Int?
    /// Shows only; nil for movies and books.
    var episodes: [CatalogEpisode]?
}

/// Catalog reads: search (CAT-004) and title detail with lazy episode hydration (CAT-006).
struct CatalogService: Sendable {
    /// Shows with an episode airing within this window re-hydrate daily.
    static let airingWindow: TimeInterval = 30 * 24 * 60 * 60
    static let airingStaleness: TimeInterval = 24 * 60 * 60
    static let dormantStaleness: TimeInterval = 30 * 24 * 60 * 60
    /// The All scope's cap on merged hits.
    static let allLimit = 40

    let stores: Stores
    let catalogs: CatalogProviders
    var now: @Sendable () -> Date = { Date() }
    /// How long the All scope waits for AniList before answering with TMDB alone.
    var anilistDeadline: Duration = .seconds(2)

    func search(query: String, scope: SearchScope) async throws -> CatalogSearchResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 200 else {
            throw AppError(
                status: .unprocessableContent,
                code: "validation_failed",
                message: "Search needs 1–200 characters.",
                details: ["q": "Search needs 1–200 characters."]
            )
        }
        switch scope {
        case .all: return try await searchAll(trimmed)
        case .movie: return try await CatalogSearchResult(hits: catalogs.tmdb.search(query: trimmed, type: .movie))
        case .show: return try await CatalogSearchResult(hits: catalogs.tmdb.search(query: trimmed, type: .show))
        case .anime: return try await searchAnime(trimmed)
        case .book: return try await CatalogSearchResult(
                hits: catalogs.openLibrary.search(query: trimmed, type: .book)
            )
        }
    }

    func detail(_ id: TitleID) async throws -> TitleDetail {
        guard let title = try await stores.titles.title(id: id),
              let state = try await stores.titles.catalogState(id)
        else { throw AppError.notFound() }
        guard title.type == .show else {
            return TitleDetail(title: title, status: state.status, runtimeMinutes: state.runtimeMinutes, episodes: nil)
        }
        var episodes = try await stores.titles.episodes(id)
        var status = state.status
        if needsHydration(state: state, episodes: episodes) {
            let fromAniList = title.isAnime && title.ids.tmdb == nil
            let source: any EpisodeListing = fromAniList ? catalogs.anilist : catalogs.tmdb
            if var fresh = try await freshEpisodes(source, ids: title.ids, stored: episodes) {
                // AniList times are already exact. TVmaze failing never fails the hydration.
                if !fromAniList, let airTimes = catalogs.airTimes,
                   let refined = try? await airTimes.refine(fresh, ids: title.ids)
                {
                    fresh = refined
                }
                try await stores.titles.saveEpisodes(id, fresh, hydratedAt: now())
                episodes = try await stores.titles.episodes(id)
                status = fresh.status
            }
        }
        return TitleDetail(title: title, status: status, runtimeMinutes: state.runtimeMinutes, episodes: episodes)
    }

    /// The provider's episodes. While AniList is down, a show it already hydrated keeps the
    /// stored episodes rather than failing; only a never-hydrated show reports the outage.
    private func freshEpisodes(
        _ source: any EpisodeListing,
        ids: ExternalIDs,
        stored: [CatalogEpisode]
    ) async throws -> CatalogEpisodes? {
        do {
            return try await source.episodes(ids: ids)
        } catch let error as ProviderError where error.isAniListOutage && !stored.isEmpty {
            return nil
        }
    }

    /// AniList, or while it is down, TMDB's Japanese animation (CAT-021).
    private func searchAnime(_ query: String) async throws -> CatalogSearchResult {
        do {
            return try await CatalogSearchResult(hits: catalogs.anilist.search(query: query, type: .show))
        } catch let error as ProviderError where error.isAniListOutage {
            let hits = try await catalogs.tmdb.searchMulti(query: query).filter(\.isAnime)
            return CatalogSearchResult(hits: hits, incomplete: true, notice: CatalogSearchResult.aniListDown)
        }
    }

    /// Never hydrated, or older than its window: 24h while an episode airs within 30
    /// days, 30 days otherwise.
    func needsHydration(state: TitleCatalogState, episodes: [CatalogEpisode]) -> Bool {
        guard let hydratedAt = state.episodesHydratedAt else { return true }
        let now = now()
        let airingSoon = episodes.contains { episode in
            guard let airsAt = episode.airsAt else { return false }
            return abs(airsAt.timeIntervalSince(now)) <= Self.airingWindow
        }
        let window = airingSoon ? Self.airingStaleness : Self.dormantStaleness
        return now.timeIntervalSince(hydratedAt) >= window
    }
}

// MARK: - All scope (CAT-019)

extension CatalogService {
    /// TMDB multi search and AniList in parallel, AniList under a deadline. One failing leaves the
    /// other's hits, marked incomplete; both failing throws TMDB's error (502).
    func searchAll(_ query: String) async throws -> CatalogSearchResult {
        let tmdb = catalogs.tmdb
        let anilist = catalogs.anilist
        let deadline = anilistDeadline
        async let videoHits = Self.attempt { try await tmdb.searchMulti(query: query) }
        async let animeHits = Self.attempt {
            try await Self.within(deadline, provider: "anilist") {
                try await anilist.search(query: query, type: .show)
            }
        }
        let (video, anime) = await (videoHits, animeHits)
        try Task.checkCancellation()
        switch (video, anime) {
        case let (.failure(error), .failure):
            throw error
        case let (.success(video), .failure):
            return CatalogSearchResult(
                hits: Self.ranked(video, [], query: query), incomplete: true, notice: CatalogSearchResult.aniListDown
            )
        case let (.failure, .success(anime)):
            return CatalogSearchResult(hits: Self.ranked([], anime, query: query), incomplete: true)
        case let (.success(video), .success(anime)):
            let (keptVideo, mappedAnime) = try await deduplicated(video: video, anime: anime)
            return CatalogSearchResult(hits: Self.ranked(keptVideo, mappedAnime, query: query))
        }
    }

    /// Drops a TMDB show only when `anime_mappings` links an AniList show in the same results to
    /// it; that AniList hit gains the TMDB id. Nothing is ever merged on a name.
    func deduplicated(video: [CatalogHit], anime: [CatalogHit]) async throws
        -> (video: [CatalogHit], anime: [CatalogHit])
    {
        let anilistIDs = anime.filter { $0.type == .show }.compactMap(\.ids.anilist)
        guard !anilistIDs.isEmpty else { return (video, anime) }
        let mappings = try await stores.animeMappings.mappings(anilist: anilistIDs)
        let tmdbByAniList = Dictionary(
            mappings.compactMap { mapping in mapping.tmdb.map { (mapping.anilist, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        var mappedTMDB: Set<String> = []
        let anime = anime.map { hit in
            guard hit.type == .show, let anilist = hit.ids.anilist, let tmdb = tmdbByAniList[anilist] else {
                return hit
            }
            mappedTMDB.insert(tmdb)
            var hit = hit
            hit.ids = hit.ids.filling(from: ExternalIDs(tmdb: tmdb))
            return hit
        }
        let video = video.filter { hit in
            !(hit.type == .show && hit.ids.tmdb.map(mappedTMDB.contains) == true)
        }
        return (video, anime)
    }

    /// Exact title matches first, then TMDB and AniList alternating, at most `allLimit`.
    static func ranked(_ video: [CatalogHit], _ anime: [CatalogHit], query: String) -> [CatalogHit] {
        var merged: [CatalogHit] = []
        for index in 0 ..< max(video.count, anime.count) {
            if index < video.count {
                merged.append(video[index])
            }
            if index < anime.count {
                merged.append(anime[index])
            }
        }
        let wanted = MatchKey.normalize(query)
        let isExact = { (hit: CatalogHit) in
            !wanted.isEmpty && [hit.title, hit.originalTitle].contains { $0.map(MatchKey.normalize) == wanted }
        }
        let exact = merged.filter(isExact)
        let rest = merged.filter { !isExact($0) }
        return Array((exact + rest).prefix(allLimit))
    }

    /// The operation's result, or its error as a value; cancellation still propagates later.
    private static func attempt<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async -> Result<T, any Error> {
        do {
            return try await .success(operation())
        } catch {
            return .failure(error)
        }
    }

    /// Runs `operation`, giving up after `deadline` with the provider unavailable.
    static func within<T: Sendable>(
        _ deadline: Duration,
        provider: String,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: deadline)
                throw ProviderError(provider: provider, kind: .unavailable)
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw ProviderError(provider: provider, kind: .unavailable)
            }
            return first
        }
    }
}
