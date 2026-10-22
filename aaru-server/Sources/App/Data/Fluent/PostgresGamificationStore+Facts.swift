import AaruCore
import FluentSQL
import Foundation

/// Badge facts for one user (GAM-004): library milestones (imports count), music, imports,
/// social, then the ledger and streak days (live only).
extension PostgresGamificationStore {
    func facts(userID: UserID) async throws -> AchievementFacts {
        var facts = AchievementFacts()
        try await libraryFacts(userID, into: &facts)
        try await spreadFacts(userID, into: &facts)
        try await showFacts(userID, into: &facts)
        try await otherFacts(userID, into: &facts)
        try await ledgerFacts(userID, into: &facts)
        try await bookRunFacts(userID, into: &facts)
        let runs = try await Streak.runs(streakDays(userID: userID))
        facts.longestStreak = runs.map(\.days).max() ?? 0
        if let firstLong = runs.firstIndex(where: { $0.days >= 7 }) {
            facts.comeback = runs[(firstLong + 1)...].contains { $0.days >= 7 }
        }
        return facts
    }

    private func libraryFacts(_ userID: UserID, into facts: inout AchievementFacts) async throws {
        let user = userID.rawValue
        guard let row = try await sql.raw("""
        SELECT
            count(*) FILTER (WHERE t.type = 'movie' AND li.status = 'finished')::int AS films_finished,
            count(*) FILTER (WHERE t.type = 'movie' AND li.status = 'finished' AND t.year < 1960)::int
                AS films_before1960,
            count(*) FILTER (WHERE t.type = 'show' AND NOT t.is_anime AND li.status = 'finished')::int
                AS shows_finished,
            count(*) FILTER (WHERE t.type = 'show' AND t.is_anime AND li.status = 'finished')::int AS anime_finished,
            count(*) FILTER (WHERE t.type = 'book' AND li.status = 'finished')::int AS books_finished,
            COALESCE(sum(CASE WHEN t.type <> 'book' THEN 0
                WHEN li.status = 'finished' THEN COALESCE(t.page_count, li.book_page, 0)
                ELSE COALESCE(li.book_page, 0) END), 0)::int AS pages_read,
            count(*) FILTER (WHERE t.type = 'book' AND li.status = 'finished' AND t.page_count >= 800)::int
                AS long_books_finished,
            count(*) FILTER (WHERE t.type = 'album' AND li.status = 'finished')::int AS albums_finished,
            count(li.rating)::int AS ratings,
            count(*) FILTER (WHERE li.rating = 10)::int AS perfect_tens,
            avg(li.rating)::float8 AS rating_mean,
            count(*) FILTER (WHERE btrim(COALESCE(li.notes, '')) <> '')::int AS notes,
            count(*) FILTER (WHERE li.is_owned)::int AS owned,
            count(DISTINCT t.year / 10) FILTER (WHERE li.status = 'finished' AND t.year IS NOT NULL)::int AS decades
        FROM library_items li JOIN titles t ON t.id = li.title_id
        WHERE li.user_id = \(bind: user)
        """).first(decoding: LibraryFactsRow.self, keyDecodingStrategy: .convertFromSnakeCase)
        else { return }
        row.apply(to: &facts)
    }

    /// Genres and networks reached: the Discovery badges.
    private func spreadFacts(_ userID: UserID, into facts: inout AchievementFacts) async throws {
        let user = userID.rawValue
        struct Counts: Decodable {
            let genres: Int
            let networks: Int
        }
        if let counts = try await sql.raw("""
        SELECT
            (SELECT count(DISTINCT g)::int FROM library_items li JOIN titles t ON t.id = li.title_id,
                unnest(t.genres) AS g
             WHERE li.user_id = \(bind: user) AND li.status = 'finished') AS genres,
            (SELECT count(DISTINCT t.network)::int FROM library_items li JOIN titles t ON t.id = li.title_id
             WHERE li.user_id = \(bind: user) AND t.type = 'show' AND t.network IS NOT NULL
               AND EXISTS (SELECT 1 FROM episode_progress ep WHERE ep.library_item_id = li.id)) AS networks
        """).first(decoding: Counts.self) {
            facts.genres = counts.genres
            facts.networks = counts.networks
        }
    }

    private func showFacts(_ userID: UserID, into facts: inout AchievementFacts) async throws {
        struct Row: Decodable {
            let episodes: Int
            let animeEpisodes: Int
            let seasons: Int
            let endedComplete: Int
            let longComplete: Int
        }
        let user = userID.rawValue
        guard let row = try await sql.raw("""
        WITH aired AS (
            SELECT li.id AS item, t.status, se.season, count(*) AS aired, count(ep.id) AS watched
            FROM library_items li
            JOIN titles t ON t.id = li.title_id AND t.type = 'show'
            JOIN show_episodes se ON se.title_id = li.title_id AND se.season > 0
            LEFT JOIN episode_progress ep ON ep.library_item_id = li.id
                AND ep.season = se.season AND ep.episode = se.episode
            WHERE li.user_id = \(bind: user)
              AND (se.airs_at <= now() OR (se.airs_at IS NULL AND t.status IN ('ended', 'canceled')))
            GROUP BY li.id, t.status, se.season
        ), shows AS (
            SELECT item, status, bool_and(watched = aired) AS done, sum(aired) AS aired FROM aired GROUP BY item, status
        )
        SELECT
            (SELECT count(*)::int FROM episode_progress ep JOIN library_items li ON li.id = ep.library_item_id
             WHERE li.user_id = \(bind: user)) AS episodes,
            (SELECT count(*)::int FROM episode_progress ep JOIN library_items li ON li.id = ep.library_item_id
             JOIN titles t ON t.id = li.title_id WHERE li.user_id = \(bind: user) AND t.is_anime) AS anime_episodes,
            (SELECT count(*)::int FROM aired WHERE watched = aired) AS seasons,
            (SELECT count(*)::int FROM shows WHERE done AND status IN ('ended', 'canceled')) AS ended_complete,
            (SELECT count(*)::int FROM shows WHERE done AND aired >= 100) AS long_complete
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase)
        else { return }
        facts.episodesTicked = row.episodes
        facts.animeEpisodes = row.animeEpisodes
        facts.seasonsComplete = row.seasons
        facts.endedShowsComplete = row.endedComplete
        facts.longShowsComplete = row.longComplete
    }

    private func otherFacts(_ userID: UserID, into facts: inout AchievementFacts) async throws {
        struct Row: Decodable {
            let lists: Int
            let shelves: Int
            let listens: Int
            let artists: Int
            let friends: Int
            let invitesRedeemed: Int
            let recommendationsSent: Int
            let recommendationsAdded: Int
            let reactions: Int
        }
        let user = userID.rawValue
        if let row = try await sql.raw("""
        SELECT
            (SELECT count(*)::int FROM lists WHERE user_id = \(bind: user)) AS lists,
            (SELECT count(*)::int FROM saved_queries WHERE user_id = \(bind: user)) AS shelves,
            (SELECT count(*)::int FROM listens WHERE user_id = \(bind: user)) AS listens,
            (SELECT count(DISTINCT COALESCE(artist_mbid, lower(artist)))::int FROM listens
             WHERE user_id = \(bind: user)) AS artists,
            (SELECT count(*)::int FROM social_friendships
             WHERE user_low = \(bind: user) OR user_high = \(bind: user)) AS friends,
            (SELECT count(*)::int FROM social_invites
             WHERE inviter_id = \(bind: user) AND redeemed_by IS NOT NULL) AS invites_redeemed,
            (SELECT count(*)::int FROM social_recommendations WHERE from_user_id = \(bind: user))
                AS recommendations_sent,
            (SELECT count(*)::int FROM social_recommendations
             WHERE from_user_id = \(bind: user) AND added_at IS NOT NULL) AS recommendations_added,
            (SELECT count(*)::int FROM social_reactions WHERE user_id = \(bind: user)) AS reactions
        """).first(decoding: Row.self, keyDecodingStrategy: .convertFromSnakeCase) {
            facts.lists = row.lists
            facts.shelves = row.shelves
            facts.listens = row.listens
            facts.artists = row.artists
            facts.friends = row.friends
            facts.invitesRedeemed = row.invitesRedeemed
            facts.recommendationsSent = row.recommendationsSent
            facts.recommendationsAdded = row.recommendationsAdded
            facts.reactions = row.reactions
        }
        struct Source: Decodable { let source: String }
        let sources = try await sql.raw("""
        SELECT DISTINCT source FROM import_jobs
        WHERE user_id = \(bind: user) AND state IN ('succeeded', 'partial')
        """).all(decoding: Source.self)
        facts.importSources = Set(sources.map(\.source))
        facts.importsApplied = sources.isEmpty ? 0 : 1
    }

    /// Active awards only: an award whose revocation exists no longer counts.
    private func ledgerFacts(_ userID: UserID, into facts: inout AchievementFacts) async throws {
        let user = userID.rawValue
        let streakKinds = PointsKind.allCases.filter(\.marksStreakDay).map(\.rawValue)
        guard let row = try await sql.raw("""
        WITH active AS (
            SELECT e.* FROM points_events e
            WHERE e.user_id = \(bind: user) AND e.reverses IS NULL
              AND NOT EXISTS (SELECT 1 FROM points_events r WHERE r.reverses = e.id)
        ), episodes AS (
            SELECT a.*, split_part(a.dedupe_root, ':', 3)::int AS season,
                split_part(a.dedupe_root, ':', 4)::int AS episode
            FROM active a WHERE a.kind = 'episode'
        ), aired AS (
            SELECT e.created_at, se.airs_at, se.airs_at_exact, se.title_id, se.season, se.episode
            FROM episodes e JOIN show_episodes se
                ON se.title_id = e.title_id AND se.season = e.season AND se.episode = e.episode
            WHERE se.airs_at IS NOT NULL AND e.created_at >= se.airs_at
              AND e.created_at < se.airs_at + interval '24 hours'
        )
        SELECT
            (SELECT count(*)::int FROM (SELECT local_date FROM active WHERE kind = 'movie_finished'
                GROUP BY local_date HAVING count(*) >= 2) d) AS double_feature_days,
            (SELECT count(*)::int FROM (SELECT local_date FROM active WHERE kind = 'episode'
                GROUP BY local_date HAVING count(*) >= 10) d) AS marathon_days,
            (SELECT count(*)::int FROM active WHERE kind = ANY(\(bind: streakKinds)::text[])
                AND extract(hour FROM created_at AT TIME ZONE time_zone) < 5) AS night_owl,
            (SELECT count(*)::int FROM active WHERE kind = 'room_attended') AS parties,
            (SELECT count(*)::int FROM aired WHERE airs_at_exact) AS day_one,
            (SELECT count(*)::int FROM aired a WHERE a.season > 0 AND a.episode = (
                SELECT max(x.episode) FROM show_episodes x WHERE x.title_id = a.title_id AND x.season = a.season
            )) AS finales,
            (SELECT count(*)::int FROM active sb
             CROSS JOIN LATERAL (
                SELECT count(*) AS size FROM show_episodes x
                WHERE x.title_id = sb.title_id AND x.season = split_part(sb.dedupe_root, ':', 3)::int
             ) s
             WHERE sb.kind = 'season_bonus' AND s.size >= 6 AND (
                SELECT count(*) FROM episodes e WHERE e.title_id = sb.title_id AND e.local_date = sb.local_date
                  AND e.season = split_part(sb.dedupe_root, ':', 3)::int
             ) >= s.size) AS binged
        """).first(decoding: LedgerFactsRow.self, keyDecodingStrategy: .convertFromSnakeCase)
        else { return }
        row.apply(to: &facts)
    }

    /// The longest run of days with book progress: Chapter a Day.
    private func bookRunFacts(_ userID: UserID, into facts: inout AchievementFacts) async throws {
        let user = userID.rawValue
        struct Day: Decodable { let localDate: String }
        let bookDays = try await sql.raw("""
        SELECT DISTINCT to_char(local_date, 'YYYY-MM-DD') AS local_date FROM points_events e
        WHERE e.user_id = \(bind: user) AND e.kind = 'book_progress' AND e.reverses IS NULL
          AND NOT EXISTS (SELECT 1 FROM points_events r WHERE r.reverses = e.id)
        """).all(decoding: Day.self, keyDecodingStrategy: .convertFromSnakeCase)
        facts.longestBookRun = Streak.runs(bookDays.map {
            StreakDay(date: $0.localDate, timeZone: "", firstAt: .distantPast)
        }).map(\.days).max() ?? 0
    }
}

private struct LibraryFactsRow: Decodable {
    let filmsFinished: Int
    let filmsBefore1960: Int
    let showsFinished: Int
    let animeFinished: Int
    let booksFinished: Int
    let pagesRead: Int
    let longBooksFinished: Int
    let albumsFinished: Int
    let ratings: Int
    let perfectTens: Int
    let ratingMean: Double?
    let notes: Int
    let owned: Int
    let decades: Int

    func apply(to facts: inout AchievementFacts) {
        facts.filmsFinished = filmsFinished
        facts.filmsBefore1960 = filmsBefore1960
        facts.showsFinished = showsFinished
        facts.animeFinished = animeFinished
        facts.booksFinished = booksFinished
        facts.pagesRead = pagesRead
        facts.longBooksFinished = longBooksFinished
        facts.albumsFinished = albumsFinished
        facts.ratings = ratings
        facts.perfectTens = perfectTens
        facts.ratingMean = ratingMean
        facts.notes = notes
        facts.owned = owned
        facts.decades = decades
    }
}

private struct LedgerFactsRow: Decodable {
    let doubleFeatureDays: Int
    let marathonDays: Int
    let nightOwl: Int
    let parties: Int
    let dayOne: Int
    let finales: Int
    let binged: Int

    func apply(to facts: inout AchievementFacts) {
        facts.doubleFeatureDays = doubleFeatureDays
        facts.marathonDays = marathonDays
        facts.nightOwlWrites = nightOwl
        facts.watchParties = parties
        facts.dayOneEpisodes = dayOne
        facts.finaleNights = finales
        facts.bingedSeasons = binged
    }
}
