import Foundation

/// A canonical work Aaru knows about: one movie, show, or book.
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
