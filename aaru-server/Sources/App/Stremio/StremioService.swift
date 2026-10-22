import AaruCore
import Foundation

/// SCR-003 · the Stremio addon's behaviour: a manifest, three personal catalogs, `meta` for
/// titles without an IMDb id, and Stremio's `player` and `library` events. No `stream`
/// resource, ever: Aaru does not touch stream sources.
struct StremioService: Sendable {
    /// A Stremio answer: a status and an encodable body.
    struct Answer: Sendable {
        var status: Int
        var body: any Encodable & Sendable
        /// Seconds a client may cache it.
        var maxAge: Int
    }

    static let pageSize = 100
    /// Wishlist pages Stremio may ask for, in items.
    static let maxSkip = 2000
    static let types = ["movie", "series"]
    static let configureURL = URL(string: "https://aaruapp.com/app/settings/connected")!

    let library: LibraryService
    let schedule: ScheduleService
    let catalog: CatalogService
    let scrobble: ScrobbleService
    /// Puts Stremio's episode numbers on the TMDB show; nil keeps them as they come.
    var episodeMap: StremioEpisodeMap?
    var now: @Sendable () -> Date = { Date() }

    // MARK: Manifest

    static let manifest = StremioManifest(
        id: "com.aaruapp.library",
        version: "1.0.0",
        name: "Aaru",
        description: "Your Aaru library in Stremio: continue watching, the week ahead and what you plan to watch. "
            + "What you watch in Stremio ticks itself off in Aaru.",
        logo: "https://aaruapp.com/icon-512.png",
        resources: [
            .init(name: "catalog", types: types, idPrefixes: nil),
            .init(name: "meta", types: types, idPrefixes: ["aaru:"]),
            .init(name: "player", types: types, idPrefixes: ["tt", "aaru:"]),
            .init(name: "library", types: types, idPrefixes: ["tt", "aaru:"]),
        ],
        types: types,
        idPrefixes: ["tt", "aaru:"],
        catalogs: [
            .init(type: "series", id: "aaru-continue", name: "Aaru · Continue watching", extra: nil),
            .init(type: "series", id: "aaru-week", name: "Aaru · Next 7 days", extra: nil),
            // Ids stay `aaru-wishlist` (installed addons keep working); only the name follows APP-014.
            .init(type: "series", id: "aaru-wishlist", name: "Aaru · Plan to watch", extra: [.init(name: "skip")]),
            .init(type: "movie", id: "aaru-wishlist", name: "Aaru · Plan to watch", extra: [.init(name: "skip")]),
        ],
        behaviorHints: .init(configurable: true, configurationRequired: false)
    )

    // MARK: Catalogs

    func catalog(id: String, type: String, extra: [String: String], caller: AgentCaller) async throws
        -> [StremioMetaPreview]
    {
        guard caller.has(.libraryRead) else { return [] }
        let userID = caller.userID
        switch (id, type) {
        case ("aaru-continue", "series"):
            return try await schedule.upNext(userID: userID).continueWatching.map { Self.preview($0.title) }
        case ("aaru-week", "series"):
            let now = now()
            let entries = try await schedule.calendar(
                userID: userID, from: now, until: now.addingTimeInterval(7 * 24 * 60 * 60)
            )
            var seen = Set<TitleID>()
            return entries.filter { seen.insert($0.title.id).inserted }.map { Self.preview($0.title) }
        case ("aaru-wishlist", "series"), ("aaru-wishlist", "movie"):
            let skip = min(max(Int(extra["skip"] ?? "") ?? 0, 0), Self.maxSkip)
            return try await wishlist(userID: userID, type: type == "movie" ? .movie : .show, skip: skip)
        default:
            return []
        }
    }

    private func wishlist(userID: UserID, type: MediaType, skip: Int) async throws -> [StremioMetaPreview] {
        var titles: [Title] = []
        var cursor: String?
        repeat {
            let page = try await library.list(
                userID: userID, filter: LibraryFilter(type: type, status: .wishlist), cursor: cursor, limit: 200
            )
            titles += page.entries.map(\.title)
            cursor = page.next
        } while cursor != nil && titles.count < skip + Self.pageSize
        return titles.dropFirst(skip).prefix(Self.pageSize).map(Self.preview)
    }

    static func preview(_ title: Title) -> StremioMetaPreview {
        StremioMetaPreview(
            id: StremioID.forTitle(title),
            type: title.type == .movie ? "movie" : "series",
            name: title.title,
            poster: title.posterURL?.absoluteString,
            background: title.backdropURL?.absoluteString,
            description: title.synopsis,
            releaseInfo: title.year.map(String.init)
        )
    }

    // MARK: Meta

    /// Details for an `aaru:` title (Cinemeta serves `tt` ones). Nil when unknown.
    func meta(id raw: String, caller: AgentCaller) async throws -> StremioMeta? {
        guard caller.has(.libraryRead), let id = StremioID(raw), case let .aaru(titleID) = id.base else { return nil }
        let detail: TitleDetail
        do {
            detail = try await catalog.detail(titleID)
        } catch let error as AppError where error.status == .notFound {
            return nil
        }
        let title = detail.title
        let base = "aaru:\(titleID.rawValue.uuidString.lowercased())"
        let iso = ISO8601DateFormatter()
        let videos = detail.episodes?.map { episode in
            StremioMeta.Video(
                id: "\(base):\(episode.season):\(episode.episode)",
                title: episode.name ?? "Episode \(episode.episode)",
                season: episode.season,
                episode: episode.episode,
                // Stremio requires a date; an undated episode sorts as not yet released.
                released: iso.string(from: episode.airsAt ?? Date(timeIntervalSince1970: 4_102_444_800)),
                thumbnail: episode.stillURL?.absoluteString,
                overview: episode.overview
            )
        }
        return StremioMeta(
            id: base, type: title.type == .movie ? "movie" : "series", name: title.title,
            poster: title.posterURL?.absoluteString, background: title.backdropURL?.absoluteString,
            description: title.synopsis, releaseInfo: title.year.map(String.init), videos: videos
        )
    }

    // MARK: Events

    enum EventResult: Equatable {
        case accepted
        case forbidden
        case ignored
    }

    /// Stremio core 0.64's `player` event: start, pause or stop with position and duration (ms).
    func player(type: String, videoID: String, extra: [String: String], caller: AgentCaller) async throws
        -> EventResult
    {
        guard caller.has(.scrobbleWrite) else { return .forbidden }
        guard let mediaType = Self.mediaType(type), let id = StremioID(videoID),
              let action = extra["action"].flatMap(PlaybackAction.init(rawValue:))
        else { return .ignored }
        if mediaType == .show, id.episode == nil {
            return .ignored
        }
        var ref = id.mediaRef
        var episode = mediaType == .show ? id.episode : nil
        if let key = episode, let mapped = try await onShow([key], of: id) {
            guard let first = mapped.episodes.first else { return .ignored }
            ref = (titleID: mapped.title.id, ids: ref.ids)
            episode = first
        }
        try await scrobble.report(PlaybackReport(
            source: .stremio, externalRef: videoID, type: mediaType, ids: ref.ids, titleID: ref.titleID,
            episode: episode, action: action,
            positionMs: Int64(extra["currentTime"] ?? "") ?? 0, durationMs: Int64(extra["duration"] ?? "") ?? 0
        ), from: caller)
        return .accepted
    }

    /// Stremio core 0.64's `library` event. `watched` ticks exactly the named episodes (or
    /// finishes a movie); `unwatched` and `libraryAdd` need the opt-in `library:write`;
    /// `libraryRemove` is always ignored, because Aaru is the source of truth.
    func library(type: String, metaID: String, extra: [String: String], caller: AgentCaller) async throws
        -> EventResult
    {
        guard let mediaType = Self.mediaType(type), let id = StremioID(metaID), let action = extra["action"]
        else { return .ignored }
        let named = (extra["videoId"] ?? "").split(separator: ",")
            .compactMap { StremioID(String($0)) }
            .filter { $0.base == id.base }
            .compactMap(\.episode)
        let ref = id.mediaRef
        let (mediaRef, episodes) = try await placed(
            named, ref: MediaRef(titleID: ref.titleID, type: mediaType, ids: ref.ids), of: id
        )
        switch action {
        case "watched":
            guard caller.has(.scrobbleWrite) else { return .forbidden }
            if mediaType == .show, episodes.isEmpty {
                return .ignored
            }
            guard let title = try await scrobble.resolve(mediaRef) else { return .ignored }
            _ = try await scrobble.markWatched(title, episodes: episodes, caller: caller)
            return .accepted
        case "unwatched":
            guard caller.has(.libraryWrite), mediaType == .show, !episodes.isEmpty else { return .ignored }
            return try await unwatch(mediaRef, episodes: episodes, caller: caller)
        case "libraryAdd":
            guard caller.has(.libraryWrite) else { return .ignored }
            return try await addToWishlist(mediaRef, caller: caller)
        default:
            return .ignored
        }
    }

    /// What a library event acts on, with Stremio's numbers put on the show. Episodes it cannot
    /// place drop out; with none left, the event is ignored.
    private func placed(_ episodes: [EpisodeKey], ref: MediaRef, of id: StremioID) async throws
        -> (MediaRef, [EpisodeKey])
    {
        guard ref.type == .show, let mapped = try await onShow(episodes, of: id) else { return (ref, episodes) }
        return (MediaRef(titleID: mapped.title.id, type: .show, ids: ref.ids), mapped.episodes)
    }

    /// Stremio's episodes of IMDb series `id` as the matched show numbers them, leaving out any it
    /// cannot place. Nil when there is nothing to translate: no map, an Aaru id, or no such show.
    private func onShow(_ keys: [EpisodeKey], of id: StremioID) async throws
        -> (title: Title, episodes: [EpisodeKey])?
    {
        guard let episodeMap, case let .imdb(imdb) = id.base, !keys.isEmpty,
              let title = try await show(imdb: imdb, map: episodeMap), title.type == .show
        else { return nil }
        let known = try await catalog.detail(title.id).episodes ?? []
        var episodes: [EpisodeKey] = []
        for key in keys {
            if let mapped = await episodeMap.episode(key, imdb: imdb, title: title, episodes: known) {
                episodes.append(mapped)
            }
        }
        return (title, episodes)
    }

    /// The show Stremio's IMDb series is: by its TVDB id first, then by the IMDb id. TMDB can list
    /// an arc that TVDB and TMDB's own show keep as a season as an entry of its own: Stremio's
    /// `tt14986406` (Bleach: Thousand-Year Blood War) finds a near-empty TMDB `336301`, while its
    /// TVDB id is Bleach's (live test, 2026-10-22).
    private func show(imdb: String, map: StremioEpisodeMap) async throws -> Title? {
        if let tvdb = await map.tvdb(imdb: imdb),
           let title = try await scrobble.resolve(MediaRef(type: .show, ids: ExternalIDs(tvdb: tvdb)))
        {
            return title
        }
        return try await scrobble.resolve(MediaRef(type: .show, ids: ExternalIDs(imdb: imdb)))
    }

    private func unwatch(_ ref: MediaRef, episodes: [EpisodeKey], caller: AgentCaller) async throws -> EventResult {
        guard let title = try await scrobble.resolve(ref),
              let item = try await scrobble.stores.library.item(userID: caller.userID, titleID: title.id)
        else { return .ignored }
        try await library.setEpisodes(
            item.id, userID: caller.userID, keys: episodes, watched: false, by: .agent(caller.token)
        )
        return .accepted
    }

    /// Adds as wishlist when absent; never changes the status of a title already in the library.
    private func addToWishlist(_ ref: MediaRef, caller: AgentCaller) async throws -> EventResult {
        guard let title = try await scrobble.resolve(ref) else { return .ignored }
        if try await scrobble.stores.library.item(userID: caller.userID, titleID: title.id) == nil {
            _ = try await library.add(
                MediaRef(titleID: title.id, type: title.type), status: .wishlist, userID: caller.userID,
                by: .agent(caller.token)
            )
        }
        return .accepted
    }

    static func mediaType(_ stremioType: String) -> MediaType? {
        switch stremioType {
        case "movie": .movie
        case "series": .show
        default: nil
        }
    }
}
