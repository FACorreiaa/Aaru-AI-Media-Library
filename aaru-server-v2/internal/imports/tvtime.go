package imports

import (
	"aaru-go-api/internal/core"
	"slices"
	"strconv"
	"strings"
	"time"
)

// IMP-012: TV Time's exports, one CSV at a time (TVTimeCSVParser). TV Time closed in July 2026 and
// left two kinds of export, both zips of CSVs the person unzips:
//
//   - Export my data (the in-app tool, 2026): `tvtime-series-episodes.csv` (every episode of every
//     followed show, `is_watched` per episode), `tvtime-series.csv` (each show's status) and
//     `tvtime-movies.csv`. TVDB and IMDb ids on every row.
//   - GDPR export (~50 CSVs): `tracking-prod-records-v2.csv` (episode watches by show TVDB id, plus
//     follow / watch-later / archived flags per show), `tracking-prod-records.csv` (movies, by name
//     and release date only), `followed_tv_show.csv` (followed shows) and, in older exports,
//     `seen_episode.csv` (episodes by show name).
//
// The layout is told by its columns, not its file name. Shows match by TVDB id (→ TMDB), then
// IMDb; when TMDB does not know an old TVDB id, by exact name as `nameOnly` allows. Episode numbers
// are TVDB's aired order, which TMDB follows for nearly every show.

// TVTimeLayout is which TV Time file a table is. 0 is none.
type TVTimeLayout int

// The layouts.
const (
	TVTimeSeriesEpisodes TVTimeLayout = iota + 1
	TVTimeSeries
	TVTimeMovies
	TVTimeTrackingV2
	TVTimeTrackingV1
	TVTimeFollowedShows
	TVTimeSeenEpisodes
)

// TVTimeLayoutOf tells the file by its headers.
func TVTimeLayoutOf(headers map[string]bool) TVTimeLayout {
	has := func(names ...string) bool {
		for _, n := range names {
			if !headers[n] {
				return false
			}
		}
		return true
	}
	switch {
	case has("series_tvdb_id", "season", "episode"):
		return TVTimeSeriesEpisodes
	case has("tvdb_id", "imdb_id", "title", "is_watched", "watched_at"):
		return TVTimeMovies
	case has("uuid", "tvdb_id", "imdb_id", "title", "status"):
		return TVTimeSeries
	case has("key") && (has("s_id") || has("series_name")):
		return TVTimeTrackingV2
	case has("type-uuid-n"):
		return TVTimeTrackingV1
	case has("tv_show_id", "notification_offset"):
		return TVTimeFollowedShows
	case has("show_name", "episode_season_number", "episode_number"):
		return TVTimeSeenEpisodes
	}
	return 0
}

const tvTimeFiles = "tvtime-series-episodes.csv, tvtime-series.csv or tvtime-movies.csv from Export my data, " +
	"or tracking-prod-records-v2.csv, tracking-prod-records.csv, followed_tv_show.csv or " +
	"seen_episode.csv from a GDPR export"

// ParseTVTime reads one TV Time file.
func ParseTVTime(table CSVTable) ([]Row, error) {
	switch TVTimeLayoutOf(table.headerSet()) {
	case TVTimeSeriesEpisodes:
		return tvTimeSeriesEpisodes(table), nil
	case TVTimeSeries:
		return tvTimeSeries(table), nil
	case TVTimeMovies:
		return tvTimeMovies(table), nil
	case TVTimeTrackingV2:
		return tvTimeTrackingV2(table), nil
	case TVTimeTrackingV1:
		return tvTimeTrackingV1(table), nil
	case TVTimeFollowedShows:
		return tvTimeFollowedShows(table), nil
	case TVTimeSeenEpisodes:
		return tvTimeSeenEpisodes(table), nil
	}
	return nil, formatError("This is not a TV Time file Aaru reads. Unzip the export and upload " + tvTimeFiles +
		", one at a time.")
}

// MARK: Export my data

func plannedUnlessTicked(row Row) *core.LibraryStatus {
	if len(row.Watched) > 0 {
		return nil
	}
	return ptr(core.StatusWishlist)
}

// tvTimeSeriesEpisodes: one row per show, its watched episodes ticked. A followed show with none
// watched is planned.
func tvTimeSeriesEpisodes(table CSVTable) []Row {
	var shows tvTimeShows
	for _, record := range table.Records {
		slot, ok := shows.slot(record.opt("series_tvdb_id"), record.opt("series_imdb_id"), record.opt("title"))
		if !ok {
			continue
		}
		if record.is("is_watched", "true") {
			shows.tick(slot, record.opt("season"), record.opt("episode"), TVTimeDate(record.opt("watched_at")))
		}
	}
	return shows.rows(plannedUnlessTicked, nil, nil)
}

// TVTimeStatus is TV Time's word for where the person is with a show.
func TVTimeStatus(word *string) *core.LibraryStatus {
	if word == nil {
		return nil
	}
	switch strings.ToLower(*word) {
	case "not_started_yet":
		return ptr(core.StatusWishlist)
	case "continuing", "up_to_date", "watching":
		return ptr(core.StatusInProgress)
	case "stopped", "archived":
		return ptr(core.StatusDropped)
	}
	return nil
}

func tvTimeSeries(table CSVTable) []Row {
	var shows tvTimeShows
	statuses := map[int]core.LibraryStatus{}
	for _, record := range table.Records {
		slot, ok := shows.slot(record.opt("tvdb_id"), record.opt("imdb_id"), record.opt("title"))
		if !ok {
			continue
		}
		if status := TVTimeStatus(record.opt("status")); status != nil {
			statuses[slot] = *status
		}
	}
	return shows.rows(func(Row) *core.LibraryStatus { return nil }, func(slot int) *core.LibraryStatus {
		if s, ok := statuses[slot]; ok {
			return &s
		}
		return nil
	}, nil)
}

// tvTimeMovies: `is_watched` false is a film on the person's to-watch list.
func tvTimeMovies(table CSVTable) []Row {
	seen := map[string]bool{}
	var rows []Row
	for _, record := range table.Records {
		imdb := tvTimeIMDb(record.opt("imdb_id"))
		var tvdb *string
		if n := tvTimeNumber(record.opt("tvdb_id")); n != nil {
			tvdb = ptr(strconv.Itoa(*n))
		}
		title := record["title"]
		year := optInt(record.opt("year"))
		if year != nil && *year < 1888 {
			year = nil
		}
		if imdb == nil && (title == "" || year == nil) {
			continue
		}
		var key string
		if imdb != nil {
			key = *imdb
		} else {
			key = core.NormalizeTitle(title) + ":" + strconv.Itoa(*year)
		}
		if seen[key] {
			continue
		}
		seen[key] = true
		watched := record.is("is_watched", "true")
		row := Row{Type: core.MediaMovie, Title: title, Year: year, Lists: []string{}}
		switch {
		case imdb != nil:
			row.SourceKey = imdb
		case tvdb != nil:
			row.SourceKey = ptr("tvdb:" + *tvdb)
		}
		// A TVDB movie id alone finds nothing on TMDB; it rides along with the IMDb id.
		if imdb != nil {
			row.IDs = core.ExternalIDs{IMDB: *imdb}
			if tvdb != nil {
				row.IDs.TVDB = *tvdb
			}
		}
		if watched {
			row.Status = ptr(core.StatusFinished)
			row.FinishedAt = TVTimeDate(record.opt("watched_at"))
		} else {
			row.Status = ptr(core.StatusWishlist)
		}
		rows = append(rows, row)
	}
	return rows
}

// MARK: GDPR export

// tvTimeTrackingV2: `watch-episode-…` and `rewatch-episode-…` rows are episode plays (`s_id` the
// show's TVDB id, `s_no`/`ep_no` or `season_number`/`episode_number`); `user-series-…` rows carry
// the show's follow, watch-later and archived flags.
func tvTimeTrackingV2(table CSVTable) []Row {
	var shows tvTimeShows
	followed := map[int]bool{}
	archived := map[int]bool{}
	for _, record := range table.Records {
		key := record["key"]
		isPlay := strings.HasPrefix(key, "watch-episode-") || strings.HasPrefix(key, "rewatch-episode-")
		if !isPlay && !strings.HasPrefix(key, "user-series-") {
			continue
		}
		slot, ok := shows.slot(record.opt("s_id"), nil, record.opt("series_name"))
		if !ok {
			continue
		}
		if isPlay {
			season, episode := record.opt("s_no"), record.opt("ep_no")
			if tvTimeNumber(record.opt("ep_no")) == nil {
				season, episode = firstNonEmpty(record.opt("season_number"), record.opt("s_no")), record.opt("episode_number")
			}
			shows.tick(slot, season, episode, TVTimeDate(record.opt("created_at")))
			continue
		}
		if record.is("is_archived", "true") {
			archived[slot] = true
		}
		if record.is("is_followed", "true") || record.is("is_for_later", "true") {
			followed[slot] = true
		}
	}
	return shows.rows(plannedUnlessTicked, func(slot int) *core.LibraryStatus {
		if archived[slot] {
			return ptr(core.StatusDropped)
		}
		return nil
	}, func(slot int, row Row) bool {
		return len(row.Watched) > 0 || followed[slot] || archived[slot]
	})
}

// tvTimeTrackingV1: movies only. TV Time's v1 tracking file repeats the episodes the v2 file has,
// without show ids. A movie has no external id, so it matches by name and release year, or by
// exact name up to the year it was watched when TV Time never knew the release date (`0001-01-01`).
func tvTimeTrackingV1(table CSVTable) []Row {
	index := map[string]int{}
	var rows []Row
	for _, record := range table.Records {
		if !record.is("entity_type", "movie") {
			continue
		}
		kind := record["type"]
		if kind != "watch" && kind != "towatch" {
			continue
		}
		title := tvTimeMovieTitle(record)
		if title == nil {
			continue
		}
		var year *int
		if d := TVTimeDate(record.opt("release_date")); d != nil {
			year = ptr(d.Year())
		}
		watchedAt := tvTimeWatchDate(record)
		key := record["uuid"]
		if key == "" {
			key = core.NormalizeTitle(*title)
		}
		slot, known := index[key]
		if !known {
			slot = len(rows)
			index[key] = slot
			row := Row{
				SourceKey: ptr("tvtime:" + key), Type: core.MediaMovie, Title: *title, Year: year,
				Status: ptr(core.StatusWishlist), Lists: []string{},
			}
			if year == nil {
				row.NameOnly = ptr(true)
			}
			rows = append(rows, row)
		}
		if kind != "watch" {
			continue
		}
		rows[slot].Status = ptr(core.StatusFinished)
		if watchedAt != nil {
			if rows[slot].FinishedAt == nil || watchedAt.After(*rows[slot].FinishedAt) {
				rows[slot].FinishedAt = watchedAt
			}
			watchedYear := watchedAt.Year()
			if year == nil && (rows[slot].NotAfter == nil || watchedYear < *rows[slot].NotAfter) {
				rows[slot].NotAfter = &watchedYear
			}
		}
	}
	return rows
}

// tvTimeFollowedShows: `followed_tv_show.csv`, every show followed, `archived` 1 when the person
// put it away.
func tvTimeFollowedShows(table CSVTable) []Row {
	var shows tvTimeShows
	archived := map[int]bool{}
	for _, record := range table.Records {
		slot, ok := shows.slot(record.opt("tv_show_id"), nil, record.opt("tv_show_name"))
		if !ok {
			continue
		}
		if record.is("archived", "1") {
			archived[slot] = true
		}
	}
	return shows.rows(func(Row) *core.LibraryStatus { return ptr(core.StatusWishlist) }, func(slot int) *core.LibraryStatus {
		if archived[slot] {
			return ptr(core.StatusDropped)
		}
		return nil
	}, nil)
}

// tvTimeSeenEpisodes: `seen_episode.csv`, episodes by show name and number, `ts` the Unix time it
// was watched. No show id, so each show matches by exact name, never past the year it was first
// watched.
func tvTimeSeenEpisodes(table CSVTable) []Row {
	var shows tvTimeShows
	for _, record := range table.Records {
		slot, ok := shows.slot(nil, nil, record.opt("show_name"))
		if !ok {
			continue
		}
		var watchedAt *time.Time
		if s := optDouble(record.opt("ts")); s != nil {
			watchedAt = ptr(unixDate(*s))
		}
		shows.tick(slot, record.opt("episode_season_number"), record.opt("episode_number"), watchedAt)
	}
	return shows.rows(func(Row) *core.LibraryStatus { return nil }, nil, nil)
}

// MARK: Reading fields

// tvTimeMovieTitle: TV Time's slug is English whatever language `movie_name` is in
// (`watch-alpha-space-sweepers` for 승리호), so it is the name searched; `movie_name` is kept when
// the two agree.
func tvTimeMovieTitle(record Record) *string {
	name := record["movie_name"]
	slug := strings.ReplaceAll(record["alpha_range_key"], record["type"]+"-alpha-", "")
	slug = trimWS(strings.ReplaceAll(slug, "-", " "))
	if slug == "" || core.NormalizeTitle(slug) == core.NormalizeTitle(name) {
		if name == "" {
			return nil
		}
		return &name
	}
	return &slug
}

// tvTimeWatchDate is `watch-date-<unix seconds>` when present, else the row's `created_at`.
func tvTimeWatchDate(record Record) *time.Time {
	if key, ok := record["watch_date_range_key"]; ok && strings.HasPrefix(key, "watch-date-") {
		if seconds, ok := swiftDouble(strings.TrimPrefix(key, "watch-date-")); ok {
			return ptr(unixDate(seconds))
		}
	}
	return TVTimeDate(record.opt("created_at"))
}

// TVTimeDate reads `2019-10-04 03:43:42`, `2022-03-18T00:03:26Z` or `2025-03-20T10:15:42.067614Z`,
// in UTC. A day alone is at noon. TV Time writes unknown dates as `0001-01-01`, which reads as none.
func TVTimeDate(raw *string) *time.Time {
	if raw == nil {
		return nil
	}
	var parts []int
	for _, p := range splitFunc(charPrefix(*raw, 19), func(r rune) bool { return strings.ContainsRune("-: T", r) }) {
		if n, ok := swiftInt(p); ok {
			parts = append(parts, n)
		}
	}
	if len(parts) < 3 || parts[0] < 1888 {
		return nil
	}
	hour, minute, second := 12, 0, 0
	if len(parts) > 3 {
		hour = parts[3]
	}
	if len(parts) > 4 {
		minute = parts[4]
	}
	if len(parts) > 5 {
		second = parts[5]
	}
	return ptr(time.Date(parts[0], time.Month(parts[1]), parts[2], hour, minute, second, 0, time.UTC))
}

// tvTimeNumber is a positive integer, else nil.
func tvTimeNumber(raw *string) *int {
	n := optInt(raw)
	if n == nil || *n <= 0 {
		return nil
	}
	return n
}

// tvTimeIMDb: TV Time writes `-1` or nothing for an unknown IMDb id.
func tvTimeIMDb(raw *string) *string {
	if raw == nil || !strings.HasPrefix(*raw, "tt") || charCount(*raw) <= 2 {
		return nil
	}
	return raw
}

func firstNonEmpty(values ...*string) *string {
	for _, v := range values {
		if v != nil && *v != "" {
			return v
		}
	}
	return nil
}

// MARK: Shows

// tvTimeShows is one row per show, in the order each first appears, keyed by TVDB id, else IMDb
// id, else name.
type tvTimeShows struct {
	index      map[string]int
	list       []Row
	firstYears map[int]int
}

// slot is the show's slot; false when the row names no show (TV Time lost some names).
func (s *tvTimeShows) slot(rawTVDB, rawIMDb, rawName *string) (int, bool) {
	if s.index == nil {
		s.index = map[string]int{}
		s.firstYears = map[int]int{}
	}
	var tvdb *string
	if n := tvTimeNumber(rawTVDB); n != nil {
		tvdb = ptr(strconv.Itoa(*n))
	}
	imdb := tvTimeIMDb(rawIMDb)
	name := ""
	if rawName != nil {
		name = trimWS(*rawName)
	}
	normalized := core.NormalizeTitle(name)
	var key string
	switch {
	case tvdb != nil:
		key = "tvdb:" + *tvdb
	case imdb != nil:
		key = *imdb
	case normalized != "":
		key = "name:" + normalized
	default:
		return 0, false
	}
	if slot, ok := s.index[key]; ok {
		if s.list[slot].NameOnly == nil && name != "" {
			s.list[slot].Title = name
			s.list[slot].NameOnly = ptr(true)
		}
		return slot, true
	}
	slot := len(s.list)
	s.index[key] = slot
	row := Row{Type: core.MediaShow, Title: name, Lists: []string{}}
	switch {
	case tvdb != nil:
		row.SourceKey = ptr("tvdb:" + *tvdb)
	case imdb != nil:
		row.SourceKey = imdb
	default:
		row.SourceKey = ptr("tvtime:" + name)
	}
	if name == "" {
		switch {
		case tvdb != nil:
			row.Title = "TVDB " + *tvdb
		case imdb != nil:
			row.Title = *imdb
		}
	} else {
		// With ids, the name is only tried when TMDB does not know them.
		row.NameOnly = ptr(true)
	}
	if imdb != nil {
		row.IDs.IMDB = *imdb
	}
	if tvdb != nil {
		row.IDs.TVDB = *tvdb
	}
	s.list = append(s.list, row)
	return slot, true
}

func (s *tvTimeShows) tick(slot int, season, episode *string, watchedAt *time.Time) {
	sn, en := optInt(season), optInt(episode)
	if sn == nil || en == nil {
		return
	}
	key, err := core.NewEpisodeKey(*sn, *en)
	if err != nil {
		return
	}
	if !slices.Contains(s.list[slot].Watched, key) {
		s.list[slot].Watched = append(s.list[slot].Watched, key)
	}
	if watchedAt != nil {
		year := watchedAt.Year()
		if first, ok := s.firstYears[slot]; !ok || year < first {
			s.firstYears[slot] = year
		}
	}
}

// rows are the shows, ticks sorted. stated (a status the file states for the show) wins over
// implied (the one its ticks imply); keep drops shows the file mentions without a relationship.
func (s *tvTimeShows) rows(implied func(Row) *core.LibraryStatus, stated func(int) *core.LibraryStatus,
	keep func(int, Row) bool,
) []Row {
	var out []Row
	for slot, row := range s.list {
		if keep != nil && !keep(slot, row) {
			continue
		}
		if row.Watched != nil {
			row.Watched = slices.Clone(row.Watched)
			slices.SortFunc(row.Watched, core.EpisodeKey.Compare)
		}
		var status *core.LibraryStatus
		if stated != nil {
			status = stated(slot)
		}
		if status == nil {
			status = implied(row)
		}
		row.Status = status
		if year, ok := s.firstYears[slot]; ok {
			row.NotAfter = ptr(year)
		}
		out = append(out, row)
	}
	return out
}
