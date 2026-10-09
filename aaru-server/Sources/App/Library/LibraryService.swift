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
    func add(_ ref: MediaRef, status: LibraryStatus?, userID: UserID) async throws -> LibraryEntry {
        let title = try await resolver.resolve(ref)
        if let existing = try await stores.library.item(userID: userID, titleID: title.id) {
            return try await entry(existing.id, userID: userID)
        }
        let status = status ?? .wishlist
        let snapshot = ItemSnapshot(
            id: LibraryItemID(),
            titleID: title.id,
            fields: ItemFields(status: status, isOwned: false, finishedAt: status == .finished ? now() : nil),
            addedAt: now(),
            watched: []
        )
        do {
            try await stores.library.apply(
                .insertItem(snapshot), userID: userID, actor: .user, kind: "add",
                summary: "Added \(title.title) to \(status.label)"
            )
            if title.type == .show {
                // Fetch episodes now so the calendar and Up Next have them. Best effort:
                // a provider outage must not fail the add; the calendar retries.
                _ = try? await catalog.detail(title.id)
            }
            return try await entry(snapshot.id, userID: userID)
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

    func patch(_ id: LibraryItemID, userID: UserID, patch: ItemPatch) async throws -> LibraryEntry {
        let current = try await entry(id, userID: userID)
        var fields = current.fields
        if let status = patch.status, status != fields.status {
            fields.status = status
            fields.finishedAt = status == .finished ? now() : nil
        }
        if patch.clear.contains(.rating) {
            fields.rating = nil
        } else if let rating = patch.rating {
            fields.rating = try Rating(rating).value
        }
        if patch.clear.contains(.notes) {
            fields.notes = nil
        } else if let notes = patch.notes {
            fields.notes = notes.nilIfBlank
        }
        if let owned = patch.isOwned {
            fields.isOwned = owned
        }
        try applyBookProgress(patch, to: &fields, type: current.title.type)
        guard fields != current.fields else { return current }
        try await stores.library.apply(
            .setFields(id, fields), userID: userID, actor: .user, kind: "update",
            summary: Self.updateSummary(current: current, fields: fields)
        )
        return try await entry(id, userID: userID)
    }

    func delete(_ id: LibraryItemID, userID: UserID) async throws {
        let current = try await entry(id, userID: userID)
        try await stores.library.apply(
            .deleteItem(id), userID: userID, actor: .user, kind: "remove",
            summary: "Removed \(current.title.title)"
        )
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
        watched: Bool
    ) async throws -> LibraryEntry {
        let show = try await showContext(id, userID: userID)
        guard show.episodes.contains(where: { $0.season == key.season && $0.episode == key.episode }) else {
            throw ValidationError.invalidEpisodeNumber(season: key.season, episode: key.episode)
        }
        let verb = watched ? "watched" : "unwatched"
        return try await applyProgress(
            watch: watched ? [key] : [], unwatch: watched ? [] : [key], show: show, userID: userID,
            journal: ("episode", "Marked \(key) of \(show.entry.title.title) \(verb)")
        )
    }

    /// Marks every aired episode of a season watched in one action; unaired ones are left alone.
    func markSeasonWatched(_ id: LibraryItemID, userID: UserID, season: Int) async throws -> LibraryEntry {
        let show = try await showContext(id, userID: userID)
        let inSeason = show.episodes.filter { $0.season == season }
        guard !inSeason.isEmpty else { throw ValidationError.invalidEpisodeNumber(season: season, episode: 1) }
        let aired = inSeason.filter { Self.hasAired($0, titleStatus: show.status, now: now()) }
            .compactMap { try? EpisodeKey(season: $0.season, episode: $0.episode) }
        let summary = "Marked season \(season) of \(show.entry.title.title) watched (\(aired.count) episodes)"
        return try await applyProgress(
            watch: aired, unwatch: [], show: show, userID: userID, journal: ("season", summary)
        )
    }

    /// Applies an episode op together with the status it implies, as one action:
    /// the first tick moves wishlist → in progress; watching every aired episode of an
    /// ended or canceled show finishes it. A running show never auto-finishes.
    private func applyProgress(
        watch: [EpisodeKey],
        unwatch: [EpisodeKey],
        show: ShowContext,
        userID: UserID,
        journal: (kind: String, summary: String)
    ) async throws -> LibraryEntry {
        let current = show.entry
        let id = current.item.id
        let titleStatus = show.status
        let op = LibraryOp.setEpisodes(id, watch: watch, unwatch: unwatch)
        var watched = try await stores.library.watched(itemID: id)
        watched.formUnion(watch)
        watched.subtract(unwatch)
        var fields = current.fields
        if fields.status == .wishlist, !watched.isEmpty {
            fields.status = .inProgress
        }
        let airedRegular = show.episodes.filter { $0.season > 0 && Self.hasAired(
            $0,
            titleStatus: titleStatus,
            now: now()
        ) }
        let allWatched = !airedRegular.isEmpty && airedRegular.allSatisfy { episode in
            watched.contains { $0.season == episode.season && $0.episode == episode.episode }
        }
        if allWatched, titleStatus == .ended || titleStatus == .canceled, fields.status != .finished {
            fields.status = .finished
            fields.finishedAt = now()
        }
        let ops: [LibraryOp] = fields == current.fields ? [op] : [op, .setFields(id, fields)]
        try await stores.library.apply(
            .batch(ops), userID: userID, actor: .user, kind: journal.kind, summary: journal.summary
        )
        return try await entry(id, userID: userID)
    }

    private func showContext(_ id: LibraryItemID, userID: UserID) async throws -> ShowContext {
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

    /// PROG-004: page or percent, never both; each validated by `AaruCore.BookProgress`.
    private func applyBookProgress(_ patch: ItemPatch, to fields: inout ItemFields, type: MediaType) throws {
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

    private static func updateSummary(current: LibraryEntry, fields: ItemFields) -> String {
        let name = current.title.title
        if fields.status != current.fields.status {
            return "Moved \(name) to \(fields.status.label)"
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

    func actions(userID: UserID, limit: Int) async throws -> [ActionRecord] {
        try await stores.library.actions(userID: userID, limit: limit)
    }

    func undo(_ actionID: UUID, userID: UserID) async throws -> ActionRecord {
        try await stores.library.undo(actionID: actionID, userID: userID)
    }
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
    var label: String {
        switch self {
        case .wishlist: "Wishlist"
        case .inProgress: "In progress"
        case .finished: "Finished"
        case .dropped: "Dropped"
        }
    }
}

extension Rating {
    static func display(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
