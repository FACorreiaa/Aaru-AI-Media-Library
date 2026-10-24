import AaruCore
import Foundation

/// The six kinds a user keeps favorites for (FAV-001). Anime is a flag on movie and show, so the
/// kind is stored rather than read from the title's type.
enum FavoriteKind: String, CaseIterable, Codable, Sendable {
    case film, show, anime, manga, book, album

    /// The kind a title counts as.
    init(_ title: Title) {
        switch title.type {
        case .movie: self = title.isAnime ? .anime : .film
        case .show: self = title.isAnime ? .anime : .show
        case .manga: self = .manga
        case .book: self = .book
        case .album: self = .album
        }
    }
}

/// A user's ordered favorites per kind: profile data, not a library write, never journaled.
protocol FavoriteStore: Sendable {
    /// Every kind the user has favorites in, each in the user's order.
    func favorites(of user: UserID) async throws -> [FavoriteKind: [TitleID]]
    /// Replaces one kind with these titles, in this order.
    func replaceFavorites(_ titles: [TitleID], kind: FavoriteKind, for user: UserID) async throws
}
