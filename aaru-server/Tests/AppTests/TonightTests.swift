import AaruCore
import Foundation
import Testing
@testable import aaru

@Suite("Tonight ranking (AG-005)")
struct TonightRankingTests {
    static let day: TimeInterval = 86400
    let now = Date(timeIntervalSince1970: 1_792_000_000)
    let zone = TimeZone(identifier: "Europe/Lisbon") ?? .gmt

    var today: LocalDay {
        LocalDay(now, in: zone)
    }

    func show(_ name: String, remaining: Int = 8, finale: Bool = false) throws -> ContinueEntry {
        try ContinueEntry(
            libraryItemID: LibraryItemID(), title: Title(type: .show, title: name),
            next: EpisodeKey(season: 2, episode: 4), nextName: "Woe's Hollow", nextRuntimeMinutes: 52,
            remainingCount: remaining, remainingMinutes: remaining * 52, isFinale: finale
        )
    }

    func film(_ name: String, runtime: Int = 124) -> StartEntry {
        StartEntry(libraryItemID: LibraryItemID(), title: Title(type: .movie, title: name), runtimeMinutes: runtime)
    }

    func book(_ name: String, pages: Int?, at page: Int?, changed: TimeInterval) -> ReadingEntry {
        ReadingEntry(
            libraryItemID: LibraryItemID(), title: Title(type: .book, title: name, pageCount: pages),
            pageCount: pages, bookPage: page, bookPercent: nil, lastChange: now.addingTimeInterval(-changed)
        )
    }

    func rank(_ library: TonightService.Library, _ feedback: [TonightFeedback] = []) -> [TonightPick] {
        TonightService.rank(library, feedback: feedback, day: today, now: now, zone: zone)
    }

    @Test("momentum and nearness order shows; three picks at most, one per item")
    func momentum() throws {
        let stale = try show("Stale")
        let fresh = try show("Fresh")
        // Scores: Fresh 5, Ending 4.5, Stale and Extra 3 (a tie the id breaks).
        let ending = try show("Ending", remaining: 3)
        let extra = try show("Extra")
        var library = TonightService.Library(
            continuing: [stale, fresh, ending, extra],
            airing: [],
            starting: [],
            reading: []
        )
        library.dates = [
            stale.libraryItemID: ItemDates(addedAt: now, lastChange: now.addingTimeInterval(-30 * Self.day)),
            fresh.libraryItemID: ItemDates(addedAt: now, lastChange: now.addingTimeInterval(-1 * Self.day)),
            ending.libraryItemID: ItemDates(addedAt: now, lastChange: now.addingTimeInterval(-20 * Self.day)),
            extra.libraryItemID: ItemDates(addedAt: now, lastChange: now.addingTimeInterval(-40 * Self.day)),
        ]
        let picks = rank(library)
        #expect(picks.map(\.title.title).prefix(2) == ["Fresh", "Ending"])
        #expect(picks.count == 3)
        #expect(Set(picks.map(\.libraryItemID)).count == 3)
        #expect(picks[1].reason == "52 min · 3 left")
        #expect(picks[1].episode == (try? EpisodeKey(season: 2, episode: 4)))

        let finale = try rank(.init(
            continuing: [show("Finale", remaining: 1, finale: true)],
            airing: [],
            starting: [],
            reading: []
        ))
        #expect(finale.first?.reason == "52 min · Last one aired · Season finale")
    }

    @Test("not tonight hides an item for the local day only; not for me weighs against it")
    func feedback() throws {
        let first = try show("First")
        let second = try show("Second")
        var library = TonightService.Library(continuing: [first, second], airing: [], starting: [], reading: [])
        library.dates = [
            first.libraryItemID: ItemDates(addedAt: now, lastChange: now),
            // Scores 5 and 4: one rejection (-2) puts First below Second, with no tie.
            second.libraryItemID: ItemDates(addedAt: now, lastChange: now.addingTimeInterval(-5 * Self.day)),
        ]
        #expect(rank(library).first?.title.title == "First")

        let notTonight = TonightFeedback(
            libraryItemID: first.libraryItemID,
            verdict: .notTonight,
            day: today,
            createdAt: now
        )
        #expect(rank(library, [notTonight]).map(\.title.title) == ["Second"])

        let yesterday = TonightFeedback(
            libraryItemID: first.libraryItemID, verdict: .notTonight, day: today.adding(days: -1), createdAt: now
        )
        #expect(rank(library, [yesterday]).first?.title.title == "First")

        let rejected = TonightFeedback(
            libraryItemID: first.libraryItemID,
            verdict: .rejected,
            day: today,
            createdAt: now
        )
        #expect(rank(library, [rejected]).map(\.title.title) == ["Second", "First"])
    }

    @Test("books show pages left, near the end ranks up; films only from the wishlist, aged on the list")
    func booksAndFilms() {
        let near = book("Dune", pages: 600, at: 536, changed: 10 * Self.day)
        let unknown = book("Untracked", pages: nil, at: nil, changed: 10 * Self.day)
        let perfectDays = film("Perfect Days")
        let wishlistShow = StartEntry(
            libraryItemID: LibraryItemID(), title: Title(type: .show, title: "Not a film"), runtimeMinutes: 50
        )
        var library = TonightService.Library(
            continuing: [], airing: [], starting: [perfectDays, wishlistShow], reading: [near, unknown]
        )
        library.dates = [perfectDays.libraryItemID: ItemDates(
            addedAt: now.addingTimeInterval(-41 * Self.day),
            lastChange: now
        )]
        let picks = rank(library)
        #expect(picks.map(\.title.title) == ["Dune", "Perfect Days", "Untracked"])
        #expect(picks[0].reason == "64 pages left")
        #expect(picks[0].kind == .reading)
        #expect(picks[1].reason == "2 h 04 · On your list 41 days")
        #expect(picks[1].minutes == 124)
        #expect(picks[2].reason == "Reading")
    }

    @Test("an airing today shows its local time; a show the user is behind on is not an airing")
    func airing() throws {
        let behind = try show("Behind")
        let airsAt = try #require(ISO8601DateFormatter().date(from: "2026-10-22T20:00:00Z"))
        func airing(_ item: LibraryItemID, _ name: String) throws -> CalendarEntry {
            try CalendarEntry(
                libraryItemID: item, title: Title(type: .show, title: name), key: EpisodeKey(season: 1, episode: 1),
                airsAt: airsAt, runtimeMinutes: 44, watched: false, kind: .premiere, airTimeKnown: true
            )
        }
        let library = try TonightService.Library(
            continuing: [behind], airing: [airing(LibraryItemID(), "New"), airing(behind.libraryItemID, "Behind")],
            starting: [], reading: []
        )
        let picks = rank(library)
        #expect(picks.map(\.title.title) == ["New", "Behind"])
        #expect(picks[0].reason == "Airs 21:00 · 44 min · Premiere")
        #expect(picks[1].kind == .continue)
    }

    @Test("durations read as minutes, then hours")
    func durations() {
        #expect(TonightService.duration(52) == "52 min")
        #expect(TonightService.duration(60) == "1 h 00")
        #expect(TonightService.duration(124) == "2 h 04")
    }
}

@Suite("Tonight over HTTP (AG-005)", .serialized)
struct TonightHTTPTests {
    func stubShow(_ env: LibraryHarness, _ name: String, aired: Int) -> String {
        let tmdb = uniqueID("tmdb")
        env.fake.stubTitle(CatalogTitle(
            hit: CatalogHit(
                type: .show, title: name, originalTitle: nil, year: 2026, posterURL: nil, overview: nil,
                byline: nil, ids: ExternalIDs(tmdb: tmdb), isAnime: false
            ),
            status: .returning, runtimeMinutes: nil
        ))
        let now = Date()
        env.fake.stubEpisodes(tmdb, CatalogEpisodes(status: .returning, episodes: (1 ... aired).map { number in
            CatalogEpisode(
                season: 1, episode: number, name: "\(name) \(number)",
                airsAt: now.addingTimeInterval(Double(number - aired - 30) * 86400), runtimeMinutes: 50,
                tmdbEpisodeID: nil
            )
        }))
        return tmdb
    }

    func picks(_ env: LibraryHarness) async throws -> [[String: Any]] {
        let reply = try await env.send(.get, "/v1/tonight?tz=Europe/Lisbon")
        #expect(reply.status == .ok)
        return try #require(try reply.json()["picks"] as? [[String: Any]])
    }

    @Test("feedback persists and changes the strip; progress on a pick counts it taken")
    func roundTrip() async throws {
        try await LibraryHarness.run { env in
            let first = try await env.add("show", tmdb: stubShow(env, "Severance", aired: 6), status: "in_progress")
            let second = try await env.add("show", tmdb: stubShow(env, "Andor", aired: 6), status: "in_progress")

            let shown = try await picks(env)
            #expect(Set(shown.compactMap { $0["libraryItemId"] as? String }) == [first, second])
            #expect(shown.allSatisfy { ($0["reason"] as? String)?.contains("50 min") == true })

            let hide = try await env.send(
                .post, "/v1/tonight/\(first)/feedback?tz=Europe/Lisbon", json: ["verdict": "not_tonight"]
            )
            #expect(hide.status == .noContent)
            let left = try await picks(env)
            #expect(left.compactMap { $0["libraryItemId"] as? String } == [second])

            // Someone else's item, or nonsense, is not found.
            let (_, other) = try await signedInUser(env.stores)
            let foreign = try await env.send(
                .post, "/v1/tonight/\(second)/feedback", json: ["verdict": "rejected"], token: other
            )
            #expect(foreign.status == .notFound)
            let badZone = try await env.send(.get, "/v1/tonight?tz=Mars/Olympus")
            #expect(badZone.status == .unprocessableContent)

            // Ticking the next episode of a shown pick marks it taken.
            _ = try await env.send(.put, "/v1/library/items/\(second)/episodes/1/1", json: ["watched": true])
            let taken = try await withSQL { sql in
                try await sql.raw("""
                SELECT count(*)::int AS count FROM tonight_picks
                WHERE user_id = \(bind: env.userID.rawValue) AND accepted_at IS NOT NULL
                """).first(decoding: TonightCountRow.self)?.count
            }
            #expect(taken == 1)
        }
    }

    @Test("an empty library gives an empty strip, never an error")
    func empty() async throws {
        try await LibraryHarness.run { env in
            let shown = try await picks(env)
            #expect(shown.isEmpty)
        }
    }
}

private struct TonightCountRow: Decodable {
    let count: Int
}
