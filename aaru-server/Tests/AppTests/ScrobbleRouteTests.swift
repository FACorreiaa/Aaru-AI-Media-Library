import AaruCore
import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
@testable import aaru

/// SCR-001's `POST /v1/scrobble/*` with the browser extension's token (SCR-007), against stubs.
@Suite("Scrobble routes (SCR-001, SCR-007)", .serialized)
struct ScrobbleRouteTests {
    /// Mints a browser token through the route, as the web connect page does.
    private func connect(_ env: LibraryHarness, kind: String = "browser") async throws -> (id: String, secret: String) {
        let body = try await env.send(.post, "/v1/agent/tokens", json: ["kind": kind]).json()
        let token = try #require(body["token"] as? [String: Any])
        return try (#require(token["id"] as? String), #require(body["secret"] as? String))
    }

    private func scrobble(
        _ env: LibraryHarness, _ action: String, _ body: [String: Any], token: String
    ) async throws -> LibraryHarness.Reply {
        try await env.send(.post, "\(ScrobbleRoutes.path)/\(action)", json: body, token: token)
    }

    /// A show the fake TMDB finds by its name, with episodes named `S1E1`… (see `stubShow`).
    private func searchableShow(_ env: LibraryHarness, _ name: String) -> String {
        let tmdb = env.stubShow(name, status: .returning)
        env.fake.stubSearch(name, [CatalogHit(
            type: .show, title: name, originalTitle: nil, year: 2020, posterURL: nil, overview: nil,
            byline: nil, ids: ExternalIDs(tmdb: tmdb), isAnime: false
        )])
        return tmdb
    }

    private func episode(_ show: String, ref: String, progress: Double, number: Int? = 2) -> [String: Any] {
        var episode: [String: Any] = ["season": 1, "title": "S1E2"]
        episode["number"] = number
        return [
            "source": "netflix", "ref": ref, "show": ["title": show], "episode": episode,
            "progress": progress, "durationMs": 3_000_000,
        ]
    }

    @Test("start → pause → stop at 85% ticks the episode once, journaled as the extension; a repeat stop is a no-op")
    func watchedEpisode() async throws {
        try await LibraryHarness.run { env in
            let name = uniqueID("Severance")
            let tmdb = searchableShow(env, name)
            let token = try await connect(env).secret
            let before = try await env.actionCount()
            let ref = uniqueID("81000")

            let start = try await scrobble(env, "start", episode(name, ref: ref, progress: 0), token: token)
            #expect(start.status == .ok)
            let answer = try start.json()
            #expect(answer["outcome"] as? String == "recorded")
            #expect((answer["title"] as? [String: Any])?["name"] as? String == name)
            _ = try await scrobble(env, "pause", episode(name, ref: ref, progress: 30), token: token)
            #expect(try await env.actionCount() == before, "start and pause never change progress")
            let stop = try await scrobble(env, "stop", episode(name, ref: ref, progress: 85), token: token)
            #expect(try stop.json()["outcome"] as? String == "watched")
            #expect(try await env.actionCount() == before + 2, "added to the library, then ticked")
            let title = try #require(try await env.stores.titles.find(ids: ExternalIDs(tmdb: tmdb), type: .show))
            let item = try #require(try await env.stores.library.item(userID: env.userID, titleID: title.id))
            #expect(try await env.stores.library.watched(itemID: item.id) == [EpisodeKey(season: 1, episode: 2)])
            let actions = try #require(try await env.send(.get, "/v1/actions?limit=1").json()["items"]
                as? [[String: Any]])
            #expect(actions.first?["summary"] as? String == "Browser extension: marked S01E02 of \(name) watched")

            let again = try await scrobble(env, "stop", episode(name, ref: ref, progress: 85), token: token)
            #expect(try again.json()["outcome"] as? String == "stopped")
            #expect(try await env.actionCount() == before + 2, "a duplicate stop writes nothing")
        }
    }

    @Test("An episode with no number is matched by its name; a film two entries share stays unmatched")
    func byName() async throws {
        try await LibraryHarness.run { env in
            let name = uniqueID("Pluribus")
            let tmdb = searchableShow(env, name)
            let token = try await connect(env).secret
            let stop = try await scrobble(
                env, "stop", episode(name, ref: uniqueID("ref"), progress: 95, number: nil), token: token
            )
            #expect(try stop.json()["outcome"] as? String == "watched")
            let title = try #require(try await env.stores.titles.find(ids: ExternalIDs(tmdb: tmdb), type: .show))
            let item = try #require(try await env.stores.library.item(userID: env.userID, titleID: title.id))
            #expect(try await env.stores.library.watched(itemID: item.id) == [EpisodeKey(season: 1, episode: 2)])

            let film = uniqueID("Solaris")
            env.fake.stubSearch(film, [1972, 2002].map { year in
                CatalogHit(
                    type: .movie, title: film, originalTitle: nil, year: year, posterURL: nil, overview: nil,
                    byline: nil, ids: ExternalIDs(tmdb: uniqueID("tmdb")), isAnime: false
                )
            })
            let before = try await env.actionCount()
            let unmatched = try await scrobble(env, "stop", [
                "source": "prime_video", "ref": uniqueID("ref"), "movie": ["title": film], "progress": 99,
            ], token: token)
            let answer = try unmatched.json()
            #expect(answer["outcome"] as? String == "unmatched" && answer["title"] == nil)
            #expect(try await env.actionCount() == before)
        }
    }

    @Test("Only a live browser token gets in: not a session, an MCP token, a Stremio link or a revoked one")
    func auth() async throws {
        try await LibraryHarness.run { env in
            let body = episode("Anything", ref: "1", progress: 10)
            let browser = try await connect(env)
            let mcp = try await connect(env, kind: "claude_code").secret
            let stremio = try await connect(env, kind: "stremio").secret
            for token in [env.token, mcp, stremio, "aaru_scr_nope"] {
                #expect(try await scrobble(env, "start", body, token: token).status == .unauthorized)
            }
            #expect(try await env.send(.delete, "/v1/agent/tokens/\(browser.id)").status == .noContent)
            #expect(try await scrobble(env, "start", body, token: browser.secret).status == .unauthorized)
        }
    }

    @Test("A browser token can only scrobble, and is listed on its own surface")
    func tokenScope() async throws {
        try await LibraryHarness.run { env in
            let secret = try await connect(env).secret
            #expect(secret.hasPrefix(AgentTokenService.scrobblePrefix))
            let listed = try #require(try await env.send(.get, "/v1/agent/tokens?for=scrobble").json()["items"]
                as? [[String: Any]])
            #expect(listed.map { $0["kind"] as? String } == ["browser"])
            #expect(listed.first?["scopes"] as? [String] == ["scrobble:write"])
            let stremio = try #require(try await env.send(.get, "/v1/agent/tokens").json()["items"] as? [Any])
            #expect(stremio.isEmpty)
            let mcp = try await env.send(.post, MCPRoutes.path, json: [
                "jsonrpc": "2.0", "id": 1, "method": "tools/list",
            ], token: secret)
            #expect(mcp.status == .unauthorized)
        }
    }

    @Test("A body that is not a scrobble is refused with a reason")
    func validation() async throws {
        try await LibraryHarness.run { env in
            let token = try await connect(env).secret
            let bad: [[String: Any]] = [
                ["source": "stremio", "ref": "1", "movie": ["title": "Roma"], "progress": 10],
                ["source": "netflix", "ref": "1", "show": ["title": "Dark"], "progress": 10],
                ["source": "netflix", "ref": "1", "movie": ["title": "Roma"], "progress": 140],
                ["source": "netflix", "ref": "", "movie": ["title": "Roma"], "progress": 10],
                ["source": "netflix", "ref": "1", "movie": [:] as [String: Any], "progress": 10],
                ["source": "netflix", "ref": "1", "progress": 10],
            ]
            for body in bad {
                let reply = try await scrobble(env, "start", body, token: token)
                #expect(reply.status == .unprocessableContent, "\(body)")
                #expect(try reply.json()["code"] as? String == "validation_failed")
            }
        }
    }
}
