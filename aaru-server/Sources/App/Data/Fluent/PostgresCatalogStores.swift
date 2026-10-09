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
        let tmdb, imdb, trakt, tvdb, isbn, openLibrary, anilist, mal, anidb: String?
        let isAnime: Bool
        let status: String?
        let runtimeMinutes: Int?
        let episodesHydratedAt: Date?

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
                ids: ExternalIDs(
                    tmdb: tmdb, imdb: imdb, trakt: trakt, tvdb: tvdb, isbn: isbn,
                    openLibrary: openLibrary, anilist: anilist, mal: mal, anidb: anidb
                ),
                isAnime: isAnime
            )
        }
    }

    func insert(_ title: Title, status: TitleStatus?, runtimeMinutes: Int?) async throws {
        try title.validate()
        let ids = title.ids
        let row = Row(
            id: title.id.rawValue, type: title.type.rawValue, title: title.title,
            originalTitle: title.originalTitle, year: title.year, synopsis: title.synopsis,
            posterUrl: title.posterURL?.absoluteString,
            tmdb: ids.tmdb, imdb: ids.imdb, trakt: ids.trakt, tvdb: ids.tvdb, isbn: ids.isbn,
            openLibrary: ids.openLibrary, anilist: ids.anilist, mal: ids.mal, anidb: ids.anidb,
            isAnime: title.isAnime, status: status?.rawValue, runtimeMinutes: runtimeMinutes,
            episodesHydratedAt: nil
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

    func saveEpisodes(
        _ id: TitleID,
        _ episodes: [CatalogEpisode],
        status: TitleStatus?,
        hydratedAt: Date
    ) async throws {
        for episode in episodes {
            try await sql.raw("""
            INSERT INTO show_episodes (id, title_id, season, episode, name, airs_at, runtime_minutes, tmdb_episode_id)
            VALUES (\(bind: UUID()), \(bind: id.rawValue), \(bind: episode.season), \(bind: episode.episode),
                    \(bind: episode.name), \(bind: episode.airsAt), \(bind: episode.runtimeMinutes),
                    \(bind: episode.tmdbEpisodeID))
            ON CONFLICT (title_id, season, episode) DO UPDATE SET
                name = EXCLUDED.name, airs_at = EXCLUDED.airs_at,
                runtime_minutes = EXCLUDED.runtime_minutes, tmdb_episode_id = EXCLUDED.tmdb_episode_id
            """).run()
        }
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

    func episodes(_ id: TitleID) async throws -> [CatalogEpisode] {
        struct Row: Decodable {
            let season: Int
            let episode: Int
            let name: String?
            let airsAt: Date?
            let runtimeMinutes: Int?
            let tmdbEpisodeId: String?
        }
        return try await sql.select()
            .columns("season", "episode", "name", "airs_at", "runtime_minutes", "tmdb_episode_id")
            .from("show_episodes")
            .where("title_id", .equal, id.rawValue)
            .orderBy("season").orderBy("episode")
            .all(decoding: Row.self, keyDecodingStrategy: snake)
            .map {
                CatalogEpisode(
                    season: $0.season, episode: $0.episode, name: $0.name, airsAt: $0.airsAt,
                    runtimeMinutes: $0.runtimeMinutes, tmdbEpisodeID: $0.tmdbEpisodeId
                )
            }
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
        try await sql.select().columns(SQLLiteral.all).from("anime_mappings")
            .where("anilist", .equal, anilist)
            .first(decoding: Row.self, keyDecodingStrategy: snake)
            .map {
                AnimeMapping(
                    anilist: $0.anilist, mal: $0.mal, anidb: $0.anidb, tvdb: $0.tvdb,
                    tmdb: $0.tmdb, tmdbSeason: $0.tmdbSeason
                )
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
