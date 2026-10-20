import aaruAPI
import AaruCore
import Foundation
import OpenAPIRuntime

extension APIImplementation {
    func searchCatalog(_ input: Operations.SearchCatalog.Input) async throws -> Operations.SearchCatalog.Output {
        guard let scope = SearchScope(rawValue: input.query._type.rawValue) else { throw AppError.badRequest() }
        let hits = try await catalog.search(query: input.query.q, scope: scope)
        return .ok(.init(body: .json(.init(items: hits.map { Components.Schemas.CatalogHit($0) }))))
    }

    func getDiscover(_: Operations.GetDiscover.Input) async throws -> Operations.GetDiscover.Output {
        let rows = try await services.discover.rows(userID: currentUser())
        return .ok(.init(body: .json(.init(rows: rows.map { row in
            .init(id: row.list.rawValue, title: row.title, items: row.items.map {
                Components.Schemas.CatalogHit($0.hit, libraryItemID: $0.libraryItemID)
            })
        }))))
    }

    func getTitle(_ input: Operations.GetTitle.Input) async throws -> Operations.GetTitle.Output {
        guard let id = TitleID(uuidString: input.path.id) else { throw AppError.notFound() }
        return try await .ok(.init(body: .json(.init(catalog.detail(id)))))
    }
}

extension Components.Schemas.ExternalIds {
    init(_ ids: ExternalIDs) {
        self.init(
            tmdb: ids.tmdb, imdb: ids.imdb, trakt: ids.trakt, tvdb: ids.tvdb, isbn: ids.isbn,
            openLibrary: ids.openLibrary, anilist: ids.anilist, mal: ids.mal, anidb: ids.anidb
        )
    }
}

extension Components.Schemas.MediaType {
    init(_ type: MediaType) {
        switch type {
        case .movie: self = .movie
        case .show: self = .show
        case .book: self = .book
        }
    }
}

extension Components.Schemas.CatalogHit {
    init(_ hit: CatalogHit, libraryItemID: LibraryItemID? = nil) {
        self.init(
            _type: .init(hit.type),
            title: hit.title,
            originalTitle: hit.originalTitle,
            year: hit.year,
            posterUrl: hit.posterURL?.absoluteString,
            overview: hit.overview,
            byline: hit.byline,
            isAnime: hit.isAnime,
            ids: .init(hit.ids),
            libraryItemId: libraryItemID?.description
        )
    }
}

extension Components.Schemas.TitleDetail {
    init(_ detail: TitleDetail) {
        let title = detail.title
        let seasons = detail.episodes.map { episodes in
            Dictionary(grouping: episodes, by: \.season)
                .sorted { $0.key < $1.key }
                .map { number, episodes in
                    Components.Schemas.Season(number: number, episodes: episodes.map {
                        .init(
                            season: $0.season,
                            number: $0.episode,
                            name: $0.name,
                            airsAt: $0.airsAt,
                            runtimeMinutes: $0.runtimeMinutes
                        )
                    })
                }
        }
        self.init(
            id: title.id.description,
            _type: .init(title.type),
            title: title.title,
            originalTitle: title.originalTitle,
            year: title.year,
            synopsis: title.synopsis,
            posterUrl: title.posterURL?.absoluteString,
            isAnime: title.isAnime,
            ids: .init(title.ids),
            status: detail.status.flatMap { .init(rawValue: $0.rawValue) },
            runtimeMinutes: detail.runtimeMinutes,
            seasons: seasons
        )
    }
}
