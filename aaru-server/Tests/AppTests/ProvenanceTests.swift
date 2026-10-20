import AaruCore
import Foundation
import Testing
@testable import aaru

@Suite("Action provenance for agent tokens (OUT-002, minimal)", .serialized)
struct ProvenanceTests {
    func library(_ env: LibraryHarness) -> LibraryService {
        let catalogs = FakeCatalog.providers(env.fake)
        return LibraryService(
            stores: env.stores,
            resolver: TitleResolver(stores: env.stores, catalogs: catalogs),
            catalog: CatalogService(stores: env.stores, catalogs: catalogs)
        )
    }

    @Test("An agent's write is one external_agent row naming the token, kept after revoke, undoable")
    func agentWrite() async throws {
        try await LibraryHarness.run { env in
            let itemID = try await env.add("show", tmdb: env.stubShow("Severance", status: .ended))
            let item = try LibraryItemID(#require(UUID(uuidString: itemID)))
            let tokens = AgentTokenService(stores: env.stores, publicBaseURL: URL(string: "https://api.aaruapp.com")!)
            let minted = try await tokens.create(
                userID: env.userID, kind: .stremio, name: nil, allowLibraryWrites: false
            )
            let caller = Caller.agent(minted.token)
            let keys = try [
                EpisodeKey(season: 1, episode: 1),
                EpisodeKey(season: 1, episode: 2),
                EpisodeKey(season: 9, episode: 9),
            ]
            let before = try await env.actionCount()

            let entry = try await library(env).setEpisodes(
                item,
                userID: env.userID,
                keys: keys,
                watched: true,
                by: caller
            )
            #expect(entry?.item.status == .inProgress)
            #expect(try await env.actionCount() == before + 1, "one action for the batch; unknown episodes skipped")
            #expect(try await library(env).setEpisodes(
                item, userID: env.userID, keys: keys, watched: true, by: caller
            ) == nil, "already watched: no write")
            #expect(try await env.actionCount() == before + 1)

            try await tokens.revoke(id: minted.token.id, userID: env.userID)
            let actions = try #require(try await env.send(.get, "/v1/actions?limit=1").json()["items"]
                as? [[String: Any]])
            let latest = try #require(actions.first)
            #expect(latest["actor"] as? String == "external_agent")
            #expect(latest["agentName"] as? String == "Stremio")
            #expect(latest["summary"] as? String == "Stremio: marked 2 episodes of Severance watched")

            let id = try #require(latest["id"] as? String)
            #expect(try await env.send(.post, "/v1/actions/\(id)/undo").status == .ok)
            #expect(try await env.stores.library.watched(itemID: item).isEmpty)
        }
    }
}
