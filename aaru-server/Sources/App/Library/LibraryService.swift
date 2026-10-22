import AaruCore
import Foundation

/// A partial update to a library item. Absent fields are left alone; `clear` names
/// fields to empty (JSON cannot tell "absent" from "null" through the generated types).
struct ItemPatch: Sendable {
    enum Clearable: String, Sendable {
        case rating, notes, bookProgress
    }

    var status: LibraryStatus?
    var rating: Double?
    var notes: String?
    var isOwned: Bool?
    var bookPage: Int?
    var bookPercent: Double?
    var clear: Set<Clearable> = []
}

/// Library rules (M4, M5). Handlers call this; every write becomes a journaled
/// `LibraryOp` in `LibraryStore.apply`.
/// What a show's progress write needs: the item, its episodes, and the show's status.
struct ShowContext: Sendable {
    var entry: LibraryEntry
    var episodes: [CatalogEpisode]
    var status: TitleStatus?
}

/// PROG-005: the item after the whole show was marked watched, the action that did it (nil when
/// nothing changed), and how many episodes it ticked.
struct ShowWatched: Sendable {
    var entry: LibraryEntry
    var action: ActionRecord?
    var episodes: Int
}

/// One sync answer: what changed, what was deleted, and the token for next time.
struct SyncResult: Sendable {
    var entries: [LibraryEntry]
    var deleted: [LibraryItemID]
    var token: String
}

struct LibraryService: Sendable {
    /// A sync token lags the server clock by this much, so a write whose transaction
    /// started before the sync and committed after it is still delivered next time.
    static let syncOverlap: TimeInterval = 5

    let stores: Stores
    let resolver: TitleResolver
    let catalog: CatalogService
    var now: @Sendable () -> Date = { Date() }

    // MARK: Items (LIB-001…003)

    /// Adds a title, or returns the existing item: posting the same `MediaRef` twice is
    /// idempotent, never a duplicate and never a 500 from the unique index.
    func add(
        _ ref: MediaRef,
        status: LibraryStatus?,
        userID: UserID,
        by caller: Caller = .user
    ) async throws -> LibraryEntry {
        let title = try await resolver.resolve(ref)
        if let existing = try await stores.library.item(userID: userID, titleID: title.id) {
            return try await entry(existing.id, userID: userID)
        }
        var write = prepareAdd(title, status: status, caller: caller)
        if title.type == .show, status == .finished, case var .insertItem(snapshot) = write.op {
            // PROG-005: added as watched means every aired episode, in the same one action.
            // An insert writes its ticks undated, like the whole-show mark.
            let detail = try await catalog.detail(title.id)
            snapshot.watched = (detail.episodes ?? []).filter {
                $0.season > 0 && Self.hasAired($0, titleStatus: detail.status, now: now())
            }.compactMap { try? EpisodeKey(season: $0.season, episode: $0.episode) }
            if snapshot.watched.isEmpty || !(detail.status == .ended || detail.status == .canceled) {
                snapshot.fields.status = snapshot.watched.isEmpty ? .wishlist : .inProgress
                snapshot.fields.finishedAt = nil
                snapshot.fields.statusByHand = false
            }
            write.op = .insertItem(snapshot)
            write.episodes = snapshot.watched.count
        }
        do {
            try await commit(write, userID: userID, caller: caller)
            if title.type == .show {
                // Fetch episodes now so the calendar and Up Next have them. Best effort:
                // a provider outage must not fail the add; the calendar retries.
                _ = try? await catalog.detail(title.id)
            }
            return try await entry(write.itemID, userID: userID)
        } catch is StoreConflict {
            guard let winner = try await stores.library.item(userID: userID, titleID: title.id)
            else { throw AppError.notFound() }
            return try await entry(winner.id, userID: userID)
        }
    }

    func entry(_ id: LibraryItemID, userID: UserID) async throws -> LibraryEntry {
        // Another user's item is 404, never 403: do not confirm it exists.
        guard let entry = try await stores.library.entry(id: id, userID: userID, now: now())
        else { throw AppError.notFound() }
        return entry
    }

    func list(
        userID: UserID,
        filter: LibraryFilter,
        cursor: String?,
        limit: Int
    ) async throws -> (entries: [LibraryEntry], next: String?) {
        let after: LibraryCursor?
        if let cursor {
            guard let parsed = LibraryCursor(token: cursor) else {
                throw AppError(status: .badRequest, code: "bad_request", message: "That cursor is not valid.")
            }
            after = parsed
        } else {
            after = nil
        }
        let page = try await stores.library.entries(
            userID: userID, filter: filter, after: after, limit: max(1, min(limit, 200)), now: now()
        )
        return (page.entries, page.next?.token)
    }

    func patch(
        _ id: LibraryItemID,
        userID: UserID,
        patch: ItemPatch,
        by caller: Caller = .user
    ) async throws -> LibraryEntry {
        let current = try await entry(id, userID: userID)
        if current.title.type == .show, patch.status == .finished, current.fields.status != .finished {
            // PROG-005: a show set to watched by hand is the whole show watched.
            let show = try await showContext(id, userID: userID)
            guard let write = try await prepareShowWatched(show, patch: patch, caller: caller) else { return current }
            try await commit(write, userID: userID, caller: caller)
            return try await entry(id, userID: userID)
        }
        guard let write = try preparePatch(current, patch: patch, caller: caller) else { return current }
        try await commit(write, userID: userID, caller: caller)
        return try await entry(id, userID: userID)
    }

    /// PROG-005: every aired episode of a show watched, as one undoable action. The action is nil
    /// when there was nothing left to tick; `episodes` is how many this ticked.
    func markShowWatched(_ id: LibraryItemID, userID: UserID, by caller: Caller = .user) async throws
        -> ShowWatched
    {
        let show = try await showContext(id, userID: userID)
        guard let write = try await prepareShowWatched(show, caller: caller) else {
            return ShowWatched(entry: show.entry, action: nil, episodes: 0)
        }
        let action = try await commit(write, userID: userID, caller: caller)
        return try await ShowWatched(entry: entry(id, userID: userID), action: action, episodes: write.episodes)
    }

    func delete(_ id: LibraryItemID, userID: UserID, by caller: Caller = .user) async throws {
        try await commit(prepareDelete(entry(id, userID: userID)), userID: userID, caller: caller)
    }

    // MARK: Sync (LIB-004)

    func sync(userID: UserID, token: String?) async throws -> SyncResult {
        let since: Date?
        if let token {
            guard let micros = Data(base64Encoded: token).flatMap({ String(bytes: $0, encoding: .utf8) })
                .flatMap(Int64.init)
            else { throw AppError(status: .badRequest, code: "bad_request", message: "That sync token is not valid.") }
            since = Date(timeIntervalSince1970: Double(micros) / 1_000_000)
        } else {
            since = nil
        }
        let next = now().addingTimeInterval(-Self.syncOverlap)
        let changes = try await stores.library.changes(userID: userID, since: since, now: now())
        let nextToken = Data(String(Int64(next.timeIntervalSince1970 * 1_000_000)).utf8).base64EncodedString()
        return SyncResult(entries: changes.entries, deleted: changes.deleted, token: nextToken)
    }

    // MARK: Progress (PROG-001…004)

    func setEpisode(
        _ id: LibraryItemID,
        userID: UserID,
        key: EpisodeKey,
        watched: Bool,
        by caller: Caller = .user
    ) async throws -> LibraryEntry {
        let show = try await showContext(id, userID: userID)
        guard show.episodes.contains(where: { $0.season == key.season && $0.episode == key.episode }) else {
            throw ValidationError.invalidEpisodeNumber(season: key.season, episode: key.episode)
        }
        let verb = watched ? "watched" : "unwatched"
        let write = try await prepareProgress(
            watch: watched ? [key] : [], unwatch: watched ? [] : [key], show: show,
            journal: ("episode", "Marked \(key) of \(show.entry.title.title) \(verb)")
        )
        try await commit(write, userID: userID, caller: caller)
        return try await entry(id, userID: userID)
    }

    /// Ticks or unticks several episodes of one show as one action, for outside callers
    /// (Stremio's player and library events). Episodes the show does not have are skipped, and
    /// episodes already in the asked state are left alone; with nothing left to change there is
    /// no write and no journal row, so a repeated event is a no-op. Returns nil when nothing changed.
    @discardableResult
    func setEpisodes(
        _ id: LibraryItemID,
        userID: UserID,
        keys: [EpisodeKey],
        watched: Bool,
        by caller: Caller
    ) async throws -> LibraryEntry? {
        let show = try await showContext(id, userID: userID)
        guard let write = try await prepareEpisodes(show, keys: keys, watched: watched) else { return nil }
        try await commit(write, userID: userID, caller: caller)
        return try await entry(id, userID: userID)
    }

    /// Marks every aired episode of a season watched in one action; unaired ones are left alone.
    func markSeasonWatched(_ id: LibraryItemID, userID: UserID, season: Int, by caller: Caller = .user) async throws
        -> LibraryEntry
    {
        let show = try await showContext(id, userID: userID)
        try await commit(prepareSeason(show, season: season), userID: userID, caller: caller)
        return try await entry(id, userID: userID)
    }

    func showContext(_ id: LibraryItemID, userID: UserID) async throws -> ShowContext {
        let current = try await entry(id, userID: userID)
        guard current.title.type == .show else {
            throw AppError(
                status: .unprocessableContent, code: "validation_failed",
                message: "Only shows have episodes.", details: ["episode": "Only shows have episodes."]
            )
        }
        // Hydrates episodes on first use (CAT-006), so a tick never races an empty list.
        let detail = try await catalog.detail(current.title.id)
        return ShowContext(entry: current, episodes: detail.episodes ?? [], status: detail.status)
    }

    static func hasAired(_ episode: CatalogEpisode, titleStatus: TitleStatus?, now: Date) -> Bool {
        if let airsAt = episode.airsAt {
            return airsAt <= now
        }
        return titleStatus == .ended || titleStatus == .canceled
    }

    func actions(userID: UserID, limit: Int) async throws -> [ActionRecord] {
        try await stores.library.actions(userID: userID, limit: limit)
    }

    func undo(_ actionID: UUID, userID: UserID) async throws -> ActionRecord {
        let undo = try await stores.library.undo(actionID: actionID, userID: userID)
        await GamificationService(stores: stores, now: now).afterUndo(
            userID: userID, undone: actionID, undoAction: undo.id
        )
        return undo
    }
}

/// Field validation and journal wording for `patch`.
extension LibraryService {
    /// PROG-004: page or percent, never both; each validated by `AaruCore.BookProgress`.
    func applyBookProgress(_ patch: ItemPatch, to fields: inout ItemFields, type: MediaType) throws {
        let touchesBook = patch.bookPage != nil || patch.bookPercent != nil || patch.clear.contains(.bookProgress)
        guard touchesBook else { return }
        guard type == .book else {
            throw AppError(
                status: .unprocessableContent, code: "validation_failed",
                message: "Only books have page progress.", details: ["progress": "Only books have page progress."]
            )
        }
        if patch.bookPage != nil, patch.bookPercent != nil {
            throw AppError(
                status: .unprocessableContent, code: "validation_failed",
                message: "Send a page or a percent, not both.",
                details: ["progress": "Send a page or a percent, not both."]
            )
        }
        if patch.clear.contains(.bookProgress) {
            fields.bookPage = nil
            fields.bookPercent = nil
        }
        if let page = patch.bookPage {
            _ = try BookProgress(page: page)
            fields.bookPage = page
            fields.bookPercent = nil
        }
        if let percent = patch.bookPercent {
            _ = try BookProgress(percent: percent)
            fields.bookPercent = percent
            fields.bookPage = nil
        }
    }

    static func updateSummary(current: LibraryEntry, fields: ItemFields) -> String {
        let name = current.title.title
        if fields.status != current.fields.status {
            return "Moved \(name) to \(fields.status.label(for: current.title.type))"
        }
        if fields.rating != current.fields.rating {
            return fields.rating.map { "Rated \(name) \(Rating.display($0))" } ?? "Cleared the rating on \(name)"
        }
        if fields.isOwned != current.fields.isOwned {
            return fields.isOwned ? "Marked \(name) owned" : "Marked \(name) not owned"
        }
        return "Updated \(name)"
    }

    // MARK: Journal (AUD-002)
}

extension LibraryEntry {
    var fields: ItemFields {
        ItemFields(
            status: item.status,
            rating: item.rating?.value,
            notes: item.notes,
            isOwned: item.isOwned,
            finishedAt: item.finishedAt,
            bookPage: bookProgress?.page,
            bookPercent: bookProgress?.percent
        )
    }
}

extension LibraryStatus {
    /// The status as people read it, per kind (APP-014). The stored value never changes:
    /// films, shows and anime read Plan to watch / Watching / Watched; books Plan to read /
    /// Reading / Read; albums Plan to listen / Listening / Listened (MUS-001).
    func label(for type: MediaType) -> String {
        switch (self, type) {
        case (.wishlist, .book): "Plan to read"
        case (.wishlist, .album): "Plan to listen"
        case (.wishlist, _): "Plan to watch"
        case (.inProgress, .book): "Reading"
        case (.inProgress, .album): "Listening"
        case (.inProgress, _): "Watching"
        case (.finished, .book): "Read"
        case (.finished, .album): "Listened"
        case (.finished, _): "Watched"
        case (.dropped, _): "Dropped"
        }
    }
}

extension Rating {
    static func display(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
