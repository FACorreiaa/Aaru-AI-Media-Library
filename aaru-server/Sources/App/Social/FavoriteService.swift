import AaruCore
import Foundation

/// A user's favorites, every kind in order, with the titles they name.
struct Favorites: Sendable {
    var byKind: [FavoriteKind: [Title]]

    subscript(kind: FavoriteKind) -> [Title] {
        byKind[kind] ?? []
    }
}

/// FAV-001: an ordered top 10 per kind, any catalog title. Profile data like the handle: not a
/// library write and not journaled. A friend sees it only while the user shares their library.
struct FavoriteService: Sendable {
    let stores: Stores
    let resolver: TitleResolver

    static let limit = 10

    func favorites(of user: UserID) async throws -> Favorites {
        try await Self.favorites(of: user, stores: stores)
    }

    /// Without a resolver: a friend's profile only reads them.
    static func favorites(of user: UserID, stores: Stores) async throws -> Favorites {
        let ids = try await stores.favorites.favorites(of: user)
        let unique = Array(Set(ids.values.joined()))
        guard !unique.isEmpty else { return Favorites(byKind: [:]) }
        let titles = try await Dictionary(stores.titles.titles(ids: unique).map { ($0.id, $0) }) { first, _ in first }
        return Favorites(byKind: ids.mapValues { $0.compactMap { titles[$0] } })
    }

    /// Replaces one kind: adding, removing and reordering are all this one write.
    func replace(_ kind: FavoriteKind, with refs: [MediaRef], user: UserID) async throws -> Favorites {
        guard refs.count <= Self.limit else {
            throw Self.invalid("A top 10 holds at most \(Self.limit) titles.")
        }
        var titles: [Title] = []
        for ref in refs {
            try await titles.append(resolver.resolve(ref))
        }
        if let misfit = titles.first(where: { FavoriteKind($0) != kind }) {
            throw Self.invalid("\(misfit.title) is not \(Self.article(kind)).")
        }
        guard Set(titles.map(\.id)).count == titles.count else {
            throw Self.invalid("Each title can be in the top 10 once.")
        }
        try await stores.favorites.replaceFavorites(titles.map(\.id), kind: kind, for: user)
        return try await favorites(of: user)
    }

    private static func article(_ kind: FavoriteKind) -> String {
        switch kind {
        case .film: "a film"
        case .show: "a show"
        case .anime: "an anime"
        case .manga: "a manga"
        case .book: "a book"
        case .album: "an album"
        }
    }

    private static func invalid(_ message: String) -> AppError {
        AppError(
            status: .unprocessableContent,
            code: "validation_failed",
            message: message,
            details: ["items": message]
        )
    }
}
