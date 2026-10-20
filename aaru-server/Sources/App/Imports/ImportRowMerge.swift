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

    /// Each row with its ticks in the TMDB season its anime mapping names.
    func seasonRows(_ rows: [PlannedRow]) async throws -> [ImportRow] {
        var result: [ImportRow] = []
        for planned in rows {
            var row = planned.row
            if let watched = row.watched, !watched.isEmpty, let titleID = planned.titleID,
               let season = try await mappedSeason(row.ids, titleID: titleID)
            {
                row.watched = watched.compactMap { key in
                    key.season == 1 ? try? EpisodeKey(season: season, episode: key.episode) : key
                }
            }
            result.append(row)
        }
        return result
    }

    /// The TMDB season an anime entry maps to, when its title is that TMDB show.
    private func mappedSeason(_ ids: ExternalIDs, titleID: TitleID) async throws -> Int? {
        guard ids.anilist != nil || ids.mal != nil,
              let mapping = try await resolver.animeMapping(ids),
              let season = mapping.tmdbSeason, season != 1, let tmdb = mapping.tmdb,
              try await stores.titles.title(id: titleID)?.ids.tmdb == tmdb
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
