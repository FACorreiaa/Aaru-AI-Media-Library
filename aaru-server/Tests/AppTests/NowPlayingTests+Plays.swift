import AaruCore
import Foundation
import Testing
@testable import aaru

/// SCR-009: tracks and videos beside library episodes, in one activity.
extension NowPlayingTests {
    func track(_ name: String, durationMs: Int? = 200_000, origin: String? = nil) -> NewListen {
        NewListen(
            listenedAt: Date(), artist: "Artist", track: name, durationMs: durationMs, originURL: origin,
            client: "Web Scrobbler", musicService: "YouTube Music"
        )
    }

    func video(_ id: String, _ state: OpenSession.State = .playing, at now: Date = Date()) -> LivePlay {
        LivePlay.video(LivePlay.VideoReport(
            id: id, title: "A video", channel: "A channel", state: state, positionMs: 30000, durationMs: 600_000
        ), now: now)
    }

    @Test("The set: episodes and videos first, newest first, then tracks; three at most; no double video")
    func order() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let show = Title(id: TitleID(), type: .show, title: "Andor")
        let session = try OpenSession(
            id: UUID(), source: .stremio, externalRef: "tt1:1:1", titleID: show.id, libraryItemID: LibraryItemID(),
            episode: EpisodeKey(season: 1, episode: 1), episodeName: nil, runtimeMinutes: 50, state: .playing,
            positionMs: 0, durationMs: 3_000_000, updatedAt: now.addingTimeInterval(-60)
        )
        var notInLibrary = session
        notInLibrary.id = UUID()
        notInLibrary.libraryItemID = nil
        let song = LivePlay.track(track("Song"), now: now.addingTimeInterval(-10))
        let clip = video("dQw4w9WgXcQ", at: now.addingTimeInterval(-30))
        let heard = LivePlay.track(
            track("Same clip", origin: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"), now: now.addingTimeInterval(-5)
        )
        let set = LiveSet.compute(
            sessions: [(session, show), (notInLibrary, show)], plays: [song, clip, heard], now: now
        )
        #expect(set.map(\.activityItem.kind) == [.video, .episode, .track])
        #expect(set.map(\.activityItem.title) == ["A video", "Andor", "Song"])

        var expired = song
        expired.expiresAt = now
        #expect(LiveSet.compute(sessions: [], plays: [expired], now: now).isEmpty)
        #expect(LiveSet.compute(
            sessions: [(session, show)], plays: [song, clip, LivePlay.track(track("Two"), now: now)], now: now
        ).count == 3)
    }

    @Test("A report changes the activity only when what it shows changes")
    func differs() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let item = NowPlayingActivityItem(
            id: "a", kind: .video, title: "A video", startedAt: start, endsAt: start.addingTimeInterval(600)
        )
        var later = item
        later.startedAt = start.addingTimeInterval(2)
        later.endsAt = start.addingTimeInterval(602)
        #expect(!LiveSetNotifier.differs(.init(items: [item]), .init(items: [later])), "a heartbeat")
        var seeked = item
        seeked.endsAt = start.addingTimeInterval(900)
        #expect(LiveSetNotifier.differs(.init(items: [item]), .init(items: [seeked])))
        var paused = item
        paused.pausedAt = start
        #expect(LiveSetNotifier.differs(.init(items: [item]), .init(items: [paused])))
        var next = item
        next.id = "b"
        #expect(LiveSetNotifier.differs(.init(items: [item]), .init(items: [next])))
    }

    @Test("A song joins the episode's activity, the next song replaces it, and it leaves when it ends")
    func trackBesideEpisode() async throws {
        try await withScrobble { env in
            let tmdb = env.harness.stubShow("Slow Horses", status: .returning)
            _ = try await env.harness.add("show", tmdb: tmdb, status: "in_progress")
            #expect(try await token(env, kind: "start").status == .noContent)
            _ = try await env.scrobble.report(episode(tmdb, 1, .start, at: 0), from: env.caller)
            #expect(try await token(env, kind: "update").status == .noContent)
            let pushed = env.apns.pushes.count

            let now = Date()
            try await env.scrobble.play(.track(track("First"), now: now), from: env.caller)
            let joined = try #require(env.apns.pushes.last)
            #expect(env.apns.pushes.count == pushed + 1)
            #expect(joined.0.event == .update)
            #expect(joined.0.content.items.map(\.kind) == [.episode, .track])
            let first = try #require(joined.0.content.items.last)
            #expect(first.title == "First")
            #expect(first.subtitle == "Artist")
            #expect(first.service == "YouTube Music")

            // The same track again is no change; the next track is a new row.
            try await env.scrobble.play(.track(track("First"), now: now), from: env.caller)
            #expect(env.apns.pushes.count == pushed + 1)
            try await env.scrobble.play(.track(track("Second"), now: now), from: env.caller)
            let second = try #require(env.apns.pushes.last?.0.content.items.last)
            #expect(second.title == "Second")
            #expect(second.id != first.id)

            let reply = try await env.harness.send(.get, "/v1/me/now-playing").json()
            let items = try #require(reply["items"] as? [[String: Any]])
            #expect(items.map { $0["kind"] as? String } == ["episode", "track"])
            #expect(items.last?["source"] as? String == "listenbrainz")
            #expect(items.last?["name"] as? String == "Second")
            #expect(reply["nowPlaying"] != nil, "older clients still get the episode")

            // The track ends with nothing after it: the sweep takes its row away.
            try await sweep(env, at: now.addingTimeInterval(200 + LivePlay.trackGrace + 1))
            let gone = try #require(env.apns.pushes.last)
            #expect(gone.0.content.items.map(\.kind) == [.episode])
        }
    }

    @Test("A video alone starts the activity, pauses it, and its stop ends it")
    func videoAndTrackAlone() async throws {
        try await withScrobble { env in
            #expect(try await token(env, kind: "start").status == .noContent)
            try await env.scrobble.play(video("dQw4w9WgXcQ"), from: env.caller)
            let started = try #require(env.apns.pushes.last)
            #expect(started.0.event == .start(alertTitle: "Now playing", alertBody: "A video · A channel"))
            #expect(started.0.content.items.first?.artworkURL == "https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg")
            #expect(try await token(env, kind: "update").status == .noContent)

            try await env.scrobble.play(video("dQw4w9WgXcQ", .paused), from: env.caller)
            #expect(env.apns.pushes.last?.0.content.items.first?.pausedAt != nil)
            try await env.scrobble.stopPlay(.video, from: env.caller)
            guard case .end = try #require(env.apns.pushes.last).0.event else {
                Issue.record("expected an end push")
                return
            }
            let reply = try await env.harness.send(.get, "/v1/me/now-playing").json()
            #expect((reply["items"] as? [Any])?.isEmpty == true)
        }
    }

    @Test("The sweep claims a due user once")
    func sweepClaims() async throws {
        try await withScrobble { env in
            let watchEvents = env.harness.stores.watchEvents
            let userID = env.caller.userID
            _ = try await watchEvents.liveActivityState(userID: userID)
            let now = Date()
            try await watchEvents.scheduleLiveActivityCheck(userID: userID, at: now)
            try await watchEvents.scheduleLiveActivityCheck(userID: userID, at: now.addingTimeInterval(60))
            #expect(
                try await watchEvents.claimDueLiveActivityChecks(now: now, limit: 10) == [userID],
                "a later check never pushes back an earlier one"
            )
            #expect(try await watchEvents.claimDueLiveActivityChecks(now: now, limit: 10).isEmpty)
        }
    }

    @Test("A video scrobble body: YouTube's id, its name and a duration; nothing else")
    func videoBody() throws {
        func body(_ json: String) throws -> ScrobbleBody {
            try JSONDecoder().decode(ScrobbleBody.self, from: Data(json.utf8))
        }
        let good = try body("""
        {"source":"youtube","ref":"dQw4w9WgXcQ","video":{"id":"dQw4w9WgXcQ","title":" A video "},
         "progress":50,"durationMs":600000}
        """).video(.start, now: Date())
        #expect(good.title == "A video")
        #expect(good.subtitle == nil)
        #expect(good.positionMs == 300_000)
        let clip = #""video":{"id":"dQw4w9WgXcQ","title":"x"},"progress":1"#
        for bad in [
            #"{"source":"youtube","ref":"short","video":{"id":"short","title":"x"},"progress":1,"durationMs":1}"#,
            #"{"source":"netflix","ref":"dQw4w9WgXcQ","# + clip + #","durationMs":1}"#,
            #"{"source":"youtube","ref":"dQw4w9WgXcQ","# + clip + "}",
            #"{"source":"youtube","ref":"other","# + clip + #","durationMs":1}"#,
        ] {
            #expect(throws: ScrobbleBody.Invalid.self) { try body(bad).video(.start, now: Date()) }
        }
    }
}
