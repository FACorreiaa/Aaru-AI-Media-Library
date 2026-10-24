import AaruCore
import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
@testable import aaru

/// AG-006 · capture as an import source: links by id, text and images through the model, the
/// monthly quota, and nothing written before the plan is approved.
@Suite("Capture", .serialized)
struct CaptureTests {
    let imports = ImportFlowTests()

    // MARK: Links

    @Test("AG-006: catalog links name their title by id; export sites point at their CSV")
    func links() throws {
        func parse(_ raw: String) throws -> CaptureLink {
            try CaptureLink.parse(#require(URL(string: raw)))
        }
        guard case let .title(movie) = try parse("https://www.themoviedb.org/movie/603-the-matrix") else {
            Issue.record("TMDB movie")
            return
        }
        #expect(movie.type == .movie)
        #expect(movie.ids.tmdb == "603")
        #expect(movie.status == .wishlist)
        guard case let .title(show) = try parse("https://www.themoviedb.org/tv/1396?language=en") else {
            Issue.record("TMDB show")
            return
        }
        #expect(show.type == .show && show.ids.tmdb == "1396")
        guard case let .title(anime) = try parse("https://anilist.co/anime/21/One-Piece/") else {
            Issue.record("AniList")
            return
        }
        #expect(anime.type == .show && anime.ids.anilist == "21")
        guard case let .title(book) = try parse("https://openlibrary.org/works/OL45804W/Fantastic_Mr_Fox") else {
            Issue.record("Open Library")
            return
        }
        #expect(book.type == .book && book.ids.openLibrary == "OL45804W")
        guard case let .title(manga) = try parse("https://anilist.co/manga/30013/One-Piece") else {
            Issue.record("an AniList manga link is a manga")
            return
        }
        #expect(manga.type == .manga && manga.ids.anilist == "30013")

        #expect(try parse("https://letterboxd.com/someone/list/films/") == .useCSV(site: "Letterboxd"))
        #expect(try parse("https://boxd.it/abc") == .useCSV(site: "Letterboxd"))
        #expect(try parse("https://m.imdb.com/title/tt0133093/") == .useCSV(site: "IMDb"))
        for other in [
            "https://www.themoviedb.org/person/6384",
            "https://openlibrary.org/authors/OL34184A", "https://example.com/movie/603", "ftp://themoviedb.org/movie/1",
        ] {
            #expect(try parse(other) == .unsupported, "\(other)")
        }
    }

    // MARK: What the model reports

    @Test("AG-006: reported titles become wishlist rows, deduplicated, anime as shows")
    func reportedRows() {
        let rows = CaptureExtractor.rows(.object(["titles": .array([
            .object(["title": .string(" Arrival "), "year": .number(2016), "type": .string("movie")]),
            .object(["title": .string("arrival"), "year": .number(2016), "type": .string("movie")]),
            .object(["title": .string("Frieren"), "type": .string("anime")]),
            .object(["title": .string("Dune"), "type": .string("book"), "year": .number(12)]),
            .object(["title": .string(""), "type": .string("movie")]),
            .object(["type": .string("movie")]),
        ])]))
        #expect(rows.map(\.title) == ["Arrival", "Frieren", "Dune"])
        #expect(rows.map(\.type) == [.movie, .show, .book])
        #expect(rows.map(\.year) == [2016, nil, nil])
        #expect(rows.allSatisfy { $0.status == .wishlist && $0.ids.isEmpty })

        let many = CaptureExtractor.rows(.object(["titles": .array((0 ..< 80).map {
            .object(["title": .string("Film \($0)"), "type": .string("movie")])
        })]))
        #expect(many.count == CaptureExtractor.maxTitles)
        #expect(CaptureExtractor.rows(.object([:])).isEmpty)
    }

    @Test("AG-006: a forced tool goes out as tool_choice; costs are counted in millionths of a dollar")
    func toolChoiceAndCost() {
        let request = ModelRequest(
            system: "s", turns: [.user("x")], tools: [CaptureExtractor.tool], maxTokens: 10,
            toolChoice: CaptureExtractor.toolName
        )
        let body = AnthropicMessagesProvider.body(request, model: "claude-haiku-5-5", effort: "low")
        #expect(body["tool_choice"] == .object(["type": .string("tool"), "name": .string("report_titles")]))
        var plain = request
        plain.toolChoice = nil
        #expect(AnthropicMessagesProvider.body(plain, model: "m", effort: nil)["tool_choice"] == nil)

        let pricing = ModelPricing(inputPerMTok: 0.10, outputPerMTok: 0.50)
        let response = ModelResponse(content: [], stop: .done, inputTokens: 1500, outputTokens: 101)
        // 150 + 50.5, rounded up.
        #expect(pricing.micros(response) == 201)
        #expect(ModelPricing.free.micros(response) == 0)
    }

    // MARK: End to end

    /// A film the fake catalog finds by name, and by a numeric TMDB id as a link carries.
    func stubFilm(_ env: LibraryHarness, _ name: String) -> String {
        let tmdb = String(Int.random(in: 10_000_000 ... 99_999_999))
        let hit = CatalogHit(
            type: .movie, title: name, originalTitle: nil, year: 2001, posterURL: nil, overview: nil, byline: nil,
            ids: ExternalIDs(tmdb: tmdb), isAnime: false
        )
        env.fake.stubTitle(CatalogTitle(hit: hit, status: nil, runtimeMinutes: 100))
        env.fake.stubSearch(name, [hit])
        return tmdb
    }

    func capture(_ env: LibraryHarness, json: [String: Any]) async throws -> LibraryHarness.Reply {
        try await env.send(.post, "/v1/imports/capture", json: json)
    }

    func report(_ titles: [(String, Int?)]) -> ModelResponse {
        ScriptedModel.tool(CaptureExtractor.toolName, ["titles": .array(titles.map { title, year in
            var item: [String: ModelJSON] = ["title": .string(title), "type": .string("movie")]
            if let year {
                item["year"] = .number(Double(year))
            }
            return .object(item)
        })])
    }

    @Test("AG-006: pasted titles plan as one import, write nothing, then apply as one undoable action")
    func pastedText() async throws {
        let name = uniqueID("Heat")
        let model = ScriptedModel([.success(report([(name, 2001), (uniqueID("Nobody Made This"), nil)]))])
        try await LibraryHarness.run(model: model) { env in
            _ = stubFilm(env, name)
            let created = try await capture(env, json: ["text": "\(name) (2001)\nsomething else"])
            #expect(created.status == .accepted)
            let id = try #require(created.json()["id"] as? String)
            #expect(try created.json()["source"] as? String == "capture")
            let jobID = try #require(ImportJobID(uuidString: id))
            #expect(try await env.stores.capture.input(jobID: jobID) != nil)

            let planned = try await imports.plan(env, id, service: env.services.imports)
            let job = try #require(planned["job"] as? [String: Any])
            #expect(job["state"] as? String == "planned")
            let rows = try #require(planned["rows"] as? [[String: Any]])
            #expect(rows.map { $0["outcome"] as? String } == ["create", "unmatched"])
            // Read once, then gone; the model was told it is data, and forced to report.
            #expect(try await env.stores.capture.input(jobID: jobID) == nil)
            let sent = try #require(await model.requests.first)
            #expect(sent.toolChoice == "report_titles")
            #expect(await model.everythingSeen.contains(name))
            // Metered: one request, with its cost.
            let usage = try await env.stores.agent.usage(env.userID, day: Date())
            #expect(usage.requests >= 1)
            // Nothing in the library until the plan is approved.
            let before = try await env.send(.get, "/v1/library/items").json()
            #expect((before["items"] as? [Any])?.isEmpty == true)

            let applied = try await env.send(.post, "/v1/imports/\(id)/apply").json()
            let actionID = try #require(applied["actionId"] as? String)
            let after = try await env.send(.get, "/v1/library/items").json()
            let items = try #require(after["items"] as? [[String: Any]])
            #expect(items.count == 1)
            #expect(items.first?["status"] as? String == "wishlist")
            #expect(try await env.send(.post, "/v1/actions/\(actionID)/undo").status == .ok)
        }
    }

    @Test("AG-006: an image goes to the model as one base64 block with its type")
    func image() async throws {
        let model = ScriptedModel([.success(report([(uniqueID("Poster"), nil)]))])
        try await LibraryHarness.run(model: model) { env in
            let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])
            let created = try await env.client.execute(
                uri: "/v1/imports/capture", method: .post,
                headers: [.authorization: "Bearer \(env.token)", .contentType: "image/png"],
                body: ByteBuffer(bytes: png)
            ) { LibraryHarness.Reply(status: $0.status, body: Data(buffer: $0.body)) }
            #expect(created.status == .accepted)
            let id = try #require(created.json()["id"] as? String)
            _ = try await imports.plan(env, id, service: env.services.imports)
            let sent = try #require(await model.requests.first)
            let block = try #require(sent.turns.first?.content.first)
            #expect(block["type"]?.string == "image")
            #expect(block["source"]?["media_type"]?.string == "image/png")
            #expect(block["source"]?["data"]?.string == png.base64EncodedString())
        }
    }

    @Test("AG-006: the model finding nothing, or declining, fails the job with a reason and keeps nothing")
    func nothingFound() async throws {
        let model = ScriptedModel([.success(report([]))])
        try await LibraryHarness.run(model: model) { env in
            let created = try await capture(env, json: ["text": "just a shopping list"])
            let id = try #require(created.json()["id"] as? String)
            let planned = try await imports.plan(env, id, service: env.services.imports)
            let job = try #require(planned["job"] as? [String: Any])
            #expect(job["state"] as? String == "failed")
            #expect((job["errorSummary"] as? String)?.contains("no film") == true)
            #expect(try await env.stores.capture.input(jobID: #require(ImportJobID(uuidString: id))) == nil)
        }
    }

    @Test("AG-006: links plan without the model; export sites and other links are refused")
    func linkCaptures() async throws {
        try await LibraryHarness.run { env in
            let tmdb = stubFilm(env, uniqueID("Linked"))
            let created = try await capture(env, json: ["url": "https://www.themoviedb.org/movie/\(tmdb)-linked"])
            #expect(created.status == .accepted)
            let id = try #require(created.json()["id"] as? String)
            let planned = try await imports.plan(env, id, service: env.services.imports)
            let rows = try #require(planned["rows"] as? [[String: Any]])
            #expect(rows.map { $0["outcome"] as? String } == ["create"])

            let letterboxd = try await capture(env, json: ["url": "https://letterboxd.com/me/watchlist/"])
            #expect(letterboxd.status == .unprocessableContent)
            #expect(try letterboxd.json()["code"] as? String == "capture_use_csv")
            let other = try await capture(env, json: ["url": "https://example.com/film"])
            #expect(try other.json()["code"] as? String == "capture_unsupported_url")
            // No model here: text cannot be read, and says so.
            let text = try await capture(env, json: ["text": "Heat"])
            #expect(text.status == .serviceUnavailable)
            #expect(try text.json()["code"] as? String == "capture_unavailable")
            let both = try await capture(env, json: ["text": "Heat", "url": "https://example.com"])
            #expect(both.status == .unprocessableContent)
        }
    }

    @Test("AG-006: a free account gets three captures a month; the fourth is a 402")
    func quota() async throws {
        try await LibraryHarness.run { env in
            let tmdb = stubFilm(env, uniqueID("Quota"))
            for _ in 0 ..< ImportService.freeCapturesPerMonth {
                let created = try await capture(env, json: ["url": "https://www.themoviedb.org/movie/\(tmdb)"])
                #expect(created.status == .accepted)
            }
            let refused = try await capture(env, json: ["url": "https://www.themoviedb.org/movie/\(tmdb)"])
            #expect(refused.status.code == 402)
            #expect(try refused.json()["code"] as? String == "capture_quota")
        }
    }

    @Test("AG-006: the sweep deletes inputs left an hour")
    func sweep() async throws {
        try await withMigratedStores { stores in
            let (userID, _) = try await signedInUser(stores)
            let jobID = ImportJobID()
            let old = Date().addingTimeInterval(-2 * 60 * 60)
            try await stores.capture.saveInput(CaptureInput(
                jobID: jobID, userID: userID, content: .text("Heat"), createdAt: old
            ))
            let fresh = ImportJobID()
            try await stores.capture.saveInput(CaptureInput(
                jobID: fresh, userID: userID, content: .image(Data([1, 2]), mediaType: "image/jpeg"), createdAt: Date()
            ))
            #expect(try await stores.capture.sweep(before: Date().addingTimeInterval(-60 * 60)) >= 1)
            #expect(try await stores.capture.input(jobID: jobID) == nil)
            let kept = try await stores.capture.input(jobID: fresh)
            #expect(kept?.content == .image(Data([1, 2]), mediaType: "image/jpeg"))
        }
    }

    @Test("AG-006: capture month boundaries are UTC")
    func month() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-10-31T23:30:00-02:00"))
        let month = ImportService.monthStart(date)
        #expect(month.start == ISO8601DateFormatter().date(from: "2026-11-01T00:00:00Z"))
        #expect(month.next == ISO8601DateFormatter().date(from: "2026-12-01T00:00:00Z"))
    }
}
