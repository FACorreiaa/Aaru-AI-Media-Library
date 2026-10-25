import AaruAPI
import Foundation

extension HomeModel {
    /// For previews: a Home that looks like a real one. No artwork, so previews check the fallbacks.
    static var sample: HomeModel {
        let now = Date.now
        func title(_ name: String, _ network: String? = nil, type: Components.Schemas.MediaType = .show)
            -> Components.Schemas.TitleSummary
        {
            .init(id: UUID().uuidString, _type: type, title: name, network: network, isAnime: false, ids: .init())
        }
        let continueWatching: [ContinueEntry] = [
            .init(
                libraryItemId: UUID().uuidString, title: title("Severance", "Apple TV+"),
                next: .init(season: 2, number: 8), nextName: "Sweet Vitriol", nextRuntimeMinutes: 57,
                remainingCount: 3, remainingMinutes: 160, isFinale: false
            ),
            .init(
                libraryItemId: UUID().uuidString, title: title("The Bear", "FX"),
                next: .init(season: 4, number: 10), nextName: "Forever", nextRuntimeMinutes: 41,
                remainingCount: 1, remainingMinutes: 41, isFinale: true
            ),
            .init(
                libraryItemId: UUID().uuidString, title: title("Frieren: Beyond Journey's End", "Crunchyroll"),
                next: .init(season: 1, number: 18), nextName: nil, nextRuntimeMinutes: 24,
                remainingCount: 10, remainingMinutes: 240, isFinale: false
            ),
        ]
        let startWatching: [StartEntry] = [
            .init(libraryItemId: UUID().uuidString, title: title("Arrival", type: .movie), runtimeMinutes: 116),
            .init(libraryItemId: UUID().uuidString, title: title("Shōgun", "FX"), runtimeMinutes: 60),
            .init(libraryItemId: UUID().uuidString, title: title("Past Lives", type: .movie), runtimeMinutes: 106),
            .init(libraryItemId: UUID().uuidString, title: title("Dune: Part Two", type: .movie), runtimeMinutes: 166),
        ]
        func airing(
            _ show: Components.Schemas.TitleSummary, _ season: Int, _ number: Int, _ name: String,
            in seconds: TimeInterval, exact: Bool = true, kind: CalendarEntry.KindPayload = .regular
        ) -> CalendarEntry {
            .init(
                libraryItemId: show.id, title: show, season: season, number: number, episodeName: name,
                airsAt: now.addingTimeInterval(seconds), airTimeKnown: exact, watched: false, kind: kind
            )
        }
        let airing: [CalendarEntry] = [
            airing(title("The Pitt", "HBO Max"), 1, 15, "9:00 P.M.", in: 3 * 3600),
            airing(title("Andor", "Disney+"), 2, 4, "Ever Been to Ghorman?", in: 86400 + 600),
            airing(title("Pluribus"), 1, 1, "We Is Us", in: 2 * 86400, exact: false, kind: .premiere),
            airing(title("Slow Horses", "Apple TV+"), 5, 6, "Missing Persons", in: 4 * 86400, kind: .finale),
        ]
        return HomeModel(
            preview: .init(
                upNext: .init(
                    continueWatching: continueWatching,
                    startWatching: startWatching,
                    counts: .init(wishlist: 60, inProgress: 12, onHold: 0, finished: 186, dropped: 4)
                ),
                airing: airing
            ),
            discover: sampleDiscover,
            listening: sampleListening,
            now: now
        )
    }

    /// The sample Home while Stremio plays an episode of the first Continue watching show and a
    /// track plays beside it (SCR-008, SCR-009): Now playing leads, and Tonight moves on to the
    /// next thing.
    static var samplePlaying: HomeModel {
        let home = sample
        guard let lead = home.continueWatching.first else { return home }
        var episode = NowPlayingItem.sample(libraryItemId: lead.libraryItemId)
        episode.name = lead.title.title
        episode.title = lead.title
        episode.episode = lead.next
        episode.subtitle = ["S\(lead.next.season) · E\(lead.next.number)", lead.nextName].compactMap(\.self)
            .joined(separator: " · ")
        episode.artworkUrl = lead.title.posterUrl
        return HomeModel(
            preview: .init(
                upNext: .init(
                    continueWatching: home.continueWatching,
                    startWatching: home.startWatching,
                    counts: home.counts
                ),
                airing: home.upcoming
            ),
            discover: home.discover,
            listening: sampleListening,
            nowPlaying: [episode, .sampleTrack]
        )
    }

    /// Albums marked Listening (MUS-001), square covers left to the fallback.
    static var sampleListening: [LibraryRow] {
        [
            AlbumSample.entry("OK Computer", artist: "Radiohead", year: 1997),
            AlbumSample.entry("Blonde", artist: "Frank Ocean", year: 2016),
            AlbumSample.entry(
                "Promises", artist: "Floating Points, Pharoah Sanders & London Symphony Orchestra", year: 2021
            ),
            AlbumSample.entry("Vespertine", artist: "Björk", year: 2001),
        ].map(LibraryRow.init)
    }

    /// A new account: nothing tracked, only the public rows (DISC-001).
    static var newAccount: HomeModel {
        HomeModel(
            preview: .init(upNext: .init(continueWatching: [], startWatching: []), airing: []),
            discover: sampleDiscover
        )
    }

    private static var sampleDiscover: [DiscoverRow] {
        func hit(_ name: String, _ year: Int, type: Components.Schemas.MediaType = .show, anime: Bool = false)
            -> CatalogHit
        {
            .init(_type: type, title: name, year: year, isAnime: anime, ids: .init(tmdb: name))
        }
        return [
            .init(id: "tv_trending", title: "Trending shows", items: [
                hit("Pluribus", 2025), hit("The Pitt", 2025), hit("Severance", 2022), hit("Andor", 2022),
            ]),
            .init(id: "anime_season", title: "Fall 2026 anime", items: [
                hit("The Apothecary Diaries", 2026, anime: true), hit("Black Clover", 2026, anime: true),
                hit("Cyberpunk: Edgerunners 2", 2026, type: .movie, anime: true),
            ]),
            .init(id: "books_trending", title: "Trending books", items: [
                .init(
                    _type: .book,
                    title: "Atomic Habits",
                    year: 2016,
                    byline: "James Clear",
                    isAnime: false,
                    ids: .init(openLibrary: "OL17930368W")
                ),
            ]),
        ]
    }
}

extension ImportJob {
    /// For previews: one import still matching, one done.
    static var sampleWorking: ImportJob {
        .init(
            id: UUID().uuidString, source: .netflixCsv, state: .running,
            stats: .init(created: 0, updated: 0, skipped: 0, unmatched: 0),
            filename: "NetflixViewingHistory.csv", createdAt: .now, updatedAt: .now,
            rowsTotal: 1240, rowsMatched: 512
        )
    }

    static var sampleDone: ImportJob {
        .init(
            id: UUID().uuidString, source: .letterboxdCsv, state: .partial,
            stats: .init(created: 210, updated: 14, skipped: 3, unmatched: 18),
            filename: "diary.csv", createdAt: .now.addingTimeInterval(-86400), updatedAt: .now,
            rowsTotal: 245, rowsMatched: 245
        )
    }
}

extension ListsModel {
    /// For previews: two lists.
    static var sample: ListsModel {
        ListsModel(preview: [
            .init(id: UUID().uuidString, name: "Rainy-night books", itemCount: 9, createdAt: .now, updatedAt: .now),
            .init(id: UUID().uuidString, name: "Winter movies", itemCount: 14, createdAt: .now, updatedAt: .now),
        ])
    }
}
