import AaruCore
import Foundation

/// Rows that land on one title. AniList and MAL list each anime season as its own entry, all
/// ticked as season 1; when the community mapping sends an entry to a later TMDB season, its
/// ticks move there, and every entry of the show merges into one row.
extension ImportService {
    /// Matched rows by title, in the order each title first appears.
    static func groups(_ rows: [PlannedRow]) -> [(titleID: TitleID, indices: [Int])] {
        var order: [TitleID] = []
        var indices: [TitleID: [Int]] = [:]
        for (index, row) in rows.enumerated() where row.outcome != .unmatched {
            guard let titleID = row.titleID else { continue }
            if indices[titleID] == nil {
                order.append(titleID)
            }
            indices[titleID, default: []].append(index)
        }
        return order.map { ($0, indices[$0] ?? []) }
    }

    /// What merging and deciding a plan's titles read, loaded once for the whole plan: the
    /// user's items for those titles, the anime mappings of rows with ticks, and the TMDB id of
    /// each title. Before this, each title cost four to seven queries.
    struct MergeContext: Sendable {
        var states: [TitleID: ImportItemState] = [:]
        var byAniList: [String: AnimeMapping] = [:]
        var byMAL: [String: AnimeMapping] = [:]
        var tmdb: [TitleID: String] = [:]
    }

    func mergeContext(_ rows: [PlannedRow], userID: UserID) async throws -> MergeContext {
        let matched = rows.filter { $0.outcome != .unmatched && $0.titleID != nil }
        let titleIDs = Array(Set(matched.compactMap(\.titleID)))
        let anime = matched.filter { $0.row.watched?.isEmpty == false }
        let anilist = Array(Set(anime.compactMap(\.row.ids.anilist)))
        let mal = Array(Set(anime.compactMap(\.row.ids.mal)))
        async let states = stores.library.importStates(userID: userID, titleIDs: titleIDs)
        async let byAniList = stores.animeMappings.mappings(anilist: anilist)
        async let byMAL = stores.animeMappings.mappings(mal: mal)
        let animeTitles = Array(Set(anime.compactMap(\.titleID)))
        async let titles = stores.titles.titles(ids: animeTitles)
        var context = try await MergeContext(states: states, byMAL: byMAL)
        context.byAniList = try await Dictionary(
            byAniList.map { ($0.anilist, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        context.tmdb = try await Dictionary(
            titles.compactMap { title in title.ids.tmdb.map { (title.id, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        return context
    }

    /// Each row with its ticks in the TMDB season its anime mapping names.
    static func seasonRows(_ rows: [PlannedRow], context: MergeContext) -> [ImportRow] {
        rows.map { planned in
            var row = planned.row
            if let watched = row.watched, !watched.isEmpty, let titleID = planned.titleID,
               let season = mappedSeason(row.ids, titleID: titleID, context: context)
            {
                row.watched = watched.compactMap { key in
                    key.season == 1 ? try? EpisodeKey(season: season, episode: key.episode) : key
                }
            }
            return row
        }
    }

    /// The TMDB season an anime entry maps to, when its title is that TMDB show. The AniList
    /// id's mapping wins; the MAL id's is the fallback (`TitleResolver.animeMapping`).
    private static func mappedSeason(_ ids: ExternalIDs, titleID: TitleID, context: MergeContext) -> Int? {
        let mapping = ids.anilist.flatMap { context.byAniList[$0] } ?? ids.mal.flatMap { context.byMAL[$0] }
        guard let mapping, let season = mapping.tmdbSeason, season != 1, let tmdb = mapping.tmdb,
              context.tmdb[titleID] == tmdb
        else { return nil }
        return season
    }

    /// One row for a title: every tick, the furthest status, the first rating, the latest finish.
    static func merged(_ rows: [ImportRow]) -> ImportRow {
        guard var merged = rows.first else { preconditionFailure("merged needs at least one row") }
        for row in rows.dropFirst() {
            if merged.status != .dropped, let status = row.status,
               status.importRank > (merged.status?.importRank ?? -1)
            {
                merged.status = status
            }
            merged.rating = merged.rating ?? row.rating
            if let finished = row.finishedAt, finished > (merged.finishedAt ?? .distantPast) {
                merged.finishedAt = finished
            }
            if let watched = row.watched {
                merged.watched = Array(Set(merged.watched ?? []).union(watched)).sorted()
            }
            merged.mangaChapter = [merged.mangaChapter, row.mangaChapter].compactMap(\.self).max()
            merged.mangaVolume = [merged.mangaVolume, row.mangaVolume].compactMap(\.self).max()
            if row.listOnly != true {
                merged.listOnly = nil
            }
        }
        return merged
    }
}

extension LibraryStatus {
    /// How far along a status is, for imports that only move forward. Dropped is not on the
    /// line: an import never moves an item into or out of it.
    var importRank: Int {
        switch self {
        case .wishlist: 0
        case .inProgress: 1
        case .finished: 2
        case .dropped: -1
        }
    }
}
