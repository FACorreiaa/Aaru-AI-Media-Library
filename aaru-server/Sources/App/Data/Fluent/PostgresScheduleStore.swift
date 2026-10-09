import AaruCore
import FluentKit
import FluentSQL
import Foundation

/// Calendar and Up Next reads. Each is one query: no per-show round trips.
struct PostgresScheduleStore: ScheduleStore {
    let sql: any SQLDatabase

    /// Title columns every query here selects, decoded by `TitleColumns`.
    private static let titleColumns: SQLQueryString = """
    t.id AS title_id, t.type, t.title, t.original_title, t.year, t.synopsis, t.poster_url, t.is_anime,
    t.tmdb, t.imdb, t.trakt, t.tvdb, t.isbn, t.open_library, t.anilist, t.mal, t.anidb
    """

    /// The same "aired" rule as library progress (PROG-003).
    private static func aired(_ now: Date) -> SQLQueryString {
        "(se.airs_at <= \(bind: now) OR (se.airs_at IS NULL AND t.status IN ('ended', 'canceled')))"
    }

    private static let unwatched: SQLQueryString = """
    NOT EXISTS (SELECT 1 FROM episode_progress ep WHERE ep.library_item_id = li.id
                AND ep.season = se.season AND ep.episode = se.episode)
    """

    func calendar(userID: UserID, from: Date, until: Date, now _: Date) async throws -> [CalendarEntry] {
        let query: SQLQueryString = """
        SELECT li.id AS item_id, \(Self.titleColumns), se.season, se.episode, se.name, se.airs_at, se.runtime_minutes,
            NOT \(Self.unwatched) AS watched,
            (SELECT max(s2.episode) FROM show_episodes s2 WHERE s2.title_id = se.title_id AND s2.season = se.season)
                AS season_last
        FROM library_items li
        JOIN titles t ON t.id = li.title_id AND t.type = 'show'
        JOIN show_episodes se ON se.title_id = li.title_id
        WHERE li.user_id = \(bind: userID.rawValue) AND li.status IN ('wishlist', 'in_progress')
          AND se.airs_at >= \(bind: from) AND se.airs_at < \(bind: until)
        ORDER BY se.airs_at, t.title, se.season, se.episode
        """
        return try await sql.raw(query).all(decoding: CalendarRow.self, keyDecodingStrategy: .convertFromSnakeCase)
            .compactMap { row in
                guard let title = row.title.asTitle, let key = try? EpisodeKey(season: row.season, episode: row.episode)
                else { return nil }
                let kind: CalendarEntry.Kind = row.episode == 1 ? .premiere : row.episode == row
                    .seasonLast ? .finale : .regular
                return CalendarEntry(
                    libraryItemID: LibraryItemID(row.itemId), title: title, key: key, episodeName: row.name,
                    airsAt: row.airsAt, runtimeMinutes: row.runtimeMinutes, watched: row.watched, kind: kind
                )
            }
    }

    func continueWatching(userID: UserID, now: Date, limit: Int) async throws -> [ContinueEntry] {
        let query: SQLQueryString = """
        SELECT li.id AS item_id, \(Self.titleColumns),
            next.season AS next_season, next.episode AS next_episode, next.name AS next_name,
            coalesce(next.runtime_minutes, t.runtime_minutes) AS next_runtime,
            rem.count AS remaining_count, rem.minutes AS remaining_minutes,
            next.episode = (SELECT max(s2.episode) FROM show_episodes s2
                            WHERE s2.title_id = li.title_id AND s2.season = next.season) AS is_finale
        FROM library_items li
        JOIN titles t ON t.id = li.title_id AND t.type = 'show'
        JOIN LATERAL (
            SELECT se.season, se.episode, se.name, se.runtime_minutes FROM show_episodes se
            WHERE se.title_id = li.title_id AND se.season > 0 AND \(Self.aired(now)) AND \(Self.unwatched)
            ORDER BY se.season, se.episode LIMIT 1
        ) next ON true
        JOIN LATERAL (
            SELECT count(*)::int AS count,
                coalesce(sum(coalesce(se.runtime_minutes, t.runtime_minutes, 0)), 0)::int AS minutes
            FROM show_episodes se
            WHERE se.title_id = li.title_id AND se.season > 0 AND \(Self.aired(now)) AND \(Self.unwatched)
        ) rem ON true
        WHERE li.user_id = \(bind: userID.rawValue) AND li.status = 'in_progress'
        ORDER BY li.updated_at DESC, li.id DESC
        LIMIT \(literal: limit)
        """
        return try await sql.raw(query).all(decoding: ContinueRow.self, keyDecodingStrategy: .convertFromSnakeCase)
            .compactMap { row in
                guard let title = row.title.asTitle,
                      let next = try? EpisodeKey(season: row.nextSeason, episode: row.nextEpisode)
                else { return nil }
                return ContinueEntry(
                    libraryItemID: LibraryItemID(row.itemId), title: title, next: next, nextName: row.nextName,
                    nextRuntimeMinutes: row.nextRuntime, remainingCount: row.remainingCount,
                    remainingMinutes: row.remainingMinutes, isFinale: row.isFinale
                )
            }
    }

    func startWatching(userID: UserID, limit: Int) async throws -> [StartEntry] {
        let query: SQLQueryString = """
        SELECT li.id AS item_id, \(Self.titleColumns), t.runtime_minutes
        FROM library_items li JOIN titles t ON t.id = li.title_id
        WHERE li.user_id = \(bind: userID.rawValue) AND li.status = 'wishlist'
        ORDER BY li.added_at DESC, li.id DESC
        LIMIT \(literal: limit)
        """
        return try await sql.raw(query).all(decoding: StartRow.self, keyDecodingStrategy: .convertFromSnakeCase)
            .compactMap { row in
                row.title.asTitle.map {
                    StartEntry(libraryItemID: LibraryItemID(row.itemId), title: $0, runtimeMinutes: row.runtimeMinutes)
                }
            }
    }

    func unhydratedTrackedShows(userID: UserID, limit: Int) async throws -> [TitleID] {
        struct Row: Decodable { let id: UUID }
        return try await sql.raw("""
        SELECT t.id FROM library_items li JOIN titles t ON t.id = li.title_id
        WHERE li.user_id = \(bind: userID.rawValue) AND li.status IN ('wishlist', 'in_progress')
          AND t.type = 'show' AND t.episodes_hydrated_at IS NULL
        LIMIT \(literal: limit)
        """).all(decoding: Row.self).map { TitleID($0.id) }
    }
}

/// The title columns `PostgresScheduleStore.titleColumns` selects, decoded from the same row.
private struct TitleColumns: Decodable {
    let titleId: UUID
    let type: String
    let title: String
    let originalTitle: String?
    let year: Int?
    let synopsis: String?
    let posterUrl: String?
    let isAnime: Bool
    let tmdb, imdb, trakt, tvdb, isbn, openLibrary, anilist, mal, anidb: String?

    var asTitle: Title? {
        MediaType(rawValue: type).map {
            Title(
                id: TitleID(titleId), type: $0, title: self.title, originalTitle: originalTitle, year: year,
                synopsis: synopsis, posterURL: posterUrl.flatMap(URL.init(string:)),
                ids: ExternalIDs(
                    tmdb: tmdb, imdb: imdb, trakt: trakt, tvdb: tvdb, isbn: isbn,
                    openLibrary: openLibrary, anilist: anilist, mal: mal, anidb: anidb
                ),
                isAnime: isAnime
            )
        }
    }
}

private struct CalendarRow: Decodable {
    let itemId: UUID
    let title: TitleColumns
    let season: Int
    let episode: Int
    let name: String?
    let airsAt: Date
    let runtimeMinutes: Int?
    let watched: Bool
    let seasonLast: Int

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        itemId = try container.decode(UUID.self, forKey: .itemId)
        season = try container.decode(Int.self, forKey: .season)
        episode = try container.decode(Int.self, forKey: .episode)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        airsAt = try container.decode(Date.self, forKey: .airsAt)
        runtimeMinutes = try container.decodeIfPresent(Int.self, forKey: .runtimeMinutes)
        watched = try container.decode(Bool.self, forKey: .watched)
        seasonLast = try container.decode(Int.self, forKey: .seasonLast)
        title = try TitleColumns(from: decoder)
    }

    enum CodingKeys: String, CodingKey {
        case itemId, season, episode, name, airsAt, runtimeMinutes, watched, seasonLast
    }
}

private struct ContinueRow: Decodable {
    let itemId: UUID
    let title: TitleColumns
    let nextSeason: Int
    let nextEpisode: Int
    let nextName: String?
    let nextRuntime: Int?
    let remainingCount: Int
    let remainingMinutes: Int
    let isFinale: Bool

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        itemId = try container.decode(UUID.self, forKey: .itemId)
        nextSeason = try container.decode(Int.self, forKey: .nextSeason)
        nextEpisode = try container.decode(Int.self, forKey: .nextEpisode)
        nextName = try container.decodeIfPresent(String.self, forKey: .nextName)
        nextRuntime = try container.decodeIfPresent(Int.self, forKey: .nextRuntime)
        remainingCount = try container.decode(Int.self, forKey: .remainingCount)
        remainingMinutes = try container.decode(Int.self, forKey: .remainingMinutes)
        isFinale = try container.decode(Bool.self, forKey: .isFinale)
        title = try TitleColumns(from: decoder)
    }

    enum CodingKeys: String, CodingKey {
        case itemId, nextSeason, nextEpisode, nextName, nextRuntime, remainingCount, remainingMinutes, isFinale
    }
}

private struct StartRow: Decodable {
    let itemId: UUID
    let title: TitleColumns
    let runtimeMinutes: Int?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        itemId = try container.decode(UUID.self, forKey: .itemId)
        runtimeMinutes = try container.decodeIfPresent(Int.self, forKey: .runtimeMinutes)
        title = try TitleColumns(from: decoder)
    }

    enum CodingKeys: String, CodingKey {
        case itemId, runtimeMinutes
    }
}
