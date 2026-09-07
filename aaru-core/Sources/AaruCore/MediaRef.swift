/// A pointer to a title that may not exist in Aaru yet.
///
/// This is what a client sends to add something to the library, and what an
/// importer produces for each source row. The server resolves it to a `Title`
/// (find or hydrate) before creating a `LibraryItem`.
public struct MediaRef: Codable, Hashable, Sendable {
    /// Set when the caller already knows Aaru's title.
    public var titleID: TitleID?
    public var type: MediaType
    public var ids: ExternalIDs
    public var title: String?
    public var year: Int?

    public init(
        titleID: TitleID? = nil,
        type: MediaType,
        ids: ExternalIDs = ExternalIDs(),
        title: String? = nil,
        year: Int? = nil
    ) {
        self.titleID = titleID
        self.type = type
        self.ids = ids
        self.title = title
        self.year = year
    }

    /// The fallback key, when there is enough to build one.
    ///
    /// `nil` when no name is known — a ref with only a type is not matchable.
    public var matchKey: MatchKey? {
        guard let title else { return nil }
        return MatchKey(title: title, year: year, type: type)
    }

    /// True when the server has something to resolve against.
    public var isResolvable: Bool {
        if titleID != nil { return true }
        if !ids.isEmpty { return true }
        guard let title else { return false }
        return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && year != nil
    }

    public func validate() throws {
        guard isResolvable else { throw ValidationError.unresolvableMediaRef }
        if let year, !Title.validYears.contains(year) {
            throw ValidationError.invalidYear(year)
        }
    }
}
