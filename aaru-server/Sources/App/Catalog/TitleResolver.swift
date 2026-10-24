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
    /// AniList entries fetched ahead for one import run, by `malKey` (IMP-017), and the MAL ids
    /// AniList was asked about and does not know.
    private var prefetchedMAL: [String: CatalogTitle] = [:]
    private var unknownMAL: Set<String> = []
    /// AniList's failure on this run's batch, when the caller chose to go on without it: refs
    /// only AniList could match fail with it at once instead of each asking again.
    private var aniListDown: ProviderError?

    init(stores: Stores, catalogs: CatalogProviders) {
        self.stores = stores
        self.catalogs = catalogs
    }

    /// A resolver that already holds AniList's answer for every MyAnimeList-only ref that is not
    /// in the catalog yet and has no TMDB mapping: one request per 50 entries instead of one
    /// each. Refs that resolve another way are left alone.
    func prefetchingMAL(_ refs: [MediaRef]) async throws -> TitleResolver {
        guard let batch = catalogs.anilist as? any MALBatchHydrating else { return self }
        var anime: Set<String> = []
        var manga: Set<String> = []
        for ref in refs where [.movie, .show, .manga].contains(ref.type) && ref.titleID == nil {
            let ids = ref.ids
            let isManga = ref.type == .manga
            guard let mal = ids.mal, ids.anilist == nil, ids.tmdb == nil, ids.imdb == nil, ids.tvdb == nil,
                  !(isManga ? manga : anime).contains(mal)
            else { continue }
            if try await stores.titles.find(ids: ids, type: ref.type) != nil {
                continue
            }
            if !isManga, try await animeMapping(ids)?.tmdb != nil {
                continue
            }
            if isManga {
                manga.insert(mal)
            } else {
                anime.insert(mal)
            }
        }
        guard !(anime.isEmpty && manga.isEmpty), aniListDown == nil else { return self }
        var resolver = self
        for (wanted, type) in [(anime, MediaType.show), (manga, .manga)] where !wanted.isEmpty {
            let found = try await batch.hydrate(malIDs: Array(wanted), type: type)
            for (mal, title) in found {
                resolver.prefetchedMAL[Self.malKey(mal, type)] = title
            }
            for mal in wanted.subtracting(found.keys) {
                resolver.unknownMAL.insert(Self.malKey(mal, type))
            }
        }
        return resolver
    }

    /// A MAL id as the prefetch keeps it: MAL numbers anime and manga apart (MNG-001).
    private static func malKey(_ mal: String, _ type: MediaType) -> String {
        type == .manga ? "manga:\(mal)" : mal
    }

    /// A resolver that no longer asks AniList, after it failed with `error`. Anime with a TMDB
    /// mapping still resolve through TMDB.
    func withoutAniList(_ error: ProviderError) -> TitleResolver {
        var resolver = self
        resolver.aniListDown = error
        return resolver
    }

    /// `searchHint` (an author, for books) narrows a title search. The only match it loosens is a
    /// book's year, by one, when the hint is also the hit's author (IMP-020).
    func resolve(_ ref: MediaRef, searchHint: String? = nil) async throws -> Title {
        try ref.validate()
        if let titleID = ref.titleID {
            guard let title = try await stores.titles.title(id: titleID) else { throw ResolutionError.notFound }
            return title
        }
        if !ref.ids.isEmpty {
            return try await resolve(ids: ref.ids, type: ref.type)
        }
        return try await resolveByTitle(ref, hint: searchHint)
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
            backdropURL: catalog.hit.backdropURL,
            network: catalog.hit.network,
            byline: catalog.hit.byline,
            pageCount: catalog.hit.pageCount,
            chapterCount: catalog.hit.chapterCount,
            volumeCount: catalog.hit.volumeCount,
            ids: mergedIDs,
            isAnime: catalog.hit.isAnime
        )
        do {
            try await stores.titles.insert(
                title, status: catalog.status, runtimeMinutes: catalog.runtimeMinutes, genres: catalog.genres
            )
            return title
        } catch is StoreConflict {
            // A concurrent resolution inserted it first.
            guard let winner = try await stores.titles.find(ids: mergedIDs, type: title.type)
            else { throw ResolutionError.notFound }
            return winner
        }
    }

    /// CAT-018 backfill: the genres the title's provider lists now; nil when no provider knows it.
    func genres(of title: Title) async throws -> [String]? {
        try await hydrate(ids: title.ids, type: title.type)?.genres
    }

    /// Which provider knows these ids. Anime with a community TMDB mapping resolves to the
    /// TMDB show (CAT-009); otherwise AniList owns it. Manga is AniList's alone (MNG-001).
    private func hydrate(ids: ExternalIDs, type: MediaType) async throws -> CatalogTitle? {
        if type == .book {
            return try await catalogs.openLibrary.hydrate(ids: ids, type: type)
        }
        if type == .album {
            return try await catalogs.music?.hydrate(ids: ids, type: type)
        }
        if type == .manga {
            return try await hydrateFromAniList(ids: ids, type: type)
        }
        if let mapping = try await animeMapping(ids), let tmdb = mapping.tmdb {
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
        return try await hydrateFromAniList(ids: ids, type: type)
    }

    /// AniList by its own id or a MAL id, through this run's prefetch when it has the answer.
    private func hydrateFromAniList(ids: ExternalIDs, type: MediaType) async throws -> CatalogTitle? {
        if ids.anilist == nil, let mal = ids.mal {
            let key = Self.malKey(mal, type)
            if var title = prefetchedMAL[key] {
                title.hit.ids = title.hit.ids.filling(from: ids)
                return title
            }
            if unknownMAL.contains(key) {
                return nil
            }
        }
        if ids.anilist != nil || ids.mal != nil {
            if let aniListDown {
                throw aniListDown
            }
            return try await catalogs.anilist.hydrate(ids: ids, type: type)
        }
        return nil // e.g. a Trakt-only id: Trakt resolution arrives with M8
    }

    /// The community mapping for an anime: by AniList id, else by MAL id (a MAL export has no
    /// AniList id, and must still land on the TMDB show a Trakt import created).
    func animeMapping(_ ids: ExternalIDs) async throws -> AnimeMapping? {
        if let anilist = ids.anilist, let mapping = try await stores.animeMappings.mapping(anilist: anilist) {
            return mapping
        }
        if let mal = ids.mal {
            return try await stores.animeMappings.mapping(mal: mal)
        }
        return nil
    }

    // MARK: By title + year

    private func resolveByTitle(_ ref: MediaRef, hint: String?) async throws -> Title {
        guard let title = ref.title else { throw ResolutionError.notFound }
        let provider: any CatalogSearching
        switch ref.type {
        case .book: provider = catalogs.openLibrary
        case .album:
            guard let music = catalogs.music else { throw ResolutionError.notFound }
            provider = music
        case .movie, .show: provider = catalogs.tmdb
        case .manga: provider = catalogs.anilist
        }
        let query = [title, hint].compactMap(\.self).joined(separator: " ")
        let hits = try await provider.search(query: query, type: ref.type)
        let wanted = MediaRef(type: ref.type, title: ref.title, year: ref.year)
        var matches = hits.filter { hit in
            hit.year != nil && MatchKey.canMerge(wanted, hit.mediaRef)
        }
        // IMP-020: a book one year off, only when the author is the hit's too.
        if matches.isEmpty, ref.type == .book {
            matches = hits.filter { hit in
                MatchKey.canMergeBook(wanted, author: hint, hit.mediaRef, byline: hit.byline)
            }
        }
        guard !matches.isEmpty else { throw ResolutionError.notFound }
        guard matches.count == 1 else { throw ResolutionError.ambiguous }
        return try await resolve(ids: matches[0].ids, type: ref.type)
    }

    // MARK: By name only

    /// A movie or show known only by its name (Pogdesign CAT, IMP-009; Netflix, IMP-018): the one
    /// TMDB entry of `type` whose normalized title equals it, in any year up to `notAfter` (the year
    /// it was watched). Two with the name (a remake) are ambiguous, never a guess, unless `airing`
    /// (from CAT's calendar) is an episode exactly one of the shows airs that day.
    func resolve(
        named name: String, type: MediaType, airing: ImportAiring? = nil, notAfter: Int? = nil
    ) async throws -> Title {
        let wanted = MatchKey.normalize(name)
        guard type == .movie || type == .show, !wanted.isEmpty else { throw ResolutionError.notFound }
        let hits = try await catalogs.tmdb.search(query: name, type: type)
        let matches = hits.filter { hit in
            guard hit.type == type, let year = hit.year, MatchKey.normalize(hit.title) == wanted else { return false }
            return notAfter.map { year <= $0 } ?? true
        }
        guard !matches.isEmpty else { throw ResolutionError.notFound }
        if matches.count == 1 {
            return try await resolve(ids: matches[0].ids, type: type)
        }
        guard type == .show, let airing, let hit = try await airs(airing, among: matches)
        else { throw ResolutionError.ambiguous }
        return try await resolve(ids: hit.ids, type: .show)
    }

    /// The episodes of `title` that `names` describe (Netflix names episodes, it does not number
    /// them). Names that match nothing, or more than one episode, are left out.
    func episodes(of title: Title, named names: [NamedEpisode]) async throws -> [EpisodeKey] {
        guard title.type == .show, !names.isEmpty,
              let list = try await catalogs.tmdb.episodes(ids: title.ids)
        else { return [] }
        let keys = names.compactMap { EpisodeNameMatcher.match($0, in: list.episodes) }
        return Array(Set(keys)).sorted()
    }

    /// More same-name shows than this are not worth reading every episode list for.
    static let maxAiringCandidates = 4

    /// The one candidate with `airing`'s episode dated within a day of it (calendar times are
    /// local, catalog dates are UTC days). None or several is no answer.
    private func airs(_ airing: ImportAiring, among hits: [CatalogHit]) async throws -> CatalogHit? {
        guard hits.count <= Self.maxAiringCandidates, let day = Date.catalogDay(airing.day),
              let year = catalogYear(airing.day)
        else { return nil }
        var airingHits: [CatalogHit] = []
        for hit in hits where (hit.year ?? year) <= year {
            guard let list = try await catalogs.tmdb.episodes(ids: hit.ids) else { continue }
            let aired = list.episodes.contains { episode in
                guard episode.season == airing.season, episode.episode == airing.episode,
                      let airsAt = episode.airsAt
                else { return false }
                return abs(airsAt.timeIntervalSince(day)) <= 86400
            }
            if aired {
                airingHits.append(hit)
            }
        }
        return airingHits.count == 1 ? airingHits[0] : nil
    }
}
