/// Provider identifiers Aaru knows for a title.
///
/// Every saved title stores whichever of these are known. They are the primary
/// matching key during import — normalized title + year is only the fallback.
public struct ExternalIDs: Codable, Hashable, Sendable {
    public var tmdb: String?
    public var imdb: String?
    public var trakt: String?
    public var tvdb: String?
    public var isbn: String?
    public var openLibrary: String?

    public init(
        tmdb: String? = nil,
        imdb: String? = nil,
        trakt: String? = nil,
        tvdb: String? = nil,
        isbn: String? = nil,
        openLibrary: String? = nil
    ) {
        self.tmdb = tmdb
        self.imdb = imdb
        self.trakt = trakt
        self.tvdb = tvdb
        self.isbn = isbn
        self.openLibrary = openLibrary
    }

    /// True when no provider identifier is known.
    public var isEmpty: Bool {
        tmdb == nil && imdb == nil && trakt == nil
            && tvdb == nil && isbn == nil && openLibrary == nil
    }

    /// Every identifier that is set, as `(provider, value)` pairs.
    public var known: [(provider: String, value: String)] {
        var pairs: [(String, String)] = []
        if let tmdb { pairs.append(("tmdb", tmdb)) }
        if let imdb { pairs.append(("imdb", imdb)) }
        if let trakt { pairs.append(("trakt", trakt)) }
        if let tvdb { pairs.append(("tvdb", tvdb)) }
        if let isbn { pairs.append(("isbn", isbn)) }
        if let openLibrary { pairs.append(("openLibrary", openLibrary)) }
        return pairs
    }

    /// True when both sides agree on at least one provider identifier.
    ///
    /// Two titles that share no identifier must never be merged on name alone.
    public func matches(_ other: ExternalIDs) -> Bool {
        func same(_ lhs: String?, _ rhs: String?) -> Bool {
            guard let lhs, let rhs else { return false }
            return lhs == rhs
        }
        return same(tmdb, other.tmdb)
            || same(imdb, other.imdb)
            || same(trakt, other.trakt)
            || same(tvdb, other.tvdb)
            || same(isbn, other.isbn)
            || same(openLibrary, other.openLibrary)
    }

    /// Copies identifiers from `other` into fields that are still empty.
    ///
    /// Fill-empty-only: a later import source never overwrites an identifier an
    /// earlier source already established.
    public func filling(from other: ExternalIDs) -> ExternalIDs {
        ExternalIDs(
            tmdb: tmdb ?? other.tmdb,
            imdb: imdb ?? other.imdb,
            trakt: trakt ?? other.trakt,
            tvdb: tvdb ?? other.tvdb,
            isbn: isbn ?? other.isbn,
            openLibrary: openLibrary ?? other.openLibrary
        )
    }
}
