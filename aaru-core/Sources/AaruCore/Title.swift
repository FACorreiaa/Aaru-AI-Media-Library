import Foundation

/// A canonical work Aaru knows about: one movie, show, book, album, or manga.
///
/// Titles are shared across users. Ratings, status, notes, and progress belong on
/// `LibraryItem` and must never appear here.
public struct Title: Codable, Hashable, Sendable, Identifiable {
    /// Years Aaru accepts. Wide enough for early cinema and for announced titles.
    public static let validYears: ClosedRange<Int> = 1870 ... 2200

    public var id: TitleID
    public var type: MediaType
    public var title: String
    public var originalTitle: String?
    public var year: Int?
    public var synopsis: String?
    /// Catalog URL. Aaru does not host provider artwork.
    public var posterURL: URL?
    /// Wide art (TMDB backdrop, AniList banner): the week grid's cell banner. Catalog URL.
    public var backdropURL: URL?
    /// Network or streaming service, for shows: "HBO", "Netflix", "Crunchyroll".
    public var network: String?
    /// Who made it, as the catalog credits them: an album's artist ("Simon & Garfunkel").
    public var byline: String?
    /// A book's length in pages (Open Library's median across editions), for a reading bar.
    public var pageCount: Int?
    /// A manga's length as AniList knows it: `nil` while it is still running.
    public var chapterCount: Int?
    public var volumeCount: Int?
    public var ids: ExternalIDs
    /// Anime is a facet on `movie`/`show`, not a fourth `MediaType`: an anime series
    /// shares show progress, calendar, Up Next, and widgets with every other show.
    public var isAnime: Bool
    /// Shows only. `nil` means "not loaded yet", `[]` means "loaded, none known".
    public var seasons: [Season]?

    public init(
        id: TitleID = TitleID(),
        type: MediaType,
        title: String,
        originalTitle: String? = nil,
        year: Int? = nil,
        synopsis: String? = nil,
        posterURL: URL? = nil,
        backdropURL: URL? = nil,
        network: String? = nil,
        byline: String? = nil,
        pageCount: Int? = nil,
        chapterCount: Int? = nil,
        volumeCount: Int? = nil,
        ids: ExternalIDs = ExternalIDs(),
        isAnime: Bool = false,
        seasons: [Season]? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.originalTitle = originalTitle
        self.year = year
        self.synopsis = synopsis
        self.posterURL = posterURL
        self.backdropURL = backdropURL
        self.network = network
        self.byline = byline
        self.pageCount = pageCount
        self.chapterCount = chapterCount
        self.volumeCount = volumeCount
        self.ids = ids
        self.isAnime = isAnime
        self.seasons = seasons
    }

    /// The key used when no external id matches on either side.
    public var matchKey: MatchKey {
        MatchKey(title: title, year: year, type: type)
    }

    public func validate() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.emptyTitle
        }
        if let year, !Title.validYears.contains(year) {
            throw ValidationError.invalidYear(year)
        }
    }
}
