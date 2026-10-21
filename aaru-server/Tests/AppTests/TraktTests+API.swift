import AaruCore
import FluentSQL
import Foundation
import Hummingbird
import Testing
@testable import aaru

/// IMP-002/003 against Trakt's 2026 API: paging, hosts and headers, the single-use refresh
/// token, account answers and revoke. Same stubbed Trakt as `TraktTests`.
extension TraktTests {
    @Test("IMP-003: every page is read (Trakt sends 10–100 without asking); shows ask for progress")
    func readsEveryPage() async throws {
        let fake = FakeTrakt()
        func movies(_ page: Int) -> String {
            let entries = (0 ..< 5).map { index in
                #"{"movie":{"title":"M\#(page)-\#(index)","year":2000,"ids":{"trakt":\#(page * 10 + index)}}}"#
            }
            return "[" + entries.joined(separator: ",") + "]"
        }
        fake.route("sync/watched/movies", pages: [movies(1), movies(2), movies(3)])
        let severance = #"{"title":"Severance","year":2022,"ids":{"trakt":900}}"#
        let seasons = #"[{"number":1,"episodes":[{"number":1}]}]"#
        fake.route("sync/watched/shows", pages: [#"[{"show":\#(severance),"seasons":\#(seasons)}]"#])
        for path in ["sync/watchlist/movies", "sync/watchlist/shows", "sync/ratings/movies", "sync/ratings/shows"] {
            fake.route(path, pages: ["[]"])
        }
        fake.route("users/me/lists", #"[{"name":"Faves","ids":{"trakt":77}}]"#) // not paged: no header
        fake.route("users/me/lists/77/items", pages: ["[]"])

        let rows = try await TraktImporter(api: api(fake)).rows(token: "at-1")
        #expect(rows.count(where: { $0.type == .movie }) == 15, "all three pages")
        #expect(fake.requests(to: "sync/watched/movies").count == 3)
        #expect(fake.requests(to: "users/me/lists").count == 1, "an endpoint without paging is read once")
        let shows = try #require(fake.requests(to: "sync/watched/shows").first)
        #expect(FakeTrakt.query(shows, "extended") == "progress")
        #expect(FakeTrakt.query(shows, "limit") == "250")
        #expect(rows.first { $0.type == .show }?.watched?.count == 1, "progress carries the episodes")
    }

    @Test("IMP-002: every call names Aaru; OAuth goes to auth.trakt.tv and data to api.trakt.tv")
    func hostsAndHeaders() async throws {
        let fake = FakeTrakt()
        try await LibraryHarness.run(trakt: api(fake)) { env in
            _ = try await connect(env, fake)
            stubLibrary(env, fake)
            let id = try #require(try await env.send(.post, "/v1/imports/trakt").json()["id"] as? String)
            _ = try await plan(env, fake, id: id)
            let all = fake.transport.requests
            #expect(all.count > 5)
            for request in all {
                let headers = Dictionary(request.headers, uniquingKeysWith: { first, _ in first })
                #expect(headers["User-Agent"] == TraktSettings.userAgent, "\(request.url)")
                #expect(headers["trakt-api-key"] == "test-client")
                let oauth = request.url.path.hasPrefix("/oauth/")
                #expect(request.url.host == (oauth ? "auth.trakt.tv" : "api.trakt.tv"), "\(request.url)")
            }
        }
    }

    /// Makes the stored token look expired, so the next use refreshes it.
    func expire(_ env: LibraryHarness) async throws {
        try await withSQL { sql in
            try await sql.raw("""
            UPDATE trakt_connections SET expires_at = now() - interval '1 day'
            WHERE user_id = \(bind: env.userID.rawValue)
            """).run()
        }
    }

    @Test("IMP-002: two callers needing a refresh at once spend the single-use refresh token once")
    func refreshesOnce() async throws {
        let fake = FakeTrakt()
        try await LibraryHarness.run(trakt: api(fake)) { env in
            _ = try await connect(env, fake)
            try await expire(env)
            fake.route("oauth/token", tokens("at-fresh", refresh: "rt-2"))
            let before = fake.requests(to: "oauth/token").count
            let service = TraktConnectService(stores: env.stores, settings: api(fake).settings, api: api(fake))
            async let first = service.accessToken(userID: env.userID)
            async let second = service.accessToken(userID: env.userID)
            #expect(try await [first, second] == ["at-fresh", "at-fresh"])
            #expect(fake.requests(to: "oauth/token").count - before == 1)
        }
    }

    @Test("IMP-003: a refresh Trakt refuses (invalid_grant) fails the import at once and disconnects")
    func refusedRefresh() async throws {
        let fake = FakeTrakt()
        try await LibraryHarness.run(trakt: api(fake)) { env in
            _ = try await connect(env, fake)
            try await expire(env)
            fake.route(
                "oauth/token",
                status: 400,
                #"{"error":"invalid_grant","error_description":"session not found"}"#
            )
            let id = try #require(try await env.send(.post, "/v1/imports/trakt").json()["id"] as? String)
            let job = try #require(try await plan(env, fake, id: id)["job"] as? [String: Any])
            #expect(job["state"] as? String == "failed")
            #expect((job["errorSummary"] as? String)?.contains("Connect Trakt again") == true)
            let status = try await env.send(.get, "/v1/imports/trakt/connection").json()
            #expect(status["connected"] as? Bool == false)
        }
    }

    @Test("IMP-003: Trakt's account limit (420) fails the import at once with a reason, still connected")
    func accountLimit() async throws {
        let fake = FakeTrakt()
        try await LibraryHarness.run(trakt: api(fake)) { env in
            _ = try await connect(env, fake)
            stubLibrary(env, fake)
            fake.route("sync/watched/movies", status: 420, "{}")
            let id = try #require(try await env.send(.post, "/v1/imports/trakt").json()["id"] as? String)
            let job = try #require(try await plan(env, fake, id: id)["job"] as? [String: Any])
            #expect(job["state"] as? String == "failed")
            #expect((job["errorSummary"] as? String)?.contains("Trakt's limits") == true)
            #expect(fake.requests(to: "sync/watched/movies").count == 1, "not retried")
            let status = try await env.send(.get, "/v1/imports/trakt/connection").json()
            #expect(status["connected"] as? Bool == true)
        }
    }

    @Test("IMP-002: disconnecting revokes the token on Trakt, and still disconnects when Trakt is down")
    func disconnectRevokes() async throws {
        let fake = FakeTrakt()
        try await LibraryHarness.run(trakt: api(fake)) { env in
            _ = try await connect(env, fake)
            fake.route("oauth/revoke", "")
            #expect(try await env.send(.delete, "/v1/imports/trakt/connection").status.code < 300)
            let revoke = try #require(fake.requests(to: "oauth/revoke").first?.body)
            let sent = try #require(try JSONSerialization.jsonObject(with: revoke) as? [String: String])
            #expect(sent == ["token": "at-123", "client_id": "test-client"])
            #expect(try await env.send(.get, "/v1/imports/trakt/connection").json()["connected"] as? Bool == false)

            _ = try await connect(env, fake)
            fake.route("oauth/revoke", status: 503, "")
            #expect(try await env.send(.delete, "/v1/imports/trakt/connection").status.code < 300)
            #expect(try await env.send(.get, "/v1/imports/trakt/connection").json()["connected"] as? Bool == false)
        }
    }
}

extension TraktTests.FakeTrakt {
    static func query(_ request: OutboundRequest, _ name: String) -> String? {
        URLComponents(url: request.url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == name }?.value
    }
}

extension UntouchedStore {
    func refreshConnection(
        userID _: UserID,
        _: @escaping @Sendable (TraktConnectionRecord) async throws -> TraktConnectionRecord
    ) async throws -> TraktConnectionRecord? {
        throw Touched()
    }
}
