import AaruCore
import FluentKit
import FluentSQL
import Foundation

// Postgres implementations for the catalog layer: titles, episodes, anime mappings.

private var snake: SQLRowDecoder.KeyDecodingStrategy {
    .convertFromSnakeCase
}

/// Column ↔ `ExternalIDs` field. `type` scopes tmdb and trakt (see migration 002).
/// Computed: key paths are not Sendable, so this cannot be a stored global.
private var idColumns: [(column: String, path: KeyPath<ExternalIDs, String?>)] {
    [
        ("tmdb", \.tmdb), ("imdb", \.imdb), ("trakt", \.trakt), ("tvdb", \.tvdb), ("isbn", \.isbn),
        ("open_library", \.openLibrary), ("anilist", \.anilist), ("mal", \.mal), ("anidb", \.anidb),
    ]
}

struct PostgresTitleStore: TitleStore {
    let sql: any SQLDatabase

    private struct Row: Codable {
        let id: UUID
        let type: String
        let title: String
        let originalTitle: String?
        let year: Int?
        let synopsis: String?
        let posterUrl: String?
        let backdropUrl: String?
        let network: String?
        let tmdb, imdb, trakt, tvdb, isbn, openLibrary, anilist, mal, anidb: String?
        let isAnime: Bool
        let status: String?
        let runtimeMinutes: Int?
        let episodesHydratedAt: Date?
        let genres: [String]

        var asTitle: Title? {
            guard let type = MediaType(rawValue: type) else { return nil }
            return Title(
                id: TitleID(id),
                type: type,
                title: title,
                originalTitle: originalTitle,
                year: year,
                synopsis: synopsis,
                posterURL: posterUrl.flatMap(URL.init(string:)),
                backdropURL: backdropUrl.flatMap(URL.init(string:)),
                network: network,
                ids: ExternalIDs(
                    tmdb: tmdb, imdb: imdb, trakt: trakt, tvdb: tvdb, isbn: isbn,
                    openLibrary: openLibrary, anilist: anilist, mal: mal, anidb: anidb
                ),
                isAnime: isAnime
            )
        }
    }

    func insert(_ title: Title, status: TitleStatus?, runtimeMinutes: Int?, genres: [String]) async throws {
        try title.validate()
        let ids = title.ids
        let row = Row(
            id: title.id.rawValue, type: title.type.rawValue, title: title.title,
            originalTitle: title.originalTitle, year: title.year, synopsis: title.synopsis,
            posterUrl: title.posterURL?.absoluteString,
            backdropUrl: title.backdropURL?.absoluteString, network: title.network,
            tmdb: ids.tmdb, imdb: ids.imdb, trakt: ids.trakt, tvdb: ids.tvdb, isbn: ids.isbn,
            openLibrary: ids.openLibrary, anilist: ids.anilist, mal: ids.mal, anidb: ids.anidb,
            isAnime: title.isAnime, status: status?.rawValue, runtimeMinutes: runtimeMinutes,
            episodesHydratedAt: nil, genres: genres
        )
        do {
            try await sql.insert(into: "titles").model(row, keyEncodingStrategy: .convertToSnakeCase).run()
        } catch let error as any DatabaseError where error.isConstraintFailure {
            throw StoreConflict(message: "Another title already has one of these external ids.")
        }
    }

    func title(id: TitleID) async throws -> Title? {
        try await sql.select().columns(SQLLiteral.all).from("titles")
            .where("id", .equal, id.rawValue)
            .first(decoding: Row.self, keyDecodingStrategy: snake)?.asTitle
    }

    func find(ids: ExternalIDs, type: MediaType) async throws -> Title? {
        let known = idColumns.compactMap { column in ids[keyPath: column.path].map { (column.column, $0) } }
        guard !known.isEmpty else { return nil }
        return try await sql.select().columns(SQLLiteral.all).from("titles")
            .where("type", .equal, type.rawValue)
            .where { group in
                for (column, value) in known {
                    group.orWhere(SQLIdentifier(column), .equal, SQLBind(value))
                }
                return group
            }
            .orderBy("created_at")
            .first(decoding: Row.self, keyDecodingStrategy: snake)?.asTitle
    }

    func fillIDs(_ id: TitleID, from ids: ExternalIDs) async throws {
        for (column, path) in idColumns {
            guard let value = ids[keyPath: path] else { continue }
            do {
                try await sql.update("titles")
                    .set(SQLIdentifier(column), to: SQLBind(value))
                    .where("id", .equal, id.rawValue)
                    .where(SQLIdentifier(column), .is, SQLLiteral.null)
                    .run()
            } catch let error as any DatabaseError where error.isConstraintFailure {
                continue // another title holds it: skip, never merge
            }
        }
    }

    func catalogState(_ id: TitleID) async throws -> TitleCatalogState? {
        guard let row = try await sql.select().columns(SQLLiteral.all).from("titles")
            .where("id", .equal, id.rawValue)
            .first(decoding: Row.self, keyDecodingStrategy: snake)
        else { return nil }
        return TitleCatalogState(
            status: row.status.flatMap(TitleStatus.init(rawValue:)),
            runtimeMinutes: row.runtimeMinutes,
            episodesHydratedAt: row.episodesHydratedAt
        )
    }

    func saveEpisodes(_ id: TitleID, _ fresh: CatalogEpisodes, hydratedAt: Date) async throws {
        for episode in fresh.episodes {
            try await sql.raw("""
            INSERT INTO show_episodes
                (id, title_id, season, episode, name, overview, airs_at, airs_at_exact, runtime_minutes,
                 tmdb_episode_id, still_url)
            VALUES (\(bind: UUID()), \(bind: id.rawValue), \(bind: episode.season), \(bind: episode.episode),
                    \(bind: episode.name), \(bind: episode.overview), \(bind: episode.airsAt),
                    \(bind: episode.airTimeKnown), \(bind: episode.runtimeMinutes), \(bind: episode.tmdbEpisodeID),
                    \(bind: episode.stillURL?.absoluteString))
            ON CONFLICT (title_id, season, episode) DO UPDATE SET
                name = EXCLUDED.name, overview = EXCLUDED.overview,
                airs_at = EXCLUDED.airs_at, airs_at_exact = EXCLUDED.airs_at_exact,
                runtime_minutes = EXCLUDED.runtime_minutes, tmdb_episode_id = EXCLUDED.tmdb_episode_id,
                still_url = EXCLUDED.still_url
            """).run()
        }
        let status = fresh.status
        // A provider that drops its art does not erase ours.
        try await sql.raw("""
        UPDATE titles SET backdrop_url = coalesce(\(bind: fresh.backdropURL?.absoluteString), backdrop_url),
            network = coalesce(\(bind: fresh.network), network)
        WHERE id = \(bind: id.rawValue)
        """).run()
        try await sql.update("titles")
            .set("episodes_hydrated_at", to: hydratedAt)
            .set("status", to: status?.rawValue)
            .set("updated_at", to: hydratedAt)
            .where("id", .equal, id.rawValue)
            .run()
    }

    func titles(ids: [TitleID]) async throws -> [Title] {
        guard !ids.isEmpty else { return [] }
        let rows = try await sql.select().columns(SQLLiteral.all).from("titles")
            .where("id", .in, ids.map(\.rawValue))
            .all(decoding: Row.self, keyDecodingStrategy: snake)
        let byID = Dictionary(rows.compactMap(\.asTitle).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    func airing(ids: [TitleID], now: Date) async throws -> [TitleID: TitleAiring] {
        struct Row: Decodable {
            let id: UUID
            let status: String?
            let season: Int?
            let episode: Int?
            let name: String?
            let airsAt: Date?
            let airsAtExact: Bool?
        }
        guard !ids.isEmpty else { return [:] }
        let rows = try await sql.raw("""
        SELECT t.id, t.status, next.season, next.episode, next.name, next.airs_at, next.airs_at_exact
        FROM titles t
        LEFT JOIN LATERAL (
            SELECT se.season, se.episode, se.name, se.airs_at, se.airs_at_exact FROM show_episodes se
            WHERE se.title_id = t.id AND se.season > 0 AND se.airs_at > \(bind: now)
            ORDER BY se.airs_at, se.season, se.episode LIMIT 1
        ) next ON true
        WHERE t.type = 'show' AND t.id = ANY(\(bind: ids.map(\.rawValue)))
        """).all(decoding: Row.self, keyDecodingStrategy: snake)
        return Dictionary(uniqueKeysWithValues: rows.map { row in
            var next: CatalogEpisode?
            if let season = row.season, let episode = row.episode {
                next = CatalogEpisode(
                    season: season, episode: episode, name: row.name, airsAt: row.airsAt,
                    airTimeKnown: row.airsAtExact ?? false
                )
            }
            return (TitleID(row.id), TitleAiring(status: row.status.flatMap(TitleStatus.init(rawValue:)), next: next))
        })
    }

    func staleTrackedShows(now: Date, retryAfter: Date, limit: Int) async throws -> [TitleID] {
        struct Row: Decodable { let id: UUID }
        let airingStale = now.addingTimeInterval(-CatalogService.airingStaleness)
        let dormantStale = now.addingTimeInterval(-CatalogService.dormantStaleness)
        let windowStart = now.addingTimeInterval(-CatalogService.airingWindow)
        let windowEnd = now.addingTimeInterval(CatalogService.airingWindow)
        return try await sql.raw("""
        SELECT t.id FROM titles t
        WHERE t.type = 'show'
          AND (EXISTS (SELECT 1 FROM library_items li
                       WHERE li.title_id = t.id AND li.status IN ('wishlist', 'in_progress'))
               OR EXISTS (SELECT 1 FROM list_items lst WHERE lst.title_id = t.id))
          AND (t.episodes_attempted_at IS NULL OR t.episodes_attempted_at < \(bind: retryAfter))
          AND (t.episodes_hydrated_at IS NULL
               OR t.episodes_hydrated_at < \(bind: dormantStale)
               OR (t.episodes_hydrated_at < \(bind: airingStale)
                   AND EXISTS (SELECT 1 FROM show_episodes e
                               WHERE e.title_id = t.id
                                 AND e.airs_at BETWEEN \(bind: windowStart) AND \(bind: windowEnd))))
        ORDER BY t.episodes_hydrated_at NULLS FIRST, t.id
        LIMIT \(literal: limit)
        """).all(decoding: Row.self).map { TitleID($0.id) }
    }

    func markEpisodesAttempted(_ id: TitleID, at date: Date) async throws {
        try await sql.update("titles")
            .set("episodes_attempted_at", to: date)
            .where("id", .equal, id.rawValue)
            .run()
    }

    func episodes(_ id: TitleID) async throws -> [CatalogEpisode] {
        struct Row: Decodable {
            let season: Int
            let episode: Int
            let name: String?
            let airsAt: Date?
            let airsAtExact: Bool
            let runtimeMinutes: Int?
            let tmdbEpisodeId: String?
            let overview: String?
            let stillUrl: String?
        }
        return try await sql.select()
            .columns(
                "season", "episode", "name", "airs_at", "airs_at_exact", "runtime_minutes", "tmdb_episode_id",
                "overview", "still_url"
            )
            .from("show_episodes")
            .where("title_id", .equal, id.rawValue)
            .orderBy("season").orderBy("episode")
            .all(decoding: Row.self, keyDecodingStrategy: snake)
            .map {
                CatalogEpisode(
                    season: $0.season, episode: $0.episode, name: $0.name, airsAt: $0.airsAt,
                    runtimeMinutes: $0.runtimeMinutes, tmdbEpisodeID: $0.tmdbEpisodeId,
                    airTimeKnown: $0.airsAtExact, overview: $0.overview,
                    stillURL: $0.stillUrl.flatMap(URL.init(string:))
                )
            }
    }
}

/// CAT-018: genres stored at hydration, and the backfill's queue.
extension PostgresTitleStore {
    func titlesMissingGenres(retryAfter: Date, limit: Int) async throws -> [Title] {
        try await sql.raw("""
        SELECT t.* FROM titles t
        WHERE t.type <> 'book' AND t.genres = '{}'
          AND (t.genres_attempted_at IS NULL OR t.genres_attempted_at < \(bind: retryAfter))
          AND (EXISTS (SELECT 1 FROM library_items li WHERE li.title_id = t.id)
               OR EXISTS (SELECT 1 FROM list_items lst WHERE lst.title_id = t.id))
        ORDER BY t.genres_attempted_at NULLS FIRST, t.created_at, t.id
        LIMIT \(literal: limit)
        """).all(decoding: Row.self, keyDecodingStrategy: snake).compactMap(\.asTitle)
    }

    func fillGenres(_ id: TitleID, _ genres: [String], attemptedAt: Date) async throws {
        try await sql.raw("""
        UPDATE titles
        SET genres = CASE WHEN genres = '{}' THEN \(bind: genres)::text[] ELSE genres END,
            genres_attempted_at = \(bind: attemptedAt)
        WHERE id = \(bind: id.rawValue)
        """).run()
    }

    func genres(_ id: TitleID) async throws -> [String] {
        struct GenresRow: Decodable { let genres: [String] }
        return try await sql.select().column("genres").from("titles")
            .where("id", .equal, id.rawValue)
            .first(decoding: GenresRow.self)?.genres ?? []
    }
}

struct PostgresAnimeMappingStore: AnimeMappingStore {
    let sql: any SQLDatabase

    private struct Row: Codable {
        let anilist: String
        let mal, anidb, tvdb, tmdb: String?
        let tmdbSeason: Int?
    }

    func mapping(anilist: String) async throws -> AnimeMapping? {
        try await first(where: "anilist", equals: anilist)
    }

    func mapping(mal: String) async throws -> AnimeMapping? {
        try await first(where: "mal", equals: mal)
    }

    private func first(where column: String, equals value: String) async throws -> AnimeMapping? {
        try await sql.select().columns(SQLLiteral.all).from("anime_mappings")
            .where(SQLIdentifier(column), .equal, SQLBind(value))
            .orderBy("anilist")
            .first(decoding: Row.self, keyDecodingStrategy: snake)
            .map {
                AnimeMapping(
                    anilist: $0.anilist, mal: $0.mal, anidb: $0.anidb, tvdb: $0.tvdb,
                    tmdb: $0.tmdb, tmdbSeason: $0.tmdbSeason
                )
            }
    }

    func mappings(anilist ids: [String]) async throws -> [AnimeMapping] {
        guard !ids.isEmpty else { return [] }
        return try await sql.select().columns(SQLLiteral.all).from("anime_mappings")
            .where("anilist", .in, ids)
            .all(decoding: Row.self, keyDecodingStrategy: snake)
            .map {
                AnimeMapping(
                    anilist: $0.anilist, mal: $0.mal, anidb: $0.anidb, tvdb: $0.tvdb,
                    tmdb: $0.tmdb, tmdbSeason: $0.tmdbSeason
                )
            }
    }

    func upsertMany(_ mappings: [AnimeMapping]) async throws {
        let rows = mappings.map {
            Row(
                anilist: $0.anilist,
                mal: $0.mal,
                anidb: $0.anidb,
                tvdb: $0.tvdb,
                tmdb: $0.tmdb,
                tmdbSeason: $0.tmdbSeason
            )
        }
        try await sql.transaction { sql in
            for start in stride(from: 0, to: rows.count, by: 1000) {
                let batch = Array(rows[start ..< min(start + 1000, rows.count)])
                try await sql.insert(into: "anime_mappings")
                    .models(batch, keyEncodingStrategy: .convertToSnakeCase, nilEncodingStrategy: .asNil)
                    .onConflict(with: ["anilist"]) {
                        $0.set(excludedValueOf: "mal").set(excludedValueOf: "anidb").set(excludedValueOf: "tvdb")
                            .set(excludedValueOf: "tmdb").set(excludedValueOf: "tmdb_season")
                    }
                    .run()
            }
        }
    }

    func upsert(_ mapping: AnimeMapping) async throws {
        let row = Row(
            anilist: mapping.anilist, mal: mapping.mal, anidb: mapping.anidb, tvdb: mapping.tvdb,
            tmdb: mapping.tmdb, tmdbSeason: mapping.tmdbSeason
        )
        try await sql.insert(into: "anime_mappings")
            .model(row, keyEncodingStrategy: .convertToSnakeCase)
            .onConflict(with: ["anilist"]) {
                try $0.set(excludedContentOf: row, keyEncodingStrategy: .convertToSnakeCase)
            }
            .run()
    }
}
