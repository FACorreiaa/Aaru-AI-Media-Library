import AaruCore
import Foundation
import Testing
@testable import aaru

/// SCR-008: the Live Activity's token reaches the server late (a background launch).
extension NowPlayingTests {
    @Test("Live Activity: a token that arrives late hears the pause, then the stop, it missed")
    func lateToken() async throws {
        try await withScrobble { env in
            let tmdb = env.harness.stubShow("Severance", status: .returning)
            _ = try await env.harness.add("show", tmdb: tmdb, status: "in_progress")
            #expect(try await token(env, kind: "start").status == .noContent)
            _ = try await env.scrobble.report(episode(tmdb, 1, .start, at: 60000), from: env.caller)
            let (push, _) = try #require(env.apns.pushes.first)
            guard case .start = push.event else {
                Issue.record("expected a start push, got \(push.event)")
                return
            }
            _ = try await env.scrobble.report(episode(tmdb, 1, .pause, at: 600_000), from: env.caller)
            #expect(env.apns.pushes.count == 1, "no activity token yet, so the pause has nowhere to go")

            let notifier = try #require(env.scrobble.liveActivity)
            let late = LiveActivityToken(
                token: PushTests.token(), kind: .update, environment: .production,
                topic: "com.fernandocorreia.aaru.beta"
            )
            await notifier.caughtUp(late, userID: env.caller.userID, now: Date())
            let caught = try #require(env.apns.pushes.last)
            #expect(caught.0.event == .update)
            #expect(caught.0.content.items.first?.pausedAt != nil)
            #expect(caught.1.token == late.token)

            // Stopped short of 80%: nothing is left, so a token turning up after hears the end.
            _ = try await env.scrobble.report(episode(tmdb, 1, .stop, at: 700_000), from: env.caller)
            await notifier.caughtUp(late, userID: env.caller.userID, now: Date())
            let ended = try #require(env.apns.pushes.last)
            guard case .end = ended.0.event else {
                Issue.record("expected an end push, got \(ended.0.event)")
                return
            }
            #expect(env.apns.pushes.count == 3)
        }
    }
}
