import AaruCore
import Foundation
import Testing
@testable import aaru

@Suite("Scrobble service (SCR-001)", .serialized)
struct ScrobbleTests {
    struct Env: Sendable {
        let harness: LibraryHarness
        let scrobble: ScrobbleService
        let caller: AgentCaller
    }

    func withScrobble(_ body: @escaping @Sendable (Env) async throws -> Void) async throws {
        try await LibraryHarness.run { env in
            let catalogs = FakeCatalog.providers(env.fake)
            let resolver = TitleResolver(stores: env.stores, catalogs: catalogs)
            let library = LibraryService(
                stores: env.stores, resolver: resolver, catalog: CatalogService(stores: env.stores, catalogs: catalogs)
            )
            let minted = try await AgentTokenService(
                stores: env.stores, publicBaseURL: URL(string: "https://api.aaruapp.com")!
            ).create(userID: env.userID, kind: .stremio, name: nil, allowLibraryWrites: false)
            try await body(Env(
                harness: env,
                scrobble: ScrobbleService(stores: env.stores, library: library, resolver: resolver),
                caller: AgentCaller(userID: env.userID, token: minted.token)
            ))
        }
    }

    func episode(_ tmdb: String, _ action: PlaybackAction, at position: Int64, of duration: Int64 = 3_000_000)
        throws -> PlaybackReport
    {
        try PlaybackReport(
            source: .stremio, externalRef: "\(tmdb):1:2", type: .show, ids: ExternalIDs(tmdb: tmdb),
            episode: EpisodeKey(season: 1, episode: 2), action: action, positionMs: position, durationMs: duration
        )
    }

    func item(_ env: Env, tmdb: String) async throws -> LibraryItem? {
        guard let title = try await env.harness.stores.titles.find(ids: ExternalIDs(tmdb: tmdb), type: .show)
        else { return nil }
        return try await env.harness.stores.library.item(userID: env.caller.userID, titleID: title.id)
    }

    @Test("start → pause → stop at 85% ticks the episode once, as one action; a repeat stop is a no-op")
    func watchedEpisode() async throws {
        try await withScrobble { env in
            let tmdb = env.harness.stubShow("Andor", status: .ended)
            _ = try await env.harness.add("show", tmdb: tmdb, status: "in_progress")
            let before = try await env.harness.actionCount()

            #expect(try await env.scrobble.report(episode(tmdb, .start, at: 0, of: 0), from: env.caller) == .recorded)
            #expect(try await env.scrobble.report(episode(tmdb, .pause, at: 900_000), from: env.caller) == .recorded)
            #expect(try await env.harness.actionCount() == before, "start and pause never change progress")
            #expect(try await env.scrobble.report(episode(tmdb, .stop, at: 2_550_000), from: env.caller) == .watched)
            #expect(try await env.harness.actionCount() == before + 1)
            let watched = try await env.harness.stores.library
                .watched(itemID: #require(try await item(env, tmdb: tmdb)).id)
            #expect(try watched == [EpisodeKey(season: 1, episode: 2)])

            #expect(try await env.scrobble.report(episode(tmdb, .stop, at: 2_550_000), from: env.caller)
                == .stoppedWithoutChange)
            #expect(try await env.harness.actionCount() == before + 1, "a duplicate stop writes nothing")
        }
    }

    @Test("Stop short of 80%, or with no known duration, ticks nothing")
    func shortOrUnknown() async throws {
        try await withScrobble { env in
            let tmdb = env.harness.stubShow("Pluribus", status: .ended)
            _ = try await env.harness.add("show", tmdb: tmdb, status: "in_progress")
            let before = try await env.harness.actionCount()
            #expect(try await env.scrobble.report(episode(tmdb, .stop, at: 1_500_000), from: env.caller)
                == .stoppedWithoutChange)
            var unknown = try episode(tmdb, .stop, at: 2_900_000, of: 0)
            unknown.externalRef = "\(tmdb):1:3"
            #expect(try await env.scrobble.report(unknown, from: env.caller) == .stoppedWithoutChange)
            #expect(try await env.harness.actionCount() == before)
        }
    }

    @Test("A duration learned at start counts when stop reports 0")
    func durationFromEarlierReport() async throws {
        try await withScrobble { env in
            let tmdb = env.harness.stubShow("Shogun", status: .ended)
            _ = try await env.harness.add("show", tmdb: tmdb, status: "in_progress")
            _ = try await env.scrobble.report(episode(tmdb, .start, at: 0, of: 3_000_000), from: env.caller)
            #expect(try await env.scrobble.report(episode(tmdb, .stop, at: 2_700_000, of: 0), from: env.caller)
                == .watched)
        }
    }

    @Test("A show not in the library is added in progress and ticked, journaled as the agent")
    func absentShow() async throws {
        try await withScrobble { env in
            let tmdb = env.harness.stubShow("Slow Horses", status: .returning)
            #expect(try await env.scrobble.report(episode(tmdb, .stop, at: 2_900_000), from: env.caller) == .watched)
            let added = try #require(try await item(env, tmdb: tmdb))
            #expect(added.status == .inProgress)
            let actions = try #require(try await env.harness.send(.get, "/v1/actions?limit=2").json()["items"]
                as? [[String: Any]])
            #expect(actions.allSatisfy { $0["actor"] as? String == "external_agent" })
            #expect(actions.first?["summary"] as? String == "Stremio: marked S01E02 of Slow Horses watched")
        }
    }

    @Test("A movie stopped past 80% is finished; an unknown id is kept as unmatched")
    func movieAndUnmatched() async throws {
        try await withScrobble { env in
            let tmdb = env.harness.stubMovie("Arrival")
            let movie = PlaybackReport(
                source: .stremio, externalRef: "tt-\(tmdb)", type: .movie, ids: ExternalIDs(tmdb: tmdb), episode: nil,
                action: .stop, positionMs: 6_500_000, durationMs: 7_000_000
            )
            #expect(try await env.scrobble.report(movie, from: env.caller) == .watched)
            let title = try #require(try await env.harness.stores.titles.find(
                ids: ExternalIDs(tmdb: tmdb),
                type: .movie
            ))
            let item = try await env.harness.stores.library.item(userID: env.caller.userID, titleID: title.id)
            #expect(item?.status == .finished)

            let before = try await env.harness.actionCount()
            let unknown = PlaybackReport(
                source: .stremio, externalRef: "tt0000000", type: .movie, ids: ExternalIDs(imdb: "tt0000000"),
                episode: nil, action: .stop, positionMs: 100, durationMs: 100
            )
            #expect(try await env.scrobble.report(unknown, from: env.caller) == .unmatched)
            #expect(try await env.harness.actionCount() == before)
        }
    }
}
