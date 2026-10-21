import AaruCore
import Foundation
import Testing
@testable import aaru

/// MusicBrainz against canned JSON. No network.
@Suite("MusicBrainz adapter (MUS-001)")
struct MusicBrainzAdapterTests {
    /// Routes by URL path to canned JSON bodies; anything else is a 404.
    func transport(_ routes: [String: String]) -> StubTransport {
        StubTransport { request in
            let path = request.url.path
            guard let body = routes.first(where: { path.hasSuffix($0.key) })?.value else {
                return OutboundResponse(status: 404, body: Data())
            }
            return OutboundResponse(status: 200, body: Data(body.utf8))
        }
    }

    func catalog(_ stub: StubTransport) -> MusicBrainzCatalog {
        MusicBrainzCatalog(
            client: ProviderClient(
                name: "musicbrainz", transport: stub, pacer: RequestPacer(requestsPerSecond: 1000, burst: 100)
            ),
            userAgent: "Aaru-test"
        )
    }

    @Test("Search keeps albums and EPs, joins the artist credit, and points the cover at Cover Art Archive")
    func search() async throws {
        let stub = transport(["/release-group": #"""
        {"release-groups":[
          {"id":"b1392450-e666-3926-a536-22c65f834433","title":"OK Computer","primary-type":"Album",
           "first-release-date":"1997-05-21","artist-credit":[{"name":"Radiohead","joinphrase":""}]},
          {"id":"single-1","title":"Paranoid Android","primary-type":"Single","first-release-date":"1997-05-26",
           "artist-credit":[{"name":"Radiohead"}]},
          {"id":"ep-1","title":"Duet EP","primary-type":"EP","first-release-date":"2001",
           "artist-credit":[{"name":"Simon","joinphrase":" & "},{"name":"Garfunkel"}]}
        ]}
        """#])
        let hits = try await catalog(stub).search(query: "ok computer (live)", type: .album)
        #expect(hits.map(\.title) == ["OK Computer", "Duet EP"], "singles are not tracked")
        let album = try #require(hits.first)
        #expect(album.type == .album)
        #expect(album.year == 1997 && album.releaseDate == "1997-05-21")
        #expect(album.byline == "Radiohead")
        #expect(album.ids == ExternalIDs(musicbrainz: "b1392450-e666-3926-a536-22c65f834433"))
        #expect(album.posterURL?.absoluteString
            == "https://coverartarchive.org/release-group/b1392450-e666-3926-a536-22c65f834433/front-250")
        #expect(hits.last?.byline == "Simon & Garfunkel")

        let request = try #require(stub.requests.first)
        let query = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.contains(URLQueryItem(name: "fmt", value: "json")))
        let lucene = try #require(query.first { $0.name == "query" }?.value)
        #expect(lucene.contains(#"ok computer \(live\)"#), "the user's punctuation is escaped, never syntax")
        #expect(request.headers.contains { $0 == ("User-Agent", "Aaru-test") })
    }

    @Test("Hydrate keeps the five most-tagged genres; an unknown id is nil, not an error")
    func hydrate() async throws {
        let stub = transport(["/release-group/rg-1": #"""
        {"id":"rg-1","title":"Kid A","primary-type":"Album","first-release-date":"2000-10-02",
         "artist-credit":[{"name":"Radiohead"}],
         "genres":[{"name":"electronic","count":9},{"name":"art rock","count":12},{"name":"ambient","count":3},
                   {"name":"experimental","count":7},{"name":"idm","count":2},{"name":"glitch","count":1}]}
        """#])
        let title = try #require(try await catalog(stub).hydrate(ids: ExternalIDs(musicbrainz: "rg-1"), type: .album))
        #expect(title.genres == ["art rock", "electronic", "experimental", "ambient", "idm"])
        #expect(title.hit.byline == "Radiohead")
        #expect(try await catalog(stub).hydrate(ids: ExternalIDs(musicbrainz: "rg-404"), type: .album) == nil)
        #expect(try await catalog(stub).hydrate(ids: ExternalIDs(tmdb: "603"), type: .album) == nil)
    }

    @Test("Tracks come from the earliest dated official release, by disc then position")
    func tracks() async throws {
        let stub = transport(["/release": #"""
        {"releases":[
          {"date":"2009-03-24",
           "media":[{"position":1,"tracks":[{"position":1,"title":"Remaster Intro","length":1000}]}]},
          {"media":[{"position":1,"tracks":[{"position":1,"title":"Undated","length":1}]}]},
          {"date":"1997-05-21","media":[
            {"position":1,"tracks":[{"position":1,"title":"Airbag","length":284000},
                                    {"position":2,"title":"Paranoid Android","length":383000}]},
            {"position":2,"tracks":[{"position":1,"title":"Bonus","length":null}]}
          ]}
        ]}
        """#])
        let tracks = try #require(try await catalog(stub).tracks(ids: ExternalIDs(musicbrainz: "rg-1")))
        #expect(tracks == [
            AlbumTrack(disc: 1, position: 1, name: "Airbag", lengthMs: 284_000),
            AlbumTrack(disc: 1, position: 2, name: "Paranoid Android", lengthMs: 383_000),
            AlbumTrack(disc: 2, position: 1, name: "Bonus", lengthMs: nil),
        ])
        let query = try URLComponents(url: #require(stub.requests.first).url, resolvingAgainstBaseURL: false)?
            .queryItems ?? []
        #expect(query.contains(URLQueryItem(name: "release-group", value: "rg-1")))
        #expect(query.contains(URLQueryItem(name: "status", value: "official")))
    }
}

@Suite("Albums in the library (MUS-001)", .serialized)
struct AlbumLibraryTests {
    func stubAlbum(_ env: LibraryHarness, _ name: String) -> String {
        let mbid = uniqueID("mb")
        env.fake.stubTitle(CatalogTitle(
            hit: CatalogHit(
                type: .album, title: name, originalTitle: nil, year: 1997,
                posterURL: MusicBrainzCatalog.coverURL(releaseGroup: mbid), overview: nil, byline: "Radiohead",
                ids: ExternalIDs(musicbrainz: mbid), isAnime: false
            ),
            status: nil, runtimeMinutes: nil, genres: ["art rock", "alternative rock"]
        ))
        return mbid
    }

    @Test("An album is added by its MusicBrainz id; its page carries the artist, genres and tracklist")
    func addAndDetail() async throws {
        try await LibraryHarness.run { env in
            let mbid = stubAlbum(env, "OK Computer")
            env.fake.stubTracks(mbid, [
                AlbumTrack(disc: 1, position: 1, name: "Airbag", lengthMs: 284_000),
                AlbumTrack(disc: 1, position: 2, name: "Paranoid Android", lengthMs: nil),
            ])
            let added = try await env.send(.post, "/v1/library/items", json: [
                "mediaRef": ["type": "album", "ids": ["musicbrainz": mbid]],
            ]).json()
            let title = try #require(added["title"] as? [String: Any])
            #expect(title["type"] as? String == "album")
            #expect(title["byline"] as? String == "Radiohead")
            #expect((title["ids"] as? [String: Any])?["musicbrainz"] as? String == mbid)
            let titleID = try #require(title["id"] as? String)

            let detail = try await env.send(.get, "/v1/titles/\(titleID)").json()
            #expect(detail["byline"] as? String == "Radiohead")
            #expect(detail["genres"] as? [String] == ["art rock", "alternative rock"])
            let tracks = try #require(detail["tracks"] as? [[String: Any]])
            #expect(tracks.compactMap { $0["name"] as? String } == ["Airbag", "Paranoid Android"])
            #expect(tracks.first?["lengthMs"] as? Int == 284_000)
            #expect(detail["seasons"] == nil)

            _ = try await env.send(.get, "/v1/titles/\(titleID)")
            #expect(env.fake.callCount("tracks") == 1, "a stored tracklist is not fetched again")
        }
    }

    @Test("A tracklist MusicBrainz cannot give does not fail the page")
    func tracksDown() async throws {
        try await LibraryHarness.run { env in
            let mbid = stubAlbum(env, "Kid A")
            let added = try await env.send(.post, "/v1/library/items", json: [
                "mediaRef": ["type": "album", "ids": ["musicbrainz": mbid]],
            ]).json()
            let titleID = try #require((added["title"] as? [String: Any])?["id"] as? String)
            env.fake.fail(with: ProviderError(provider: "musicbrainz", kind: .unavailable))
            let detail = try await env.send(.get, "/v1/titles/\(titleID)")
            #expect(detail.status == .ok)
            #expect(try detail.json()["tracks"] == nil, "no tracklist yet, rather than an empty one")
        }
    }

    @Test("Albums read Plan to listen, Listening, Listened in the journal; albums filter by type")
    func labelsAndFilter() async throws {
        try await LibraryHarness.run { env in
            let movie = try await env.add("movie", tmdb: env.stubMovie("Dune"))
            let album = try #require(try await env.send(.post, "/v1/library/items", json: [
                "mediaRef": ["type": "album", "ids": ["musicbrainz": stubAlbum(env, "OK Computer")]],
            ]).json()["id"] as? String)
            _ = try await env.send(.patch, "/v1/library/items/\(album)", json: ["status": "in_progress"])
            _ = try await env.send(.patch, "/v1/library/items/\(album)", json: ["status": "finished"])

            let journal = try await env.send(.get, "/v1/actions?limit=10").json()
            let summaries = (journal["items"] as? [[String: Any]])?.compactMap { $0["summary"] as? String }
            #expect(summaries == [
                "Moved OK Computer to Listened", "Moved OK Computer to Listening",
                "Added OK Computer to Plan to listen", "Added Dune to Plan to watch",
            ])
            let albums = try await env.send(.get, "/v1/library/items?type=album").json()
            #expect((albums["items"] as? [[String: Any]])?.compactMap { $0["id"] as? String } == [album])
            let movies = try await env.send(.get, "/v1/library/items?type=movie").json()
            #expect((movies["items"] as? [[String: Any]])?.compactMap { $0["id"] as? String } == [movie])
        }
    }

    @Test("Album search goes to MusicBrainz alone; all never includes albums")
    func search() async throws {
        try await LibraryHarness.run { env in
            env.fake.stubSearch("radiohead", [CatalogHit(
                type: .album, title: "OK Computer", originalTitle: nil, year: 1997, posterURL: nil, overview: nil,
                byline: "Radiohead", ids: ExternalIDs(musicbrainz: uniqueID("mb")), isAnime: false
            )])
            let albums = try await env.send(.get, "/v1/search?q=radiohead&type=album").json()
            let items = try #require(albums["items"] as? [[String: Any]])
            #expect(items.compactMap { $0["type"] as? String } == ["album"])
            #expect(items.first?["byline"] as? String == "Radiohead")
            #expect(albums["incomplete"] as? Bool == false)
        }
    }
}
