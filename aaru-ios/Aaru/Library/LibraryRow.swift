import AaruAPI
import Foundation

typealias LibraryEntry = Components.Schemas.LibraryEntry
typealias LibraryStatus = Components.Schemas.LibraryStatus
typealias CatalogHit = Components.Schemas.CatalogHit

/// How the library is browsed: anime is its own shelf even though it is a show or a film.
enum MediaKind: String, CaseIterable, Identifiable {
    case film, show, anime, book

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .film: "Films"
        case .show: "Shows"
        case .anime: "Anime"
        case .book: "Books"
        }
    }

    var symbol: String {
        switch self {
        case .film: "film"
        case .show: "tv"
        case .anime: "sparkles.tv"
        case .book: "book.closed"
        }
    }

    init(type: Components.Schemas.MediaType, isAnime: Bool) {
        switch type {
        case .book: self = .book
        case _ where isAnime: self = .anime
        case .movie: self = .film
        case .show: self = .show
        }
    }

    /// The search scope this kind maps to on `/v1/search`.
    var searchType: Operations.SearchCatalog.Input.Query._TypePayload {
        switch self {
        case .film: .movie
        case .show: .show
        case .anime: .anime
        case .book: .book
        }
    }
}

extension LibraryStatus: @retroactive Identifiable {
    public var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .wishlist: "Wishlist"
        case .inProgress: "In progress"
        case .finished: "Finished"
        case .dropped: "Dropped"
        }
    }
}

/// One library entry, ready to draw.
struct LibraryRow: Identifiable, Hashable {
    let id: String
    let title: String
    let year: Int?
    let posterURL: URL?
    let kind: MediaKind
    let status: LibraryStatus
    let detail: String?
    let updatedAt: Date

    init(_ entry: LibraryEntry) {
        id = entry.id
        title = entry.title.title
        year = entry.title.year
        posterURL = entry.title.posterUrl.flatMap(URL.init(string:))
        kind = MediaKind(type: entry.title._type, isAnime: entry.title.isAnime)
        status = entry.status
        updatedAt = entry.updatedAt
        if let progress = entry.progress, progress.airedCount > 0 {
            detail = "\(progress.watchedCount) of \(progress.airedCount) episodes"
        } else if let page = entry.bookProgress?.page {
            detail = "Page \(page)"
        } else if let percent = entry.bookProgress?.percent {
            detail = "\(Int(percent))%"
        } else {
            detail = nil
        }
    }
}

extension Components.Schemas.ExternalIds {
    /// Provider keys that identify one title, for "already in your library" on search hits.
    var keys: Set<String> {
        let pairs: [(String, String?)] = [
            ("tmdb", tmdb), ("imdb", imdb), ("isbn", isbn), ("openLibrary", openLibrary),
            ("anilist", anilist), ("mal", mal), ("trakt", trakt), ("tvdb", tvdb),
        ]
        return Set(pairs.compactMap { name, value in value.map { "\(name):\($0)" } })
    }
}

extension CatalogHit: @retroactive Identifiable {
    /// A provider key when there is one, so the same title from two searches is one hit.
    public var id: String {
        ids.keys.sorted().first ?? "\(title)-\(year ?? 0)"
    }
}
