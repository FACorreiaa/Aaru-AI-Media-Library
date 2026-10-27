import AaruCore
import Foundation

/// One reader per service, built at boot (MUS-004): ListenBrainz on the Discover rows' client, so
/// both share its pacer, and Last.fm only with `LASTFM_API_KEY`.
func makeListenHistory(config: AppConfig, listenBrainz: ProviderClient, _ transport: any HTTPTransport)
    -> [ImportSource: any ListenHistoryReading]
{
    var readers: [ImportSource: any ListenHistoryReading] = [
        .listenBrainz: ListenBrainzHistory(client: listenBrainz, userAgent: config.openLibraryUserAgent),
    ]
    if let key = config.lastFMAPIKey {
        readers[.lastFM] = LastFMHistory(
            // Last.fm asks for at most 5 requests a second, averaged over 5 minutes.
            client: ProviderClient(
                name: "lastfm", transport: transport, pacer: RequestPacer(requestsPerSecond: 4, burst: 4),
                classify: LastFMHistory.classify
            ),
            apiKey: key, userAgent: config.openLibraryUserAgent
        )
    }
    return readers
}

/// MUS-004 · a service's public listening history, read by username.
protocol ListenHistoryReading: Sendable {
    /// Reads `user`'s plays newest first, back to `since` (exclusive) or the beginning, a page at a
    /// time. An unknown user throws `ProviderError` `.notFound`.
    func read(user: String, since: Date?, now: Date, page: (ListenHistoryPage) async throws -> Void) async throws
}

/// Last.fm's `user.getRecentTracks`, 200 scrobbles a page, with an API key (`LASTFM_API_KEY`).
/// The range is fixed when the read starts, so scrobbles arriving meanwhile do not shift the pages.
struct LastFMHistory: ListenHistoryReading {
    static let baseURL = URL(string: "https://ws.audioscrobbler.com/2.0/")!
    static let pageSize = 200
    /// Last.fm's error for a user who hides their recent listening.
    static let privateListening = 17

    let client: ProviderClient
    let apiKey: String
    let userAgent: String

    func read(user: String, since: Date?, now: Date, page: (ListenHistoryPage) async throws -> Void) async throws {
        let until = Int64(now.timeIntervalSince1970)
        var number = 1
        var pages = 1
        repeat {
            var query = [
                "method": "user.getrecenttracks", "user": user, "api_key": apiKey, "format": "json",
                "limit": "\(Self.pageSize)", "page": "\(number)", "to": "\(until)",
            ]
            if let since {
                query["from"] = "\(Int64(since.timeIntervalSince1970) + 1)"
            }
            let body = try await get(query)
            pages = Int(body.recenttracks.attr?.totalPages ?? "") ?? 1
            try await page(Self.page(body.recenttracks.track, now: now))
            number += 1
        } while number <= pages
    }

    /// A page's scrobbles. The track playing now has no time yet and is not a scrobble.
    static func page(_ tracks: [LastFMTrack], now: Date) -> ListenHistoryPage {
        var page = ListenHistoryPage()
        for track in tracks where track.attr?.nowplaying != "true" {
            let playedAt = track.date?.uts.flatMap(TimeInterval.init).map { Date(timeIntervalSince1970: $0) }
            guard let playedAt, ListenFileDetector.plausible(playedAt, now: now),
                  let artist = ListenSubmission.text(track.artist?.text),
                  let name = ListenSubmission.text(track.name)
            else {
                page.ignored += 1
                continue
            }
            page.listens.append(NewListen(
                listenedAt: playedAt, artist: artist, track: name, album: ListenSubmission.text(track.album?.text),
                recordingMBID: ListenSubmission.mbid(track.mbid), releaseMBID: ListenSubmission.mbid(track.album?.mbid),
                artistMBID: ListenSubmission.mbid(track.artist?.mbid), client: "Last.fm"
            ))
        }
        return page
    }

    private func get(_ query: [String: String]) async throws -> LastFMPage {
        var components = URLComponents(url: Self.baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components?.url else { throw ProviderError(provider: "lastfm", kind: .malformed) }
        let data = try await client.data(OutboundRequest(
            url: url, headers: [("User-Agent", userAgent), ("Accept", "application/json")]
        ))
        // Last.fm can answer an error with a 200.
        if let code = Self.errorCode(data) {
            throw ProviderError(provider: "lastfm", kind: Self.kind(code))
        }
        guard let body = try? JSONDecoder().decode(LastFMPage.self, from: data) else {
            throw ProviderError(provider: "lastfm", kind: .malformed)
        }
        return body
    }

    /// Last.fm's own error codes, read before the status code: 6 is an unknown user, 17 a private
    /// one, 29 over the rate limit. A bad key (10, 26) is Aaru's, not the person's: an outage.
    static func classify(_ response: OutboundResponse) -> ProviderError.Kind? {
        errorCode(response.body).map(kind)
    }

    private static func kind(_ code: Int) -> ProviderError.Kind {
        switch code {
        case 6: .notFound
        case privateListening: .refused(privateListening)
        default: .unavailable
        }
    }

    private static func errorCode(_ data: Data) -> Int? {
        struct Failure: Decodable {
            let error: Int
        }
        return (try? JSONDecoder().decode(Failure.self, from: data))?.error
    }
}

// MARK: - Last.fm wire shapes

/// One `user.getRecentTracks` page.
struct LastFMPage: Decodable {
    var recenttracks: LastFMRecentTracks
}

struct LastFMRecentTracks: Decodable {
    struct PageInfo: Decodable {
        var totalPages: String?
    }

    var track: [LastFMTrack]
    var attr: PageInfo?

    enum CodingKeys: String, CodingKey {
        case track
        case attr = "@attr"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // One scrobble comes as an object, not a list of one.
        track = (try? container.decode([LastFMTrack].self, forKey: .track))
            ?? (try? container.decode(LastFMTrack.self, forKey: .track)).map { [$0] } ?? []
        attr = try? container.decodeIfPresent(PageInfo.self, forKey: .attr)
    }
}

/// A named thing on Last.fm: an artist or an album, with its MusicBrainz id when known.
struct LastFMNamed: Decodable {
    var mbid: String?
    var text: String?

    enum CodingKeys: String, CodingKey {
        case mbid
        case text = "#text"
    }
}

struct LastFMTrack: Decodable {
    struct When: Decodable {
        var uts: String?
    }

    struct Flags: Decodable {
        var nowplaying: String?
    }

    var name: String?
    var mbid: String?
    var artist: LastFMNamed?
    var album: LastFMNamed?
    var date: When?
    var attr: Flags?

    enum CodingKeys: String, CodingKey {
        case name, mbid, artist, album, date
        case attr = "@attr"
    }
}

/// ListenBrainz's `GET /1/user/{name}/listens`, 1,000 a page, older pages asked by `max_ts`. It
/// shares the Discover rows' client, and so their one-a-second pacer.
struct ListenBrainzHistory: ListenHistoryReading {
    static let pageSize = 1000

    let client: ProviderClient
    let userAgent: String

    /// Letters, digits and `-._~` stay as they are in the path; anything else is escaped.
    private static let pathSafe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))

    func read(user: String, since: Date?, now: Date, page: (ListenHistoryPage) async throws -> Void) async throws {
        guard let name = user.addingPercentEncoding(withAllowedCharacters: Self.pathSafe),
              let base = URL(string: ListenBrainzReleases.baseURL.absoluteString + "/user/\(name)/listens")
        else { throw ProviderError(provider: "listenbrainz", kind: .notFound) }
        // `max_ts` and `min_ts` are both exclusive.
        let floor = since.map { [URLQueryItem(name: "min_ts", value: "\(Int64($0.timeIntervalSince1970))")] } ?? []
        var before = Int64(now.timeIntervalSince1970) + 1
        while true {
            var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
            components?.queryItems = [
                URLQueryItem(name: "count", value: "\(Self.pageSize)"),
                URLQueryItem(name: "max_ts", value: "\(before)"),
            ] + floor
            guard let url = components?.url else { throw ProviderError(provider: "listenbrainz", kind: .malformed) }
            let data = try await client.data(OutboundRequest(
                url: url, headers: [("User-Agent", userAgent), ("Accept", "application/json")]
            ))
            let read: (page: ListenHistoryPage, oldest: Int64?)
            do {
                read = try ListenSubmission.historyPage(json: data, now: now)
            } catch {
                throw ProviderError(provider: "listenbrainz", kind: .malformed)
            }
            // An empty page is the end; a page not older than the last would never end.
            guard let oldest = read.oldest, oldest < before else { return }
            try await page(read.page)
            before = oldest
        }
    }
}
