import AaruCore
import Foundation
import Testing
@testable import aaru

/// MUS-008: listening on Insights and the Recap, through `/v1/me/stats` and the top lists.
@Suite("Listening stats (MUS-008)", .serialized)
struct ListenStatsTests {
    private func listen(
        _ artist: String, _ track: String, daysAgo: Double, album: String? = nil, cover: String? = nil
    ) -> NewListen {
        NewListen(
            listenedAt: Date().addingTimeInterval(-daysAgo * 86400 - 3600), artist: artist, track: track,
            album: album, durationMs: 240_000, releaseGroupMBID: cover
        )
    }

    @Test("Stats carry the period's listening apart from the library's numbers, with the top artist's tracks")
    func statsMusic() async throws {
        try await LibraryHarness.run { env in
            let empty = try await env.send(.get, "/v1/me/stats?span=last7").json()
            #expect(empty["music"] == nil, "nothing heard: no music block")

            _ = try await env.stores.listens.insert([
                listen("Radiohead", "Airbag", daysAgo: 1, album: "OK Computer", cover: "rg-ok"),
                listen("Radiohead", "Airbag", daysAgo: 2),
                listen("Radiohead", "Reckoner", daysAgo: 2),
                listen("Radiohead", "Reckoner", daysAgo: 3),
                listen("radiohead", "Weird Fishes", daysAgo: 4),
                listen("Radiohead", "Nude", daysAgo: 1),
                listen("Portishead", "Roads", daysAgo: 1),
                listen("Portishead", "Roads", daysAgo: 10),
            ], userID: env.userID, agentTokenID: nil)

            let stats = try await env.send(.get, "/v1/me/stats?span=last7").json()
            let music = try #require(stats["music"] as? [String: Any])
            #expect(music["listens"] as? Int == 7)
            #expect(music["minutes"] as? Int == 28)
            #expect(music["priorListens"] as? Int == 1)
            #expect(music["priorMinutes"] as? Int == 4)
            let top = try #require(music["topArtist"] as? [String: Any])
            #expect(top["artist"] as? String == "Radiohead")
            #expect(top["count"] as? Int == 6)
            #expect(top["coverUrl"] as? String == "https://coverartarchive.org/release-group/rg-ok/front-250")
            let tracks = try #require(music["topArtistTracks"] as? [[String: Any]])
            #expect(tracks.compactMap { $0["track"] as? String }.prefix(2) == ["Airbag", "Reckoner"])
            #expect(tracks.count == 3)
            #expect(!tracks.contains { $0["track"] as? String == "Roads" }, "only the top artist's tracks")
            #expect((stats["totals"] as? [String: Any])?["minutesWatched"] as? Int == 0, "listening is not watching")

            let year = try await env.send(.get, "/v1/me/stats?year=\(Calendar.current.component(.year, from: Date()))")
                .json()
            #expect((year["music"] as? [String: Any])?["priorListens"] == nil, "a calendar period has no prior window")
        }
    }

    @Test("Top lists carry covers, link tracks and albums to their album, and narrow to one artist")
    func topRows() async throws {
        try await LibraryHarness.run { env in
            _ = try await env.stores.listens.insert([
                listen("Massive Attack", "Teardrop", daysAgo: 1, album: "Mezzanine", cover: "rg-mez"),
                listen("Massive Attack", "Angel", daysAgo: 1, album: "Mezzanine"),
                listen("Burial", "Archangel", daysAgo: 1, album: "Untrue"),
            ], userID: env.userID, agentTokenID: nil)

            let artists = try #require(
                try await env.send(.get, "/v1/me/listens/top?by=artist&span=last7").json()["items"] as? [[String: Any]]
            )
            let massive = try #require(artists.first { $0["artist"] as? String == "Massive Attack" })
            #expect(massive["coverUrl"] as? String == "https://coverartarchive.org/release-group/rg-mez/front-250")
            #expect(massive["albumRef"] == nil)
            #expect(artists.first { $0["artist"] as? String == "Burial" }?["coverUrl"] == nil)

            let albums = try #require(
                try await env.send(.get, "/v1/me/listens/top?by=album&span=last7").json()["items"] as? [[String: Any]]
            )
            let mezzanine = try #require(albums.first { $0["album"] as? String == "Mezzanine" })
            let ref = try #require(mezzanine["albumRef"] as? [String: Any])
            #expect((ref["ids"] as? [String: Any])?["musicbrainz"] as? String == "rg-mez")
            #expect(ref["type"] as? String == "album")

            let narrowed = try #require(
                try await env.send(.get, "/v1/me/listens/top?by=track&span=last7&artist=massive%20%20ATTACK")
                    .json()["items"] as? [[String: Any]]
            )
            #expect(Set(narrowed.compactMap { $0["track"] as? String }) == ["Teardrop", "Angel"])
        }
    }
}
