import AaruCore
import Foundation

/// The user-editable fields of a library item. Episode progress is separate.
struct ItemFields: Codable, Sendable, Equatable {
    var status: LibraryStatus
    var rating: Double?
    var notes: String?
    var isOwned: Bool
    var finishedAt: Date?
    var bookPage: Int?
    var bookPercent: Double?
}

/// Everything needed to recreate a deleted item, including its episode ticks.
struct ItemSnapshot: Codable, Sendable, Equatable {
    var id: LibraryItemID
    var titleID: TitleID
    var fields: ItemFields
    var addedAt: Date
    var watched: [EpisodeKey]
}

/// One primitive library write. Applying an op returns its exact inverse, which the
/// journal stores (AUD-001) and undo applies (AUD-002). Every mutating library path —
/// a tap, an agent call, an undo — is expressed as ops, so nothing writes without an
/// inverse (X-007).
indirect enum LibraryOp: Codable, Sendable, Equatable {
    case insertItem(ItemSnapshot)
    case deleteItem(LibraryItemID)
    case setFields(LibraryItemID, ItemFields)
    case setEpisodes(LibraryItemID, watch: [EpisodeKey], unwatch: [EpisodeKey])
    case batch([LibraryOp])
}

/// Who made a write. The ribbon shows it; external agents arrive with M14.
enum Actor: String, Codable, Sendable {
    case user
    case agent
    case externalAgent = "external_agent"
}

/// One row of the action journal, as the ribbon reads it.
struct ActionRecord: Sendable, Equatable {
    var id: UUID
    var actor: Actor
    var kind: String
    var summary: String
    var itemIDs: [LibraryItemID]
    var createdAt: Date
    var undoneAt: Date?
    var undoOf: UUID?
}

/// An action cannot be undone (twice, or its target changed out from under it).
struct ActionConflict: Error, Equatable {
    let message: String
}

/// A library item with the title it points at and, for shows, derived progress.
struct LibraryEntry: Sendable, Equatable {
    var item: LibraryItem
    var title: Title
    var bookProgress: (page: Int?, percent: Double?)?
    var progress: ProgressSummary?

    static func == (lhs: LibraryEntry, rhs: LibraryEntry) -> Bool {
        lhs.item == rhs.item && lhs.title == rhs.title && lhs.progress == rhs.progress
            && lhs.bookProgress?.page == rhs.bookProgress?.page
            && lhs.bookProgress?.percent == rhs.bookProgress?.percent
    }
}

/// PROG-003: counts exclude specials (season 0). `aired` counts episodes whose air time
/// has passed, plus undated episodes of an ended or canceled show.
struct ProgressSummary: Sendable, Equatable {
    var watchedCount: Int
    var airedCount: Int
    var nextEpisode: EpisodeKey?
}

/// The filter grammar `GET /v1/library/items` accepts. Shelves store exactly this.
struct LibraryFilter: Codable, Sendable, Equatable {
    var type: MediaType?
    var isAnime: Bool?
    var status: LibraryStatus?
    var isOwned: Bool?
    var listID: ListID?
}

/// Keyset cursor over `(updated_at, id)` descending.
struct LibraryCursor: Sendable, Equatable {
    var updatedAtMicros: Int64
    var id: UUID

    var token: String {
        Data("\(updatedAtMicros)|\(id.uuidString)".utf8).base64EncodedString()
    }

    init(updatedAtMicros: Int64, id: UUID) {
        self.updatedAtMicros = updatedAtMicros
        self.id = id
    }

    init?(token: String) {
        guard let data = Data(base64Encoded: token), let text = String(bytes: data, encoding: .utf8) else { return nil }
        let parts = text.split(separator: "|")
        guard parts.count == 2, let micros = Int64(parts[0]),
              let id = UUID(uuidString: String(parts[1])) else { return nil }
        self.init(updatedAtMicros: micros, id: id)
    }
}
