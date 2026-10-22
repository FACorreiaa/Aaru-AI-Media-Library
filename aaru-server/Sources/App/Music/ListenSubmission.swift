import Foundation

/// A ListenBrainz `submit-listens` body, checked: `single` and `import` carry listens with the
/// time they started; `playing_now` carries one track and no time, and is no listen: it says what
/// plays now (SCR-009).
struct ListenSubmission {
    struct Invalid: Error {
        let message: String
    }

    enum Kind: String {
        case single
        case playingNow = "playing_now"
        case `import`
    }

    /// ListenBrainz refuses listens from before Audioscrobbler existed (2002-10-01).
    static let earliest = Date(timeIntervalSince1970: 1_033_430_400)
    /// A clock slightly ahead is forgiven; a listen from tomorrow is not.
    static let futureSlack: TimeInterval = 60 * 60
    static let maxText = 500

    let kind: Kind
    let listens: [NewListen]
    /// The track a `playing_now` names; nil for any other kind.
    let playingNow: NewListen?

    init(json: Data, now: Date) throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let body = try? decoder.decode(SubmissionBody.self, from: json) else {
            throw Invalid(message: "The body is not a ListenBrainz submission.")
        }
        guard let kind = Kind(rawValue: body.listenType) else {
            throw Invalid(message: "listen_type must be single, playing_now or import.")
        }
        switch kind {
        case .single, .playingNow:
            guard body.payload.count == 1 else {
                throw Invalid(message: "\(kind.rawValue) carries exactly one listen.")
            }
        case .import:
            guard (1 ... ListenBrainzRoutes.maxListens).contains(body.payload.count) else {
                throw Invalid(message: "An import carries 1 to \(ListenBrainzRoutes.maxListens) listens.")
            }
        }
        self.kind = kind
        let parsed = try body.payload.map { try Self.listen($0, kind: kind, now: now) }
        listens = kind == .playingNow ? [] : parsed
        playingNow = kind == .playingNow ? parsed.first : nil
    }

    private static func listen(_ payload: SubmissionBody.Payload, kind: Kind, now: Date) throws -> NewListen {
        let metadata = payload.trackMetadata
        guard let artist = text(metadata.artistName), let track = text(metadata.trackName) else {
            throw Invalid(message: "Every listen needs artist_name and track_name.")
        }
        var listenedAt = now
        if kind != .playingNow {
            guard let seconds = payload.listenedAt else { throw Invalid(message: "Every listen needs listened_at.") }
            listenedAt = Date(timeIntervalSince1970: TimeInterval(seconds))
            guard listenedAt >= earliest, listenedAt <= now.addingTimeInterval(futureSlack) else {
                throw Invalid(message: "listened_at is not a plausible time.")
            }
        }
        let info = metadata.additionalInfo
        return NewListen(
            listenedAt: listenedAt, artist: artist, track: track, album: text(metadata.releaseName),
            durationMs: info?.durationMs, isrc: text(info?.isrc), recordingMBID: mbid(info?.recordingMbid),
            releaseMBID: mbid(info?.releaseMbid), releaseGroupMBID: mbid(info?.releaseGroupMbid),
            artistMBID: mbid(info?.artistMbids?.first), spotifyID: text(info?.spotifyId),
            originURL: text(info?.originUrl).flatMap { $0.hasPrefix("https://") || $0.hasPrefix("http://") ? $0 : nil },
            client: text(info?.submissionClient ?? info?.mediaPlayer),
            musicService: text(info?.musicServiceName ?? info?.musicService)
        )
    }

    private static func text(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxText))
    }

    /// MusicBrainz ids are UUIDs; anything else is dropped rather than stored.
    private static func mbid(_ value: String?) -> String? {
        value.flatMap(UUID.init(uuidString:))?.uuidString.lowercased()
    }
}

/// ListenBrainz's submission JSON, with keys converted from snake_case.
private struct SubmissionBody: Decodable {
    struct Payload: Decodable {
        var listenedAt: Int64?
        var trackMetadata: TrackMetadata
    }

    struct TrackMetadata: Decodable {
        var artistName: String?
        var trackName: String?
        var releaseName: String?
        var additionalInfo: ListenAdditionalInfo?
    }

    var listenType: String
    var payload: [Payload]
}

/// `additional_info` is free-form; the fields Aaru keeps are read leniently and a field of
/// an unexpected type is ignored, never a reason to refuse the listen.
private struct ListenAdditionalInfo: Decodable {
    var durationMs: Int?
    var isrc: String?
    var recordingMbid: String?
    var releaseMbid: String?
    var releaseGroupMbid: String?
    var artistMbids: [String]?
    var spotifyId: String?
    var originUrl: String?
    var musicService: String?
    var musicServiceName: String?
    var submissionClient: String?
    var mediaPlayer: String?

    /// Raw values are camelCase: the decoder converts ListenBrainz's snake_case first.
    enum CodingKeys: String, CodingKey {
        case durationMs, duration, isrc, recordingMbid, releaseMbid, releaseGroupMbid, artistMbids, spotifyId
        case originUrl, musicService, musicServiceName, submissionClient, mediaPlayer
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func string(_ key: CodingKeys) -> String? {
            try? container.decodeIfPresent(String.self, forKey: key)
        }
        func number(_ key: CodingKeys) -> Double? {
            (try? container.decodeIfPresent(Double.self, forKey: key)) ?? string(key).flatMap(Double.init)
        }
        // `duration_ms`, or `duration` in seconds.
        let milliseconds = number(.durationMs) ?? number(.duration).map { $0 * 1000 }
        durationMs = milliseconds.flatMap { $0 >= 1 && $0 < 86_400_000 ? Int($0) : nil }
        isrc = string(.isrc)
        recordingMbid = string(.recordingMbid)
        releaseMbid = string(.releaseMbid)
        releaseGroupMbid = string(.releaseGroupMbid)
        artistMbids = try? container.decodeIfPresent([String].self, forKey: .artistMbids)
        spotifyId = string(.spotifyId)
        originUrl = string(.originUrl)
        musicService = string(.musicService)
        musicServiceName = string(.musicServiceName)
        submissionClient = string(.submissionClient)
        mediaPlayer = string(.mediaPlayer)
    }
}
