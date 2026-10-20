import AaruCore
import Foundation

/// What an import does to one title (IMP-004). It never overwrites: it fills an empty rating or
/// finish date, adds missing ticks, and moves a status forward (wishlist → in progress →
/// finished), never backward, never out of dropped, never past a status the user chose.
extension ImportService {
    struct Decision {
        var outcome: ImportOutcome
        var reason: String?
        var fields: ItemFields?
        var fieldsChanged = false
        var itemID: LibraryItemID?
        /// Episodes to tick: all of them on create, only the missing ones on update.
        var watch: [EpisodeKey] = []
    }

    func decide(_ row: ImportRow, titleID: TitleID, userID: UserID) async throws -> Decision {
        guard let item = try await stores.library.item(userID: userID, titleID: titleID) else {
            let status = row.status ?? (row.watched?.isEmpty == false ? .inProgress : .wishlist)
            let fields = ItemFields(
                status: status, rating: Self.rating(row.rating), notes: nil, isOwned: false,
                finishedAt: status == .finished ? row.finishedAt : nil, bookPage: nil, bookPercent: nil
            )
            return Decision(outcome: .create, fields: fields, watch: row.watched ?? [])
        }
        guard let entry = try await stores.library.entry(id: item.id, userID: userID, now: now()) else {
            return Decision(outcome: .skip, reason: "Already on your shelf.")
        }
        var fields = ItemFields(
            status: item.status, rating: item.rating?.value, notes: item.notes, isOwned: item.isOwned,
            finishedAt: item.finishedAt, bookPage: entry.bookProgress?.page, bookPercent: entry.bookProgress?.percent
        )
        let moved = try await promote(&fields, by: row, itemID: item.id)
        var filled: [String] = []
        if fields.rating == nil, let rating = Self.rating(row.rating) {
            fields.rating = rating
            filled.append("rating")
        }
        if fields.finishedAt == nil, fields.status == .finished, let finished = row.finishedAt {
            fields.finishedAt = finished
            filled.append("finish date")
        }
        let fieldsChanged = moved != nil || !filled.isEmpty
        let ticked = try await stores.library.watched(itemID: item.id)
        let missing = (row.watched ?? []).filter { !ticked.contains($0) }.sorted()
        if !missing.isEmpty {
            filled.append(missing.count == 1 ? "1 watched episode" : "\(missing.count) watched episodes")
        }
        guard let reason = Self.reason(moved: moved, filled: filled, type: row.type) else {
            return Decision(outcome: .skip, reason: "Already on your shelf; nothing new to add.")
        }
        return Decision(
            outcome: .update, reason: reason, fields: fields, fieldsChanged: fieldsChanged, itemID: item.id,
            watch: missing
        )
    }

    /// Moves the status forward when the row is further along. Returns the new status, if any.
    private func promote(_ fields: inout ItemFields, by row: ImportRow, itemID: LibraryItemID) async throws
        -> LibraryStatus?
    {
        let incoming = row.status ?? (row.watched?.isEmpty == false ? .inProgress : nil)
        guard let incoming, fields.status != .dropped, incoming.importRank > fields.status.importRank,
              try await !stores.library.statusSetByHand(itemID: itemID)
        else { return nil }
        fields.status = incoming
        return incoming
    }

    private static func reason(moved: LibraryStatus?, filled: [String], type: MediaType) -> String? {
        let adds = filled.isEmpty ? nil : "adds the \(filled.joined(separator: " and "))"
        switch (moved, adds) {
        case let (status?, adds?): return "Moves it to \(status.label(for: type)) and \(adds)."
        case let (status?, nil): return "Moves it to \(status.label(for: type))."
        case let (nil, adds?): return "A\(adds.dropFirst())."
        case (nil, nil): return nil
        }
    }
}
