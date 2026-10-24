import AaruAPI
import Foundation
import Observation

typealias Favorites = Components.Schemas.Favorites
typealias FavoriteKind = Components.Schemas.FavoriteKind

/// FAV-001: a top 10 per kind from `/v1/me/favorites`, first is the favorite. Every change sends
/// the whole kind in order (`PUT /v1/me/favorites/{kind}`): add, remove and reorder are one call.
/// Profile data, not a library write, so nothing here is journaled or undone.
@MainActor
@Observable
final class FavoritesModel {
    private(set) var favorites: Favorites?
    private(set) var isLoading = false
    /// A failed load or save, in the server's words when it gave any.
    var problem: String?

    /// For the title picker the editor opens.
    @ObservationIgnored let api: Client?

    /// The most a kind holds; the server answers 422 past it.
    static let limit = 10

    init(api: Client?, favorites: Favorites? = nil) {
        self.api = api
        self.favorites = favorites
    }

    func load() async {
        guard let api, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            switch try await api.getMyFavorites() {
            case let .ok(response):
                favorites = try response.body.json
                problem = nil
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "Your favorites didn't load."
            }
        } catch {
            problem = "Aaru could not reach the server."
        }
    }

    /// Reorder or remove: shown at once, put back if the server says no.
    func reorder(_ kind: FavoriteKind, to titles: [TitleSummary]) async {
        guard let before = favorites else { return }
        favorites?[kind] = titles
        if await save(kind, titles.map(\.mediaRef)) == false {
            favorites = before
        }
    }

    /// Adds a pick at the end. Not optimistic: the server resolves the hit to an Aaru title first.
    /// True when it was saved.
    func add(_ hit: CatalogHit, to kind: FavoriteKind) async -> Bool {
        guard let current = favorites?[kind], current.count < Self.limit else { return false }
        return await save(kind, current.map(\.mediaRef) + [hit.mediaRef])
    }

    private func save(_ kind: FavoriteKind, _ refs: [MediaRef]) async -> Bool {
        guard let api else { return false }
        problem = nil
        do {
            switch try await api.setMyFavorites(path: .init(kind: kind), body: .json(.init(items: refs))) {
            case let .ok(response):
                favorites = try response.body.json
                return true
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "Your favorites weren't saved."
            }
        } catch {
            problem = "Your favorites weren't saved. Aaru could not reach the server."
        }
        return false
    }
}

extension Favorites {
    static let empty = Favorites(film: [], show: [], anime: [], manga: [], book: [], album: [])

    /// One kind's titles, in order.
    subscript(kind: FavoriteKind) -> [TitleSummary] {
        get {
            switch kind {
            case .film: film
            case .show: show
            case .anime: anime
            case .manga: manga
            case .book: book
            case .album: album
            }
        }
        set {
            switch kind {
            case .film: film = newValue
            case .show: show = newValue
            case .anime: anime = newValue
            case .manga: manga = newValue
            case .book: book = newValue
            case .album: album = newValue
            }
        }
    }

    /// The kinds with at least one title, in the picker's order.
    var filledKinds: [FavoriteKind] {
        FavoriteKind.allCases.filter { !self[$0].isEmpty }
    }
}

extension FavoriteKind: @retroactive Identifiable {
    public var id: String {
        rawValue
    }

    /// The library shelf it matches: the search scope for the picker.
    var mediaKind: MediaKind {
        switch self {
        case .film: .film
        case .show: .show
        case .anime: .anime
        case .manga: .manga
        case .book: .book
        case .album: .music
        }
    }

    /// "Films", "Shows", "Anime", "Manga", "Books", "Albums".
    var label: String {
        self == .album ? "Albums" : mediaKind.label
    }
}
