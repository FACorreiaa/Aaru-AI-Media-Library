import AaruCore
import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
@testable import aaru

/// `GET /v1/me/export`: the whole account as JSON, and a CSV Aaru's own importer reads back.
@Suite("Account export", .serialized)
struct ExportTests {
    struct Download {
        var status: HTTPResponse.Status
        var body: String
        var disposition: String?
    }

    func raw(_ env: LibraryHarness, _ format: String) async throws -> Download {
        try await env.client.execute(
            uri: "/v1/me/export?format=\(format)", method: .get, headers: [.authorization: "Bearer \(env.token)"]
        ) { Download(status: $0.status, body: String(buffer: $0.body), disposition: $0.headers[.contentDisposition]) }
    }

    @Test("JSON carries the account, every item with ratings, notes and watched episodes, and lists")
    func json() async throws {
        try await LibraryHarness.run { env in
            let show = try await env.add("show", tmdb: env.stubShow("Andor", status: .returning), status: "in_progress")
            _ = try await env.send(.put, "/v1/library/items/\(show)/episodes/1/2", json: ["watched": true])
            _ = try await env.send(.put, "/v1/library/items/\(show)/episodes/1/1", json: ["watched": true])
            let tmdb = env.stubMovie("Arrival")
            let movie = try await env.add("movie", tmdb: tmdb, status: "finished")
            _ = try await env.send(
                .patch,
                "/v1/library/items/\(movie)",
                json: ["rating": 9, "notes": "Again, \"slowly\""]
            )
            let list = try await env.send(.post, "/v1/lists", json: ["name": "Sci-fi"]).json()
            let listID = try #require(list["id"] as? String)
            _ = try await env.send(
                .post, "/v1/lists/\(listID)/items", json: ["mediaRef": ["type": "movie", "ids": ["tmdb": tmdb]]]
            )

            let download = try await raw(env, "json")
            #expect(download.status == .ok)
            #expect(download.disposition?.contains("aaru-export-") == true)
            let export = try #require(
                try JSONSerialization.jsonObject(with: Data(download.body.utf8)) as? [String: Any]
            )
            #expect((export["account"] as? [String: Any])?["userId"] as? String == env.userID.description)
            let library = try #require(export["library"] as? [[String: Any]])
            #expect(library.count == 2)
            let andor = try #require(library.first { $0["id"] as? String == show })
            #expect((andor["watchedEpisodes"] as? [[String: Any]])?.compactMap { $0["number"] as? Int } == [1, 2])
            let arrival = try #require(library.first { $0["id"] as? String == movie })
            #expect(arrival["rating"] as? Double == 9 && arrival["notes"] as? String == "Again, \"slowly\"")
            let lists = try #require(export["lists"] as? [[String: Any]])
            #expect(lists.first?["name"] as? String == "Sci-fi")
            #expect((lists.first?["items"] as? [[String: Any]])?.first?["title"] as? String == "Arrival")
        }
    }

    @Test("CSV re-imports through Aaru's own generic importer with the same ids, status and rating")
    func csvRoundTrip() async throws {
        try await LibraryHarness.run { env in
            let tmdb = env.stubMovie("Arrival")
            let movie = try await env.add("movie", tmdb: tmdb, status: "finished")
            _ = try await env.send(.patch, "/v1/library/items/\(movie)", json: ["rating": 8, "notes": "=SUM(A1)"])
            let download = try await raw(env, "csv")
            let body = download.body
            #expect(download.status == .ok && download.disposition?.contains(".csv") == true)
            #expect(try ImportFormatDetector.detect(body) == .genericCSV)
            let rows = try GenericCSVParser.parse(CSVTable(body))
            let row = try #require(rows.first)
            #expect(rows.count == 1 && row.title == "Arrival" && row.type == .movie)
            #expect(row.status == .finished && row.rating == 8)
            // Test stubs use text ids; real TMDB ids are numeric and re-import from this column.
            #expect(body.contains(",\(tmdb),"))
            #expect(body.contains("'=SUM(A1)"), "a formula-looking note is defused for spreadsheets")
        }
    }
}
