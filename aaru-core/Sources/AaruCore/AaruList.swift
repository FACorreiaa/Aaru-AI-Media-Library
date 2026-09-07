import Foundation

/// A user-curated collection of titles.
///
/// Named `AaruList` because a bare `List` collides with SwiftUI in every client
/// file. The domain word stays "list" in the API and the UI.
///
/// Members are `TitleID`, not `LibraryItemID`, so a list can hold a title the
/// user has not given a status yet.
public struct AaruList: Codable, Hashable, Sendable, Identifiable {
    public var id: ListID
    public var userID: UserID
    public var name: String
    public var titleIDs: [TitleID]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: ListID = ListID(),
        userID: UserID,
        name: String,
        titleIDs: [TitleID] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userID = userID
        self.name = name
        self.titleIDs = titleIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.emptyListName
        }
    }
}
