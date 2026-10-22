import AaruCore
import Foundation
import Logging
import Testing
@testable import aaru

/// SCR-008, SCR-009: what plays now, the next episode closing the last, and the Live Activity
/// pushes, against a fake APNs. No real key, no network.
@Suite("Now playing (SCR-008, SCR-009)", .serialized)
struct NowPlayingTests {
    /// Records what would have gone to Apple; some tokens are "dead".
    final class FakeLiveActivity: LiveActivityPushing, @unchecked Sendable {
        // @unchecked: test-only; `lock` guards `sent`.
        private let lock = NSLock()
        private var sent: [(LiveActivityPush, LiveActivityToken)] = []
        let dead: Set<String>

        init(dead: Set<String> = []) {
            self.dead = dead
        }

        var pushes: [(LiveActivityPush, LiveActivityToken)] {
            lock.withLock { sent }
        }

        func send(_ push: LiveActivityPush, to token: LiveActivityToken) async throws -> PushOutcome {
            if dead.contains(token.token) {
                return .deadToken
            }
            lock.withLock { sent.append((push, token)) }
            return .sent
        }
    }

    struct Env: Sendable {
        let harness: LibraryHarness
        let scrobble: ScrobbleService
        let caller: AgentCaller
        let apns: FakeLiveActivity
    }

    func withScrobble(
        dead: Set<String> = [],
        _ body: @escaping @Sendable (Env) async throws -> Void
    ) async throws {
        try await LibraryHarness.run { env in
            let catalogs = FakeCatalog.providers(env.fake)
            let resolver = TitleResolver(stores: env.stores, catalogs: catalogs)
            let library = LibraryService(
                stores: env.stores, resolver: resolver, catalog: CatalogService(stores: env.stores, catalogs: catalogs)
            )
            let minted = try await AgentTokenService(
                stores: env.stores, publicBaseURL: URL(string: "https://api.aaruapp.com")!
            ).create(userID: env.userID, kind: .stremio, name: nil, allowLibraryWrites: false)
            let apns = FakeLiveActivity(dead: dead)
            var scrobble = ScrobbleService(stores: env.stores, library: library, resolver: resolver)
            scrobble.liveActivity = LiveSetNotifier(stores: env.stores, sender: apns)
            try await body(Env(
                harness: env, scrobble: scrobble, caller: AgentCaller(userID: env.userID, token: minted.token),
                apns: apns
            ))
        }
    }

    func episode(
        _ tmdb: String, _ number: Int, _ action: PlaybackAction, at position: Int64, of duration: Int64 = 3_000_000
    ) throws -> PlaybackReport {
        try PlaybackReport(
            source: .stremio, externalRef: "\(tmdb):1:\(number)", type: .show, ids: ExternalIDs(tmdb: tmdb),
            episode: EpisodeKey(season: 1, episode: number), action: action, positionMs: position,
            durationMs: duration
        )
    }

    func watched(_ env: Env, tmdb: String) async throws -> [EpisodeKey] {
        let title = try #require(try await env.harness.stores.titles.find(ids: ExternalIDs(tmdb: tmdb), type: .show))
        let item = try #require(try await env.harness.stores.library.item(userID: env.caller.userID, titleID: title.id))
        return try await env.harness.stores.library.watched(itemID: item.id).sorted()
    }

    func session(
        state: OpenSession.State, position: Int64, duration: Int64, runtime: Int? = nil, reportedAgo: TimeInterval
    ) -> OpenSession {
        OpenSession(
            id: UUID(), source: .stremio, externalRef: "tt1:1:1", titleID: TitleID(), libraryItemID: nil,
            episode: nil, episodeName: nil, runtimeMinutes: runtime, state: state, positionMs: position,
            durationMs: duration, updatedAt: Date(timeIntervalSince1970: 1_000_000 - reportedAgo)
        )
    }

    func token(_ env: Env, kind: String, token: String = PushTests.token()) async throws -> LibraryHarness.Reply {
        try await env.harness.send(.put, "/v1/devices/live-activity", json: [
            "token": token, "kind": kind, "environment": "production", "bundleId": "com.fernandocorreia.aaru.beta",
        ])
    }

    /// The notifier's sweep at `now`, as the background service runs it.
    func sweep(_ env: Env, at now: Date) async throws {
        let notifier = try #require(env.scrobble.liveActivity)
        try await LiveActivitySweepService(
            notifier: notifier, stores: env.harness.stores, logger: Logger(label: "test"), now: { now }
        ).sweep(notifier)
    }

    @Test("A playing session lasts to its end plus grace, a paused one 30 minutes, an unknown one 3 hours")
    func liveness() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        // 20 of 50 minutes in, reported 25 minutes ago: 5 minutes left.
        #expect(NowPlaying.isLive(session(
            state: .playing,
            position: 1_200_000,
            duration: 3_000_000,
            reportedAgo: 25 * 60
        ), now: now))
        // Reported 41 minutes ago: past its end and the 10-minute grace.
        #expect(!NowPlaying.isLive(session(
            state: .playing,
            position: 1_200_000,
            duration: 3_000_000,
            reportedAgo: 41 * 60
        ), now: now))
        #expect(NowPlaying.isLive(session(state: .paused, position: 0, duration: 0, reportedAgo: 29 * 60), now: now))
        #expect(!NowPlaying.isLive(session(state: .paused, position: 0, duration: 0, reportedAgo: 31 * 60), now: now))
        #expect(NowPlaying.isLive(session(state: .playing, position: 0, duration: 0, reportedAgo: 2 * 3600), now: now))
        #expect(!NowPlaying.isLive(session(state: .playing, position: 0, duration: 0, reportedAgo: 4 * 3600), now: now))
        // No player duration: the 45-minute runtime stands in.
        #expect(!NowPlaying.isLive(session(
            state: .playing,
            position: 0,
            duration: 0,
            runtime: 45,
            reportedAgo: 56 * 60
        ), now: now))
    }

    @Test("Episode after episode: each stop past 80% ticks its own episode once")
    func bingeWithStops() async throws {
        try await withScrobble { env in
            let tmdb = env.harness.stubShow("Cyberpunk: Edgerunners", status: .ended)
            _ = try await env.harness.add("show", tmdb: tmdb, status: "in_progress")
            let before = try await env.harness.actionCount()
            _ = try await env.scrobble.report(episode(tmdb, 2, .start, at: 0), from: env.caller)
            #expect(try await env.scrobble.report(episode(tmdb, 2, .stop, at: 2_980_000), from: env.caller) == .watched)
            _ = try await env.scrobble.report(episode(tmdb, 3, .start, at: 0), from: env.caller)
            #expect(try await env.scrobble.report(episode(tmdb, 3, .stop, at: 2_980_000), from: env.caller) == .watched)
            #expect(try await watched(env, tmdb: tmdb)
                == [EpisodeKey(season: 1, episode: 2), EpisodeKey(season: 1, episode: 3)])
            #expect(try await env.harness.actionCount() == before + 2)
            #expect(
                try await env.scrobble.report(episode(tmdb, 3, .stop, at: 2_980_000), from: env.caller)
                    == .stoppedWithoutChange,
                "a repeat stop is still a no-op"
            )
        }
    }

    @Test("The next episode starting without a stop closes the last, ticking it only past 80% reported")
    func nextEpisodeWithoutStop() async throws {
        try await withScrobble { env in
            let tmdb = env.harness.stubShow("Andor", status: .ended)
            _ = try await env.harness.add("show", tmdb: tmdb, status: "in_progress")
            _ = try await env.scrobble.report(episode(tmdb, 1, .start, at: 0), from: env.caller)
            _ = try await env.scrobble.report(episode(tmdb, 1, .pause, at: 1_200_000), from: env.caller)
            _ = try await env.scrobble.report(episode(tmdb, 2, .start, at: 0), from: env.caller)
            #expect(try await watched(env, tmdb: tmdb) == [], "40% reported is not watched")

            _ = try await env.scrobble.report(episode(tmdb, 2, .pause, at: 2_700_000), from: env.caller)
            _ = try await env.scrobble.report(episode(tmdb, 3, .start, at: 0), from: env.caller)
            #expect(try await watched(env, tmdb: tmdb) == [EpisodeKey(season: 1, episode: 2)])

            let open = try await env.harness.stores.watchEvents.openSessions(
                userID: env.caller.userID, source: .stremio, limit: 10
            )
            #expect(open.map(\.externalRef) == ["\(tmdb):1:3"], "only the new episode stays open")
        }
    }

    @Test("GET /v1/me/now-playing shows the open episode, and nothing once it stops")
    func endpoint() async throws {
        try await withScrobble { env in
            let tmdb = env.harness.stubShow("Slow Horses", status: .returning)
            let itemID = try await env.harness.add("show", tmdb: tmdb, status: "in_progress")
            #expect(try await env.harness.send(.get, "/v1/me/now-playing").json()["nowPlaying"] == nil)

            _ = try await env.scrobble.report(episode(tmdb, 2, .start, at: 600_000), from: env.caller)
            let reply = try await env.harness.send(.get, "/v1/me/now-playing")
            #expect(reply.status == .ok)
            let playing = try #require(try reply.json()["nowPlaying"] as? [String: Any])
            #expect(playing["state"] as? String == "playing")
            #expect(playing["source"] as? String == "stremio")
            #expect(playing["positionMs"] as? Int == 600_000)
            #expect(playing["durationMs"] as? Int == 3_000_000)
            #expect((playing["libraryItemId"] as? String)?.lowercased() == itemID.lowercased())
            #expect(playing["episodeName"] as? String == "S1E2")
            #expect((playing["episode"] as? [String: Any])?["number"] as? Int == 2)
            #expect((playing["title"] as? [String: Any])?["title"] as? String == "Slow Horses")

            _ = try await env.scrobble.report(episode(tmdb, 2, .stop, at: 2_900_000), from: env.caller)
            #expect(try await env.harness.send(.get, "/v1/me/now-playing").json()["nowPlaying"] == nil)
        }
    }

    @Test("Live Activity: pushed to start once, updated on pause, watched lingers, then the sweep ends it")
    func liveActivity() async throws {
        try await withScrobble(dead: ["dead".padding(toLength: 64, withPad: "0", startingAt: 0)]) { env in
            let tmdb = env.harness.stubShow("Pluribus", status: .returning)
            _ = try await env.harness.add("show", tmdb: tmdb, status: "in_progress")
            let start = PushTests.token()
            let dead = "dead".padding(toLength: 64, withPad: "0", startingAt: 0)
            #expect(try await token(env, kind: "start", token: start).status == .noContent)
            #expect(try await token(env, kind: "start", token: dead).status == .noContent)

            _ = try await env.scrobble.report(episode(tmdb, 2, .start, at: 60000), from: env.caller)
            let started = env.apns.pushes
            #expect(started.count == 1)
            let (push, sentTo) = try #require(started.first)
            #expect(sentTo.token == start)
            #expect(push.event == .start(alertTitle: "Now playing", alertBody: "Pluribus · S1 · E2 · S1E2"))
            #expect(push.priority == .immediate)
            let item = try #require(push.content.items.first)
            #expect(push.content.items.count == 1)
            #expect(item.kind == .episode)
            #expect(item.service == "Stremio")
            #expect(try #require(item.endsAt).timeIntervalSince(item.startedAt) == 3000)
            #expect(
                try await env.harness.stores.watchEvents.liveActivityStartTokens(userID: env.caller.userID)
                    .map(\.token) == [start],
                "the dead token is forgotten"
            )

            // The player reporting on, with nothing new to show, pushes nothing.
            _ = try await env.scrobble.report(episode(tmdb, 2, .start, at: 90000), from: env.caller)
            #expect(env.apns.pushes.count == 1)

            let running = PushTests.token()
            #expect(try await token(env, kind: "update", token: running).status == .noContent)
            _ = try await env.scrobble.report(episode(tmdb, 2, .pause, at: 900_000), from: env.caller)
            let paused = try #require(env.apns.pushes.last)
            #expect(paused.0.event == .update)
            #expect(paused.0.priority == .considerate)
            #expect(paused.0.content.items.first?.pausedAt != nil)
            #expect(paused.1.token == running)

            _ = try await env.scrobble.report(episode(tmdb, 2, .stop, at: 2_950_000), from: env.caller)
            let watched = try #require(env.apns.pushes.last)
            #expect(watched.0.event == .update)
            #expect(watched.0.content.items.map(\.watched) == [true], "the ticked row lingers as Watched")
            #expect(env.apns.pushes.count == 3)

            try await sweep(env, at: Date().addingTimeInterval(LiveSetNotifier.watchedLinger + 1))
            let ended = try #require(env.apns.pushes.last)
            guard case .end = ended.0.event else {
                Issue.record("expected an end push, got \(ended.0.event)")
                return
            }
            #expect(env.apns.pushes.count == 4)
            #expect(try await env.harness.stores.watchEvents.liveActivityUpdateTokens(userID: env.caller.userID)
                .isEmpty)
        }
    }

    @Test("Live Activity tokens: bad input is refused; a watch event id is no longer needed")
    func registration() async throws {
        try await withScrobble { env in
            #expect(try await token(env, kind: "update").status == .noContent)
            #expect(try await token(env, kind: "start", token: "not-hex").status == .unprocessableContent)
            let foreign = try await env.harness.send(.put, "/v1/devices/live-activity", json: [
                "token": PushTests.token(), "kind": "start", "environment": "sandbox", "bundleId": "com.example.other",
            ])
            #expect(foreign.status == .unprocessableContent)
        }
    }
}
