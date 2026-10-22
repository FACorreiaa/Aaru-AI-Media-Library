import aaruAPI
import AaruCore
import Foundation
import OpenAPIRuntime

extension APIImplementation {
    func getNowPlaying(_: Operations.GetNowPlaying.Input) async throws -> Operations.GetNowPlaying.Output {
        let userID = try currentUser()
        let playing = try await services.scrobble.nowPlaying(userID: userID)
        let items = try await services.scrobble.playingNow(userID: userID)
        return .ok(.init(body: .json(.init(
            nowPlaying: playing.map(Components.Schemas.NowPlaying.init),
            items: items.map(Components.Schemas.NowPlayingItem.init)
        ))))
    }

    func registerLiveActivityToken(_ input: Operations.RegisterLiveActivityToken.Input) async throws
        -> Operations.RegisterLiveActivityToken.Output
    {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let token = body.token.trimmingCharacters(in: .whitespaces).lowercased()
        guard (32 ... 400).contains(token.count), token.allSatisfy(\.isHexDigit) else {
            throw Self.invalid("token", "Hex, as ActivityKit gave it.")
        }
        guard PushTopics.allowed.contains(body.bundleId) else {
            throw Self.invalid("bundleId", "Not an Aaru app.")
        }
        // `watchEventId` is ignored since SCR-009: one activity shows everything that plays.
        let kind: LiveActivityToken.Kind = body.kind == .update ? .update : .start
        let registration = LiveActivityToken(
            token: token, kind: kind, environment: body.environment == .production ? .production : .sandbox,
            topic: body.bundleId
        )
        let userID = try currentUser()
        try await stores.watchEvents.registerLiveActivity(registration, userID: userID, now: Date())
        if kind == .update {
            await services.scrobble.liveActivity?.caughtUp(registration, userID: userID, now: Date())
        }
        return .noContent(.init())
    }

    private static func invalid(_ field: String, _ hint: String) -> AppError {
        AppError(
            status: .unprocessableContent, code: "validation_failed",
            message: "That Live Activity token cannot be registered.", details: [field: hint]
        )
    }
}

extension Components.Schemas.NowPlaying {
    init(_ playing: NowPlaying) {
        let session = playing.session
        self.init(
            watchEventId: session.id.uuidString.lowercased(),
            libraryItemId: session.libraryItemID?.description,
            title: .init(playing.title),
            episode: session.episode.map { .init(season: $0.season, number: $0.episode) },
            episodeName: session.episodeName,
            source: .init(rawValue: session.source.rawValue) ?? .stremio,
            state: session.state == .paused ? .paused : .playing,
            positionMs: session.positionMs,
            durationMs: session.knownDurationMs,
            updatedAt: session.updatedAt
        )
    }
}

extension Components.Schemas.NowPlayingItem {
    init(_ entry: LiveEntry) {
        switch entry {
        case let .session(session, title):
            let item = entry.activityItem
            self.init(
                id: item.id, kind: title.type == .movie ? .movie : .episode, name: title.title,
                subtitle: item.subtitle, service: item.service,
                source: .init(rawValue: session.source.rawValue) ?? .stremio,
                state: session.state == .paused ? .paused : .playing, positionMs: session.positionMs,
                durationMs: session.knownDurationMs, updatedAt: session.updatedAt, artworkUrl: item.artworkURL,
                libraryItemId: session.libraryItemID?.description, title: .init(title),
                episode: session.episode.map { .init(season: $0.season, number: $0.episode) }
            )
        case let .play(play):
            self.init(
                id: play.id.uuidString.lowercased(), kind: play.kind == .track ? .track : .video, name: play.title,
                subtitle: play.subtitle, service: play.service,
                source: play.source == .youtube ? .youtube : .listenbrainz,
                state: play.state == .paused ? .paused : .playing,
                // A track's scrobbler says only when it began.
                positionMs: play.kind == .track
                    ? Int64(max(0, play.updatedAt.timeIntervalSince(play.startedAt)) * 1000) : play.positionMs,
                durationMs: play.durationMs, updatedAt: play.updatedAt, artworkUrl: play.artworkURL,
                originUrl: play.originURL
            )
        }
    }
}
