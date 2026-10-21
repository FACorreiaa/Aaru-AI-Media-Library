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

    func notificationSettings(userID: UserID) async throws -> NotificationSettings {
        struct Row: Decodable {
            let airing: Bool
            let groupMentions: Bool
            let groupInvites: Bool
        }
        let row = try await sql.raw("""
        SELECT airing, group_mentions, group_invites FROM notification_settings
        WHERE user_id = \(bind: userID.rawValue)
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)
        return row.map {
            NotificationSettings(airing: $0.airing, groupMentions: $0.groupMentions, groupInvites: $0.groupInvites)
        } ?? NotificationSettings()
    }

    func saveNotificationSettings(_ settings: NotificationSettings, userID: UserID, now: Date) async throws {
        try await sql.raw("""
        INSERT INTO notification_settings (user_id, airing, airing_since, group_mentions, group_invites)
        VALUES (\(bind: userID.rawValue), \(bind: settings.airing), \(bind: settings.airing ? now : nil),
            \(bind: settings.groupMentions), \(bind: settings.groupInvites))
        ON CONFLICT (user_id) DO UPDATE SET airing = EXCLUDED.airing,
            airing_since = CASE WHEN EXCLUDED.airing AND NOT notification_settings.airing
                THEN EXCLUDED.airing_since ELSE notification_settings.airing_since END,
            group_mentions = EXCLUDED.group_mentions, group_invites = EXCLUDED.group_invites
        """).run()
    }

    func mentionRecipients(group: UUID, users: [UserID]) async throws -> [UserID] {
        struct Row: Decodable { let userId: UUID }
        guard !users.isEmpty else { return [] }
        return try await sql.raw("""
        SELECT gm.user_id FROM group_members gm
        JOIN notification_settings ns ON ns.user_id = gm.user_id AND ns.group_mentions
        WHERE gm.group_id = \(bind: group) AND NOT gm.muted
          AND gm.user_id = ANY(\(bind: users.map(\.rawValue)))
        """).all(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase).map { UserID($0.userId) }
    }

    func dueAirings(now: Date, since: Date) async throws -> [DueAiring] {
        struct Row: Decodable {
            let userId: UUID
            let titleId: UUID
            let id: UUID
            let title: String
            let season: Int
            let episode: Int
            let name: String?
        }
        return try await sql.raw("""
        SELECT li.user_id, li.title_id, li.id, t.title, se.season, se.episode, se.name
        FROM show_episodes se
        JOIN titles t ON t.id = se.title_id
        JOIN library_items li ON li.title_id = se.title_id AND li.status = 'in_progress'
        JOIN notification_settings ns ON ns.user_id = li.user_id AND ns.airing
        WHERE se.season > 0
          AND se.airs_at > \(bind: since) AND se.airs_at <= \(bind: now)
          AND se.airs_at > ns.airing_since
          AND (EXISTS (SELECT 1 FROM apns_devices d WHERE d.user_id = li.user_id)
               OR EXISTS (SELECT 1 FROM web_push_subscriptions w WHERE w.user_id = li.user_id))
          AND NOT EXISTS (SELECT 1 FROM episode_progress ep WHERE ep.library_item_id = li.id
                          AND ep.season = se.season AND ep.episode = se.episode)
          AND NOT EXISTS (SELECT 1 FROM notifications_sent sent WHERE sent.user_id = li.user_id
                          AND sent.title_id = se.title_id AND sent.season = se.season AND sent.episode = se.episode)
        ORDER BY se.airs_at
        LIMIT 500
        """).all(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase).map {
            DueAiring(
                userID: UserID($0.userId), titleID: TitleID($0.titleId), libraryItemID: LibraryItemID($0.id),
                title: $0.title,
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

    func saveWebPush(_ subscription: WebPushSubscription, userID: UserID) async throws {
        try await sql.raw("""
        INSERT INTO web_push_subscriptions (endpoint, user_id, p256dh, auth, vapid_key_id, updated_at)
        VALUES (\(bind: subscription.endpoint), \(bind: userID.rawValue), \(bind: subscription.p256dh),
            \(bind: subscription.auth), \(bind: subscription.vapidKeyID), now())
        ON CONFLICT (endpoint) DO UPDATE SET user_id = EXCLUDED.user_id, p256dh = EXCLUDED.p256dh,
            auth = EXCLUDED.auth, vapid_key_id = EXCLUDED.vapid_key_id, updated_at = now()
        """).run()
    }

    func deleteWebPush(endpoint: String, userID: UserID) async throws {
        try await sql.raw("""
        DELETE FROM web_push_subscriptions WHERE endpoint = \(bind: endpoint) AND user_id = \(bind: userID.rawValue)
        """).run()
    }

    func forgetWebPush(endpoint: String) async throws {
        try await sql.raw("DELETE FROM web_push_subscriptions WHERE endpoint = \(bind: endpoint)").run()
    }

    func webPushSubscriptions(userID: UserID) async throws -> [WebPushSubscription] {
        struct Row: Decodable {
            let endpoint: String
            let p256dh: String
            let auth: String
            let vapidKeyId: String
        }
        return try await sql.raw("""
        SELECT endpoint, p256dh, auth, vapid_key_id FROM web_push_subscriptions
        WHERE user_id = \(bind: userID.rawValue) ORDER BY updated_at DESC
        """).all(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase).map {
            WebPushSubscription(endpoint: $0.endpoint, p256dh: $0.p256dh, auth: $0.auth, vapidKeyID: $0.vapidKeyId)
        }
    }
}
