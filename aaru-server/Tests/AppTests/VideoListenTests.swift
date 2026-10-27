import AaruCore
import Foundation
import Testing
@testable import aaru

/// SCR-011: a YouTube music video the extension reports becomes one live listen once heard, and
/// a music scrobbler's listen of the same video is the same play.
@Suite("YouTube music videos as listens (SCR-011)", .serialized)
struct VideoListenTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func body(progress: Double, durationMs: Int64 = 330_000, music: Bool = true) throws -> ScrobbleBody {
        let track = music ? #","music":{"artist":" Massive Attack ","track":"Teardrop"}"# : ""
        return try JSONDecoder().decode(ScrobbleBody.self, from: Data("""
        {"source":"youtube","ref":"u7K72X4eo_s","video":{"id":"u7K72X4eo_s","title":"Teardrop",
         "channel":"Massive Attack - Topic"\(track)},"progress":\(progress),"durationMs":\(durationMs)}
        """.utf8))
    }

    @Test("Heard means half the video or 4 minutes, whichever comes first, of a video of 30 s or more")
    func heard() throws {
        #expect(try body(progress: 30).videoListen(now: now) == nil, "99 s of 330 s")
        let listen = try #require(try body(progress: 60).videoListen(now: now))
        #expect(listen.listenedAt == now.addingTimeInterval(-198), "dated from when it began")
        #expect(listen.artist == "Massive Attack")
        #expect(listen.track == "Teardrop")
        #expect(listen.originURL == "https://www.youtube.com/watch?v=u7K72X4eo_s")
        #expect(listen.client == "Aaru extension" && listen.musicService == "YouTube")
        #expect(try body(progress: 20, durationMs: 1_200_000).videoListen(now: now) != nil, "4 min of 20")
        #expect(try body(progress: 100, durationMs: 20000).videoListen(now: now) == nil, "a 20 s clip")
        #expect(try body(progress: 90, music: false).videoListen(now: now) == nil, "not music")
    }

    @Test("A video's id is read from every YouTube watch link, and from nothing else")
    func videoIDs() {
        #expect(Listen.youTubeVideoID("https://www.youtube.com/watch?v=u7K72X4eo_s&t=4") == "u7K72X4eo_s")
        #expect(Listen.youTubeVideoID("https://music.youtube.com/watch?v=u7K72X4eo_s") == "u7K72X4eo_s")
        #expect(Listen.youTubeVideoID("https://youtu.be/u7K72X4eo_s") == "u7K72X4eo_s")
        #expect(Listen.youTubeVideoID("https://www.youtube.com/shorts/u7K72X4eo_s") == nil)
        #expect(Listen.youTubeVideoID("https://evil.example/watch?v=u7K72X4eo_s") == nil)
        #expect(Listen.youTubeVideoID("https://www.youtube.com/watch?v=short") == nil)
    }

    private func connect(_ env: LibraryHarness) async throws -> String {
        let body = try await env.send(.post, "/v1/agent/tokens", json: ["kind": "browser"]).json()
        return try #require(body["secret"] as? String)
    }

    private func report(
        _ env: LibraryHarness, _ action: String, token: String, progress: Double, music: Bool = true,
        id: String = "u7K72X4eo_s"
    ) async throws -> LibraryHarness.Reply {
        var video: [String: Any] = ["id": id, "title": "Teardrop", "channel": "Massive Attack - Topic"]
        if music {
            video["music"] = ["artist": "Massive Attack", "track": "Teardrop"]
        }
        return try await env.send(
            .post, "\(ScrobbleRoutes.path)/\(action)",
            json: ["source": "youtube", "ref": id, "video": video, "progress": progress, "durationMs": 330_000],
            token: token
        )
    }

    private func listens(_ env: LibraryHarness) async throws -> [[String: Any]] {
        try await env.send(.get, "/v1/me/listens").json()["items"] as? [[String: Any]] ?? []
    }

    @Test("The extension's music video is one listen however often it reports, and earns a live listen's points")
    func oneListen() async throws {
        try await LibraryHarness.run { env in
            let token = try await connect(env)
            #expect(try await report(env, "start", token: token, progress: 10).status == .ok)
            #expect(try await listens(env).isEmpty, "not heard yet")
            #expect(try await report(env, "start", token: token, progress: 55).status == .ok)
            #expect(try await report(env, "pause", token: token, progress: 70).status == .ok)
            #expect(try await report(env, "stop", token: token, progress: 98).status == .ok)
            let logged = try await listens(env)
            #expect(logged.count == 1)
            #expect(logged.first?["track"] as? String == "Teardrop")
            #expect(try await env.stores.gamification.totalPoints(userID: env.userID) > 0)

            #expect(try await report(env, "start", token: token, progress: 90, music: false, id: "dQw4w9WgXcQ")
                .status == .ok)
            #expect(try await listens(env).count == 1, "a video that is not music stays a play")
        }
    }

    @Test("A music scrobbler's listen of the same video is the same play, whichever comes first")
    func sameVideo() async throws {
        try await LibraryHarness.run { env in
            // Web Scrobbler spelled it its own way, on YouTube Music's link for the video.
            let started = Date().addingTimeInterval(-198).timeIntervalSince1970.rounded(.down)
            _ = try await env.stores.listens.insert([NewListen(
                listenedAt: Date(timeIntervalSince1970: started + 20), artist: "Massive Attack",
                track: "Teardrop (2006 Remaster)", durationMs: 330_000,
                originURL: "https://music.youtube.com/watch?v=u7K72X4eo_s", client: "Web Scrobbler"
            )], userID: env.userID, agentTokenID: nil)
            let token = try await connect(env)
            #expect(try await report(env, "start", token: token, progress: 60).status == .ok)
            let logged = try await listens(env)
            #expect(logged.count == 1, "the extension adds nothing")
            #expect(logged.first?["track"] as? String == "Teardrop (2006 Remaster)")

            let later = NewListen(
                listenedAt: Date(timeIntervalSince1970: started + 400), artist: "Massive Attack", track: "Teardrop",
                durationMs: 330_000, originURL: "https://www.youtube.com/watch?v=u7K72X4eo_s"
            )
            #expect(
                try await env.stores.listens.insert([later], userID: env.userID, agentTokenID: nil) == 1,
                "past the video's length it is another play"
            )
        }
    }
}
