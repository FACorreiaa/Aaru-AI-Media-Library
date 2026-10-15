import AaruCore
import FluentSQL
import Foundation

struct PostgresPushStore: PushStore {
    let sql: any SQLDatabase

    func register(_ device: PushDevice, userID: UserID) async throws {
        try await sql.raw("""
        INSERT INTO apns_devices (token, user_id, environment, topic, updated_at)
        VALUES (\(bind: device.token), \(bind: userID.rawValue), \(bind: device.environment.rawValue),
            \(bind: device.topic), now())
        ON CONFLICT (token) DO UPDATE SET user_id = EXCLUDED.user_id, environment = EXCLUDED.environment,
            topic = EXCLUDED.topic, updated_at = now()
        """).run()
    }

    func unregister(token: String, userID: UserID) async throws {
        try await sql.raw("""
        DELETE FROM apns_devices WHERE token = \(bind: token) AND user_id = \(bind: userID.rawValue)
        """).run()
    }

    func forget(token: String) async throws {
        try await sql.raw("DELETE FROM apns_devices WHERE token = \(bind: token)").run()
    }

    func devices(userID: UserID) async throws -> [PushDevice] {
        struct Row: Decodable {
            let token: String
            let environment: String
            let topic: String
        }
        return try await sql.raw("""
        SELECT token, environment, topic FROM apns_devices WHERE user_id = \(bind: userID.rawValue)
        """).all(decoding: Row.self).compactMap { row in
            PushEnvironment(rawValue: row.environment).map {
                PushDevice(token: row.token, environment: $0, topic: row.topic)
            }
        }
    }

    func airingEnabled(userID: UserID) async throws -> Bool {
        struct Row: Decodable { let airing: Bool }
        return try await sql.raw("""
        SELECT airing FROM notification_settings WHERE user_id = \(bind: userID.rawValue)
        """).first(decoding: Row.self)?.airing ?? false
    }

    func setAiring(_ enabled: Bool, userID: UserID, now: Date) async throws {
        try await sql.raw("""
        INSERT INTO notification_settings (user_id, airing, airing_since)
        VALUES (\(bind: userID.rawValue), \(bind: enabled), \(bind: enabled ? now : nil))
        ON CONFLICT (user_id) DO UPDATE SET airing = EXCLUDED.airing,
            airing_since = CASE WHEN EXCLUDED.airing AND NOT notification_settings.airing
                THEN EXCLUDED.airing_since ELSE notification_settings.airing_since END
        """).run()
    }

    func dueAirings(now: Date, since: Date) async throws -> [DueAiring] {
        struct Row: Decodable {
            let userId: UUID
            let titleId: UUID
            let title: String
            let season: Int
            let episode: Int
            let name: String?
        }
        return try await sql.raw("""
        SELECT li.user_id, li.title_id, t.title, se.season, se.episode, se.name
        FROM show_episodes se
        JOIN titles t ON t.id = se.title_id
        JOIN library_items li ON li.title_id = se.title_id AND li.status = 'in_progress'
        JOIN notification_settings ns ON ns.user_id = li.user_id AND ns.airing
        WHERE se.season > 0
          AND se.airs_at > \(bind: since) AND se.airs_at <= \(bind: now)
          AND se.airs_at > ns.airing_since
          AND EXISTS (SELECT 1 FROM apns_devices d WHERE d.user_id = li.user_id)
          AND NOT EXISTS (SELECT 1 FROM episode_progress ep WHERE ep.library_item_id = li.id
                          AND ep.season = se.season AND ep.episode = se.episode)
          AND NOT EXISTS (SELECT 1 FROM notifications_sent sent WHERE sent.user_id = li.user_id
                          AND sent.title_id = se.title_id AND sent.season = se.season AND sent.episode = se.episode)
        ORDER BY se.airs_at
        LIMIT 500
        """).all(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase).map {
            DueAiring(
                userID: UserID($0.userId), titleID: TitleID($0.titleId), title: $0.title,
                season: $0.season, episode: $0.episode, episodeName: $0.name
            )
        }
    }

    func claim(_ airing: DueAiring) async throws -> Bool {
        struct Row: Decodable { let season: Int }
        return try await sql.raw("""
        INSERT INTO notifications_sent (user_id, title_id, season, episode)
        VALUES (\(bind: airing.userID.rawValue), \(bind: airing.titleID.rawValue), \(bind: airing.season),
            \(bind: airing.episode))
        ON CONFLICT DO NOTHING RETURNING season
        """).first(decoding: Row.self) != nil
    }
}
