import aaruAPI
import AaruCore
import Foundation
import OpenAPIRuntime

extension APIImplementation {
    func getNowPlaying(_: Operations.GetNowPlaying.Input) async throws -> Operations.GetNowPlaying.Output {
        let playing = try await services.scrobble.nowPlaying(userID: currentUser())
        return .ok(.init(body: .json(.init(nowPlaying: playing.map(Components.Schemas.NowPlaying.init)))))
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
        let kind: LiveActivityToken.Kind = body.kind == .update ? .update : .start
        let watchEventID = try body.watchEventId.map { raw in
            guard let id = UUID(uuidString: raw) else { throw Self.invalid("watchEventId", "A watch event id.") }
            return id
        }
        guard (kind == .update) == (watchEventID != nil) else {
            throw Self.invalid("watchEventId", "Sent with `update` only, and always with it.")
        }
        let registration = LiveActivityToken(
            token: token, kind: kind, environment: body.environment == .production ? .production : .sandbox,
            topic: body.bundleId, watchEventID: watchEventID
        )
        let userID = try currentUser()
        guard try await stores.watchEvents.registerLiveActivity(registration, userID: userID, now: Date())
        else { throw AppError.notFound() }
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
