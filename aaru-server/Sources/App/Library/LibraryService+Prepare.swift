import AaruCore
import Foundation

/// A library write worked out against the current state but not applied. A tap commits it at
/// once; an agent's larger change stores it in a plan, and approval runs the same op (AG-003).
struct PreparedWrite: Sendable {
    var op: LibraryOp
    /// The journal's `kind` when committed alone.
    var kind: String
    /// What it does, without a caller's name: "Marked S01E01 of Andor watched".
    var summary: String
    /// The item it touches, or creates.
    var itemID: LibraryItemID
    var title: Title
    /// True when it creates the item, so a plan checks the title is still absent.
    var adds = false
    var episodes = 0
}

/// The dry-run half of every write. Each one reads, never writes.
extension LibraryService {
    func prepareAdd(_ title: Title, status: LibraryStatus?, caller: Caller) -> PreparedWrite {
        let status = status ?? .wishlist
        let snapshot = ItemSnapshot(
            id: LibraryItemID(),
            titleID: title.id,
            fields: ItemFields(
                status: status, isOwned: false, finishedAt: status == .finished ? now() : nil,
                // A wishlist add says nothing yet; an import may still move it forward.
                statusByHand: caller.actor == .user && status != .wishlist
            ),
            addedAt: now(),
            watched: []
        )
        return PreparedWrite(
            op: .insertItem(snapshot), kind: "add",
            summary: "Added \(title.title) to \(status.label(for: title.type))",
            itemID: snapshot.id, title: title, adds: true
        )
    }

    /// Nil when the patch changes nothing.
    func preparePatch(_ current: LibraryEntry, patch: ItemPatch, caller: Caller) throws -> PreparedWrite? {
        let fields = try patchedFields(current, patch: patch, caller: caller)
        guard fields != current.fields else { return nil }
        return PreparedWrite(
            op: .setFields(current.item.id, fields), kind: "update",
            summary: Self.updateSummary(current: current, fields: fields),
            itemID: current.item.id, title: current.title
        )
    }

    /// The item's fields with `patch` applied.
    func patchedFields(_ current: LibraryEntry, patch: ItemPatch, caller: Caller) throws -> ItemFields {
        var fields = current.fields
        if let status = patch.status, status != fields.status {
            fields.status = status
            fields.finishedAt = status == .finished ? now() : nil
            if caller.actor == .user {
                fields.statusByHand = true
            }
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
        return fields
    }

    func prepareDelete(_ current: LibraryEntry) -> PreparedWrite {
        PreparedWrite(
            op: .deleteItem(current.item.id), kind: "remove", summary: "Removed \(current.title.title)",
            itemID: current.item.id, title: current.title
        )
    }

    /// Episodes the show has and that are not already in the asked state; nil when none are.
    func prepareEpisodes(_ show: ShowContext, keys: [EpisodeKey], watched: Bool) async throws -> PreparedWrite? {
        let known = Set(show.episodes.compactMap { try? EpisodeKey(season: $0.season, episode: $0.episode) })
        let current = try await stores.library.watched(itemID: show.entry.item.id)
        let changing = Array(Set(keys)).filter { known.contains($0) && current.contains($0) != watched }
            .sorted { ($0.season, $0.episode) < ($1.season, $1.episode) }
        guard !changing.isEmpty else { return nil }
        let verb = watched ? "watched" : "unwatched"
        let what = changing.count == 1 ? "\(changing[0])" : "\(changing.count) episodes"
        return try await prepareProgress(
            watch: watched ? changing : [], unwatch: watched ? [] : changing, show: show,
            journal: ("episode", "Marked \(what) of \(show.entry.title.title) \(verb)")
        )
    }

    /// Every aired episode of a season; unaired ones are left alone.
    func prepareSeason(_ show: ShowContext, season: Int) async throws -> PreparedWrite {
        let inSeason = show.episodes.filter { $0.season == season }
        guard !inSeason.isEmpty else { throw ValidationError.invalidEpisodeNumber(season: season, episode: 1) }
        let aired = inSeason.filter { Self.hasAired($0, titleStatus: show.status, now: now()) }
            .compactMap { try? EpisodeKey(season: $0.season, episode: $0.episode) }
        let summary = "Marked season \(season) of \(show.entry.title.title) watched (\(aired.count) episodes)"
        return try await prepareProgress(watch: aired, unwatch: [], show: show, journal: ("season", summary))
    }

    /// PROG-005: the whole show watched, as one action. Every aired regular episode is ticked, with
    /// the watch date unknown (the journal kind "show" marks the ticks undated), and the status
    /// follows `prepareProgress`: an ended or canceled show finishes, a running one stays in
    /// progress, caught up. `patch` carries any other fields of the same tap (its status is the
    /// reason for this write and is not applied as such). Nil when nothing would change.
    func prepareShowWatched(_ show: ShowContext, patch: ItemPatch = ItemPatch(), caller: Caller) async throws
        -> PreparedWrite?
    {
        var rest = patch
        rest.status = nil
        var fields = try patchedFields(show.entry, patch: rest, caller: caller)
        let current = try await stores.library.watched(itemID: show.entry.item.id)
        let airedRegular = show.episodes.filter {
            $0.season > 0 && Self.hasAired($0, titleStatus: show.status, now: now())
        }
        let unwatched = airedRegular.compactMap { try? EpisodeKey(season: $0.season, episode: $0.episode) }
            .filter { !current.contains($0) }
        let finishes = !airedRegular.isEmpty && (show.status == .ended || show.status == .canceled)
        if finishes, fields.status != .finished, caller.actor == .user {
            fields.statusByHand = true
        }
        let summary = "Marked \(show.entry.title.title) watched (\(unwatched.count) episodes)"
        let write = try await prepareProgress(
            watch: unwatched, unwatch: [], show: show, fields: fields, journal: ("show", summary)
        )
        guard case let .batch(ops) = write.op, ops.count > 1 || !unwatched.isEmpty else { return nil }
        return write
    }

    /// An episode op together with the status it implies, as one action: the first tick moves
    /// wishlist → in progress; watching every aired episode of an ended or canceled show finishes
    /// it. A running show never auto-finishes.
    func prepareProgress(
        watch: [EpisodeKey],
        unwatch: [EpisodeKey],
        show: ShowContext,
        fields base: ItemFields? = nil,
        journal: (kind: String, summary: String)
    ) async throws -> PreparedWrite {
        let current = show.entry
        let id = current.item.id
        let titleStatus = show.status
        let op = LibraryOp.setEpisodes(id, watch: watch, unwatch: unwatch)
        var watched = try await stores.library.watched(itemID: id)
        watched.formUnion(watch)
        watched.subtract(unwatch)
        var fields = base ?? current.fields
        if fields.status == .wishlist, !watched.isEmpty {
            fields.status = .inProgress
        }
        let airedRegular = show.episodes.filter {
            $0.season > 0 && Self.hasAired($0, titleStatus: titleStatus, now: now())
        }
        let allWatched = !airedRegular.isEmpty && airedRegular.allSatisfy { episode in
            watched.contains { $0.season == episode.season && $0.episode == episode.episode }
        }
        if allWatched, titleStatus == .ended || titleStatus == .canceled, fields.status != .finished {
            fields.status = .finished
            fields.finishedAt = now()
        }
        let ops: [LibraryOp] = fields == current.fields ? [op] : [op, .setFields(id, fields)]
        return PreparedWrite(
            op: .batch(ops), kind: journal.kind, summary: journal.summary, itemID: id, title: current.title,
            episodes: watch.count + unwatch.count
        )
    }

    /// Applies one prepared write as one journaled action.
    @discardableResult
    func commit(_ write: PreparedWrite, userID: UserID, caller: Caller) async throws -> ActionRecord {
        let action = try await stores.library.apply(
            write.op, userID: userID, caller: caller, kind: write.kind, summary: caller.summary(write.summary)
        )
        await GamificationService(stores: stores, now: now).afterWrite(userID: userID, actionID: action.id)
        return action
    }
}
