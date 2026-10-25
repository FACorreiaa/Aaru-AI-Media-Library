import AaruCore
import FluentSQL
import Foundation
import Hummingbird
import HummingbirdTesting
import Logging
import Testing
@testable import aaru

/// SCR-005 against a stubbed MyAnimeList. No network, no real client id.
@Suite("MyAnimeList", .serialized)
struct MALTests {
    static func form(_ body: Data?) -> [String: String] {
        let text = body.flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
        return Dictionary(text.split(separator: "&").map { pair in
            let parts = pair.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding ?? "" }
            return (parts[0], parts.count > 1 ? parts[1] : "")
        }, uniquingKeysWith: { _, last in last })
    }

    static let cipher: TokenCipher = {
        let key = Data((0 ..< 32).map { _ in UInt8.random(in: 0 ... 255) }).base64EncodedString()
        guard let cipher = try? TokenCipher(base64Key: key) else { preconditionFailure("32 random bytes") }
        return cipher
    }()

    func api(_ fake: FakeMAL, secret: String? = nil) -> MALAPI {
        MALAPI(
            client: ProviderClient(
                name: "mal", transport: fake.transport, pacer: RequestPacer(requestsPerSecond: 1000, burst: 100)
            ),
            settings: MALSettings(
                clientID: "test-client", clientSecret: secret,
                redirectURI: URL(string: "https://api.aaru.test/v1/connections/mal/callback")!,
                returnPrefixes: ["aaru://", "https://web.aaru.test/"],
                tokenCipher: Self.cipher
            )
        )
    }

    func pusher(_ env: LibraryHarness, _ fake: FakeMAL) -> MALPusher {
        let api = api(fake)
        return MALPusher(
            stores: env.stores, connect: MALConnectService(stores: env.stores, settings: api.settings, api: api),
            api: api, logger: Logger(label: "mal-tests")
        )
    }

    /// Runs connect and the callback; returns the callback's Location and the authorize URL.
    @discardableResult
    func connect(_ env: LibraryHarness, returnTo: String = "aaru://settings") async throws
        -> (location: String, authorize: URLComponents)
    {
        let start = try await env.send(.post, "/v1/connections/mal/connect", json: ["returnTo": returnTo]).json()
        let authorize = try #require(URLComponents(string: start["authorizeUrl"] as? String ?? ""))
        let state = try #require(authorize.queryItems?.first { $0.name == "state" }?.value)
        let location = try await env.client.execute(
            uri: "/v1/connections/mal/callback?code=abc&state=\(state)", method: .get
        ) { response in
            #expect(response.status == .found)
            return response.headers[.location] ?? ""
        }
        return (location, authorize)
    }

    /// A two-season anime (3 episodes each) whose seasons map to MAL entries `mal1` and `mal2`.
    func anime(_ env: LibraryHarness, seasons: [Int: [String]]) async throws -> (tmdb: String, item: String) {
        let tmdb = env.stubShow("Frieren", status: .ended)
        for (season, malIDs) in seasons {
            for mal in malIDs {
                try await env.stores.animeMappings.upsert(AnimeMapping(
                    anilist: uniqueID("al"), mal: mal, anidb: nil, tvdb: nil, tmdb: tmdb, tmdbSeason: season
                ))
            }
        }
        return try (tmdb, await env.add("show", tmdb: tmdb, status: "in_progress"))
    }

    func tick(_ env: LibraryHarness, _ item: String, _ season: Int, _ episode: Int) async throws {
        let reply = try await env.send(
            .put, "/v1/library/items/\(item)/episodes/\(season)/\(episode)", json: ["watched": true]
        )
        #expect(reply.status == .ok)
    }

    @Test("SCR-005: PKCE plain, the secret when configured, tokens sealed, a callback works once")
    func connectWithPlainPKCE() async throws {
        let fake = FakeMAL()
        try await LibraryHarness.run(mal: api(fake, secret: "shh")) { env in
            let (location, authorize) = try await connect(env)
            #expect(location == "aaru://settings?mal=connected")
            let query = Dictionary(uniqueKeysWithValues: (authorize.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            #expect(authorize.host == "myanimelist.net")
            #expect(query["code_challenge_method"] == "plain")

            let exchange = Self.form(fake.transport.requests.first { $0.url.path == "/v1/oauth2/token" }?.body)
            #expect(exchange["code_verifier"] == query["code_challenge"], "plain: the challenge is the verifier")
            #expect(exchange["client_secret"] == "shh")
            #expect(exchange["grant_type"] == "authorization_code")

            let stored = try await withSQL { sql in
                try await sql.raw("""
                SELECT access_token FROM mal_connections WHERE user_id = \(bind: env.userID.rawValue)
                """).first(decoding: [String: String].self)?["access_token"]
            }
            let sealed = try #require(stored)
            #expect(!sealed.contains("at-1"), "the token is never stored in clear")
            #expect(try Self.cipher.open(sealed) == "at-1")

            let status = try await env.send(.get, "/v1/connections/mal").json()
            #expect(status["connected"] as? Bool == true)
            #expect(status["username"] as? String == "ana")
            #expect(status["needsReconnect"] as? Bool == false)

            let state = query["state"] ?? ""
            try await env.client.execute(uri: "/v1/connections/mal/callback?code=abc&state=\(state)", method: .get) {
                #expect($0.status == .badRequest, "a replayed callback is refused")
            }
            let evil = try await env.send(
                .post,
                "/v1/connections/mal/connect",
                json: ["returnTo": "https://evil.test/"]
            )
            #expect(evil.status == .unprocessableContent, "the browser only returns to Aaru")

            #expect(try await env.send(.delete, "/v1/connections/mal").status == .noContent)
            #expect(try await env.send(.get, "/v1/connections/mal").json()["connected"] as? Bool == false)
        }
    }

    @Test("SCR-005: without a client id, connect answers 503")
    func unavailableWithoutClientID() async throws {
        try await LibraryHarness.run { env in
            let reply = try await env.send(.post, "/v1/connections/mal/connect", json: ["returnTo": "aaru://x"])
            #expect(reply.status == .serviceUnavailable)
        }
    }

    @Test("SCR-005: a show splits into one MAL entry per mapped season; the same state is never sent twice")
    func pushesPerSeason() async throws {
        let fake = FakeMAL()
        try await LibraryHarness.run(mal: api(fake)) { env in
            let (mal1, mal2) = (uniqueID("m"), uniqueID("m"))
            try await connect(env)
            let (_, item) = try await anime(env, seasons: [1: [mal1], 2: [mal2]])
            for episode in 1 ... 3 {
                try await tick(env, item, 1, episode)
            }
            try await tick(env, item, 2, 1)
            _ = try await env.send(.patch, "/v1/library/items/\(item)", json: ["rating": 7.5])

            #expect(try await pusher(env, fake).runOnce() == 2)
            let sent = Dictionary(fake.patches.map { ($0.malID, $0.fields) }, uniquingKeysWith: { _, last in last })
            #expect(sent[mal1] == ["status": "completed", "num_watched_episodes": "3", "score": "8"])
            #expect(sent[mal2] == ["status": "watching", "num_watched_episodes": "1", "score": "8"])

            #expect(try await pusher(env, fake).runOnce() == 0, "nothing changed: nothing sent")
            try await tick(env, item, 2, 2)
            #expect(try await pusher(env, fake).runOnce() == 1, "only the season that moved")
            #expect(fake.patches.last?.malID == mal2)
            #expect(fake.patches.last?.fields["num_watched_episodes"] == "2")
        }
    }

    @Test("SCR-005: a show finished before its new season aired sends that season as watching")
    func airingSeasonOfFinishedShow() async throws {
        let fake = FakeMAL()
        try await LibraryHarness.run(mal: api(fake)) { env in
            let (mal1, mal2) = (uniqueID("m"), uniqueID("m"))
            try await connect(env)
            let tmdb = env.stubShow("Aoashi", status: .ended)
            for (season, mal) in [(1, mal1), (2, mal2)] {
                try await env.stores.animeMappings.upsert(AnimeMapping(
                    anilist: uniqueID("al"), mal: mal, anidb: nil, tvdb: nil, tmdb: tmdb, tmdbSeason: season
                ))
            }
            let item = try await env.add("show", tmdb: tmdb, status: "finished")
            try await pusher(env, fake).runOnce()
            #expect(fake.patches.count { $0.fields["status"] == "completed" } == 2)

            // Season 2 grows an episode still to air; the show stays finished in Aaru.
            let title = try #require(try await env.stores.titles.find(ids: ExternalIDs(tmdb: tmdb), type: .show))
            let next = CatalogEpisode(
                season: 2, episode: 4, name: nil, airsAt: Date().addingTimeInterval(7 * 86400),
                runtimeMinutes: nil, tmdbEpisodeID: nil
            )
            try await env.stores.titles.saveEpisodes(
                title.id, CatalogEpisodes(status: .returning, episodes: [next]), hydratedAt: Date()
            )
            _ = try await env.send(.patch, "/v1/library/items/\(item)", json: ["rating": 8])
            try await pusher(env, fake).runOnce()
            let last = try #require(fake.patches.last { $0.malID == mal2 })
            #expect(last.fields["status"] == "watching", "season 2 is still airing: never completed")
            #expect(last.fields["num_watched_episodes"] == "3")
        }
    }

    @Test("SCR-005: connecting never pushes the library as it was; a split cour is skipped")
    func onlyLaterWritesAndNoSplitCours() async throws {
        let fake = FakeMAL()
        try await LibraryHarness.run(mal: api(fake)) { env in
            let (mal1, partA, partB) = (uniqueID("m"), uniqueID("m"), uniqueID("m"))
            let (_, item) = try await anime(env, seasons: [1: [mal1], 2: [partA, partB]])
            try await tick(env, item, 1, 1)
            try await connect(env)
            #expect(try await pusher(env, fake).runOnce() == 0, "written before connecting: not pushed")

            try await tick(env, item, 2, 1)
            try await pusher(env, fake).runOnce()
            #expect(Set(fake.patches.map(\.malID)) == [mal1], "season 2 has two MAL entries: Aaru cannot split it")
        }
    }

    @Test("SCR-005: an entry on hold on MAL stays on hold until Aaru's ticks move")
    func keepsOnHold() async throws {
        let fake = FakeMAL()
        try await LibraryHarness.run(mal: api(fake)) { env in
            let mal1 = uniqueID("m")
            try await connect(env)
            let (_, item) = try await anime(env, seasons: [1: [mal1]])
            try await env.stores.mal.saveEntryState(
                MALEntryState(malID: mal1, status: .onHold, episodes: 0, score: 0), title: nil, userID: env.userID
            )
            _ = try await env.send(.patch, "/v1/library/items/\(item)", json: ["rating": 6])
            try await pusher(env, fake).runOnce()
            #expect(fake.patches.last?.fields["status"] == "on_hold")
            #expect(fake.patches.last?.fields["score"] == "6")

            try await tick(env, item, 1, 1)
            try await pusher(env, fake).runOnce()
            #expect(fake.patches.last?.fields["status"] == "watching")
        }
    }

    @Test("SCR-005: MAL refusing the token marks the connection for reconnecting and stops pushing")
    func revokedToken() async throws {
        let fake = FakeMAL()
        try await LibraryHarness.run(mal: api(fake)) { env in
            let mal1 = uniqueID("m")
            try await connect(env)
            let (_, item) = try await anime(env, seasons: [1: [mal1]])
            fake.failPatches(401)
            try await tick(env, item, 1, 1)
            #expect(try await pusher(env, fake).runOnce() == 0)
            let status = try await env.send(.get, "/v1/connections/mal").json()
            #expect(status["needsReconnect"] as? Bool == true)

            let before = fake.patches.count
            try await tick(env, item, 1, 2)
            try await pusher(env, fake).runOnce()
            #expect(fake.patches.count == before, "a revoked connection sends nothing")

            fake.failPatches(200)
            try await connect(env)
            #expect(try await env.send(.get, "/v1/connections/mal").json()["needsReconnect"] as? Bool == false)
            try await pusher(env, fake).runOnce()
            #expect(fake.patches.last?.fields["num_watched_episodes"] == "2", "writes made while revoked go out")
        }
    }

    @Test("SCR-005: target and state rules")
    func rules() {
        let show = Title(type: .show, title: "X", ids: ExternalIDs(mal: "9"))
        #expect(MALPusher.targets(show, tmdbMappings: [], anilistMapping: nil) == [.init(malID: "9", season: nil)])
        let movie = Title(type: .movie, title: "X", ids: ExternalIDs(mal: "9"))
        #expect(MALPusher.targets(movie, tmdbMappings: [], anilistMapping: nil).isEmpty)

        func state(
            _ status: LibraryStatus, ticks: Int, total: Int? = 12, first: Bool = true, airing: Bool = false
        ) -> MALEntryState? {
            let item = LibraryItem(userID: UserID(), titleID: TitleID(), status: status)
            return MALPusher.state(
                malID: "1", item: item,
                share: .init(ticks: ticks, total: total, isFirst: first, isAiring: airing), known: nil
            )
        }
        #expect(state(.finished, ticks: 0)?.episodes == 12, "finished counts every episode")
        let airing = state(.finished, ticks: 1, total: 24, first: false, airing: true)
        #expect(airing?.status == .watching, "a season still airing is never completed")
        #expect(airing?.episodes == 1)
        #expect(state(.finished, ticks: 0, first: false, airing: true) == nil, "an unstarted new season stays off MAL")
        #expect(state(.wishlist, ticks: 0)?.status == .planToWatch)
        #expect(state(.wishlist, ticks: 0, first: false) == nil, "a plan does not add every season")
        #expect(state(.inProgress, ticks: 0, first: false) == nil, "an unstarted later season stays off MAL")
        #expect(state(.inProgress, ticks: 12)?.status == .completed)
        #expect(state(.dropped, ticks: 3)?.status == .dropped)
    }
}
