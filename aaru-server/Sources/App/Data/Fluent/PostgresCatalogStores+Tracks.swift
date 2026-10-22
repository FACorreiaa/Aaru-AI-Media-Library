import AaruCore
import FluentSQL
import Foundation

/// MUS-001: an album's tracklist, stored the first time its page opens.
extension PostgresTitleStore {
    func saveTracks(_ id: TitleID, _ tracks: [AlbumTrack], hydratedAt: Date) async throws {
        // One transaction: a reader never sees the tracklist emptied between the delete and the
        // inserts, and the whole list is one statement (an album has dozens of tracks, not thousands).
        try await sql.transaction { sql in
            try await sql.delete(from: "album_tracks").where("title_id", .equal, id.rawValue).run()
            if !tracks.isEmpty {
                let values = SQLList(tracks.map { track in
                    SQLQueryString("""
                    (\(bind: id.rawValue), \(bind: track.disc), \(bind: track.position), \(bind: track.name),
                     \(bind: track.lengthMs))
                    """)
                })
                try await sql.raw("""
                INSERT INTO album_tracks (title_id, disc, position, name, length_ms) VALUES \(values)
                ON CONFLICT (title_id, disc, position) DO NOTHING
                """).run()
            }
            try await sql.update("titles")
                .set("tracks_hydrated_at", to: hydratedAt)
                .set("updated_at", to: hydratedAt)
                .where("id", .equal, id.rawValue)
                .run()
        }
    }

    func tracks(_ id: TitleID) async throws -> [AlbumTrack] {
        struct Row: Decodable {
            let disc: Int
            let position: Int
            let name: String
            let lengthMs: Int?
        }
        return try await sql.select().columns("disc", "position", "name", "length_ms").from("album_tracks")
            .where("title_id", .equal, id.rawValue)
            .orderBy("disc").orderBy("position")
            .all(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)
            .map { AlbumTrack(disc: $0.disc, position: $0.position, name: $0.name, lengthMs: $0.lengthMs) }
    }
}
