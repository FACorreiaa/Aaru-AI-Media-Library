import aaruAPI
import AaruCore
import Foundation
import OpenAPIRuntime

extension APIImplementation {
    func listListens(_ input: Operations.ListListens.Input) async throws -> Operations.ListListens.Output {
        let limit = ListenService.pageSize(input.query.limit)
        let listens = try await services.listens.listens(
            userID: currentUser(), before: input.query.before, limit: limit
        )
        return .ok(.init(body: .json(.init(
            items: listens.map(Components.Schemas.Listen.init),
            next: listens.count == limit ? listens.last?.listenedAt : nil
        ))))
    }

    func getTopListens(_ input: Operations.GetTopListens.Input) async throws -> Operations.GetTopListens.Output {
        let query = input.query
        let period = try services.listens.period(
            span: query.span.flatMap { StatsPeriod.Span(rawValue: $0.rawValue) },
            year: query.year, month: query.month, timeZone: query.tz
        )
        let grouping = ListenGrouping(rawValue: query.by.rawValue) ?? .artist
        let top = try await services.listens.top(
            userID: currentUser(), by: grouping, period: period, limit: query.limit, artist: query.artist
        )
        return .ok(.init(body: .json(.init(
            by: .init(rawValue: query.by.rawValue) ?? .artist,
            span: .init(rawValue: top.period.span.rawValue) ?? .year,
            year: top.period.year,
            month: top.period.month,
            timeZone: top.period.timeZone.identifier,
            listens: top.listens,
            minutes: Int(top.durationMs / 60000),
            items: top.items.map { item in
                .init(
                    artist: item.artist, track: item.track, album: item.album, count: item.count,
                    minutes: Int(item.durationMs / 60000),
                    coverUrl: item.releaseGroupMBID.flatMap(MusicBrainzCatalog.coverURL(releaseGroup:))?.absoluteString,
                    // An artist spans albums; only a track or an album row points at one.
                    albumRef: grouping == .artist ? nil : item.releaseGroupMBID.map {
                        .album(musicbrainz: $0, titleID: item.albumTitleID, title: item.album)
                    }
                )
            }
        ))))
    }
}

extension Components.Schemas.MediaRef {
    /// An album by its MusicBrainz release-group id, and by Aaru's title id once it is in the catalog.
    static func album(musicbrainz: String, titleID: UUID?, title: String?) -> Self {
        .init(titleId: titleID?.uuidString, _type: .album, ids: .init(musicbrainz: musicbrainz), title: title)
    }
}

extension Components.Schemas.Listen {
    init(_ listen: Listen) {
        self.init(
            id: listen.id.uuidString.lowercased(),
            listenedAt: listen.listenedAt,
            artist: listen.artist,
            track: listen.track,
            album: listen.album,
            durationMs: listen.durationMs,
            coverUrl: listen.releaseGroupMBID.flatMap(MusicBrainzCatalog.coverURL(releaseGroup:))?.absoluteString,
            originUrl: listen.originURL,
            client: listen.client,
            musicService: listen.musicService,
            albumRef: listen.releaseGroupMBID.map {
                .album(musicbrainz: $0, titleID: listen.albumTitleID, title: listen.album)
            }
        )
    }
}
