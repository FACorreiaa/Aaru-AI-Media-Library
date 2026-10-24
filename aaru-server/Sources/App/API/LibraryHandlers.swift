import aaruAPI
import AaruCore
import Foundation
import OpenAPIRuntime

extension APIImplementation {
    func listLibraryItems(_ input: Operations.ListLibraryItems.Input) async throws -> Operations.ListLibraryItems
        .Output
    {
        let query = input.query
        var filter = LibraryFilter()
        filter.type = query._type.map(MediaType.init)
        filter.isAnime = query.anime
        filter.status = query.status.map(LibraryStatus.init)
        filter.isOwned = query.owned
        if let list = query.list {
            guard let id = ListID(uuidString: list) else { throw AppError.badRequest("That list id is not valid.") }
            filter.listID = id
        }
        let page = try await library.list(
            userID: currentUser(), filter: filter, cursor: query.cursor, limit: query.limit ?? 50
        )
        return .ok(.init(body: .json(.init(
            items: page.entries.map(Components.Schemas.LibraryEntry.init),
            page: .init(nextCursor: page.next)
        ))))
    }

    func addLibraryItem(_ input: Operations.AddLibraryItem.Input) async throws -> Operations.AddLibraryItem.Output {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let entry = try await library.add(
            MediaRef(body.mediaRef), status: body.status.map(LibraryStatus.init), userID: currentUser()
        )
        return .ok(.init(body: .json(.init(entry))))
    }

    func getLibraryItem(_ input: Operations.GetLibraryItem.Input) async throws -> Operations.GetLibraryItem.Output {
        try await .ok(.init(body: .json(withWatched(library.entry(itemID(input.path.id), userID: currentUser())))))
    }

    func updateLibraryItem(_ input: Operations.UpdateLibraryItem.Input) async throws -> Operations.UpdateLibraryItem
        .Output
    {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let entry = try await library.patch(itemID(input.path.id), userID: currentUser(), patch: ItemPatch(body))
        return .ok(.init(body: .json(.init(entry))))
    }

    func deleteLibraryItem(_ input: Operations.DeleteLibraryItem.Input) async throws -> Operations.DeleteLibraryItem
        .Output
    {
        try await library.delete(itemID(input.path.id), userID: currentUser())
        return .noContent(.init())
    }

    func setEpisodeWatched(_ input: Operations.SetEpisodeWatched.Input) async throws -> Operations.SetEpisodeWatched
        .Output
    {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let key = try EpisodeKey(season: input.path.season, episode: input.path.episode)
        let entry = try await library.setEpisode(
            itemID(input.path.id), userID: currentUser(), key: key, watched: body.watched
        )
        return try await .ok(.init(body: .json(withWatched(entry))))
    }

    func markSeasonWatched(_ input: Operations.MarkSeasonWatched.Input) async throws -> Operations.MarkSeasonWatched
        .Output
    {
        let entry = try await library.markSeasonWatched(
            itemID(input.path.id), userID: currentUser(), season: input.path.season
        )
        return try await .ok(.init(body: .json(withWatched(entry))))
    }

    func markShowWatched(_ input: Operations.MarkShowWatched.Input) async throws -> Operations.MarkShowWatched.Output {
        let result = try await library.markShowWatched(itemID(input.path.id), userID: currentUser())
        return try await .ok(.init(body: .json(.init(
            entry: withWatched(result.entry),
            action: result.action.map(Components.Schemas.Action.init),
            episodes: result.episodes
        ))))
    }

    private func withWatched(_ entry: LibraryEntry) async throws -> Components.Schemas.LibraryEntry {
        try await .withWatched(entry, stores: stores)
    }

    func syncLibrary(_ input: Operations.SyncLibrary.Input) async throws -> Operations.SyncLibrary.Output {
        let result = try await library.sync(userID: currentUser(), token: input.query.since)
        return .ok(.init(body: .json(.init(
            items: result.entries.map(Components.Schemas.LibraryEntry.init),
            deleted: result.deleted.map(\.description),
            token: result.token
        ))))
    }

    func listActions(_ input: Operations.ListActions.Input) async throws -> Operations.ListActions.Output {
        let actions = try await library.actions(userID: currentUser(), limit: input.query.limit ?? 20)
        return .ok(.init(body: .json(.init(items: actions.map(Components.Schemas.Action.init)))))
    }

    func undoAction(_ input: Operations.UndoAction.Input) async throws -> Operations.UndoAction.Output {
        guard let id = UUID(uuidString: input.path.id) else { throw AppError.notFound("No such action.") }
        return try await .ok(.init(body: .json(.init(library.undo(id, userID: currentUser())))))
    }

    private func itemID(_ raw: String) throws -> LibraryItemID {
        guard let id = LibraryItemID(uuidString: raw) else { throw AppError.notFound() }
        return id
    }
}

// MARK: - DTO mapping

extension ItemPatch {
    /// The route and the agent tools (`apply_library_patch`) read the same patch shape.
    init(_ dto: Components.Schemas.LibraryItemPatch) {
        self.init(
            status: dto.status.map(LibraryStatus.init),
            rating: dto.rating,
            notes: dto.notes,
            isOwned: dto.isOwned,
            bookPage: dto.bookPage,
            bookPercent: dto.bookPercent,
            mangaChapter: dto.mangaChapter,
            mangaVolume: dto.mangaVolume,
            clear: Set((dto.clear ?? []).compactMap { ItemPatch.Clearable(rawValue: $0.rawValue) })
        )
    }
}

extension MediaType {
    init(_ dto: Components.Schemas.MediaType) {
        switch dto {
        case .movie: self = .movie
        case .show: self = .show
        case .book: self = .book
        case .album: self = .album
        case .manga: self = .manga
        }
    }
}

extension LibraryStatus {
    init(_ dto: Components.Schemas.LibraryStatus) {
        switch dto {
        case .wishlist: self = .wishlist
        case .inProgress: self = .inProgress
        case .finished: self = .finished
        case .dropped: self = .dropped
        }
    }
}

extension Components.Schemas.LibraryStatus {
    init(_ status: LibraryStatus) {
        switch status {
        case .wishlist: self = .wishlist
        case .inProgress: self = .inProgress
        case .finished: self = .finished
        case .dropped: self = .dropped
        }
    }
}

extension ExternalIDs {
    init(_ dto: Components.Schemas.ExternalIds?) {
        self.init(
            tmdb: dto?.tmdb, imdb: dto?.imdb, trakt: dto?.trakt, tvdb: dto?.tvdb, isbn: dto?.isbn,
            openLibrary: dto?.openLibrary, anilist: dto?.anilist, mal: dto?.mal, anidb: dto?.anidb,
            musicbrainz: dto?.musicbrainz
        )
    }
}

extension Components.Schemas.LibraryEntry {
    /// A single-item response: the entry plus every watched episode, so a client can draw ticks.
    static func withWatched(_ entry: LibraryEntry, stores: Stores) async throws -> Self {
        var response = Self(entry)
        if entry.title.type == .show {
            response.watchedEpisodes = try await stores.library.watched(itemID: entry.item.id)
                .sorted()
                .map { .init(season: $0.season, number: $0.episode) }
        }
        return response
    }
}

extension MediaRef {
    init(_ dto: Components.Schemas.MediaRef) {
        self.init(
            titleID: dto.titleId.flatMap(TitleID.init(uuidString:)),
            type: MediaType(dto._type),
            ids: ExternalIDs(dto.ids),
            title: dto.title,
            year: dto.year
        )
    }
}

extension Components.Schemas.TitleSummary {
    init(_ title: Title) {
        self.init(
            id: title.id.description, _type: .init(title.type), title: title.title,
            originalTitle: title.originalTitle, year: title.year, posterUrl: title.posterURL?.absoluteString,
            backdropUrl: title.backdropURL?.absoluteString, network: title.network, byline: title.byline,
            pageCount: title.pageCount, chapterCount: title.chapterCount, volumeCount: title.volumeCount,
            isAnime: title.isAnime, ids: .init(title.ids)
        )
    }
}

extension Components.Schemas.LibraryEntry {
    init(_ entry: LibraryEntry) {
        let item = entry.item
        self.init(
            id: item.id.description,
            title: .init(entry.title),
            status: .init(item.status),
            rating: item.rating?.value,
            notes: item.notes,
            isOwned: item.isOwned,
            addedAt: item.addedAt,
            updatedAt: item.updatedAt,
            finishedAt: item.finishedAt,
            progress: entry.progress.map {
                .init(
                    watchedCount: $0.watchedCount,
                    airedCount: $0.airedCount,
                    nextEpisode: $0.nextEpisode.map { .init(season: $0.season, number: $0.episode) }
                )
            },
            bookProgress: entry.bookProgress.flatMap { progress in
                progress.page == nil && progress.percent == nil ? nil : .init(
                    page: progress.page,
                    percent: progress.percent
                )
            },
            mangaProgress: entry.mangaProgress.flatMap { progress in
                progress.chapter == nil && progress.volume == nil ? nil : .init(
                    chapter: progress.chapter,
                    volume: progress.volume
                )
            },
            lastWatchedAt: entry.lastWatchedAt,
            inBacklog: entry.inBacklog
        )
    }
}

extension Components.Schemas.Action {
    init(_ action: ActionRecord) {
        self.init(
            id: action.id.uuidString,
            actor: .init(rawValue: action.actor.rawValue) ?? .user,
            kind: action.kind,
            summary: action.summary,
            itemIds: action.itemIDs.map(\.description),
            createdAt: action.createdAt,
            undoneAt: action.undoneAt,
            undoOf: action.undoOf?.uuidString,
            agentName: action.agentName
        )
    }
}
