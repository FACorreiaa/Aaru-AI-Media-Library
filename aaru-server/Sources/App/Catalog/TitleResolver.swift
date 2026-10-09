import AaruCore
import Foundation

/// Why a `MediaRef` could not become a `Title`. Import jobs count these as unmatched.
enum ResolutionError: Error, Equatable {
    /// No provider knows these ids, or no catalog entry matches the title + year.
    case notFound
    /// Title + year matched more than one catalog entry. Never guess (IMP-007).
    case ambiguous

    var appError: AppError {
        switch self {
        case .notFound:
            AppError(
                status: .unprocessableContent,
                code: "unresolvable",
                message: "No catalog entry matches that title."
            )
        case .ambiguous:
            AppError(
                status: .unprocessableContent,
                code: "ambiguous_match",
                message: "More than one catalog entry matches that title and year."
            )
        }
    }
}

/// `MediaRef` → `Title`, finding or hydrating (CAT-005). Every add and every import row
/// goes through here.
///
/// External ids first. Title + year only through a provider search with exactly one
/// match, so two titles that merely share a name are never merged. Concurrent
/// resolutions of the same work yield one `titles` row: the unique indexes decide,
/// not a Swift lock.
struct TitleResolver: Sendable {
    let stores: Stores
    let catalogs: CatalogProviders

    func resolve(_ ref: MediaRef) async throws -> Title {
        try ref.validate()
        if let titleID = ref.titleID {
            guard let title = try await stores.titles.title(id: titleID) else { throw ResolutionError.notFound }
            return title
        }
        if !ref.ids.isEmpty {
            return try await resolve(ids: ref.ids, type: ref.type)
        }
        return try await resolveByTitle(ref)
    }

    // MARK: By ids

    private func resolve(ids: ExternalIDs, type: MediaType) async throws -> Title {
        if let existing = try await stores.titles.find(ids: ids, type: type) {
            try await stores.titles.fillIDs(existing.id, from: ids)
            return existing
        }
        guard let catalog = try await hydrate(ids: ids, type: type) else { throw ResolutionError.notFound }
        let mergedIDs = catalog.hit.ids.filling(from: ids)
        // The provider may have revealed an id another row already holds.
        if let existing = try await stores.titles.find(ids: mergedIDs, type: catalog.hit.type) {
            try await stores.titles.fillIDs(existing.id, from: mergedIDs)
            return existing
        }
        let title = Title(
            type: catalog.hit.type,
            title: catalog.hit.title,
            originalTitle: catalog.hit.originalTitle,
            year: catalog.hit.year,
            synopsis: catalog.hit.overview,
            posterURL: catalog.hit.posterURL,
            ids: mergedIDs,
            isAnime: catalog.hit.isAnime
        )
        do {
            try await stores.titles.insert(title, status: catalog.status, runtimeMinutes: catalog.runtimeMinutes)
            return title
        } catch is StoreConflict {
            // A concurrent resolution inserted it first.
            guard let winner = try await stores.titles.find(ids: mergedIDs, type: title.type)
            else { throw ResolutionError.notFound }
            return winner
        }
    }

    /// Which provider knows these ids. Anime with a community TMDB mapping resolves to the
    /// TMDB show (CAT-009); otherwise AniList owns it.
    private func hydrate(ids: ExternalIDs, type: MediaType) async throws -> CatalogTitle? {
        if type == .book {
            return try await catalogs.openLibrary.hydrate(ids: ids, type: type)
        }
        if let anilist = ids.anilist, let mapping = try await stores.animeMappings.mapping(anilist: anilist),
           let tmdb = mapping.tmdb
        {
            let mapped = ids.filling(from: ExternalIDs(
                tmdb: tmdb,
                tvdb: mapping.tvdb,
                mal: mapping.mal,
                anidb: mapping.anidb
            ))
            if var title = try await catalogs.tmdb.hydrate(ids: mapped, type: .show) {
                title.hit.isAnime = true
                title.hit.ids = title.hit.ids.filling(from: mapped)
                return title
            }
        }
        if ids.tmdb != nil || ids.imdb != nil || ids.tvdb != nil {
            return try await catalogs.tmdb.hydrate(ids: ids, type: type)
        }
        if ids.anilist != nil || ids.mal != nil {
            return try await catalogs.anilist.hydrate(ids: ids, type: type)
        }
        return nil // e.g. a Trakt-only id: Trakt resolution arrives with M8
    }

    // MARK: By title + year

    private func resolveByTitle(_ ref: MediaRef) async throws -> Title {
        guard let query = ref.title else { throw ResolutionError.notFound }
        let provider: any CatalogSearching = ref.type == .book ? catalogs.openLibrary : catalogs.tmdb
        let hits = try await provider.search(query: query, type: ref.type)
        let matches = hits.filter { hit in
            hit.year != nil && MatchKey.canMerge(
                MediaRef(type: ref.type, title: ref.title, year: ref.year),
                hit.mediaRef
            )
        }
        guard !matches.isEmpty else { throw ResolutionError.notFound }
        guard matches.count == 1 else { throw ResolutionError.ambiguous }
        return try await resolve(ids: matches[0].ids, type: ref.type)
    }
}
