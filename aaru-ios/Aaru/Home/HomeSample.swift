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
                upNext: .init(continueWatching: continueWatching, startWatching: startWatching),
                airing: airing
            ),
            discover: sampleDiscover,
            now: now
        )
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
