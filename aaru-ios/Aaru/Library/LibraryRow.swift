import AaruAPI
import CoreGraphics
import Foundation

typealias LibraryEntry = Components.Schemas.LibraryEntry
typealias LibraryStatus = Components.Schemas.LibraryStatus
typealias CatalogHit = Components.Schemas.CatalogHit

/// How the library is browsed: anime is its own shelf even though it is a show or a film. Music
/// is albums (MUS-001); manga is AniList's MANGA type (MNG-001).
enum MediaKind: String, CaseIterable, Identifiable {
    case film, show, anime, manga, book, music

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .film: "Films"
        case .show: "Shows"
        case .anime: "Anime"
        case .manga: "Manga"
        case .book: "Books"
        case .music: "Music"
        }
    }

    /// One of them: "Film", "Show", "Anime", "Book", "Album".
    var noun: String {
        switch self {
        case .film: "Film"
        case .show: "Show"
        case .anime: "Anime"
        case .manga: "Manga"
        case .book: "Book"
        case .music: "Album"
        }
    }

    var symbol: String {
        switch self {
        case .film: "film"
        case .show: "tv"
        case .anime: "sparkles.tv"
        case .manga: "book.pages"
        case .book: "book.closed"
        case .music: "music.note"
        }
    }

    /// Width over height of the kind's artwork: a square album cover, a 2:3 poster for the rest.
    var posterAspect: CGFloat {
        self == .music ? 1 : 2 / 3
    }

    init(type: Components.Schemas.MediaType, isAnime: Bool) {
        switch type {
        case .book: self = .book
        case .album: self = .music
        case .manga: self = .manga
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
        case .manga: .manga
        case .book: .book
        case .music: .album
        }
    }
}

extension LibraryStatus: @retroactive Identifiable {
    public var id: String {
        rawValue
    }

    /// The status in the words of what it is on: "Watching" a show, "Reading" a book,
    /// "Listening" to an album. With no kind (a mixed shelf, the Any filter) the neutral words.
    func label(for kind: MediaKind?) -> String {
        let words = switch kind {
        case .book, .manga: Words(planned: "Plan to read", active: "Reading", done: "Read")
        case .music: Words(planned: "Plan to listen", active: "Listening", done: "Listened")
        case .film, .show, .anime: Words(planned: "Plan to watch", active: "Watching", done: "Watched")
        case nil: Words(planned: "Planned", active: "In progress", done: "Finished")
        }
        return switch self {
        case .wishlist: words.planned
        case .inProgress: words.active
        case .finished: words.done
        case .dropped: "Dropped"
        }
    }

    /// One kind's words for planned, in progress and finished.
    private struct Words {
        let planned: String
        let active: String
        let done: String
    }
}

/// One library entry, ready to draw.
struct LibraryRow: Identifiable, Hashable {
    let id: String
    let title: String
    /// The title in its own language, so the filter finds "進撃の巨人" too.
    let originalTitle: String?
    let year: Int?
    /// The artist for an album, the authors for a book.
    let byline: String?
    let posterURL: URL?
    let kind: MediaKind
    let status: LibraryStatus
    let detail: String?
    let updatedAt: Date

    init(_ entry: LibraryEntry) {
        id = entry.id
        title = entry.title.title
        originalTitle = entry.title.originalTitle
        year = entry.title.year
        byline = entry.title.byline
        posterURL = entry.title.posterUrl.flatMap(URL.init(string:))
        kind = MediaKind(type: entry.title._type, isAnime: entry.title.isAnime)
        status = entry.status
        updatedAt = entry.updatedAt
        if let progress = entry.progress, progress.airedCount > 0 {
            detail = "\(progress.watchedCount) of \(progress.airedCount) episodes"
        } else if let manga = entry.mangaProgressLabel {
            detail = manga
        } else if let page = entry.bookProgress?.page {
            detail = "Page \(page)"
        } else if let percent = entry.bookProgress?.percent {
            detail = "\(Int(percent))%"
        } else {
            detail = nil
        }
    }
}

extension LibraryEntry {
    /// Where a manga reader is (MNG-001): "Ch. 112 of 364 · Vol. 12", either part alone, or nil
    /// before they log any.
    var mangaProgressLabel: String? {
        var parts: [String] = []
        if let chapter = mangaProgress?.chapter {
            parts.append(title.chapterCount.map { "Ch. \(chapter) of \($0)" } ?? "Ch. \(chapter)")
        }
        if let volume = mangaProgress?.volume {
            parts.append("Vol. \(volume)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

extension Components.Schemas.ExternalIds {
    /// Provider keys that identify one title, for "already in your library" on search hits.
    var keys: Set<String> {
        let pairs: [(String, String?)] = [
            ("tmdb", tmdb), ("imdb", imdb), ("isbn", isbn), ("openLibrary", openLibrary),
            ("anilist", anilist), ("mal", mal), ("trakt", trakt), ("tvdb", tvdb), ("musicbrainz", musicbrainz),
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
