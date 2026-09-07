/// Episode ticks for a show.
public struct ShowProgress: Codable, Hashable, Sendable {
    /// Every episode the user has marked watched.
    public var watched: Set<EpisodeKey>
    public var currentSeason: Int?
    public var currentEpisode: Int?

    public init(
        watched: Set<EpisodeKey> = [],
        currentSeason: Int? = nil,
        currentEpisode: Int? = nil
    ) {
        self.watched = watched
        self.currentSeason = currentSeason
        self.currentEpisode = currentEpisode
    }

    public var watchedCount: Int { watched.count }

    /// The furthest episode ticked, by season then episode.
    public var furthestWatched: EpisodeKey? { watched.max() }
}

/// Optional reading position for a book.
public struct BookProgress: Codable, Hashable, Sendable {
    public var page: Int?
    public var percent: Double?

    public init(page: Int? = nil, percent: Double? = nil) throws {
        if let page, page < 0 { throw ValidationError.invalidBookProgress }
        if let percent, !(0...100).contains(percent) { throw ValidationError.invalidBookProgress }
        self.page = page
        self.percent = percent
    }
}

/// Progress for a library item, if the media type has any.
///
/// Movies carry none: `finished` is the whole signal. v1 stores no continuous
/// playback position.
public enum Progress: Hashable, Sendable {
    case show(ShowProgress)
    case book(BookProgress)

    public var show: ShowProgress? {
        if case .show(let progress) = self { return progress }
        return nil
    }

    public var book: BookProgress? {
        if case .book(let progress) = self { return progress }
        return nil
    }
}

extension Progress: Codable {
    private enum Kind: String, Codable {
        case show, book
    }

    private enum CodingKeys: String, CodingKey {
        case kind, show, book
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .show:
            self = .show(try container.decode(ShowProgress.self, forKey: .show))
        case .book:
            self = .book(try container.decode(BookProgress.self, forKey: .book))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .show(let progress):
            try container.encode(Kind.show, forKey: .kind)
            try container.encode(progress, forKey: .show)
        case .book(let progress):
            try container.encode(Kind.book, forKey: .kind)
            try container.encode(progress, forKey: .book)
        }
    }
}
