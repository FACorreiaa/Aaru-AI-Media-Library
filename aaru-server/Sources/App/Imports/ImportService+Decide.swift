import AaruCore
import Foundation

/// What an import does to one title (IMP-004). It never overwrites: it fills an empty rating,
/// finish date or notes, sets owned but never clears it (IMP-020), adds missing ticks, and moves
/// a status forward (wishlist → in progress → finished), never backward, never out of dropped,
/// never past a status the user chose.
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

    /// `item` is the user's item for the title as `importStates` read it, nil when they have none.
    static func decide(_ row: ImportRow, item: ImportItemState?) -> Decision {
        guard let item else {
            let status = row.status ?? (row.hasProgress ? .inProgress : .wishlist)
            let isManga = row.type == .manga
            let fields = ItemFields(
                status: status, rating: Self.rating(row.rating), notes: row.notes, isOwned: row.isOwned == true,
                finishedAt: status == .finished ? row.finishedAt : nil, bookPage: nil, bookPercent: nil,
                mangaChapter: isManga ? row.mangaChapter : nil, mangaVolume: isManga ? row.mangaVolume : nil
            )
            return Decision(outcome: .create, fields: fields, watch: row.watched ?? [])
        }
        var fields = item.fields
        let moved = promote(&fields, by: row, byHand: item.statusByHand)
        var filled: [String] = []
        if fields.rating == nil, let rating = Self.rating(row.rating) {
            fields.rating = rating
            filled.append("rating")
        }
        if fields.finishedAt == nil, fields.status == .finished, let finished = row.finishedAt {
            fields.finishedAt = finished
            filled.append("finish date")
        }
        if fields.notes?.nilIfBlank == nil, let notes = row.notes {
            fields.notes = notes
            filled.append("notes")
        }
        if !fields.isOwned, row.isOwned == true {
            fields.isOwned = true
            filled.append("owned mark")
        }
        if row.type == .manga {
            filled += forwardMangaProgress(&fields, by: row)
        }
        let fieldsChanged = moved != nil || !filled.isEmpty
        let missing = (row.watched ?? []).filter { !item.watched.contains($0) }.sorted()
        if !missing.isEmpty {
            filled.append(missing.count == 1 ? "1 watched episode" : "\(missing.count) watched episodes")
        }
        guard let reason = Self.reason(moved: moved, filled: filled, type: row.type) else {
            return Decision(outcome: .skip, reason: "Already on your shelf; nothing new to add.")
        }
        return Decision(
            outcome: .update, reason: reason, fields: fields, fieldsChanged: fieldsChanged, itemID: item.itemID,
            watch: missing
        )
    }

    /// Moves the status forward when the row is further along. Returns the new status, if any.
    private static func promote(_ fields: inout ItemFields, by row: ImportRow, byHand: Bool) -> LibraryStatus? {
        let incoming = row.status ?? (row.hasProgress ? .inProgress : nil)
        guard let incoming, fields.status != .dropped, incoming.importRank > fields.status.importRank, !byHand
        else { return nil }
        fields.status = incoming
        return incoming
    }

    /// A reading position only moves forward, like ticks are only added. Returns what it filled.
    private static func forwardMangaProgress(_ fields: inout ItemFields, by row: ImportRow) -> [String] {
        var filled: [String] = []
        if let chapter = row.mangaChapter, chapter > fields.mangaChapter ?? 0 {
            fields.mangaChapter = chapter
            filled.append("chapter \(chapter)")
        }
        if let volume = row.mangaVolume, volume > fields.mangaVolume ?? 0 {
            fields.mangaVolume = volume
            filled.append("volume \(volume)")
        }
        return filled
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
