import AaruCore
import Foundation

// MARK: Discover (DISC-001)

extension AniListCatalog: DiscoverListing {
    var discoverLists: Set<DiscoverList> {
        [.animeSeason, .animeTrending, .mangaTrending, .mangaPublishing]
    }

    func list(_ list: DiscoverList, now: Date) async throws -> [CatalogHit] {
        if list.kind == .manga {
            return try await mangaList(list)
        }
        let filter: String
        switch list {
        case .animeSeason:
            guard let current = SeasonOfYear.current(now) else { return [] }
            filter = "season: \(current.season.anilist), seasonYear: \(current.year), sort: POPULARITY_DESC"
        case .animeTrending:
            filter = "status: RELEASING, sort: TRENDING_DESC"
        default:
            throw ProviderError(provider: "anilist", kind: .notFound)
        }
        let body = try await post(SearchData.self, """
        query {
          Page(perPage: 20) {
            media(type: ANIME, isAdult: false, format_in: [TV, TV_SHORT, ONA, MOVIE], \(filter)) {
              \(Self.mediaFields)
            }
          }
        }
        """, variables: [:])
        return body.page.media.map(\.hit)
    }

    /// DISC-004: what is trending, and the most popular series still publishing. No adult works.
    private func mangaList(_ list: DiscoverList) async throws -> [CatalogHit] {
        let sort = list == .mangaTrending ? "TRENDING_DESC" : "POPULARITY_DESC"
        let body = try await post(SearchData.self, """
        query {
          Page(perPage: 20) {
            media(type: MANGA, isAdult: false, status: RELEASING, sort: \(sort)) {
              \(Self.fields(.manga))
            }
          }
        }
        """, variables: [:])
        return body.page.media.map(\.hit)
    }
}

// MARK: Seasons (DISC-002)

extension AniListCatalog: SeasonBrowsing {
    static let seasonPageSize = 50

    var seasonKinds: Set<SeasonKind> {
        [.anime]
    }

    func season(_ key: SeasonKey, kind: SeasonKind, page: Int, now _: Date) async throws -> SeasonPage {
        guard kind == .anime else { throw ProviderError(provider: "anilist", kind: .notFound) }
        let body = try await post(SeasonData.self, """
        query ($season: MediaSeason, $year: Int, $page: Int, $perPage: Int) {
          Page(page: $page, perPage: $perPage) {
            pageInfo { hasNextPage total }
            media(season: $season, seasonYear: $year, type: ANIME, isAdult: false,
                  format_in: [TV, TV_SHORT, ONA, MOVIE], sort: POPULARITY_DESC) {
              \(Self.mediaFields)
            }
          }
        }
        """, variables: [
            "season": .string(key.season.anilist), "year": .int(key.year),
            "page": .int(page), "perPage": .int(Self.seasonPageSize),
        ])
        return SeasonPage(
            hits: body.page.media.map(\.hit),
            hasMore: body.page.pageInfo?.hasNextPage ?? false,
            total: body.page.pageInfo?.total
        )
    }
}

private struct SeasonData: Decodable {
    struct PageInfo: Decodable {
        let hasNextPage: Bool?
        let total: Int?
    }

    struct Page: Decodable {
        let pageInfo: PageInfo?
        let media: [AniListMedia]
    }

    let page: Page

    enum CodingKeys: String, CodingKey { case page = "Page" }
}
