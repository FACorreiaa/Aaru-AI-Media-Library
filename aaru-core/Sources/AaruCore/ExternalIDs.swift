/// Provider identifiers Aaru knows for a title.
///
/// Every saved title stores whichever of these are known. They are the primary
/// matching key during import — normalized title + year is only the fallback.
///
/// TMDB and Trakt number movies and shows separately, so a `tmdb` or `trakt` match
/// only means "same work" between titles of the same `MediaType`.
public struct ExternalIDs: Codable, Hashable, Sendable {
    public var tmdb: String?
    public var imdb: String?
    public var trakt: String?
    public var tvdb: String?
    public var isbn: String?
    public var openLibrary: String?
    public var anilist: String?
    public var mal: String?
    public var anidb: String?

    public init(
        tmdb: String? = nil,
        imdb: String? = nil,
        trakt: String? = nil,
        tvdb: String? = nil,
        isbn: String? = nil,
        openLibrary: String? = nil,
        anilist: String? = nil,
        mal: String? = nil,
        anidb: String? = nil
    ) {
        self.tmdb = tmdb
        self.imdb = imdb
        self.trakt = trakt
        self.tvdb = tvdb
        self.isbn = isbn
        self.openLibrary = openLibrary
        self.anilist = anilist
        self.mal = mal
        self.anidb = anidb
    }

    // Computed: key paths are not Sendable, so this cannot be a stored static.
    private static var fields: [(name: String, path: WritableKeyPath<ExternalIDs, String?>)] {
        [
            ("tmdb", \.tmdb),
            ("imdb", \.imdb),
            ("trakt", \.trakt),
            ("tvdb", \.tvdb),
            ("isbn", \.isbn),
            ("openLibrary", \.openLibrary),
            ("anilist", \.anilist),
            ("mal", \.mal),
            ("anidb", \.anidb),
        ]
    }

    /// True when no provider identifier is known.
    public var isEmpty: Bool {
        Self.fields.allSatisfy { self[keyPath: $0.path] == nil }
    }

    /// Every identifier that is set, as `(provider, value)` pairs.
    public var known: [(provider: String, value: String)] {
        Self.fields.compactMap { field in self[keyPath: field.path].map { (field.name, $0) } }
    }

    /// True when both sides agree on at least one provider identifier.
    ///
    /// Two titles that share no identifier must never be merged on name alone. Callers
    /// comparing titles must also require the same `MediaType` (see `MatchKey.canMerge`).
    public func matches(_ other: ExternalIDs) -> Bool {
        Self.fields.contains { field in
            guard let lhs = self[keyPath: field.path], let rhs = other[keyPath: field.path] else { return false }
            return lhs == rhs
        }
    }

    /// Copies identifiers from `other` into fields that are still empty.
    ///
    /// Fill-empty-only: a later import source never overwrites an identifier an
    /// earlier source already established.
    public func filling(from other: ExternalIDs) -> ExternalIDs {
        var result = self
        for field in Self.fields where result[keyPath: field.path] == nil {
            result[keyPath: field.path] = other[keyPath: field.path]
        }
        return result
    }
}
