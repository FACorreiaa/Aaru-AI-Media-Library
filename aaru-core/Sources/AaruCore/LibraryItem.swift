import Foundation

/// One user's relationship to one title.
///
/// The library layer. Catalog facts (name, year, poster, provider ids) live on
/// `Title` and are never copied here.
public struct LibraryItem: Codable, Hashable, Sendable, Identifiable {
    public var id: LibraryItemID
    public var userID: UserID
    public var titleID: TitleID
    /// Consumption state only.
    public var status: LibraryStatus
    /// Ownership, independent of consumption. A wishlist item can be owned.
    public var isOwned: Bool
    public var rating: Rating?
    public var notes: String?
    public var progress: Progress?
    public var addedAt: Date
    public var updatedAt: Date
    public var finishedAt: Date?

    public init(
        id: LibraryItemID = LibraryItemID(),
        userID: UserID,
        titleID: TitleID,
        status: LibraryStatus,
        isOwned: Bool = false,
        rating: Rating? = nil,
        notes: String? = nil,
        progress: Progress? = nil,
        addedAt: Date = Date(),
        updatedAt: Date = Date(),
        finishedAt: Date? = nil
    ) {
        self.id = id
        self.userID = userID
        self.titleID = titleID
        self.status = status
        self.isOwned = isOwned
        self.rating = rating
        self.notes = notes
        self.progress = progress
        self.addedAt = addedAt
        self.updatedAt = updatedAt
        self.finishedAt = finishedAt
    }
}
