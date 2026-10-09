import AaruCore
import Foundation

/// The search scopes a client can ask for. `anime` is AniList; the others map to
/// their `MediaType`.
enum SearchScope: String, Sendable {
    case movie, show, anime, book
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

    let stores: Stores
    let catalogs: CatalogProviders
    var now: @Sendable () -> Date = { Date() }

    func search(query: String, scope: SearchScope) async throws -> [CatalogHit] {
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
        case .movie: return try await catalogs.tmdb.search(query: trimmed, type: .movie)
        case .show: return try await catalogs.tmdb.search(query: trimmed, type: .show)
        case .anime: return try await catalogs.anilist.search(query: trimmed, type: .show)
        case .book: return try await catalogs.openLibrary.search(query: trimmed, type: .book)
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
            let source: any EpisodeListing = title.isAnime && title.ids.tmdb == nil ? catalogs.anilist : catalogs.tmdb
            if let fresh = try await source.episodes(ids: title.ids) {
                try await stores.titles.saveEpisodes(id, fresh.episodes, status: fresh.status, hydratedAt: now())
                episodes = try await stores.titles.episodes(id)
                status = fresh.status
            }
        }
        return TitleDetail(title: title, status: status, runtimeMinutes: state.runtimeMinutes, episodes: episodes)
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
