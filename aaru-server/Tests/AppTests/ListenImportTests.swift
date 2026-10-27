import AaruCore
import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
@testable import aaru

/// MUS-004 end to end: a listening history is staged, counted, applied into the listening log,
/// counted on its own days in Insights, earns no points, and undoes in one step.
@Suite("Listening history imports (MUS-004)", .serialized)
struct ListenImportTests {
    /// The same play three ways: Spotify's end time, and a scrobbler's start time.
    static let started = Date().addingTimeInterval(-3 * 86400).rounded()
    static let ended = started.addingTimeInterval(240)

    struct Play {
        var track: String
        var ended: Date
        var played: Int

        init(_ track: String, _ ended: Date, _ played: Int) {
            self.track = track
            self.ended = ended
            self.played = played
        }
    }

    func spotifyFile(_ plays: [Play]) throws -> Data {
        try JSONSerialization.data(withJSONObject: plays.map { play in
            [
                "ts": ISO8601DateFormatter().string(from: play.ended), "ms_played": play.played,
                "master_metadata_track_name": play.track, "master_metadata_album_artist_name": "Radiohead",
                "master_metadata_album_album_name": "OK Computer", "spotify_track_uri": "spotify:track:x",
                "episode_name": NSNull(), "ip_addr": "203.0.113.9",
            ] as [String: Any]
        })
    }

    func upload(_ env: LibraryHarness, _ data: Data, source: String = "auto") async throws -> LibraryHarness.Reply {
        try await env.client.execute(
            uri: "/v1/imports/csv?source=\(source)&filename=Streaming_History_Audio_2024.json",
            method: .post,
            headers: [.authorization: "Bearer \(env.token)", .contentType: "application/octet-stream"],
            body: ByteBuffer(data: data)
        ) { LibraryHarness.Reply(status: $0.status, body: Data(buffer: $0.body)) }
    }

    func importer(_ env: LibraryHarness, history: [ImportSource: any ListenHistoryReading] = [:]) -> ImportService {
        var service = ImportService(
            stores: env.stores,
            resolver: TitleResolver(stores: env.stores, catalogs: FakeCatalog.providers(env.fake))
        )
        service.listenHistory = history
        return service
    }

    func plan(_ env: LibraryHarness, _ id: String, service: ImportService) async throws -> [String: Any] {
        for _ in 0 ..< 50 {
            let job = try await env.send(.get, "/v1/imports/\(id)").json()
            let state = (job["job"] as? [String: Any])?["state"] as? String
            if state != "queued", state != "running" {
                return job["job"] as? [String: Any] ?? [:]
            }
            guard try await service.runNext(for: env.userID) else { break }
        }
        return try await env.send(.get, "/v1/imports/\(id)").json()["job"] as? [String: Any] ?? [:]
    }

    func listens(_ env: LibraryHarness) async throws -> [[String: Any]] {
        try await env.send(.get, "/v1/me/listens?limit=100").json()["items"] as? [[String: Any]] ?? []
    }

    @Test("A Spotify file plans new and repeated plays, writes nothing until applied, counts in Insights, undoes")
    func spotifyPlanApplyUndo() async throws {
        try await LibraryHarness.run { env in
            // A scrobbler already sent the first play, live, at its start.
            _ = try await env.stores.listens.insert([
                NewListen(listenedAt: Self.started, artist: "Radiohead", track: "Airbag", durationMs: 284_000),
            ], userID: env.userID, agentTokenID: nil)
            let file = try spotifyFile([
                Play("Airbag", Self.ended, 240_000),
                Play("Paranoid Android", Self.ended.addingTimeInterval(400), 383_000),
                Play("Subterranean Homesick Alien", Self.ended.addingTimeInterval(800), 267_000),
                Play("Exit Music", Self.ended.addingTimeInterval(900), 9000),
            ])
            let created = try await upload(env, file)
            #expect(created.status == .accepted)
            let id = try #require(created.json()["id"] as? String)
            #expect(try created.json()["source"] as? String == "spotify_json")

            let job = try await plan(env, id, service: importer(env))
            #expect(job["state"] as? String == "planned")
            #expect(job["rowsTotal"] as? Int == 3)
            let stats = try #require(job["stats"] as? [String: Int])
            #expect(stats["created"] == 2, "two plays are new")
            #expect(stats["skipped"] == 1, "the live scrobble of the same play is not counted twice")
            #expect(stats["ignored"] == 1, "a 9 s play is not a listen")
            #expect(try await listens(env).count == 1, "nothing is written before approval")

            let applied = try await env.send(.post, "/v1/imports/\(id)/apply").json()
            #expect(applied["state"] as? String == "succeeded")
            #expect((applied["stats"] as? [String: Int])?["created"] == 2)
            #expect(applied["rowsTotal"] as? Int == 3, "the counts outlive the staging")
            #expect(applied["actionId"] == nil, "a listen is not a journaled library write")
            #expect(try await listens(env).count == 3)
            #expect(try await env.send(.post, "/v1/imports/\(id)/apply").status == .conflict, "applies once")

            let week = try await env.send(.get, "/v1/me/stats?span=last7").json()
            #expect((week["music"] as? [String: Any])?["listens"] as? Int == 3, "imported listens count on their day")
            #expect(try await env.stores.gamification.totalPoints(userID: env.userID) == 0, "no points for a backlog")
            let badges = try await env.stores.gamification.badges(userID: env.userID).map(\.badge)
            #expect(badges.contains("first_listen"), "music badges count imported listens")

            #expect(try await env.send(.post, "/v1/imports/\(id)/undo").status == .noContent)
            let left = try await listens(env)
            #expect(left.count == 1, "undo removes only what the import wrote")
            #expect(left.first?["track"] as? String == "Airbag")
            #expect(try await env.send(.get, "/v1/imports/\(id)").status == .notFound, "the import goes with it")
            let after = try await env.send(.get, "/v1/me/stats?span=last7").json()
            #expect((after["music"] as? [String: Any])?["listens"] as? Int == 1)
            #expect(
                try await env.stores.gamification.badges(userID: env.userID).contains { $0.badge == "first_listen" },
                "the live listen still holds its badge"
            )
        }
    }

    @Test("Undo is for applied listening imports only; a JSON body refuses a CSV source; a CSV refuses JSON")
    func refusals() async throws {
        try await LibraryHarness.run { env in
            let file = try spotifyFile([Play("Airbag", Self.ended, 240_000)])
            let id = try #require(try await upload(env, file, source: "spotify").json()["id"] as? String)
            let undo = try await env.send(.post, "/v1/imports/\(id)/undo")
            #expect(undo.status == .conflict)
            #expect(try undo.json()["code"] as? String == "import_not_applied")
            #expect(try await upload(env, file, source: "imdb").status == .unprocessableContent)
            let csv = try await env.client.execute(
                uri: "/v1/imports/csv?source=auto", method: .post,
                headers: [.authorization: "Bearer \(env.token)", .contentType: "text/csv"],
                body: ByteBuffer(data: file)
            ) { LibraryHarness.Reply(status: $0.status, body: Data(buffer: $0.body)) }
            #expect(csv.status == .unprocessableContent, "JSON sent as a CSV says how to send it")
            let empty = try await upload(env, spotifyFile([Play("Short", Self.ended, 1000)]))
            #expect(empty.status == .unprocessableContent, "a file with no music plays")
            let lastFM = try await env.send(.post, "/v1/imports/lastfm", json: ["username": "rj"])
            #expect(lastFM.status == .serviceUnavailable, "no Last.fm key, no Last.fm import")
            #expect(try lastFM.json()["code"] as? String == "lastfm_unavailable")
        }
    }

    @Test("A username import reads the account in the worker; the next one reads only what came after")
    func accountImport() async throws {
        try await LibraryHarness.run { env in
            let reader = StubHistory(pages: [
                [NewListen(listenedAt: Self.started.addingTimeInterval(600), artist: "Burial", track: "Archangel")],
                [NewListen(listenedAt: Self.started, artist: "Burial", track: "Near Dark")],
            ])
            let service = importer(env, history: [.listenBrainz: reader])
            let job = try await service.createListenAccountImport(
                userID: env.userID, source: .listenBrainz, username: " @someone "
            )
            #expect(job.filename == "someone")
            let planned = try await plan(env, job.id.description, service: service)
            #expect(planned["state"] as? String == "planned")
            #expect((planned["stats"] as? [String: Int])?["created"] == 2)
            #expect(await reader.sinceAsked == [nil])
            _ = try await env.send(.post, "/v1/imports/\(job.id.description)/apply")

            let again = try await service.createListenAccountImport(
                userID: env.userID, source: .listenBrainz, username: "SOMEONE"
            )
            let replanned = try await plan(env, again.id.description, service: service)
            #expect(await reader.sinceAsked.last == Self.started.addingTimeInterval(600), "from the newest one")
            #expect((replanned["stats"] as? [String: Int])?["created"] == 0, "the same plays are not new")
            #expect((replanned["stats"] as? [String: Int])?["skipped"] == 2)

            let unknown = importer(env, history: [.listenBrainz: StubHistory(pages: [], missing: true)])
            let missing = try await unknown.createListenAccountImport(
                userID: env.userID, source: .listenBrainz, username: "nobody"
            )
            let failed = try await plan(env, missing.id.description, service: unknown)
            #expect(failed["state"] as? String == "failed")
            #expect((failed["errorSummary"] as? String)?.contains("no user “nobody”") == true)
        }
    }

    @Test("Undo refuses a library import, which undoes from its action")
    func libraryImportUndo() async throws {
        try await LibraryHarness.run { env in
            let job = ImportJob(userID: env.userID, source: .imdbCSV, state: .succeeded)
            try await env.stores.importJobs.insert(job)
            let undo = try await env.send(.post, "/v1/imports/\(job.id.description)/undo")
            #expect(undo.status == .conflict)
            #expect(try undo.json()["code"] as? String == "import_not_listens")
        }
    }

    @Test("Applying 20,000 staged plays is one statement, well inside a request")
    func bigApply() async throws {
        try await LibraryHarness.run { env in
            let base = Date().addingTimeInterval(-400 * 86400)
            let plays = (0 ..< 20000).map { index in
                NewListen(
                    listenedAt: base.addingTimeInterval(Double(index) * 200), artist: "Artist \(index % 300)",
                    track: "Track \(index % 2000)", durationMs: 200_000
                )
            }
            let job = ImportJob(userID: env.userID, source: .spotifyJSON, filename: "big.json", rowsTotal: plays.count)
            try await env.stores.importJobs.insert(job)
            try await env.stores.listens.stage(plays, jobID: job.id, from: 0)
            let clock = ContinuousClock()
            let planned = try await plan(env, job.id.description, service: importer(env))
            #expect((planned["stats"] as? [String: Int])?["created"] == 20000)
            var applied = 0
            let took = try await clock.measure {
                applied = try await env.stores.listens.applyStaged(jobID: job.id, userID: env.userID)
            }
            #expect(applied == 20000)
            #expect(took < .seconds(15), "took \(took)")
        }
    }
}

/// A listening history that hands over fixed pages and remembers where it was asked to stop.
actor StubHistory: ListenHistoryReading {
    let pages: [[NewListen]]
    let missing: Bool
    var sinceAsked: [Date?] = []

    init(pages: [[NewListen]], missing: Bool = false) {
        self.pages = pages
        self.missing = missing
    }

    nonisolated func read(
        user _: String, since: Date?, now _: Date, page: (ListenHistoryPage) async throws -> Void
    ) async throws {
        await asked(since)
        if missing {
            throw ProviderError(provider: "listenbrainz", kind: .notFound)
        }
        for listens in pages {
            try await page(ListenHistoryPage(listens: listens))
        }
    }

    private func asked(_ since: Date?) {
        sinceAsked.append(since)
    }
}

private extension Date {
    /// Whole seconds, as the file and the database keep them.
    func rounded() -> Date {
        Date(timeIntervalSince1970: timeIntervalSince1970.rounded(.down))
    }
}
