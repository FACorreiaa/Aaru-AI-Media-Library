import aaruAPI
import AaruCore
import Foundation
import OpenAPIRuntime

extension APIImplementation {
    func listLists(_: Operations.ListLists.Input) async throws -> Operations.ListLists.Output {
        let lists = try await services.lists.lists(userID: currentUser())
        return .ok(.init(body: .json(.init(items: lists.map {
            .init(
                id: $0.id.description, name: $0.name, itemCount: $0.titleIDs.count,
                createdAt: $0.createdAt, updatedAt: $0.updatedAt
            )
        }))))
    }

    func createList(_ input: Operations.CreateList.Input) async throws -> Operations.CreateList.Output {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        return try await .ok(.init(body: .json(.init(services.lists.create(name: body.name, userID: currentUser())))))
    }

    func getList(_ input: Operations.GetList.Input) async throws -> Operations.GetList.Output {
        try await .ok(.init(body: .json(.init(services.lists.detail(listID(input.path.id), userID: currentUser())))))
    }

    func renameList(_ input: Operations.RenameList.Input) async throws -> Operations.RenameList.Output {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let detail = try await services.lists.rename(listID(input.path.id), to: body.name, userID: currentUser())
        return .ok(.init(body: .json(.init(detail))))
    }

    func deleteList(_ input: Operations.DeleteList.Input) async throws -> Operations.DeleteList.Output {
        try await services.lists.delete(listID(input.path.id), userID: currentUser())
        return .noContent(.init())
    }

    func addListItem(_ input: Operations.AddListItem.Input) async throws -> Operations.AddListItem.Output {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let detail = try await services.lists.add(
            MediaRef(body.mediaRef),
            to: listID(input.path.id),
            userID: currentUser()
        )
        return .ok(.init(body: .json(.init(detail))))
    }

    func removeListItem(_ input: Operations.RemoveListItem.Input) async throws -> Operations.RemoveListItem.Output {
        guard let titleID = TitleID(uuidString: input.path.titleId) else { throw AppError.notFound() }
        let detail = try await services.lists.remove(titleID, from: listID(input.path.id), userID: currentUser())
        return .ok(.init(body: .json(.init(detail))))
    }

    func reorderList(_ input: Operations.ReorderList.Input) async throws -> Operations.ReorderList.Output {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let order = try body.titleIds.map { raw in
            guard let id = TitleID(uuidString: raw) else { throw AppError.badRequest("That title id is not valid.") }
            return id
        }
        let detail = try await services.lists.reorder(listID(input.path.id), to: order, userID: currentUser())
        return .ok(.init(body: .json(.init(detail))))
    }

    // MARK: Shelves

    func listShelves(_: Operations.ListShelves.Input) async throws -> Operations.ListShelves.Output {
        try await .ok(.init(body: .json(.init(items: services.shelves.shelves(userID: currentUser())
                .map { .init($0) }))))
    }

    func createShelf(_ input: Operations.CreateShelf.Input) async throws -> Operations.CreateShelf.Output {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let shelf = try await services.shelves.create(
            name: body.name, filter: LibraryFilter(body.filter), isPinned: body.isPinned ?? false, userID: currentUser()
        )
        return .ok(.init(body: .json(.init(shelf))))
    }

    func updateShelf(_ input: Operations.UpdateShelf.Input) async throws -> Operations.UpdateShelf.Output {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let shelf = try await services.shelves.update(
            shelfID(input.path.id), userID: currentUser(), name: body.name,
            filter: body.filter.map(LibraryFilter.init), isPinned: body.isPinned
        )
        return .ok(.init(body: .json(.init(shelf))))
    }

    func deleteShelf(_ input: Operations.DeleteShelf.Input) async throws -> Operations.DeleteShelf.Output {
        try await services.shelves.delete(shelfID(input.path.id), userID: currentUser())
        return .noContent(.init())
    }

    func listShelfItems(_ input: Operations.ListShelfItems.Input) async throws -> Operations.ListShelfItems.Output {
        let page = try await services.shelves.items(
            shelfID(input.path.id), userID: currentUser(), cursor: input.query.cursor, limit: input.query.limit ?? 50
        )
        return .ok(.init(body: .json(.init(
            items: page.entries.map(Components.Schemas.LibraryEntry.init),
            page: .init(nextCursor: page.next)
        ))))
    }

    private func listID(_ raw: String) throws -> ListID {
        guard let id = ListID(uuidString: raw) else { throw AppError.notFound("No such list.") }
        return id
    }

    private func shelfID(_ raw: String) throws -> UUID {
        guard let id = UUID(uuidString: raw) else { throw AppError.notFound("No such shelf.") }
        return id
    }
}

extension Components.Schemas.ListDetail {
    init(_ detail: ListDetail) {
        self.init(
            id: detail.list.id.description,
            name: detail.list.name,
            titles: detail.titles.map(Components.Schemas.TitleSummary.init),
            createdAt: detail.list.createdAt,
            updatedAt: detail.list.updatedAt
        )
    }
}

extension LibraryFilter {
    init(_ dto: Components.Schemas.ShelfFilter) {
        self.init(
            type: dto._type.map(MediaType.init),
            isAnime: dto.anime,
            status: dto.status.map(LibraryStatus.init),
            isOwned: dto.owned,
            listID: dto.list.flatMap(ListID.init(uuidString:))
        )
    }
}

extension Components.Schemas.Shelf {
    init(_ shelf: Shelf) {
        let filter = shelf.filter
        self.init(
            id: shelf.id.uuidString,
            name: shelf.name,
            filter: .init(
                _type: filter.type.map(Components.Schemas.MediaType.init),
                anime: filter.isAnime,
                status: filter.status.map(Components.Schemas.LibraryStatus.init),
                owned: filter.isOwned,
                list: filter.listID?.description
            ),
            isPinned: shelf.isPinned
        )
    }
}
