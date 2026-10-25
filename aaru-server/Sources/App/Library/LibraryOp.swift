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
    /// MNG-001: the last chapter and volume read.
    var mangaChapter: Int?
    var mangaVolume: Int?
    /// The user chose this status themselves, so an import never moves it. `nil` leaves the
    /// stored flag as it is; inverses carry the stored value, so undo restores it.
    var statusByHand: Bool?
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
    case insertList(ListSnapshot)
    case deleteList(ListID)
    case renameList(ListID, String)
    /// The list's full ordered membership: add, remove, and reorder are all this.
    case setListMembers(ListID, [TitleID])
    case batch([LibraryOp])
}

/// Everything needed to recreate a deleted list.
struct ListSnapshot: Codable, Sendable, Equatable {
    var id: ListID
    var name: String
    var createdAt: Date
    var members: [TitleID]
}

/// Who made a write. The ribbon shows it; external agents arrive with M14.
enum Actor: String, Codable, Sendable {
    case user
    case agent
    case externalAgent = "external_agent"
}

/// Who made a write and, for an outside caller, through which agent token (OUT-002). Its
/// name prefixes the journal summary, so the ribbon says "Stremio: marked S1E2 … watched".
struct Caller: Sendable, Equatable {
    var actor: Actor
    var agentTokenID: UUID?
    var agentName: String?
    /// The write came from a player (Stremio or the browser extension): it earns the scrobble
    /// bonus on top (GAM-001).
    var scrobbled = false

    static let user = Caller(actor: .user)

    static func agent(_ token: AgentToken) -> Caller {
        let group = token.kind.group
        return Caller(
            actor: .externalAgent, agentTokenID: token.id, agentName: token.name,
            scrobbled: group == .stremio || group == .scrobble
        )
    }

    func summary(_ text: String) -> String {
        agentName.map { "\($0): \(text.prefix(1).lowercased())\(text.dropFirst())" } ?? text
    }
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
    /// The agent token that made it, by its name at read time; nil for the user's own writes.
    var agentName: String?
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
    /// Manga only (MNG-001).
    var mangaProgress: (chapter: Int?, volume: Int?)?
    /// The newest episode tick made live in Aaru; imported, pulled and restored ticks do not count
    /// (`episode_progress.watched_at_known`).
    var lastWatchedAt: Date?
    /// The status was chosen by a tap, not an import (`library_items.status_by_hand`).
    var statusByHand = false

    /// APP-018 · an anime in progress the user never touched in Aaru: an imported status and no
    /// live tick. Derived, never stored, never a status; Library's Now leaves it out of Watching.
    var inBacklog: Bool {
        title.isAnime && item.status == .inProgress && !statusByHand && lastWatchedAt == nil
    }

    static func == (lhs: LibraryEntry, rhs: LibraryEntry) -> Bool {
        lhs.item == rhs.item && lhs.title == rhs.title && lhs.progress == rhs.progress
            && lhs.lastWatchedAt == rhs.lastWatchedAt && lhs.statusByHand == rhs.statusByHand
            && lhs.bookProgress?.page == rhs.bookProgress?.page
            && lhs.bookProgress?.percent == rhs.bookProgress?.percent
            && lhs.mangaProgress?.chapter == rhs.mangaProgress?.chapter
            && lhs.mangaProgress?.volume == rhs.mangaProgress?.volume
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
