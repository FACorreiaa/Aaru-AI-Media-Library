import AaruCore
import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
@testable import aaru

/// MUS-005: ListenBrainz's submit API with a music token, and the listening log it fills.
@Suite("ListenBrainz routes (MUS-005)", .serialized)
struct ListenBrainzRouteTests {
    /// Mints a token through the route, as Settings does.
    private func connect(_ env: LibraryHarness, kind: String = "music") async throws -> (id: String, secret: String) {
        let body = try await env.send(.post, "/v1/agent/tokens", json: ["kind": kind, "name": "Web Scrobbler"]).json()
        let token = try #require(body["token"] as? [String: Any])
        return try (#require(token["id"] as? String), #require(body["secret"] as? String))
    }

    /// Sends a body as a ListenBrainz client does: `Authorization: Token …`.
    private func submit(
        _ env: LibraryHarness, _ body: [String: Any], token: String, scheme: String = "Token"
    ) async throws -> LibraryHarness.Reply {
        try await env.client.execute(
            uri: "\(ListenBrainzRoutes.path)/submit-listens", method: .post,
            headers: [.authorization: "\(scheme) \(token)", .contentType: "application/json"],
            body: ByteBuffer(bytes: JSONSerialization.data(withJSONObject: body))
        ) { LibraryHarness.Reply(status: $0.status, body: Data(buffer: $0.body)) }
    }

    private func validate(_ env: LibraryHarness, token: String?) async throws -> LibraryHarness.Reply {
        var headers: HTTPFields = [:]
        if let token {
            headers[.authorization] = "Token \(token)"
        }
        return try await env.client.execute(
            uri: "\(ListenBrainzRoutes.path)/validate-token", method: .get, headers: headers, body: nil
        ) { LibraryHarness.Reply(status: $0.status, body: Data(buffer: $0.body)) }
    }

    /// A day ago, so every offset stays in the past.
    private let base = Int(Date().timeIntervalSince1970) - 86400

    private func listen(
        _ artist: String, _ track: String, at offset: Int = 0, album: String? = nil, durationMs: Int? = nil
    ) -> [String: Any] {
        var metadata: [String: Any] = ["artist_name": artist, "track_name": track]
        metadata["release_name"] = album
        var info: [String: Any] = ["submission_client": "Web Scrobbler", "music_service_name": "YouTube Music"]
        info["duration_ms"] = durationMs
        metadata["additional_info"] = info
        return ["listened_at": base + offset, "track_metadata": metadata]
    }

    private func single(_ listen: [String: Any]) -> [String: Any] {
        ["listen_type": "single", "payload": [listen]]
    }

    private func listens(_ env: LibraryHarness) async throws -> [[String: Any]] {
        try #require(try await env.send(.get, "/v1/me/listens?limit=100").json()["items"] as? [[String: Any]])
    }

    @Test("A music token sends a listen; it shows in the log and the export, and the library is untouched")
    func singleListen() async throws {
        try await LibraryHarness.run { env in
            let token = try await connect(env).secret
            #expect(token.hasPrefix("aaru_lb_"))
            let before = try await env.actionCount()

            let reply = try await submit(env, single(listen(
                "Radiohead", "Paranoid Android", album: "OK Computer", durationMs: 383_000
            )), token: token)
            #expect(reply.status == .ok)
            #expect(try reply.json()["status"] as? String == "ok")

            let items = try await listens(env)
            #expect(items.count == 1)
            let first = try #require(items.first)
            #expect(first["artist"] as? String == "Radiohead")
            #expect(first["track"] as? String == "Paranoid Android")
            #expect(first["album"] as? String == "OK Computer")
            #expect(first["durationMs"] as? Int == 383_000)
            #expect(first["client"] as? String == "Web Scrobbler")
            #expect(first["musicService"] as? String == "YouTube Music")
            #expect(try await env.actionCount() == before, "a listen never writes the library")

            let export = try await env.send(.get, "/v1/me/export?format=json").json()
            #expect((export["listens"] as? [[String: Any]])?.count == 1)
        }
    }

    @Test("Only a live music token gets in: not a session, a browser token, or a revoked one")
    func onlyMusicTokens() async throws {
        try await LibraryHarness.run { env in
            let body = single(listen("Björk", "Hyperballad"))
            #expect(try await submit(env, body, token: env.token, scheme: "Bearer").status == .unauthorized)
            let browser = try await connect(env, kind: "browser").secret
            #expect(try await submit(env, body, token: browser).status == .unauthorized)
            let music = try await connect(env)
            #expect(try await submit(env, body, token: music.secret, scheme: "Bearer").status == .ok)
            let scrobble = try await env.send(.post, "\(ScrobbleRoutes.path)/start", json: [:], token: music.secret)
            #expect(scrobble.status == .unauthorized, "a music token never scrobbles video")

            #expect(try await env.send(.delete, "/v1/agent/tokens/\(music.id)").status == .noContent)
            let revoked = try await submit(env, body, token: music.secret)
            #expect(revoked.status == .unauthorized)
            #expect(try revoked.json()["code"] as? Int == 401)
            #expect(try await listens(env).count == 1)
        }
    }

    @Test("The same play twice, or respelled, is kept once; the track played again later is kept")
    func duplicates() async throws {
        try await LibraryHarness.run { env in
            let token = try await connect(env).secret
            let play = listen("Radiohead", "Airbag", durationMs: 284_000)
            _ = try await submit(env, single(play), token: token)
            _ = try await submit(env, single(play), token: token)
            // A second scrobbler on the same play: other spelling, a minute later.
            _ = try await submit(env, single(listen("RADIOHEAD ", "airbag", at: 60, durationMs: 284_000)), token: token)
            // Played again five minutes on.
            _ = try await submit(env, single(listen("Radiohead", "Airbag", at: 300, durationMs: 284_000)), token: token)
            // A short track repeated back to back: its window is half its length.
            _ = try await submit(env, single(listen("Ramones", "Judy Is a Punk", durationMs: 90000)), token: token)
            _ = try await submit(
                env, single(listen("Ramones", "Judy Is a Punk", at: 90, durationMs: 90000)), token: token
            )
            let tracks = try await listens(env).compactMap { $0["track"] as? String }
            #expect(tracks.count(where: { $0 == "Airbag" }) == 2)
            #expect(tracks.count(where: { $0 == "Judy Is a Punk" }) == 2)
        }
    }

    @Test("playing_now stores nothing; import stores up to 1,000 and refuses more")
    func listenTypes() async throws {
        try await LibraryHarness.run { env in
            let token = try await connect(env).secret
            let now: [String: Any] = [
                "listen_type": "playing_now",
                "payload": [["track_metadata": ["artist_name": "Air", "track_name": "La femme d'argent"]]],
            ]
            #expect(try await submit(env, now, token: token).status == .ok)
            #expect(try await listens(env).isEmpty)

            let three = (0 ..< 3).map { listen("Air", "Track \($0)", at: $0 * 600) }
            #expect(try await submit(env, ["listen_type": "import", "payload": three], token: token).status == .ok)
            #expect(try await listens(env).count == 3)

            let tooMany = (0 ..< 1001).map { listen("Air", "Track \($0)", at: $0 * 600) }
            let refused = try await submit(env, ["listen_type": "import", "payload": tooMany], token: token)
            #expect(refused.status == .badRequest)
            #expect(try refused.json()["code"] as? Int == 400)
            #expect(try await listens(env).count == 3)
        }
    }

    @Test("A listen without its artist, track or a plausible time is refused with ListenBrainz's error shape")
    func invalid() async throws {
        try await LibraryHarness.run { env in
            let token = try await connect(env).secret
            var noTrack = listen("Air", "x")
            noTrack["track_metadata"] = ["artist_name": "Air"]
            var ancient = listen("Air", "Sexy Boy")
            ancient["listened_at"] = 631_152_000
            var noTime = listen("Air", "Kelly Watch the Stars")
            noTime["listened_at"] = nil
            for body in [single(noTrack), single(ancient), single(noTime), ["listen_type": "radio", "payload": []]] {
                let reply = try await submit(env, body, token: token)
                #expect(reply.status == .badRequest)
                #expect(try reply.json()["error"] is String)
            }
            #expect(try await submit(
                env,
                ["listen_type": "single", "payload": [listen("Air", "a"), listen("Air", "b")]],
                token: token
            ).status == .badRequest)
            #expect(try await listens(env).isEmpty)
        }
    }

    @Test("validate-token says whether a music token works, as ListenBrainz does")
    func validateToken() async throws {
        try await LibraryHarness.run { env in
            let token = try await connect(env).secret
            let valid = try await validate(env, token: token)
            #expect(valid.status == .ok)
            #expect(try valid.json()["valid"] as? Bool == true)
            #expect(try valid.json()["user_name"] as? String == "Web Scrobbler")

            let wrong = try await validate(env, token: "aaru_lb_nope")
            #expect(wrong.status == .ok)
            #expect(try wrong.json()["valid"] as? Bool == false)
            #expect(try await validate(env, token: nil).status == .badRequest)
        }
    }

    @Test("Pages go back in time with next")
    func pages() async throws {
        try await LibraryHarness.run { env in
            let token = try await connect(env).secret
            let five = (0 ..< 5).map { listen("Air", "Track \($0)", at: $0 * 600) }
            _ = try await submit(env, ["listen_type": "import", "payload": five], token: token)
            let first = try await env.send(.get, "/v1/me/listens?limit=3").json()
            let page = try #require(first["items"] as? [[String: Any]])
            #expect(page.compactMap { $0["track"] as? String } == ["Track 4", "Track 3", "Track 2"])
            let next = try #require(first["next"] as? String)
            let encoded = try #require(next.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
            let second = try await env.send(.get, "/v1/me/listens?limit=3&before=\(encoded)").json()
            let rest = try #require(second["items"] as? [[String: Any]])
            #expect(rest.compactMap { $0["track"] as? String } == ["Track 1", "Track 0"])
            #expect(second["next"] == nil)
        }
    }

    @Test("Top artists, tracks and albums count listens across spellings")
    func top() async throws {
        try await LibraryHarness.run { env in
            let token = try await connect(env).secret
            let plays = [
                listen("Radiohead", "Airbag", at: 0, album: "OK Computer", durationMs: 120_000),
                listen("radiohead", "Airbag", at: 600, album: "OK Computer", durationMs: 120_000),
                listen("Radiohead", "Karma Police", at: 1200, album: "OK Computer", durationMs: 120_000),
                listen("Portishead", "Roads", at: 1800, album: "Dummy", durationMs: 60000),
                listen("Portishead", "Glory Box", at: 2400),
            ]
            _ = try await submit(env, ["listen_type": "import", "payload": plays], token: token)

            let artists = try await env.send(.get, "/v1/me/listens/top?by=artist&span=all").json()
            #expect(artists["listens"] as? Int == 5)
            #expect(artists["minutes"] as? Int == 7)
            let artistItems = try #require(artists["items"] as? [[String: Any]])
            #expect(artistItems.compactMap { $0["artist"] as? String } == ["Radiohead", "Portishead"])
            #expect(artistItems.first?["count"] as? Int == 3)

            let tracks = try #require(
                try await env.send(.get, "/v1/me/listens/top?by=track&span=last7").json()["items"] as? [[String: Any]]
            )
            #expect(tracks.first?["track"] as? String == "Airbag")
            #expect(tracks.first?["count"] as? Int == 2)

            let albums = try #require(
                try await env.send(.get, "/v1/me/listens/top?by=album&span=all").json()["items"] as? [[String: Any]]
            )
            #expect(albums.compactMap { $0["album"] as? String } == ["OK Computer", "Dummy"])
            #expect(try await env.send(.get, "/v1/me/listens/top?by=artist").status == .unprocessableContent)
        }
    }

    @Test("A music token is named for its scrobbler and comes with that scrobbler's steps")
    func musicSetup() async throws {
        try await LibraryHarness.run { env in
            let body = try await env.send(.post, "/v1/agent/tokens", json: [
                "kind": "music", "scrobbler": "web_scrobbler",
            ]).json()
            let secret = try #require(body["secret"] as? String)
            let token = try #require(body["token"] as? [String: Any])
            #expect(token["name"] as? String == "Web Scrobbler")
            let music = try #require(body["music"] as? [String: Any])
            #expect(music["scrobbler"] as? String == "web_scrobbler")
            #expect(music["submitUrl"] as? String == "https://api.aaruapp.com/listenbrainz/1/submit-listens")
            #expect(music["baseUrl"] as? String == "https://api.aaruapp.com/listenbrainz/")
            let steps = try #require(music["steps"] as? [[String: Any]])
            let fields = steps.flatMap { $0["fields"] as? [[String: Any]] ?? [] }
            let tokenField = try #require(fields.first { $0["secret"] as? Bool == true })
            #expect(tokenField["value"] as? String == secret, "the steps carry the real token")
            #expect(fields.contains { $0["value"] as? String == music["submitUrl"] as? String })

            let other = try await env.send(.post, "/v1/agent/tokens", json: ["kind": "music"]).json()
            #expect((other["token"] as? [String: Any])?["name"] as? String == "Music scrobbler")
            #expect((other["music"] as? [String: Any])?["scrobbler"] as? String == "other")
            let named = try await env.send(.post, "/v1/agent/tokens", json: [
                "kind": "music", "scrobbler": "pano_scrobbler", "name": "Pixel",
            ]).json()
            #expect((named["token"] as? [String: Any])?["name"] as? String == "Pixel")

            let stremio = try await env.send(.post, "/v1/agent/tokens", json: [
                "kind": "stremio", "scrobbler": "web_scrobbler",
            ]).json()
            #expect(stremio["music"] == nil, "only music tokens get music steps")
        }
    }
}
