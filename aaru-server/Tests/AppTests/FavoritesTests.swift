import AaruCore
import Foundation
import Testing
@testable import aaru

/// FAV-001: an ordered top 10 per kind, any catalog title, shown to friends who may see the library.
@Suite("Favorites (FAV-001)", .serialized)
struct FavoritesTests {
    let friendTests = FriendTests()

    func film(_ tmdb: String) -> [String: Any] {
        ["type": "movie", "ids": ["tmdb": tmdb]]
    }

    func names(_ value: Any?) -> [String] {
        (value as? [[String: Any]] ?? []).compactMap { $0["title"] as? String }
    }

    @Test("A kind is set, reordered and cleared in one call; any catalog title, not only the library")
    func setReorderClear() async throws {
        try await LibraryHarness.run { env in
            let (arrival, dune, heat) = (env.stubMovie("Arrival"), env.stubMovie("Dune"), env.stubMovie("Heat"))
            let empty = try await env.send(.get, "/v1/me/favorites").json()
            #expect(["film", "show", "anime", "manga", "book", "album"].allSatisfy { names(empty[$0]).isEmpty })

            let set = try await env.send(
                .put, "/v1/me/favorites/film", json: ["items": [film(arrival), film(dune), film(heat)]]
            )
            #expect(set.status == .ok)
            #expect(try names(set.json()["film"]) == ["Arrival", "Dune", "Heat"])
            let library = try await env.send(.get, "/v1/library/sync").json()
            #expect((library["items"] as? [Any])?.isEmpty == true, "a favorite is not a library write")

            let reordered = try await env.send(
                .put, "/v1/me/favorites/film", json: ["items": [film(heat), film(arrival)]]
            ).json()
            #expect(names(reordered["film"]) == ["Heat", "Arrival"])
            #expect(try await names(env.send(.get, "/v1/me/favorites").json()["film"]) == ["Heat", "Arrival"])

            let cleared = try await env.send(.put, "/v1/me/favorites/film", json: ["items": [Any]()]).json()
            #expect(names(cleared["film"]).isEmpty)
        }
    }

    @Test("More than 10, a title twice, or a title of another kind is a 422 and changes nothing")
    func validation() async throws {
        try await LibraryHarness.run { env in
            let arrival = env.stubMovie("Arrival")
            _ = try await env.send(.put, "/v1/me/favorites/film", json: ["items": [film(arrival)]])

            let eleven = (0 ..< 11).map { film(env.stubMovie("Film \($0)")) }
            let tooMany = try await env.send(.put, "/v1/me/favorites/film", json: ["items": eleven])
            #expect(tooMany.status == .unprocessableContent)
            #expect(try tooMany.json()["code"] as? String == "validation_failed")

            let ten = Array(eleven.prefix(10))
            #expect(try await env.send(.put, "/v1/me/favorites/film", json: ["items": ten]).status == .ok)
            _ = try await env.send(.put, "/v1/me/favorites/film", json: ["items": [film(arrival)]])

            let twice = try await env.send(
                .put,
                "/v1/me/favorites/film",
                json: ["items": [film(arrival), film(arrival)]]
            )
            #expect(twice.status == .unprocessableContent)

            let show = env.stubShow("Severance", status: .returning)
            let wrongKind = try await env.send(
                .put, "/v1/me/favorites/film", json: ["items": [["type": "show", "ids": ["tmdb": show]]]]
            )
            #expect(wrongKind.status == .unprocessableContent)
            #expect(try (wrongKind.json()["message"] as? String)?.contains("not a film") == true)
            #expect(try await names(env.send(.get, "/v1/me/favorites").json()["film"]) == ["Arrival"])

            let unknownKind = try await env.send(.put, "/v1/me/favorites/games", json: ["items": [Any]()])
            #expect(unknownKind.status.code >= 400 && unknownKind.status.code < 500)
        }
    }

    @Test("Anime is its own kind: an anime series or film counts, a show that is not anime does not")
    func animeKind() async throws {
        try await LibraryHarness.run { env in
            let anilist = uniqueID("al")
            env.fake.stubTitle(CatalogTitle(
                hit: CatalogHit(
                    type: .show, title: "Frieren", originalTitle: nil, year: 2023, posterURL: nil, overview: nil,
                    byline: nil, ids: ExternalIDs(anilist: anilist), isAnime: true
                ),
                status: .ended, runtimeMinutes: 24
            ))
            let frieren: [String: Any] = ["type": "show", "ids": ["anilist": anilist]]
            #expect(try await env.send(.put, "/v1/me/favorites/show", json: ["items": [frieren]]).status
                == .unprocessableContent)
            let saved = try await env.send(.put, "/v1/me/favorites/anime", json: ["items": [frieren]]).json()
            #expect(names(saved["anime"]) == ["Frieren"])
            #expect(names(saved["show"]).isEmpty)
        }
    }

    @Test("A friend sees your favorites only while you share your library; strangers never")
    func friendsSeeThem() async throws {
        try await LibraryHarness.run { env in
            let ana = try await friendTests.friends(env)
            let heat = env.stubMovie("Heat")
            _ = try await env.send(.put, "/v1/me/favorites/film", json: ["items": [film(heat)]], token: ana.token)

            let shown = try await env.send(.get, "/v1/social/friends/\(ana.id)/profile").json()
            #expect(names((shown["favorites"] as? [String: Any])?["film"]) == ["Heat"])

            _ = try await env.send(
                .put, "/v1/me/social-settings", json: ["shareLibraryWithFriends": false], token: ana.token
            )
            let hidden = try await env.send(.get, "/v1/social/friends/\(ana.id)/profile").json()
            #expect(hidden["favorites"] == nil)

            let kai = try await friendTests.social.friendlyUser(env)
            #expect(try await env.send(.get, "/v1/social/friends/\(ana.id)/profile", token: kai.token).status
                == .notFound)
        }
    }

    @Test("The account export carries favorites")
    func export() async throws {
        try await LibraryHarness.run { env in
            let dune = env.stubMovie("Dune")
            _ = try await env.send(.put, "/v1/me/favorites/film", json: ["items": [film(dune)]])
            let export = try await env.send(.get, "/v1/me/export").json()
            #expect(names((export["favorites"] as? [String: Any])?["film"]) == ["Dune"])
        }
    }
}
