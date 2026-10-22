import AaruCore
import Foundation

/// IMP-012: TV Time's exports, one CSV at a time. TV Time closed in July 2026 and left two kinds of
/// export, both zips of CSVs the person unzips:
///
/// - **Export my data** (the in-app tool, 2026): `tvtime-series-episodes.csv` (every episode of
///   every followed show, `is_watched` per episode), `tvtime-series.csv` (each show's status) and
///   `tvtime-movies.csv`. TVDB and IMDb ids on every row.
/// - **GDPR export** (~50 CSVs): `tracking-prod-records-v2.csv` (episode watches by show TVDB id,
///   plus follow / watch-later / archived flags per show), `tracking-prod-records.csv` (movies,
///   by name and release date only), `followed_tv_show.csv` (followed shows) and, in older
///   exports, `seen_episode.csv` (episodes by show name).
///
/// The layout is told by its columns, not its file name. Shows match by TVDB id (→ TMDB), then
/// IMDb; when TMDB does not know an old TVDB id, by exact name as `nameOnly` allows. Episode
/// numbers are TVDB's aired order, which TMDB follows for nearly every show.
enum TVTimeCSVParser {
    enum Layout: Equatable {
        case seriesEpisodes, series, movies, trackingV2, trackingV1, followedShows, seenEpisodes
    }

    static func layout(_ headers: Set<String>) -> Layout? {
        if headers.isSuperset(of: ["series_tvdb_id", "season", "episode"]) {
            return .seriesEpisodes
        }
        if headers.isSuperset(of: ["tvdb_id", "imdb_id", "title", "is_watched", "watched_at"]) {
            return .movies
        }
        if headers.isSuperset(of: ["uuid", "tvdb_id", "imdb_id", "title", "status"]) {
            return .series
        }
        if headers.contains("key"), headers.contains("s_id") || headers.contains("series_name") {
            return .trackingV2
        }
        if headers.contains("type-uuid-n") {
            return .trackingV1
        }
        if headers.isSuperset(of: ["tv_show_id", "notification_offset"]) {
            return .followedShows
        }
        if headers.isSuperset(of: ["show_name", "episode_season_number", "episode_number"]) {
            return .seenEpisodes
        }
        return nil
    }

    static let files = "tvtime-series-episodes.csv, tvtime-series.csv or tvtime-movies.csv from Export my data, "
        + "or tracking-prod-records-v2.csv, tracking-prod-records.csv, followed_tv_show.csv or "
        + "seen_episode.csv from a GDPR export"

    static func parse(_ table: CSVTable) throws -> [ImportRow] {
        guard let layout = layout(Set(table.headers)) else {
            throw ImportFormatError(
                message: "This is not a TV Time file Aaru reads. Unzip the export and upload \(files), one at a time."
            )
        }
        return switch layout {
        case .seriesEpisodes: seriesEpisodes(table)
        case .series: series(table)
        case .movies: movies(table)
        case .trackingV2: trackingV2(table)
        case .trackingV1: trackingV1(table)
        case .followedShows: followedShows(table)
        case .seenEpisodes: seenEpisodes(table)
        }
    }

    // MARK: Export my data

    /// One row per show: its watched episodes ticked. A followed show with none watched is planned.
    static func seriesEpisodes(_ table: CSVTable) -> [ImportRow] {
        var shows = Shows()
        for record in table.records {
            guard let slot = shows.slot(
                tvdb: record["series_tvdb_id"], imdb: record["series_imdb_id"], name: record["title"]
            ) else { continue }
            if record["is_watched"] == "true" {
                shows.tick(slot, season: record["season"], episode: record["episode"], at: date(record["watched_at"]))
            }
        }
        return shows.rows(status: { $0.watched?.isEmpty == false ? nil : .wishlist })
    }

    /// TV Time's word for where the person is with a show.
    static func status(_ word: String?) -> LibraryStatus? {
        switch word?.lowercased() {
        case "not_started_yet": .wishlist
        case "continuing", "up_to_date", "watching": .inProgress
        case "stopped", "archived": .dropped
        default: nil
        }
    }

    static func series(_ table: CSVTable) -> [ImportRow] {
        var shows = Shows()
        var statuses: [Int: LibraryStatus] = [:]
        for record in table.records {
            guard let slot = shows.slot(tvdb: record["tvdb_id"], imdb: record["imdb_id"], name: record["title"])
            else { continue }
            if let status = status(record["status"]) {
                statuses[slot] = status
            }
        }
        return shows.rows(status: { _ in nil }, at: { statuses[$0] })
    }

    /// `is_watched` false is a film on the person's to-watch list.
    static func movies(_ table: CSVTable) -> [ImportRow] {
        var seen: Set<String> = []
        return table.records.compactMap { record in
            let imdb = imdbID(record["imdb_id"])
            let tvdb = number(record["tvdb_id"]).map(String.init)
            let title = record["title"] ?? ""
            let year = record["year"].flatMap { Int($0) }.flatMap { $0 >= 1888 ? $0 : nil }
            guard imdb != nil || (!title.isEmpty && year != nil) else { return nil }
            let key = imdb ?? "\(MatchKey.normalize(title)):\(year ?? 0)"
            guard seen.insert(key).inserted else { return nil }
            let watched = record["is_watched"] == "true"
            return ImportRow(
                sourceKey: imdb ?? tvdb.map { "tvdb:\($0)" }, type: .movie, title: title, year: year,
                // A TVDB movie id alone finds nothing on TMDB; it rides along with the IMDb id.
                ids: imdb.map { ExternalIDs(imdb: $0, tvdb: tvdb) } ?? ExternalIDs(),
                status: watched ? .finished : .wishlist,
                finishedAt: watched ? date(record["watched_at"]) : nil,
                lists: []
            )
        }
    }

    // MARK: GDPR export

    /// `watch-episode-…` and `rewatch-episode-…` rows are episode plays (`s_id` the show's TVDB id,
    /// `s_no`/`ep_no` or `season_number`/`episode_number`); `user-series-…` rows carry the show's
    /// follow, watch-later and archived flags.
    static func trackingV2(_ table: CSVTable) -> [ImportRow] {
        var shows = Shows()
        var followed: Set<Int> = []
        var archived: Set<Int> = []
        for record in table.records {
            let key = record["key"] ?? ""
            let isPlay = key.hasPrefix("watch-episode-") || key.hasPrefix("rewatch-episode-")
            guard isPlay || key.hasPrefix("user-series-"),
                  let slot = shows.slot(tvdb: record["s_id"], imdb: nil, name: record["series_name"])
            else { continue }
            if isPlay {
                let (season, episode) = number(record["ep_no"]) != nil
                    ? (record["s_no"], record["ep_no"])
                    : (first(record["season_number"], record["s_no"]), record["episode_number"])
                shows.tick(slot, season: season, episode: episode, at: date(record["created_at"]))
            } else {
                if record["is_archived"] == "true" {
                    archived.insert(slot)
                }
                if record["is_followed"] == "true" || record["is_for_later"] == "true" {
                    followed.insert(slot)
                }
            }
        }
        return shows.rows(
            status: { $0.watched?.isEmpty == false ? nil : .wishlist },
            at: { archived.contains($0) ? .dropped : nil },
            keep: { slot, row in row.watched?.isEmpty == false || followed.contains(slot) || archived.contains(slot) }
        )
    }

    /// Movies only: TV Time's v1 tracking file repeats the episodes the v2 file has, without show
    /// ids. A movie has no external id, so it matches by name and release year, or by exact name
    /// up to the year it was watched when TV Time never knew the release date (`0001-01-01`).
    static func trackingV1(_ table: CSVTable) -> [ImportRow] {
        var index: [String: Int] = [:]
        var rows: [ImportRow] = []
        for record in table.records where record["entity_type"] == "movie" {
            let kind = record["type"] ?? ""
            guard kind == "watch" || kind == "towatch", let title = movieTitle(record) else { continue }
            let year = date(record["release_date"]).map { Calendar.tvTimeUTC.component(.year, from: $0) }
            let watchedAt = watchDate(record)
            let key = record["uuid"].flatMap { $0.isEmpty ? nil : $0 } ?? MatchKey.normalize(title)
            let slot: Int
            if let known = index[key] {
                slot = known
            } else {
                slot = rows.count
                index[key] = slot
                rows.append(ImportRow(
                    sourceKey: "tvtime:\(key)", type: .movie, title: title, year: year, ids: ExternalIDs(),
                    status: .wishlist, lists: [], nameOnly: year == nil ? true : nil
                ))
            }
            guard kind == "watch" else { continue }
            rows[slot].status = .finished
            if let watchedAt {
                if rows[slot].finishedAt.map({ watchedAt > $0 }) ?? true {
                    rows[slot].finishedAt = watchedAt
                }
                let watchedYear = Calendar.tvTimeUTC.component(.year, from: watchedAt)
                if year == nil {
                    rows[slot].notAfter = min(rows[slot].notAfter ?? watchedYear, watchedYear)
                }
            }
        }
        return rows
    }

    /// `followed_tv_show.csv`: every show followed, `archived` 1 when the person put it away.
    static func followedShows(_ table: CSVTable) -> [ImportRow] {
        var shows = Shows()
        var archived: Set<Int> = []
        for record in table.records {
            guard let slot = shows.slot(tvdb: record["tv_show_id"], imdb: nil, name: record["tv_show_name"])
            else { continue }
            if record["archived"] == "1" {
                archived.insert(slot)
            }
        }
        return shows.rows(status: { _ in .wishlist }, at: { archived.contains($0) ? .dropped : nil })
    }

    /// `seen_episode.csv`: episodes by show name and number, `ts` the Unix time it was watched. No
    /// show id, so each show matches by exact name, never past the year it was first watched.
    static func seenEpisodes(_ table: CSVTable) -> [ImportRow] {
        var shows = Shows()
        for record in table.records {
            guard let slot = shows.slot(tvdb: nil, imdb: nil, name: record["show_name"]) else { continue }
            let watchedAt = record["ts"].flatMap { Double($0) }.map { Date(timeIntervalSince1970: $0) }
            shows.tick(slot, season: record["episode_season_number"], episode: record["episode_number"], at: watchedAt)
        }
        return shows.rows(status: { _ in nil })
    }
}

extension TVTimeCSVParser {
    // MARK: Reading fields

    /// TV Time's slug is English whatever language `movie_name` is in (`watch-alpha-space-sweepers`
    /// for 승리호), so it is the name searched; `movie_name` is kept when the two agree.
    static func movieTitle(_ record: [String: String]) -> String? {
        let name = record["movie_name"] ?? ""
        let slug = (record["alpha_range_key"] ?? "")
            .replacingOccurrences(of: "\(record["type"] ?? "")-alpha-", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)
        if slug.isEmpty || MatchKey.normalize(slug) == MatchKey.normalize(name) {
            return name.isEmpty ? nil : name
        }
        return slug
    }

    /// `watch-date-<unix seconds>` when present, else the row's `created_at`.
    static func watchDate(_ record: [String: String]) -> Date? {
        if let key = record["watch_date_range_key"], key.hasPrefix("watch-date-"),
           let seconds = Double(key.dropFirst("watch-date-".count))
        {
            return Date(timeIntervalSince1970: seconds)
        }
        return date(record["created_at"])
    }

    /// `2019-10-04 03:43:42`, `2022-03-18T00:03:26Z` or `2025-03-20T10:15:42.067614Z`, in UTC.
    /// TV Time writes unknown dates as `0001-01-01`, which reads as none.
    static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let parts = raw.prefix(19).split(whereSeparator: { "-: T".contains($0) }).compactMap { Int($0) }
        guard parts.count >= 3, parts[0] >= 1888 else { return nil }
        var components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        components.hour = parts.count > 3 ? parts[3] : 12
        components.minute = parts.count > 4 ? parts[4] : 0
        components.second = parts.count > 5 ? parts[5] : 0
        return Calendar.tvTimeUTC.date(from: components)
    }

    static func number(_ raw: String?) -> Int? {
        raw.flatMap { Int($0) }.flatMap { $0 > 0 ? $0 : nil }
    }

    /// TV Time writes `-1` or nothing for an unknown IMDb id.
    static func imdbID(_ raw: String?) -> String? {
        guard let raw, raw.hasPrefix("tt"), raw.count > 2 else { return nil }
        return raw
    }

    private static func first(_ values: String?...) -> String? {
        values.first { $0?.isEmpty == false } ?? nil
    }

    // MARK: Shows

    /// One row per show, in the order each first appears, keyed by TVDB id, else IMDb id, else name.
    struct Shows {
        private var index: [String: Int] = [:]
        private var list: [ImportRow] = []
        private var firstYears: [Int: Int] = [:]

        /// The show's slot, or nil when the row names no show (TV Time lost some names).
        mutating func slot(tvdb rawTVDB: String?, imdb rawIMDb: String?, name rawName: String?) -> Int? {
            let tvdb = TVTimeCSVParser.number(rawTVDB).map(String.init)
            let imdb = TVTimeCSVParser.imdbID(rawIMDb)
            let name = (rawName ?? "").trimmingCharacters(in: .whitespaces)
            let normalized = MatchKey.normalize(name)
            guard let key = tvdb.map({ "tvdb:\($0)" }) ?? imdb ?? (normalized.isEmpty ? nil : "name:\(normalized)")
            else { return nil }
            if let slot = index[key] {
                if list[slot].nameOnly == nil, !name.isEmpty {
                    list[slot].title = name
                    list[slot].nameOnly = true
                }
                return slot
            }
            let slot = list.count
            index[key] = slot
            list.append(ImportRow(
                sourceKey: tvdb.map { "tvdb:\($0)" } ?? imdb ?? "tvtime:\(name)", type: .show,
                title: name.isEmpty ? (tvdb.map { "TVDB \($0)" } ?? imdb ?? "") : name,
                ids: ExternalIDs(imdb: imdb, tvdb: tvdb), lists: [],
                // With ids, the name is only tried when TMDB does not know them.
                nameOnly: name.isEmpty ? nil : true
            ))
            return slot
        }

        mutating func tick(_ slot: Int, season: String?, episode: String?, at watchedAt: Date?) {
            guard let season = season.flatMap({ Int($0) }), let episode = episode.flatMap({ Int($0) }),
                  let key = try? EpisodeKey(season: season, episode: episode)
            else { return }
            if !(list[slot].watched ?? []).contains(key) {
                list[slot].watched = (list[slot].watched ?? []) + [key]
            }
            if let watchedAt {
                let year = Calendar.tvTimeUTC.component(.year, from: watchedAt)
                firstYears[slot] = min(firstYears[slot] ?? year, year)
            }
        }

        /// The rows, ticks sorted. `at` (a status the file states for the show) wins over `status`
        /// (the one its ticks imply); `keep` drops shows the file mentions without a relationship.
        func rows(
            status: (ImportRow) -> LibraryStatus?,
            at stated: (Int) -> LibraryStatus? = { _ in nil },
            keep: (Int, ImportRow) -> Bool = { _, _ in true }
        ) -> [ImportRow] {
            list.enumerated().compactMap { slot, row in
                guard keep(slot, row) else { return nil }
                var row = row
                row.watched = row.watched?.sorted()
                row.status = stated(slot) ?? status(row)
                row.notAfter = firstYears[slot]
                return row
            }
        }
    }
}

private extension Calendar {
    static let tvTimeUTC: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()
}
