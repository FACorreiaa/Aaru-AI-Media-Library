import AaruCore
import Foundation

/// A PATCH: the item after it, and the action Undo takes back (nil when nothing changed).
struct ItemWrite: Sendable {
    var entry: LibraryEntry
    var action: ActionRecord?
}

extension LibraryService {
    /// `patch`, with the action it made, so the caller can offer Undo.
    func patchWrite(
        _ id: LibraryItemID,
        userID: UserID,
        patch: ItemPatch,
        by caller: Caller = .user
    ) async throws -> ItemWrite {
        let current = try await entry(id, userID: userID)
        // PROG-005: a show set to watched by hand is the whole show watched.
        let wholeShow = current.title.type == .show && patch.status == .finished
            && current.fields.status != .finished
        let prepared = try await wholeShow
            ? prepareShowWatched(showContext(id, userID: userID), patch: patch, caller: caller)
            : preparePatch(current, patch: patch, caller: caller)
        guard let write = prepared else { return ItemWrite(entry: current, action: nil) }
        let action = try await commit(write, userID: userID, caller: caller)
        return try await ItemWrite(entry: entry(id, userID: userID), action: action)
    }
}
