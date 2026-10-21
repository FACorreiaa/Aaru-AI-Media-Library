import AaruCore
import Foundation
import Testing
@testable import aaru

/// MUS-006: MusicBrainz's recording search against canned JSON. No network.
@Suite("Recording match (MUS-006)")
struct RecordingMatchTests {
    func catalog(_ stub: StubTransport) -> MusicBrainzCatalog {
        MusicBrainzCatalog(
            client: ProviderClient(
                name: "musicbrainz", transport: stub, pacer: RequestPacer(requestsPerSecond: 1000, burst: 100)
            ),
            userAgent: "Aaru-test"
        )
    }

    func recording(
        _ id: String, _ title: String, artist: String = "Beastie Boys", artistID: String = "a-1", score: Int = 100,
        releases: [[String]]
    ) -> MusicBrainzRecording {
        let json: [String: Any] = [
            "id": id, "score": score, "title": title,
            "artist-credit": [["name": artist, "joinphrase": "", "artist": ["id": artistID, "name": artist]]],
            // Each release: title, release-group id, primary type.
            "releases": releases.map { release in
                [
                    "title": release[0],
                    "release-group": ["id": release[1], "title": release[0], "primary-type": release[2]],
                ]
            },
        ]
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(MusicBrainzRecording.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test("The search asks by the sent recording id, else the ISRC, else the exact artist and title")
    func queries() async throws {
        let stub = StubTransport { _ in OutboundResponse(status: 200, body: Data(#"{"recordings":[]}"#.utf8)) }
        let musicBrainz = catalog(stub)
        _ = try await musicBrainz.match(RecordingQuery(artist: "Beastie Boys", track: "Sabotage", recordingMBID: "r-1"))
        _ = try await musicBrainz.match(RecordingQuery(artist: "Beastie Boys", track: "Sabotage", isrc: "USCA29400153"))
        _ = try await musicBrainz.match(RecordingQuery(artist: "AC/DC", track: "T.N.T."))
        let queries = stub.requests.compactMap {
            URLComponents(url: $0.url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "query" }?.value
        }
        #expect(queries == ["rid:r-1", "isrc:USCA29400153", #"recording:"T.N.T." AND artist:"AC\/DC""#])
        #expect(stub.requests.allSatisfy { $0.url.path.hasSuffix("/ws/2/recording") })
        #expect(stub.requests.allSatisfy { request in request.headers.contains { $0 == ("User-Agent", "Aaru-test") } })
    }

    @Test("Only an exact title and artist at score 100 counts; the album is the one the listen named")
    func exactOnly() {
        let recordings = [
            recording(
                "r-1",
                "Sabotage",
                releases: [["Ill Communication", "rg-ill", "Album"], ["Sabotage", "rg-s", "Single"]]
            ),
            recording("r-2", "sabotage", releases: [["The Sounds of Science", "rg-sos", "Album"]]),
            recording("r-3", "Sabotage (live)", releases: [["Live", "rg-live", "Album"]]),
            recording("r-4", "Sabotage", score: 88, releases: [["Ill Communication", "rg-other", "Album"]]),
        ]
        let named = MusicBrainzCatalog.match(
            RecordingQuery(artist: "beastie  boys", track: "SABOTAGE", album: "ill communication"), in: recordings
        )
        #expect(
            named == RecordingMatch(recordingMBID: nil, releaseGroupMBID: "rg-ill", artistMBID: "a-1"),
            "two exact recordings: no recording id, but the named album and the artist are certain"
        )

        let unnamed = MusicBrainzCatalog.match(
            RecordingQuery(artist: "Beastie Boys", track: "Sabotage"),
            in: recordings
        )
        #expect(unnamed.releaseGroupMBID == nil, "two albums and no album named: nothing is guessed")

        let one = MusicBrainzCatalog.match(
            RecordingQuery(artist: "Beastie Boys", track: "Sabotage"),
            in: [recordings[0]]
        )
        #expect(
            one == RecordingMatch(recordingMBID: "r-1", releaseGroupMBID: "rg-ill", artistMBID: "a-1"),
            "with no album named, the only album wins over a single"
        )

        let fuzzy = MusicBrainzCatalog.match(RecordingQuery(artist: "Beastie Boys", track: "Sabotage!"), in: recordings)
        #expect(fuzzy == .none)
        let elsewhere = MusicBrainzCatalog.match(
            RecordingQuery(artist: "Beastie Boys", track: "Sabotage", album: "Hello Nasty"), in: [recordings[0]]
        )
        #expect(elsewhere == RecordingMatch(recordingMBID: "r-1", releaseGroupMBID: nil, artistMBID: "a-1"))
    }

    @Test("A recording id the scrobbler sent is trusted even when the spelling differs")
    func sentID() {
        let match = MusicBrainzCatalog.match(
            RecordingQuery(artist: "Beasties", track: "Sabotage [Remastered]", recordingMBID: "r-1"),
            in: [recording("r-1", "Sabotage", score: 100, releases: [["Ill Communication", "rg-ill", "Album"]])]
        )
        #expect(match == RecordingMatch(recordingMBID: "r-1", releaseGroupMBID: "rg-ill", artistMBID: "a-1"))
    }

    @Test("A joined credit matches the whole byline")
    func byline() throws {
        let json = #"""
        {"id":"r-9","score":100,"title":"The Boxer","artist-credit":[
          {"name":"Simon","joinphrase":" & ","artist":{"id":"a-s"}},
          {"name":"Garfunkel","joinphrase":"","artist":{"id":"a-g"}}],
         "releases":[{"title":"Bridge over Troubled Water",
           "release-group":{"id":"rg-b","title":"Bridge over Troubled Water","primary-type":"Album"}}]}
        """#
        let recording = try JSONDecoder().decode(MusicBrainzRecording.self, from: Data(json.utf8))
        let match = MusicBrainzCatalog.match(
            RecordingQuery(artist: "Simon & Garfunkel", track: "The Boxer"),
            in: [recording]
        )
        #expect(match.releaseGroupMBID == "rg-b")
        #expect(match.artistMBID == "a-s", "the first credited artist")
    }
}

/// Answers per artist; counts what it was asked.
final class FakeRecordings: RecordingMatching, @unchecked Sendable {
    // @unchecked: test-only; `lock` guards every mutable field.
    private let lock = NSLock()
    private var answers: [String: RecordingMatch] = [:]
    private var asked: [RecordingQuery] = []

    func answer(_ artist: String, _ match: RecordingMatch) {
        lock.withLock { answers[artist] = match }
    }

    func queries(for artist: String) -> [RecordingQuery] {
        lock.withLock { asked.filter { $0.artist == artist } }
    }

    func match(_ query: RecordingQuery) async throws -> RecordingMatch {
        lock.withLock {
            asked.append(query)
            return answers[query.artist] ?? .none
        }
    }
}

/// MUS-006 against Postgres. The lookup cache is shared by every user, so each test's artists are
/// unique and only their own rows are checked.
@Suite("Listen resolver (MUS-006)", .serialized)
struct ListenResolverTests {
    private func listen(_ artist: String, _ track: String, album: String?, minutesAgo: Double) -> NewListen {
        NewListen(
            listenedAt: Date().addingTimeInterval(-minutesAgo * 60), artist: artist, track: track, album: album,
            client: "Web Scrobbler"
        )
    }

    private func listens(_ env: LibraryHarness) async throws -> [[String: Any]] {
        try #require(try await env.send(.get, "/v1/me/listens?limit=100").json()["items"] as? [[String: Any]])
    }

    @Test("Each track and album is asked once; its listens gain the album, its cover and a link")
    func resolves() async throws {
        try await LibraryHarness.run { env in
            let artist = uniqueID("Radiohead")
            let recordings = FakeRecordings()
            recordings.answer(
                artist,
                RecordingMatch(recordingMBID: "r-1", releaseGroupMBID: "rg-ok", artistMBID: "a-1")
            )
            _ = try await env.stores.listens.insert([
                listen(artist, "Airbag", album: "OK Computer", minutesAgo: 30),
                listen(artist, "airbag", album: "ok computer", minutesAgo: 20),
                listen(artist, "Airbag", album: "OK Computer", minutesAgo: 10),
            ], userID: env.userID, agentTokenID: nil)
            let resolver = ListenResolver(passLimit: 1000, stores: env.stores, recordings: recordings)

            let pass = try await resolver.runOnce()
            #expect(pass.listens >= 3)
            #expect(recordings.queries(for: artist).count == 1, "three spellings of one track and album")
            #expect(recordings.queries(for: artist).first?.album == "OK Computer", "the newest listen's spelling")
            let items = try await listens(env)
            #expect(items.count == 3)
            for item in items {
                #expect(item["coverUrl"] as? String == "https://coverartarchive.org/release-group/rg-ok/front-250")
                let ref = try #require(item["albumRef"] as? [String: Any])
                #expect((ref["ids"] as? [String: Any])?["musicbrainz"] as? String == "rg-ok")
                #expect(ref["titleId"] == nil, "the album is not in the catalog yet")
            }

            _ = try await resolver.runOnce()
            #expect(recordings.queries(for: artist).count == 1, "a found track is not asked again")

            // A later play of the same track takes the ids as it is stored.
            _ = try await env.stores.listens.insert(
                [listen(artist, "Airbag", album: "OK Computer", minutesAgo: 1)], userID: env.userID, agentTokenID: nil
            )
            #expect(try await listens(env).first?["coverUrl"] != nil)
            _ = try await resolver.runOnce()
            #expect(recordings.queries(for: artist).count == 1)
        }
    }

    @Test("A miss is kept and asked again only after a month; sent ids are never overwritten")
    func missesAndSentIDs() async throws {
        try await LibraryHarness.run { env in
            let unknown = uniqueID("Nobody")
            let sent = uniqueID("Portishead")
            let recordings = FakeRecordings()
            recordings.answer(sent, RecordingMatch(recordingMBID: "r-x", releaseGroupMBID: "rg-x", artistMBID: "a-x"))
            var withIDs = listen(sent, "Roads", album: "Dummy", minutesAgo: 5)
            withIDs.releaseGroupMBID = "rg-dummy"
            _ = try await env.stores.listens.insert(
                [listen(unknown, "Demo", album: nil, minutesAgo: 5), withIDs], userID: env.userID, agentTokenID: nil
            )
            let now = Date()
            var resolver = ListenResolver(passLimit: 1000, stores: env.stores, recordings: recordings)
            resolver.now = { now }

            _ = try await resolver.runOnce()
            _ = try await resolver.runOnce()
            #expect(recordings.queries(for: unknown).count == 1, "a miss is remembered")
            #expect(recordings.queries(for: sent).isEmpty, "a listen that came with its album is not looked up")

            resolver.now = { now.addingTimeInterval(ListenResolver.retryAfter + 60) }
            _ = try await resolver.runOnce()
            #expect(recordings.queries(for: unknown).count == 2, "asked again after a month")

            let items = try await listens(env)
            let roads = try #require(items.first { $0["track"] as? String == "Roads" })
            #expect(roads["coverUrl"] as? String == "https://coverartarchive.org/release-group/rg-dummy/front-250")
            let demo = try #require(items.first { $0["track"] as? String == "Demo" })
            #expect(demo["albumRef"] == nil)
        }
    }

    @Test("An album already in the catalog is linked by its Aaru id")
    func linksCatalogAlbum() async throws {
        try await LibraryHarness.run { env in
            let artist = uniqueID("Massive Attack")
            let mbid = uniqueID("rg")
            env.fake.stubTitle(CatalogTitle(
                hit: CatalogHit(
                    type: .album, title: "Mezzanine", originalTitle: nil, year: 1998,
                    posterURL: MusicBrainzCatalog.coverURL(releaseGroup: mbid), overview: nil, byline: artist,
                    ids: ExternalIDs(musicbrainz: mbid), isAnime: false
                ),
                status: nil, runtimeMinutes: nil, genres: []
            ))
            let added = try await env.send(.post, "/v1/library/items", json: [
                "mediaRef": ["type": "album", "ids": ["musicbrainz": mbid]],
            ]).json()
            let titleID = try #require((added["title"] as? [String: Any])?["id"] as? String)

            let recordings = FakeRecordings()
            recordings.answer(artist, RecordingMatch(recordingMBID: nil, releaseGroupMBID: mbid, artistMBID: nil))
            _ = try await env.stores.listens.insert(
                [listen(artist, "Teardrop", album: "Mezzanine", minutesAgo: 3)], userID: env.userID, agentTokenID: nil
            )
            _ = try await ListenResolver(passLimit: 1000, stores: env.stores, recordings: recordings).runOnce()

            let item = try #require(try await listens(env).first)
            let ref = try #require(item["albumRef"] as? [String: Any])
            #expect(ref["titleId"] as? String == titleID)
            #expect(ref["type"] as? String == "album")
            #expect(ref["title"] as? String == "Mezzanine")
        }
    }
}
