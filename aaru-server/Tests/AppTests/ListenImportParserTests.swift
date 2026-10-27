import AaruCore
import Foundation
import Testing
@testable import aaru

/// MUS-004: listening history files and pages read into listens, with what is left out counted.
@Suite("Listening history parsers (MUS-004)")
struct ListenImportParserTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func spotify(_ ended: String, played: Int, track: String?, artist: String? = "Radiohead", episode: String? = nil)
        -> [String: Any]
    {
        var play: [String: Any] = [
            "ts": ended, "platform": "ios", "ms_played": played, "conn_country": "PT", "ip_addr": "203.0.113.9",
            "master_metadata_album_album_name": "OK Computer",
            "spotify_track_uri": "spotify:track:6LgJvl0Xdtc73RJ1mmpotq",
            "reason_start": "trackdone", "reason_end": "trackdone", "shuffle": false, "skipped": false,
        ]
        play["master_metadata_track_name"] = track ?? NSNull()
        play["master_metadata_album_artist_name"] = artist ?? NSNull()
        play["episode_name"] = episode ?? NSNull()
        return play
    }

    func json(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value)
    }

    @Test("Spotify: a play starts ms_played before ts; podcasts, audiobooks and short plays are left out")
    func spotifyHistory() throws {
        var audiobook = spotify("2024-03-01T10:10:00Z", played: 600_000, track: nil, artist: nil)
        audiobook["audiobook_title"] = "Dune"
        let data = try json([
            spotify("2024-03-01T10:04:44Z", played: 284_000, track: "Airbag"),
            spotify("2024-03-01T10:05:10Z", played: 12000, track: "Paranoid Android"),
            spotify("2024-03-01T11:00:00Z", played: 1_800_000, track: nil, artist: nil, episode: "A podcast"),
            audiobook,
        ])
        #expect(try ListenFileDetector.detect(data) == .spotifyJSON)
        let page = try SpotifyHistoryParser.parse(data, now: now)
        #expect(page.ignored == 3)
        let listen = try #require(page.listens.first)
        #expect(page.listens.count == 1)
        #expect(listen.listenedAt == Date(timeIntervalSince1970: 1_709_287_200), "10:04:44 − 4:44 = 10:00:00")
        #expect(listen.artist == "Radiohead")
        #expect(listen.track == "Airbag")
        #expect(listen.album == "OK Computer")
        #expect(listen.durationMs == 284_000)
        #expect(listen.spotifyID == "6LgJvl0Xdtc73RJ1mmpotq")
        #expect(listen.musicService == "Spotify")
        #expect(listen.originURL == nil && listen.client == nil, "nothing else from the file")
    }

    @Test("Spotify's account data and a zip are refused with what to send instead")
    func spotifyRefusals() throws {
        let basic = try json([[
            "endTime": "2024-03-01 10:04",
            "artistName": "Radiohead",
            "trackName": "Airbag",
            "msPlayed": 284_000,
        ]])
        #expect(throws: ImportFormatError.self) { try ListenFileDetector.detect(basic) }
        #expect(throws: ImportFormatError.self) { try ListenFileDetector.detect(Data("PK\u{03}\u{04}rest".utf8)) }
        #expect(throws: ImportFormatError.self) { try ListenFileDetector.detect(Data("[]".utf8)) }
    }

    func takeout(
        _ header: String, _ title: String?, channel: String?, url: String? = "https://music.youtube.com/watch?v=abc",
        advert: Bool = false, time: String = "2024-05-02T21:15:07.123Z"
    ) -> [String: Any] {
        var entry: [String: Any] = ["header": header, "time": time, "products": ["YouTube"]]
        entry["title"] = title
        entry["titleUrl"] = url
        if let channel {
            entry["subtitles"] = [["name": channel, "url": "https://www.youtube.com/channel/UC1"]]
        }
        if advert {
            entry["details"] = [["name": "From Google Ads"]]
        }
        return entry
    }

    @Test("Takeout: YouTube Music, and YouTube only from a Topic channel; ads and other videos are left out")
    func takeoutMusicOnly() throws {
        let data = try json([
            takeout("YouTube Music", "Watched Teardrop", channel: "Massive Attack - Topic"),
            takeout("YouTube Music", "Watched Karma Police", channel: "RadioheadVEVO"),
            takeout(
                "YouTube",
                "Watched Archangel",
                channel: "Burial - Topic",
                url: "https://www.youtube.com/watch?v=x1"
            ),
            takeout(
                "YouTube",
                "Watched How to bake bread",
                channel: "A Baker",
                url: "https://www.youtube.com/watch?v=x2"
            ),
            takeout("YouTube", "Watched An advert", channel: "Brand - Topic", advert: true),
            takeout("YouTube Music", "Watched a video that has been removed", channel: nil, url: nil),
            takeout("YouTube Music", "Watched https://music.youtube.com/watch?v=gone", channel: "Someone - Topic"),
        ])
        #expect(try ListenFileDetector.detect(data) == .youTubeTakeout)
        let page = try YouTubeTakeoutParser.parse(data, now: now)
        #expect(page.listens.map(\.artist) == ["Massive Attack", "Radiohead", "Burial"])
        #expect(page.listens.map(\.track) == ["Teardrop", "Karma Police", "Archangel"])
        #expect(page.listens.map(\.musicService) == ["YouTube Music", "YouTube Music", "YouTube"])
        #expect(page.listens[2].originURL == "https://www.youtube.com/watch?v=x1")
        #expect(page.listens.allSatisfy { $0.durationMs == nil }, "no length: the 30 s window")
        #expect(page.listens[0].listenedAt.timeIntervalSince1970.rounded() == 1_714_684_507)
        #expect(page.ignored == 4)
    }

    @Test("Takeout in another language: the verb every title starts with is found from the file")
    func takeoutOtherLanguage() throws {
        let songs = ["Teardrop", "Angel", "Inertia Creeps", "Archangel", "Near Dark"]
        let videos = [
            "Como fazer pão",
            "Receita de bacalhau",
            "Notícias da manhã",
            "Golos da jornada",
            "Viagem a Lisboa",
        ]
        let entries = songs.map { takeout("YouTube Music", "Assistiu a \($0)", channel: "Artista - Topic") }
            + videos.map { takeout("YouTube", "Assistiu a \($0)", channel: "Um canal") }
        let page = try YouTubeTakeoutParser.parse(json(entries), now: now)
        #expect(page.listens.map(\.track) == songs, "the verb comes from every title, videos too")
        #expect(page.ignored == videos.count)
        let few = songs.prefix(3).map { takeout("YouTube Music", "Assistiu a \($0)", channel: "Artista - Topic") }
        #expect(try YouTubeTakeoutParser.parse(json(few), now: now).ignored == 3, "too few titles to tell the verb")
    }

    @Test("Last.fm: the track playing now is no scrobble; one scrobble comes as an object")
    func lastFMPage() throws {
        let body = #"""
        {"recenttracks":{"track":[
          {"artist":{"mbid":"","#text":"Burial"},"album":{"mbid":"","#text":"Untrue"},"name":"Archangel","mbid":"",
           "@attr":{"nowplaying":"true"}},
          {"artist":{"mbid":"a74b1b7f-71a5-4011-9441-d0b5e4122711","#text":"Radiohead"},
           "album":{"mbid":"b1392450-e666-3926-a536-22c65f834433","#text":"OK Computer"},"name":"Airbag",
           "mbid":"8f2e5e5c-8b0e-4f2b-9a8d-2a5c7f1e2d3b","date":{"uts":"1700000000","#text":"14 Nov 2023, 22:13"}}
        ],"@attr":{"user":"rj","totalPages":"1","page":"1","perPage":"200","total":"1"}}}
        """#
        let decoded = try JSONDecoder().decode(LastFMPage.self, from: Data(body.utf8))
        let page = LastFMHistory.page(decoded.recenttracks.track, now: now)
        #expect(page.ignored == 0, "a track playing now is not left out, it is not yet a scrobble")
        let listen = try #require(page.listens.first)
        #expect(page.listens.count == 1)
        #expect(listen.listenedAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(listen.artistMBID == "a74b1b7f-71a5-4011-9441-d0b5e4122711")
        #expect(listen.releaseMBID == "b1392450-e666-3926-a536-22c65f834433")
        #expect(listen.recordingMBID == "8f2e5e5c-8b0e-4f2b-9a8d-2a5c7f1e2d3b")
        #expect(listen.client == "Last.fm")

        let single = #"""
        {"recenttracks":{"track":{"artist":{"#text":"Burial"},"name":"Archangel","date":{"uts":"1700000100"}},
         "@attr":{"totalPages":"1"}}}
        """#
        #expect(try JSONDecoder().decode(LastFMPage.self, from: Data(single.utf8)).recenttracks.track.count == 1)
    }

    @Test("Last.fm pages through the account and says why it refuses")
    func lastFMReader() async throws {
        let transport = StubTransport { request in
            let page = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems?
                .first { $0.name == "page" }?.value ?? "1"
            let uts = page == "1" ? 1_700_000_200 : 1_700_000_100
            let body = #"""
            {"recenttracks":{"track":[{"artist":{"#text":"Burial"},"name":"Track \#(page)","date":{"uts":"\#(uts)"}}],
             "@attr":{"totalPages":"2"}}}
            """#
            return OutboundResponse(status: 200, body: Data(body.utf8))
        }
        let client = ProviderClient(
            name: "lastfm", transport: transport, pacer: RequestPacer(requestsPerSecond: 1000, burst: 100),
            classify: LastFMHistory.classify
        )
        let reader = LastFMHistory(client: client, apiKey: "test-key", userAgent: "Aaru tests")
        let collected = Collected()
        try await reader.read(user: "rj", since: Date(timeIntervalSince1970: 1_600_000_000), now: now) { page in
            await collected.add(page.listens.map(\.track))
        }
        #expect(await collected.tracks == ["Track 1", "Track 2"])
        let first = try #require(transport.requests.first?.url.absoluteString)
        #expect(first.contains("from=1600000001") && first.contains("to=1800000000") && first.contains("user=rj"))

        for (code, kind) in [(6, ProviderError.Kind.notFound), (17, .refused(17)), (29, .unavailable)] {
            transport.respond { _ in
                OutboundResponse(status: 400, body: Data(#"{"error":\#(code),"message":"no"}"#.utf8))
            }
            await #expect(throws: ProviderError(provider: "lastfm", kind: kind)) {
                try await reader.read(user: "rj", since: nil, now: now) { _ in }
            }
        }
    }

    @Test("ListenBrainz pages back by max_ts, with its own match filling ids, and stops at an empty page")
    func listenBrainzReader() async throws {
        let transport = StubTransport { request in
            let before = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems?
                .first { $0.name == "max_ts" }?.value.flatMap(Int.init) ?? 0
            let listens = before > 1_700_000_000 ? #"""
            [{"listened_at":1700000500,"track_metadata":{"artist_name":"Burial","track_name":"Archangel",
              "release_name":"Untrue","additional_info":{"duration_ms":239000,"submission_client":"Pano Scrobbler"},
              "mbid_mapping":{"recording_mbid":"8f2e5e5c-8b0e-4f2b-9a8d-2a5c7f1e2d3b",
                "artist_mbids":["9ddce51c-2b75-4b3e-ac8c-1db09e7c89c6"]}}},
             {"listened_at":1700000000,"track_metadata":{"artist_name":"Burial","track_name":"Near Dark"}},
             {"listened_at":1699999999,"track_metadata":{"track_name":"No artist"}}]
            """# : "[]"
            return OutboundResponse(status: 200, body: Data(#"{"payload":{"count":3,"listens":\#(listens)}}"#.utf8))
        }
        let client = ProviderClient(
            name: "listenbrainz", transport: transport, pacer: RequestPacer(requestsPerSecond: 1000, burst: 100)
        )
        let reader = ListenBrainzHistory(client: client, userAgent: "Aaru tests")
        let collected = Collected()
        try await reader.read(user: "some user", since: nil, now: now) { page in
            await collected.add(page.listens.map(\.track), ignored: page.ignored)
        }
        #expect(await collected.tracks == ["Archangel", "Near Dark"])
        #expect(await collected.ignored == 1)
        let urls = transport.requests.map(\.url.absoluteString)
        #expect(urls.count == 2)
        #expect(urls[0].contains("/1/user/some%20user/listens") && urls[0].contains("max_ts=1800000001"))
        #expect(urls[1].contains("max_ts=1699999999"))
        #expect(!urls[0].contains("min_ts"))
    }

    @Test("A ListenBrainz page keeps the scrobbler's ids and fills the rest from ListenBrainz's match")
    func listenBrainzMapping() throws {
        let body = #"""
        {"payload":{"listens":[{"listened_at":1700000500,"track_metadata":{"artist_name":"Burial",
         "track_name":"Archangel","additional_info":{"recording_mbid":"11111111-1111-1111-1111-111111111111"},
         "mbid_mapping":{"recording_mbid":"8f2e5e5c-8b0e-4f2b-9a8d-2a5c7f1e2d3b",
         "release_mbid":"22222222-2222-2222-2222-222222222222"}}}]}}
        """#
        let read = try ListenSubmission.historyPage(json: Data(body.utf8), now: now)
        let listen = try #require(read.page.listens.first)
        #expect(listen.recordingMBID == "11111111-1111-1111-1111-111111111111", "what was sent wins")
        #expect(listen.releaseMBID == "22222222-2222-2222-2222-222222222222")
        #expect(listen.client == "ListenBrainz")
        #expect(read.oldest == 1_700_000_500)
    }
}

/// What a reader handed over, page by page.
actor Collected {
    var tracks: [String] = []
    var ignored = 0

    func add(_ names: [String], ignored more: Int = 0) {
        tracks += names
        ignored += more
    }
}
