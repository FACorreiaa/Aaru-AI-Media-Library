import AaruCore

extension LibraryService {
    /// LIB-006: the page for a title the user may not have. Resolving fills the catalog (a
    /// provider row becomes a `titles` row, as an add would) and writes nothing to the library.
    func preview(_ ref: MediaRef, userID: UserID) async throws -> (TitleDetail, LibraryItemID?) {
        let title = try await resolver.resolve(ref)
        async let detail = catalog.detail(title.id)
        let item = try await stores.library.item(userID: userID, titleID: title.id)
        return try await (detail, item?.id)
    }
}
