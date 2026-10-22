import AaruCore
import Foundation
import HTTPTypes
import Hummingbird
import Logging

/// SCR-001's HTTP surface, first used by the browser extension (SCR-007):
/// `POST /v1/scrobble/start|pause|stop`. Hand-written like the MCP and Stremio routes because it
/// authenticates itself: only a scrobble token (`aaru_scr_…`) gets in, never a session, an MCP
/// token or a Stremio link. The body is Trakt's scrobble shape, so existing tools map onto it,
/// plus `source` and `ref`. A player that has no ids sends the title's name, and the episode's
/// name when it has no number Aaru can trust.
struct ScrobbleRoutes: Sendable {
    static let path = "/v1/scrobble"
    static let maxBody = 16 * 1024

    let scrobble: ScrobbleService
    let tokens: AgentTokenService
    var logger = Logger(label: "aaru-scrobble")

    func register(on router: Router<AppRequestContext>) {
        for action in [PlaybackAction.start, .pause, .stop] {
            router.post(RouterPath("\(Self.path)/\(action.rawValue)")) { request, _ in
                await respond(to: request, action: action)
            }
        }
    }

    func respond(to request: Request, action: PlaybackAction) async -> Response {
        do {
            guard let secret = AuthMiddleware.bearerToken(request),
                  let caller = try await tokens.authenticate(secret, for: .scrobble)
            else {
                var response = Self.error(.unauthorized, "unauthorized", "Connect the extension in Aaru again.")
                response.headers[.wwwAuthenticate] = #"Bearer realm="aaru""#
                return response
            }
            guard caller.has(.scrobbleWrite) else {
                return Self.error(.forbidden, "forbidden", "This connection may not scrobble.")
            }
            guard await tokens.allow(caller) else {
                return Self.error(.tooManyRequests, "rate_limited", "Too many requests. Wait a minute.")
            }
            let body: ByteBuffer
            do {
                body = try await request.body.collect(upTo: Self.maxBody)
            } catch {
                return Self.error(.contentTooLarge, "validation_failed", "A scrobble is at most 16 KiB.")
            }
            let report: PlaybackReport
            do {
                let scrobble = try JSONDecoder().decode(ScrobbleBody.self, from: Data(buffer: body))
                if scrobble.video != nil {
                    return try await play(scrobble, action: action, from: caller)
                }
                report = try scrobble.report(action)
            } catch let error as ScrobbleBody.Invalid {
                return Self.error(.unprocessableContent, "validation_failed", error.message)
            } catch is DecodingError {
                return Self.error(.unprocessableContent, "validation_failed", "The body is not a scrobble.")
            }
            let (outcome, title) = try await scrobble.record(report, from: caller)
            return try Self.json(ScrobbleAnswer(outcome: outcome, title: title))
        } catch {
            logger.error("Scrobble failed", metadata: ["error": "\(error)"])
            return Self.error(.internalServerError, "internal", "Something went wrong.")
        }
    }

    /// A YouTube video (SCR-009): a play, never a watch event, so it matches and ticks nothing.
    private func play(_ body: ScrobbleBody, action: PlaybackAction, from caller: AgentCaller) async throws
        -> Response
    {
        guard action != .stop else {
            _ = try body.video(action, now: scrobble.now())
            try await scrobble.stopPlay(.video, from: caller)
            return try Self.json(ScrobbleAnswer(outcome: .stoppedWithoutChange, title: nil))
        }
        try await scrobble.play(body.video(action, now: scrobble.now()), from: caller)
        return try Self.json(ScrobbleAnswer(outcome: .recorded, title: nil))
    }

    private static func json(_ value: some Encodable) throws -> Response {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        return try Response(
            status: .ok,
            headers: [.contentType: "application/json", .cacheControl: "no-store"],
            body: .init(byteBuffer: ByteBuffer(bytes: encoder.encode(value)))
        )
    }

    /// `/v1`'s one error shape.
    private static func error(_ status: HTTPResponse.Status, _ code: String, _ message: String) -> Response {
        let body = (try? JSONEncoder().encode(["code": code, "message": message])) ?? Data()
        return Response(
            status: status,
            headers: [.contentType: "application/json", .cacheControl: "no-store"],
            body: .init(byteBuffer: ByteBuffer(bytes: body))
        )
    }
}

/// Trakt's scrobble body: `movie`, or `show` + `episode`, and `progress` in percent. Aaru adds
/// `source` (the streaming site) and `ref` (the player's own id for what plays: one film or one
/// episode). `durationMs` is optional; without it progress is all Aaru keeps. A YouTube video
/// (SCR-009) comes as `source: youtube` with `video` instead of `movie` or `show`.
struct ScrobbleBody: Decodable {
    struct Video: Decodable {
        var id: String
        var title: String
        var channel: String?
    }

    struct Item: Decodable {
        var title: String?
        var year: Int?
        var ids: ScrobbleIDs?
    }

    struct Episode: Decodable {
        var season: Int?
        var number: Int?
        var title: String?
    }

    struct Invalid: Error {
        let message: String
    }

    var source: String
    var ref: String
    var movie: Item?
    var show: Item?
    var episode: Episode?
    var video: Video?
    var progress: Double
    var durationMs: Int64?

    /// Without a duration, progress is kept on a 100-second scale: only its percentage matters.
    static let unknownDurationMs: Int64 = 100_000

    func report(_ action: PlaybackAction) throws -> PlaybackReport {
        guard let source = WatchSource(rawValue: source), source != .stremio else {
            throw Invalid(message: "source must be netflix, disney_plus or prime_video.")
        }
        guard !ref.isEmpty, ref.count <= 200 else { throw Invalid(message: "ref must be 1–200 characters.") }
        guard (0 ... 100).contains(progress) else { throw Invalid(message: "progress is a percentage, 0–100.") }
        let (type, item) = try playing()
        let ids = item.ids?.external ?? ExternalIDs()
        let name = item.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ids.isEmpty || !(name ?? "").isEmpty else { throw Invalid(message: "Send the title's ids or its name.") }
        guard (name?.count ?? 0) <= 300 else { throw Invalid(message: "The title is too long.") }
        let (episodeKey, episodeName) = type == .show ? try episodeParts() : (nil, nil)
        let duration = durationMs.flatMap { $0 > 0 ? $0 : nil } ?? Self.unknownDurationMs
        return PlaybackReport(
            source: source, externalRef: ref, type: type, ids: ids, titleID: nil, episode: episodeKey,
            title: name, year: item.year, episodeName: episodeName, action: action,
            positionMs: Int64((progress / 100 * Double(duration)).rounded()), durationMs: duration
        )
    }

    /// The video play this scrobble reports: YouTube's 11-character id, its name, and a duration.
    func video(_ action: PlaybackAction, now: Date) throws -> LivePlay {
        guard source == "youtube", let video, movie == nil, show == nil else {
            throw Invalid(message: "A video comes with source youtube and nothing else.")
        }
        guard video.id.count == 11,
              video.id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_".contains($0)) }),
              ref == video.id
        else { throw Invalid(message: "video.id is YouTube's 11-character id, and ref is the same.") }
        let title = video.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 300 else {
            throw Invalid(message: "video.title must be 1–300 characters.")
        }
        guard (0 ... 100).contains(progress) else { throw Invalid(message: "progress is a percentage, 0–100.") }
        guard let duration = durationMs, duration > 0 else { throw Invalid(message: "A video needs durationMs.") }
        let channel = video.channel?.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300)
        return LivePlay.video(LivePlay.VideoReport(
            id: video.id, title: title, channel: channel.flatMap { $0.isEmpty ? nil : String($0) },
            state: action == .pause ? .paused : .playing,
            positionMs: Int64((progress / 100 * Double(duration)).rounded()), durationMs: duration
        ), now: now)
    }

    /// The film, or the show, this scrobble is about.
    private func playing() throws -> (AaruCore.MediaType, Item) {
        switch (movie, show) {
        case let (movie?, nil): (.movie, movie)
        case let (nil, show?): (.show, show)
        default: throw Invalid(message: "Send either movie, or show with episode.")
        }
    }

    /// The episode's number when it has one, and its name when it has one; at least one.
    private func episodeParts() throws -> (EpisodeKey?, NamedEpisode?) {
        guard let episode else { throw Invalid(message: "A show needs its episode.") }
        let key = episode.season.flatMap { season in
            episode.number.flatMap { try? EpisodeKey(season: season, episode: $0) }
        }
        let title = episode.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let named = title.isEmpty ? nil : NamedEpisode(season: episode.season, name: String(title.prefix(300)))
        guard key != nil || named != nil else {
            throw Invalid(message: "An episode needs its season and number, or its title.")
        }
        return (key, named)
    }
}

/// Trakt sends numbers for its numeric ids; either form is read.
struct ScrobbleIDs: Decodable {
    var imdb: String?
    var tmdb: String?
    var tvdb: String?
    var trakt: String?

    enum CodingKeys: String, CodingKey {
        case imdb, tmdb, tvdb, trakt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) throws -> String? {
            if let number = try? container.decodeIfPresent(Int.self, forKey: key) {
                return String(number)
            }
            return try container.decodeIfPresent(String.self, forKey: key)
        }
        imdb = try text(.imdb)
        tmdb = try text(.tmdb)
        tvdb = try text(.tvdb)
        trakt = try text(.trakt)
    }

    var external: ExternalIDs {
        ExternalIDs(tmdb: tmdb, imdb: imdb, trakt: trakt, tvdb: tvdb)
    }
}

/// What Aaru made of a scrobble, so the extension can say "Matched: …" or "Not matched".
struct ScrobbleAnswer: Encodable {
    struct MatchedTitle: Encodable {
        var id: String
        var name: String
        var year: Int?
    }

    var outcome: String
    var title: MatchedTitle?

    init(outcome: ScrobbleOutcome, title: Title?) {
        self.outcome = switch outcome {
        case .recorded: "recorded"
        case .watched: "watched"
        case .stoppedWithoutChange: "stopped"
        case .unmatched: "unmatched"
        }
        self.title = title.map { MatchedTitle(id: $0.id.description, name: $0.title, year: $0.year) }
    }
}
