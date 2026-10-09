import AaruCore
import FluentKit
import FluentSQL
import Foundation

/// Library reads: entries with their title and derived show progress, sync, journal.
extension PostgresLibraryStore {
    func item(id: LibraryItemID, userID: UserID) async throws -> LibraryItem? {
        try await entry(id: id, userID: userID, now: Date())?.item
    }

    func item(userID: UserID, titleID: TitleID) async throws -> LibraryItem? {
        let rows = try await entryRows(
            userID: userID, now: Date(), extra: "AND li.title_id = \(bind: titleID.rawValue)", limit: 1
        )
        return rows.first?.entry(userID)?.item
    }

    func entry(id: LibraryItemID, userID: UserID, now: Date) async throws -> LibraryEntry? {
        try await entryRows(userID: userID, now: now, extra: "AND li.id = \(bind: id.rawValue)", limit: 1)
            .first?.entry(userID)
    }

    func entries(
        userID: UserID,
        filter: LibraryFilter,
        after: LibraryCursor?,
        limit: Int,
        now: Date
    ) async throws -> (entries: [LibraryEntry], next: LibraryCursor?) {
        var extra: SQLQueryString = ""
        if let type = filter.type {
            extra += " AND t.type = \(bind: type.rawValue)"
        }
        if let anime = filter.isAnime {
            extra += " AND t.is_anime = \(bind: anime)"
        }
        if let status = filter.status {
            extra += " AND li.status = \(bind: status.rawValue)"
        }
        if let owned = filter.isOwned {
            extra += " AND li.is_owned = \(bind: owned)"
        }
        if let list = filter.listID {
            extra += """
             AND EXISTS (SELECT 1 FROM list_items lst JOIN lists l ON l.id = lst.list_id
                WHERE lst.list_id = \(bind: list.rawValue) AND l.user_id = li.user_id AND lst.title_id = li.title_id)
            """
        }
        if let after {
            extra += """
             AND (li.updated_at, li.id) <
                ('epoch'::timestamptz + \(bind: after.updatedAtMicros) * interval '1 microsecond', \
            \(bind: after.id))
            """
        }
        let rows = try await entryRows(userID: userID, now: now, extra: extra, limit: limit + 1)
        let page = rows.prefix(limit)
        let next = rows.count > limit ? page.last
            .map { LibraryCursor(updatedAtMicros: $0.updatedMicros, id: $0.id) } : nil
        return (page.compactMap { $0.entry(userID) }, next)
    }

    func changes(
        userID: UserID,
        since: Date?,
        now: Date
    ) async throws -> (entries: [LibraryEntry], deleted: [LibraryItemID]) {
        struct Tombstone: Decodable { let libraryItemId: UUID }
        guard let since else {
            return try await (
                entryRows(userID: userID, now: now, extra: "", limit: 100_000).compactMap { $0.entry(userID) },
                []
            )
        }
        let changed = try await entryRows(
            userID: userID,
            now: now,
            extra: " AND li.updated_at > \(bind: since)",
            limit: 100_000
        )
        let deleted = try await sqlDatabase(database).raw("""
        SELECT library_item_id FROM library_tombstones
        WHERE user_id = \(bind: userID.rawValue) AND deleted_at > \(bind: since)
        """).all(decoding: Tombstone.self, keyDecodingStrategy: .convertFromSnakeCase)
        return (changed.compactMap { $0.entry(userID) }, deleted.map { LibraryItemID($0.libraryItemId) })
    }

    func watched(itemID: LibraryItemID) async throws -> Set<EpisodeKey> {
        try await Self.watchedKeys(itemID, sql: sqlDatabase(database))
    }

    func actions(userID: UserID, limit: Int) async throws -> [ActionRecord] {
        struct Row: Decodable {
            let id: UUID
            let actor: String
            let kind: String
            let summary: String
            let itemIds: [UUID]
            let createdAt: Date
            let undoneAt: Date?
            let undoOf: UUID?
        }
        return try await sqlDatabase(database).raw("""
        SELECT id, actor, kind, summary, item_ids, created_at, undone_at, undo_of FROM actions
        WHERE user_id = \(bind: userID.rawValue)
        ORDER BY created_at DESC, id DESC LIMIT \(literal: max(1, min(limit, 100)))
        """).all(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase).map {
            ActionRecord(
                id: $0.id, actor: Actor(rawValue: $0.actor) ?? .user, kind: $0.kind, summary: $0.summary,
                itemIDs: $0.itemIds.map(LibraryItemID.init), createdAt: $0.createdAt, undoneAt: $0.undoneAt,
                undoOf: $0.undoOf
            )
        }
    }

    /// One query for a page of entries with title and show progress (PROG-003: no N+1).
    private func entryRows(userID: UserID, now: Date, extra: SQLQueryString, limit: Int) async throws -> [EntryRow] {
        let aired: SQLQueryString = """
        (se.airs_at <= \(bind: now) OR (se.airs_at IS NULL AND t.status IN ('ended', 'canceled')))
        """
        let query: SQLQueryString = """
        SELECT li.id, li.title_id, li.status, li.rating, li.notes, li.is_owned, li.added_at, li.updated_at,
            li.finished_at, li.book_page, li.book_percent,
            (extract(epoch FROM li.updated_at) * 1000000)::bigint AS updated_micros,
            t.type, t.title, t.original_title, t.year, t.synopsis, t.poster_url, t.is_anime,
            t.tmdb, t.imdb, t.trakt, t.tvdb, t.isbn, t.open_library, t.anilist, t.mal, t.anidb,
            (SELECT count(*)::int FROM episode_progress ep WHERE ep.library_item_id = li.id AND ep.season > 0)
                AS watched_count,
            (SELECT count(*)::int FROM show_episodes se WHERE se.title_id = li.title_id AND se.season > 0
                AND \(aired)) AS aired_count,
            next.season AS next_season, next.episode AS next_episode
        FROM library_items li
        JOIN titles t ON t.id = li.title_id
        LEFT JOIN LATERAL (
            SELECT se.season, se.episode FROM show_episodes se
            WHERE se.title_id = li.title_id AND se.season > 0 AND \(aired)
              AND NOT EXISTS (SELECT 1 FROM episode_progress ep WHERE ep.library_item_id = li.id
                              AND ep.season = se.season AND ep.episode = se.episode)
            ORDER BY se.season, se.episode LIMIT 1
        ) next ON t.type = 'show'
        WHERE li.user_id = \(bind: userID.rawValue)
        """ + " " + extra + " ORDER BY li.updated_at DESC, li.id DESC LIMIT \(literal: limit)"
        return try await sqlDatabase(database).raw(query)
            .all(decoding: EntryRow.self, keyDecodingStrategy: .convertFromSnakeCase)
    }
}

private struct EntryRow: Decodable {
    let id: UUID
    let titleId: UUID
    let status: String
    let rating: Double?
    let notes: String?
    let isOwned: Bool
    let addedAt: Date
    let updatedAt: Date
    let finishedAt: Date?
    let bookPage: Int?
    let bookPercent: Double?
    let updatedMicros: Int64
    let type: String
    let title: String
    let originalTitle: String?
    let year: Int?
    let synopsis: String?
    let posterUrl: String?
    let isAnime: Bool
    let tmdb, imdb, trakt, tvdb, isbn, openLibrary, anilist, mal, anidb: String?
    let watchedCount: Int
    let airedCount: Int
    let nextSeason: Int?
    let nextEpisode: Int?

    func entry(_ userID: UserID) -> LibraryEntry? {
        guard let status = LibraryStatus(rawValue: status), let type = MediaType(rawValue: type) else { return nil }
        let item = LibraryItem(
            id: LibraryItemID(id),
            userID: userID,
            titleID: TitleID(titleId),
            status: status,
            isOwned: isOwned,
            rating: rating.flatMap { try? Rating($0) },
            notes: notes,
            addedAt: addedAt,
            updatedAt: updatedAt,
            finishedAt: finishedAt
        )
        let title = Title(
            id: TitleID(titleId), type: type, title: self.title, originalTitle: originalTitle, year: year,
            synopsis: synopsis, posterURL: posterUrl.flatMap(URL.init(string:)),
            ids: ExternalIDs(
                tmdb: tmdb, imdb: imdb, trakt: trakt, tvdb: tvdb, isbn: isbn,
                openLibrary: openLibrary, anilist: anilist, mal: mal, anidb: anidb
            ),
            isAnime: isAnime
        )
        let next = zip(nextSeason, nextEpisode).flatMap { try? EpisodeKey(season: $0, episode: $1) }
        return LibraryEntry(
            item: item,
            title: title,
            bookProgress: type == .book ? (bookPage, bookPercent) : nil,
            progress: type == .show ? ProgressSummary(
                watchedCount: watchedCount,
                airedCount: airedCount,
                nextEpisode: next
            )
                : nil
        )
    }
}

private func zip<A, B>(_ lhs: A?, _ rhs: B?) -> (A, B)? {
    guard let lhs, let rhs else { return nil }
    return (lhs, rhs)
}
