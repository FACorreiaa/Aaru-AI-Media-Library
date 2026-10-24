import aaruAPI
import AaruCore
import Foundation
import OpenAPIRuntime

extension APIImplementation {
    func searchCatalog(_ input: Operations.SearchCatalog.Input) async throws -> Operations.SearchCatalog.Output {
        guard let scope = SearchScope(rawValue: input.query._type.rawValue) else { throw AppError.badRequest() }
        let result = try await catalog.search(query: input.query.q, scope: scope)
        return .ok(.init(body: .json(.init(
            items: result.hits.map { Components.Schemas.CatalogHit($0) }, incomplete: result.incomplete,
            notice: result.notice
        ))))
    }

    func getDiscover(_: Operations.GetDiscover.Input) async throws -> Operations.GetDiscover.Output {
        let rows = try await services.discover.rows(userID: currentUser())
        return .ok(.init(body: .json(.init(rows: rows.map { row in
            .init(id: row.list.rawValue, title: row.title, items: row.items.map {
                Components.Schemas.CatalogHit($0.hit, libraryItemID: $0.libraryItemID)
            }, note: row.note)
        }))))
    }

    func getDiscoverSeason(
        _ input: Operations.GetDiscoverSeason.Input
    ) async throws -> Operations.GetDiscoverSeason.Output {
        let query = input.query
        guard let kind = SeasonKind(rawValue: query.kind.rawValue),
              let season = SeasonOfYear(rawValue: query.season.rawValue)
        else { throw AppError.badRequest() }
        let key = SeasonKey(season: season, year: query.year)
        let result = try await services.discover.season(
            key, kind: kind, page: query.page ?? 1, userID: currentUser()
        )
        let (from, until) = key.days
        return .ok(.init(body: .json(.init(
            kind: .init(rawValue: kind.rawValue) ?? .anime,
            season: .init(rawValue: season.rawValue) ?? .winter,
            year: key.year, from: from, until: until, title: key.title,
            items: result.items.map { Components.Schemas.CatalogHit($0.hit, libraryItemID: $0.libraryItemID) },
            page: result.page, hasMore: result.hasMore, total: result.total, unavailable: result.unavailable
        ))))
    }

    func getDiscoverOnAir(
        _ input: Operations.GetDiscoverOnAir.Input
    ) async throws -> Operations.GetDiscoverOnAir.Output {
        let region = input.query.region?.uppercased()
        guard region.map({ $0.count == 2 && $0.allSatisfy { $0.isASCII && $0.isLetter } }) ?? true else {
            let message = "Two letters, as ISO 3166-1."
            throw AppError(
                status: .unprocessableContent, code: "validation_failed", message: message, details: ["region": message]
            )
        }
        let guide = try await services.discover.onAir(userID: currentUser(), region: region)
        return .ok(.init(body: .json(.init(
            channels: guide.channels.map { group in
                .init(
                    name: group.channel.name, logoUrl: group.channel.logoURL?.absoluteString,
                    shows: group.shows.map { show in
                        .init(
                            item: .init(show.item.hit, libraryItemID: show.item.libraryItemID),
                            nextEpisode: .init(
                                season: show.next.season, number: show.next.number, name: show.next.name,
                                airsAt: show.next.airsAt, airTimeKnown: show.next.airTimeKnown
                            ),
                            streamsOn: show.streamsOn.isEmpty ? nil : show.streamsOn.map {
                                .init(name: $0.name, logoUrl: $0.logoURL?.absoluteString)
                            },
                            watchLink: show.streamsOn.isEmpty ? nil : show.watchLink?.absoluteString
                        )
                    }
                )
            },
            updatedAt: guide.updatedAt
        ))))
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
            openLibrary: ids.openLibrary, anilist: ids.anilist, mal: ids.mal, anidb: ids.anidb,
            musicbrainz: ids.musicbrainz
        )
    }
}

extension Components.Schemas.MediaType {
    init(_ type: MediaType) {
        switch type {
        case .movie: self = .movie
        case .show: self = .show
        case .book: self = .book
        case .album: self = .album
        case .manga: self = .manga
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
            libraryItemId: libraryItemID?.description,
            releaseDate: hit.releaseDate
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
                            overview: $0.overview,
                            stillUrl: $0.stillURL?.absoluteString,
                            airsAt: $0.airsAt,
                            airTimeKnown: $0.airTimeKnown,
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
            seasons: seasons,
            byline: title.byline,
            genres: title.type == .album ? detail.genres : nil,
            tracks: detail.tracks?.map {
                .init(disc: $0.disc, position: $0.position, name: $0.name, lengthMs: $0.lengthMs)
            }
        )
    }
}
