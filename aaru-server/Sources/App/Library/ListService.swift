import AaruCore
import Foundation

/// A list with its member titles, in order.
struct ListDetail: Sendable {
    var list: AaruList
    var titles: [Title]
}

/// Lists (LST-001, LST-002): membership of titles, journaled like every library write.
/// A list can hold a title the user has no library item for.
struct ListService: Sendable {
    let stores: Stores
    let resolver: TitleResolver
    var now: @Sendable () -> Date = { Date() }

    func lists(userID: UserID) async throws -> [AaruList] {
        try await stores.lists.lists(userID: userID)
    }

    func detail(_ id: ListID, userID: UserID) async throws -> ListDetail {
        guard let list = try await stores.lists.list(id: id, userID: userID)
        else { throw AppError.notFound("No such list.") }
        return try await ListDetail(list: list, titles: stores.titles.titles(ids: list.titleIDs))
    }

    func create(name: String, userID: UserID) async throws -> ListDetail {
        let snapshot = ListSnapshot(
            id: ListID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: now(),
            members: []
        )
        try AaruList(userID: userID, name: snapshot.name).validate()
        try await stores.library.apply(
            .insertList(snapshot), userID: userID, actor: .user, kind: "list", summary: "Created list \(snapshot.name)"
        )
        return try await detail(snapshot.id, userID: userID)
    }

    func rename(_ id: ListID, to name: String, userID: UserID) async throws -> ListDetail {
        let current = try await detail(id, userID: userID)
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try AaruList(userID: userID, name: name).validate()
        guard name != current.list.name else { return current }
        try await stores.library.apply(
            .renameList(id, name), userID: userID, actor: .user, kind: "list",
            summary: "Renamed \(current.list.name) to \(name)"
        )
        return try await detail(id, userID: userID)
    }

    func delete(_ id: ListID, userID: UserID) async throws {
        let current = try await detail(id, userID: userID)
        try await stores.library.apply(
            .deleteList(id), userID: userID, actor: .user, kind: "list", summary: "Deleted list \(current.list.name)"
        )
    }

    /// Adds a title at the end. Adding a member again changes nothing.
    func add(_ ref: MediaRef, to id: ListID, userID: UserID) async throws -> ListDetail {
        let current = try await detail(id, userID: userID)
        let title = try await resolver.resolve(ref)
        guard !current.list.titleIDs.contains(title.id) else { return current }
        try await stores.library.apply(
            .setListMembers(id, current.list.titleIDs + [title.id]), userID: userID, actor: .user, kind: "list",
            summary: "Added \(title.title) to \(current.list.name)"
        )
        return try await detail(id, userID: userID)
    }

    func remove(_ titleID: TitleID, from id: ListID, userID: UserID) async throws -> ListDetail {
        let current = try await detail(id, userID: userID)
        guard current.list.titleIDs.contains(titleID)
        else { throw AppError.notFound("That title is not on this list.") }
        let name = current.titles.first { $0.id == titleID }?.title ?? "a title"
        try await stores.library.apply(
            .setListMembers(id, current.list.titleIDs.filter { $0 != titleID }), userID: userID, actor: .user,
            kind: "list", summary: "Removed \(name) from \(current.list.name)"
        )
        return try await detail(id, userID: userID)
    }

    /// Manual ordering: the new order must be exactly the current members.
    func reorder(_ id: ListID, to order: [TitleID], userID: UserID) async throws -> ListDetail {
        let current = try await detail(id, userID: userID)
        guard order.count == current.list.titleIDs.count, Set(order) == Set(current.list.titleIDs) else {
            throw AppError(
                status: .unprocessableContent, code: "validation_failed",
                message: "The order must list every title on the list exactly once.",
                details: ["titleIds": "Must be a permutation of the list's titles."]
            )
        }
        guard order != current.list.titleIDs else { return current }
        try await stores.library.apply(
            .setListMembers(id, order), userID: userID, actor: .user, kind: "list",
            summary: "Reordered \(current.list.name)"
        )
        return try await detail(id, userID: userID)
    }
}

/// Shelves (SHF-001, SHF-002): saved queries. A shelf resolves through the same code as
/// `GET /v1/library/items`, so the two return identical payloads for the same filter.
struct ShelfService: Sendable {
    let stores: Stores
    let library: LibraryService
    var now: @Sendable () -> Date = { Date() }

    func shelves(userID: UserID) async throws -> [Shelf] {
        try await stores.shelves.shelves(userID: userID)
    }

    func shelf(_ id: UUID, userID: UserID) async throws -> Shelf {
        guard let shelf = try await stores.shelves.shelf(id: id, userID: userID)
        else { throw AppError.notFound("No such shelf.") }
        return shelf
    }

    func create(name: String, filter: LibraryFilter, isPinned: Bool, userID: UserID) async throws -> Shelf {
        let shelf = try Shelf(
            id: UUID(),
            name: Self.validName(name),
            filter: filter,
            isPinned: isPinned,
            createdAt: now()
        )
        try await stores.shelves.save(shelf, userID: userID)
        return shelf
    }

    func update(
        _ id: UUID,
        userID: UserID,
        name: String?,
        filter: LibraryFilter?,
        isPinned: Bool?
    ) async throws -> Shelf {
        var shelf = try await shelf(id, userID: userID)
        if let name {
            shelf.name = try Self.validName(name)
        }
        if let filter {
            shelf.filter = filter
        }
        if let isPinned {
            shelf.isPinned = isPinned
        }
        try await stores.shelves.save(shelf, userID: userID)
        return shelf
    }

    func delete(_ id: UUID, userID: UserID) async throws {
        guard try await stores.shelves.delete(id: id, userID: userID) else { throw AppError.notFound("No such shelf.") }
    }

    func items(
        _ id: UUID,
        userID: UserID,
        cursor: String?,
        limit: Int
    ) async throws -> (entries: [LibraryEntry], next: String?) {
        let shelf = try await shelf(id, userID: userID)
        return try await library.list(userID: userID, filter: shelf.filter, cursor: cursor, limit: limit)
    }

    private static func validName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppError(
                status: .unprocessableContent, code: "validation_failed",
                message: "A shelf needs a name.", details: ["name": "A shelf needs a name."]
            )
        }
        return trimmed
    }
}
