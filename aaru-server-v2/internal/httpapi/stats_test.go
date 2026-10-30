package httpapi

import (
	"context"
	"fmt"
	"net/http"
	"strconv"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Ported from StatsTests.swift, StatsTests+Rolling.swift, StatsTests+YearReview.swift,
// ListenStatsTests.swift (statsMusic) and ShowWatchedTests.swift (the stats and profile parts).
// The library is seeded with plain SQL: library writes are another area's port.

type statsEnv struct {
	*harness
	user   uuid.UUID
	bearer string
}

func newStatsEnv(t *testing.T) *statsEnv {
	h := newHarness(t)
	user, bearer := h.signIn()
	return &statsEnv{harness: h, user: user, bearer: bearer}
}

func (e *statsEnv) exec(sql string, args ...any) {
	e.t.Helper()
	_, err := e.pool.Exec(context.Background(), sql, args...)
	require.NoError(e.t, err)
}

// show is an ended (or returning) show of two seasons of three 45-minute episodes, aired.
func (e *statsEnv) show(name, status string) uuid.UUID {
	e.t.Helper()
	id := uuid.New()
	e.exec(`INSERT INTO titles (id, type, title, status, runtime_minutes) VALUES ($1, 'show', $2, $3, 45)`, id, name, status)
	for season := 1; season <= 2; season++ {
		for ep := 1; ep <= 3; ep++ {
			e.exec(`INSERT INTO show_episodes (id, title_id, season, episode, airs_at, runtime_minutes)
VALUES ($1, $2, $3, $4, '2025-01-01T00:00:00Z', 45)`, uuid.New(), id, season, ep)
		}
	}
	return id
}

func (e *statsEnv) movie(name string) uuid.UUID {
	e.t.Helper()
	id := uuid.New()
	e.exec(`INSERT INTO titles (id, type, title, runtime_minutes) VALUES ($1, 'movie', $2, 100)`, id, name)
	return id
}

func (e *statsEnv) item(user, title uuid.UUID, status string, rating *float64, finishedAt *time.Time) uuid.UUID {
	e.t.Helper()
	id := uuid.New()
	e.exec(`INSERT INTO library_items (id, user_id, title_id, status, rating, finished_at, added_at, updated_at)
VALUES ($1, $2, $3, $4, $5, $6, now(), now())`, id, user, title, status, rating, finishedAt)
	return id
}

// tick is one episode tick; known false is an imported, restored or caught-up tick.
func (e *statsEnv) tick(item uuid.UUID, season, episode int, at time.Time, known bool) {
	e.t.Helper()
	e.exec(`INSERT INTO episode_progress (id, library_item_id, season, episode, watched_at, watched_at_known)
VALUES ($1, $2, $3, $4, $5, $6)`, uuid.New(), item, season, episode, at, known)
}

func (e *statsEnv) get(path string) (int, map[string]any) {
	e.t.Helper()
	rec := e.do(http.MethodGet, path, e.bearer, nil)
	if rec.Code != http.StatusOK {
		return rec.Code, nil
	}
	return rec.Code, decode[map[string]any](e.t, rec)
}

func (e *statsEnv) totals(path string) map[string]int {
	e.t.Helper()
	code, body := e.get(path)
	require.Equal(e.t, http.StatusOK, code, path)
	out := map[string]int{}
	for k, v := range body["totals"].(map[string]any) {
		out[k] = int(v.(float64))
	}
	return out
}

func at(t *testing.T, text string) time.Time {
	t.Helper()
	v, err := time.Parse(time.RFC3339, text)
	require.NoError(t, err)
	return v
}

func ratingp(v float64) *float64 { return &v }

// seed is three real ticks (Mar 10, Mar 11, Dec 31 23:30 UTC), a date-only finished film (Jun 1,
// rated 8), a season imported today, and another user's tick.
func (e *statsEnv) seed() {
	t := e.t
	show := e.item(e.user, e.show("Severance", "ended"), "in_progress", nil, nil)
	e.tick(show, 1, 1, at(t, "2026-03-10T12:00:00Z"), true)
	e.tick(show, 1, 2, at(t, "2026-03-11T12:00:00Z"), true)
	// New Year's Eve in UTC, already 2027 in Kiritimati (UTC+14).
	e.tick(show, 1, 3, at(t, "2026-12-31T23:30:00Z"), true)
	// A date-only finish (a Letterboxd import) stays on its day west of UTC too.
	june := at(t, "2026-06-01T00:00:00Z")
	e.item(e.user, e.movie("Arrival"), "finished", ratingp(8), &june)
	// Season 2 arrives by import: ticked today, but not watched today.
	for ep := 1; ep <= 3; ep++ {
		e.tick(show, 2, ep, time.Now(), false)
	}
	// Another user's watching never shows.
	other, _ := e.signIn()
	theirs := e.item(other, e.show("Theirs", "ended"), "in_progress", nil, nil)
	e.tick(theirs, 1, 1, time.Now(), true)
}

func TestStatsRealTicksAndDatedFinishes(t *testing.T) {
	e := newStatsEnv(t)
	e.seed()
	assert.Equal(t, map[string]int{
		"episodesWatched": 3, "minutesWatched": 3*45 + 100, "activeDays": 4, "moviesFinished": 1,
		"showsFinished": 0, "animeFinished": 0, "booksFinished": 0, "albumsFinished": 0, "mangaFinished": 0,
	}, e.totals("/v1/me/stats?year=2026"))
	_, body := e.get("/v1/me/stats?year=2026")
	assert.Len(t, body["topTitles"], 2)
	assert.InDelta(t, 8.0, body["ratings"].(map[string]any)["mean"], 1e-9)
	// June's 100-minute film beats March's two episodes.
	assert.Equal(t, "2026-06-01", body["busiest"].(map[string]any)["start"])
	assert.InDelta(t, 2.0, body["longestRun"].(map[string]any)["days"], 0)
	// By episodes, March (two) beats June's film and December's one.
	assert.Equal(t, "2026-03-01", body["mostEpisodes"].(map[string]any)["start"])
	assert.Equal(t, "year", body["span"])
	assert.Equal(t, "UTC", body["timeZone"])
	assert.Nil(t, body["music"])
}

func TestStatsTimeZones(t *testing.T) {
	e := newStatsEnv(t)
	e.seed()
	assert.Equal(t, 2, e.totals("/v1/me/stats?year=2026&tz=Pacific/Kiritimati")["episodesWatched"])
	assert.Equal(t, 1, e.totals("/v1/me/stats?year=2027&month=1&tz=Pacific/Kiritimati")["episodesWatched"])
	_, next := e.get("/v1/me/stats?year=2027&month=1&tz=Pacific/Kiritimati")
	assert.Len(t, next["buckets"], 31)
	assert.Equal(t, 1, e.totals("/v1/me/stats?year=2026&month=6&tz=America/Los_Angeles")["moviesFinished"])

	code, _ := e.get("/v1/me/stats?year=2026&month=13")
	assert.Equal(t, http.StatusUnprocessableEntity, code)
	code, _ = e.get("/v1/me/stats?year=2026&tz=Nowhere")
	assert.Equal(t, http.StatusUnprocessableEntity, code)
}

func TestStatsAllTime(t *testing.T) {
	e := newStatsEnv(t)
	e.seed()
	// An earlier year: a film finished in 2024, rated 7.5 (a half star rounds up to 8).
	heat := at(t, "2024-02-10T15:00:00Z")
	e.item(e.user, e.movie("Heat"), "finished", ratingp(7.5), &heat)

	code, body := e.get("/v1/me/stats?span=all")
	require.Equal(t, http.StatusOK, code)
	thisYear := time.Now().UTC().Year()
	assert.Equal(t, "all", body["span"])
	assert.InDelta(t, float64(thisYear), body["year"], 0)
	assert.Equal(t, true, body["isPartial"])
	var starts, want []string
	for _, b := range body["buckets"].([]any) {
		starts = append(starts, b.(map[string]any)["start"].(string))
	}
	for y := 2024; y <= thisYear; y++ {
		want = append(want, fmt.Sprintf("%d-01-01", y))
	}
	assert.Equal(t, want, starts)

	summed := map[string]int{}
	for y := 2024; y <= thisYear; y++ {
		for k, v := range e.totals("/v1/me/stats?year=" + strconv.Itoa(y)) {
			summed[k] += v
		}
	}
	all := e.totals("/v1/me/stats?span=all")
	assert.Equal(t, summed, all)
	assert.Equal(t, 3, all["episodesWatched"], "season 2's imported ticks never count")

	var kinds []string
	minutes := 0
	for _, k := range body["byKind"].([]any) {
		m := k.(map[string]any)
		kinds = append(kinds, m["kind"].(string))
		minutes += int(m["minutes"].(float64))
	}
	assert.Equal(t, []string{"movie", "show", "anime", "book"}, kinds)
	assert.Equal(t, all["minutesWatched"], minutes)
	assert.InDelta(t, 2.0, body["byKind"].([]any)[0].(map[string]any)["finished"], 0)
	assert.Equal(t, []any{0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.0, 0.0, 0.0}, body["ratings"].(map[string]any)["distribution"])

	for _, bad := range []string{"span=all&year=2026", "span=all&month=2", "", "month=2"} {
		code, _ := e.get("/v1/me/stats?" + bad)
		assert.Equal(t, http.StatusUnprocessableEntity, code, bad)
	}
	code, _ = e.get("/v1/me/stats?span=decade")
	assert.Equal(t, http.StatusBadRequest, code)
}

func TestStatsRestoredTicksAreNotActivity(t *testing.T) {
	e := newStatsEnv(t)
	// Undoing a delete restores the tick with its date unknown.
	item := e.item(e.user, e.show("Lost", "ended"), "in_progress", nil, nil)
	e.tick(item, 1, 1, time.Now(), false)
	assert.Equal(t, 0, e.totals("/v1/me/stats?year="+strconv.Itoa(time.Now().UTC().Year()))["episodesWatched"])
}

func TestStatsRolling(t *testing.T) {
	e := newStatsEnv(t)
	show := e.item(e.user, e.show("Severance", "ended"), "in_progress", nil, nil)
	today := time.Now().UTC()
	noon := func(daysAgo int) time.Time {
		d := today.AddDate(0, 0, -daysAgo)
		return time.Date(d.Year(), d.Month(), d.Day(), 12, 0, 0, 0, time.UTC)
	}
	// Today, three days ago, nine days ago (last week's window), forty days ago (neither).
	for i, days := range []int{0, 3, 9, 40} {
		e.exec(`INSERT INTO show_episodes (id, title_id, season, episode, runtime_minutes)
SELECT $1, title_id, 3, $2, 45 FROM library_items WHERE id = $3`, uuid.New(), i+1, show)
		e.tick(show, 3, i+1, noon(days), true)
	}
	// A season imported today is not today's watching.
	e.tick(show, 2, 1, time.Now(), false)

	code, body := e.get("/v1/me/stats?span=last7")
	require.Equal(t, http.StatusOK, code)
	assert.Equal(t, "last7", body["span"])
	assert.Equal(t, today.Format(time.DateOnly), body["until"])
	assert.Equal(t, today.AddDate(0, 0, -6).Format(time.DateOnly), body["from"])
	assert.Len(t, body["buckets"], 7)
	week := e.totals("/v1/me/stats?span=last7")
	assert.Equal(t, 2, week["episodesWatched"])
	assert.Equal(t, 2, week["activeDays"])
	assert.InDelta(t, 1.0, body["prior"].(map[string]any)["episodesWatched"], 0)

	_, month := e.get("/v1/me/stats?span=last30")
	assert.Equal(t, 3, e.totals("/v1/me/stats?span=last30")["episodesWatched"])
	assert.InDelta(t, 1.0, month["prior"].(map[string]any)["episodesWatched"], 0)
	assert.Len(t, month["buckets"], 30)

	_, calendar := e.get("/v1/me/stats?year=2026")
	assert.NotContains(t, calendar, "prior")
	assert.NotContains(t, calendar, "from")
	for _, bad := range []string{"span=last7&year=2026", "span=last30&month=2"} {
		code, _ := e.get("/v1/me/stats?" + bad)
		assert.Equal(t, http.StatusUnprocessableEntity, code, bad)
	}
}

func TestStatsGenres(t *testing.T) {
	e := newStatsEnv(t)
	title := e.show("Severance", "ended")
	show := e.item(e.user, title, "in_progress", nil, nil)
	e.tick(show, 1, 1, at(t, "2026-03-10T12:00:00Z"), true)
	e.tick(show, 1, 2, at(t, "2026-03-10T13:00:00Z"), true)
	e.exec(`UPDATE titles SET genres = ARRAY['Drama', 'Mystery'] WHERE id = $1`, title)
	_, body := e.get("/v1/me/stats?year=2026")
	var names []string
	for _, g := range body["topGenres"].([]any) {
		names = append(names, g.(map[string]any)["name"].(string))
	}
	assert.Equal(t, []string{"Drama", "Mystery"}, names)
	assert.InDelta(t, 90.0, body["topGenres"].([]any)[0].(map[string]any)["minutes"], 0)
	assert.Equal(t, "2026-03-10", body["biggestDay"].(map[string]any)["start"])
	assert.Equal(t, "steady", body["persona"])
}

func TestStatsMusic(t *testing.T) {
	e := newStatsEnv(t)
	_, empty := e.get("/v1/me/stats?span=last7")
	assert.NotContains(t, empty, "music", "nothing heard: no music block")

	listen := func(artist, track string, daysAgo float64, album, cover *string) {
		when := time.Now().Add(-time.Duration(daysAgo*86400+3600) * time.Second)
		e.exec(`INSERT INTO listens (id, user_id, listened_at, artist, track, album, track_key, duration_ms,
release_group_mbid, source) VALUES ($1, $2, $3, $4, $5, $6, lower($4) || chr(31) || lower($5), 240000, $7, 'live')`,
			uuid.New(), e.user, when, artist, track, album, cover)
	}
	ok, rg := "OK Computer", "rg-ok"
	listen("Radiohead", "Airbag", 1, &ok, &rg)
	listen("Radiohead", "Airbag", 2, nil, nil)
	listen("Radiohead", "Reckoner", 2, nil, nil)
	listen("Radiohead", "Reckoner", 3, nil, nil)
	listen("radiohead", "Weird Fishes", 4, nil, nil)
	listen("Radiohead", "Nude", 1, nil, nil)
	listen("Portishead", "Roads", 1, nil, nil)
	listen("Portishead", "Roads", 10, nil, nil)

	_, stats := e.get("/v1/me/stats?span=last7")
	music := stats["music"].(map[string]any)
	assert.InDelta(t, 7.0, music["listens"], 0)
	assert.InDelta(t, 28.0, music["minutes"], 0)
	assert.InDelta(t, 1.0, music["priorListens"], 0)
	assert.InDelta(t, 4.0, music["priorMinutes"], 0)
	top := music["topArtist"].(map[string]any)
	assert.Equal(t, "Radiohead", top["artist"])
	assert.InDelta(t, 6.0, top["count"], 0)
	assert.Equal(t, "https://coverartarchive.org/release-group/rg-ok/front-250", top["coverUrl"])
	var tracks []string
	for _, tr := range music["topArtistTracks"].([]any) {
		tracks = append(tracks, tr.(map[string]any)["track"].(string))
	}
	require.Len(t, tracks, 3)
	assert.Equal(t, []string{"Airbag", "Reckoner"}, tracks[:2])
	assert.NotContains(t, tracks, "Roads", "only the top artist's tracks")
	assert.InDelta(t, 0.0, stats["totals"].(map[string]any)["minutesWatched"], 0, "listening is not watching")

	_, year := e.get("/v1/me/stats?year=" + strconv.Itoa(time.Now().Year()))
	assert.NotContains(t, year["music"].(map[string]any), "priorListens", "a calendar period has no prior window")
}

func TestProfileStatsWholeShowWatched(t *testing.T) {
	e := newStatsEnv(t)
	item := e.item(e.user, e.show("Severance", "ended"), "finished", nil, nil)
	e.tick(item, 1, 1, time.Now(), true)
	// PROG-005's whole show watched ticks the rest undated: not today's activity.
	for _, k := range [][2]int{{1, 2}, {1, 3}, {2, 1}, {2, 2}, {2, 3}} {
		e.tick(item, k[0], k[1], time.Now(), false)
	}
	assert.Equal(t, 1, e.totals("/v1/me/stats?span=last7")["episodesWatched"])
	_, profile := e.get("/v1/me/profile/stats")
	assert.InDelta(t, 6.0, profile["episodesWatched"], 0, "the profile counts all six")
	assert.InDelta(t, 270.0, profile["minutesWatched"], 0)
	assert.InDelta(t, 1.0, profile["shows"].(map[string]any)["finished"], 0)
}

func TestProfileStats(t *testing.T) {
	e := newStatsEnv(t)
	_, empty := e.get("/v1/me/profile/stats")
	assert.InDelta(t, 0.0, empty["minutesWatched"], 0)
	assert.Equal(t, []any{}, empty["topGenres"])
	assert.NotNil(t, empty["memberSince"])

	e.item(e.user, e.movie("Heat"), "finished", ratingp(8), nil)
	dark := e.item(e.user, e.show("Dark", "returning"), "in_progress", ratingp(6), nil)
	for ep := 1; ep <= 3; ep++ {
		e.tick(dark, 1, ep, time.Now(), false)
	}
	_, profile := e.get("/v1/me/profile/stats")
	assert.InDelta(t, float64(100+3*45), profile["minutesWatched"], 0)
	assert.InDelta(t, 1.0, profile["movies"].(map[string]any)["finished"], 0)
	assert.InDelta(t, 1.0, profile["shows"].(map[string]any)["inProgress"], 0)
	ratings := profile["ratings"].(map[string]any)
	assert.InDelta(t, 2.0, ratings["count"], 0)
	assert.InDelta(t, 7.0, ratings["mean"], 1e-9)
	top := profile["mostWatched"].([]any)[0].(map[string]any)
	assert.Equal(t, "Dark", top["title"].(map[string]any)["title"])
	assert.Equal(t, "Heat", ratings["highest"].(map[string]any)["title"])
}

func TestStatsSignedOut(t *testing.T) {
	h := newHarness(t)
	assert.Equal(t, http.StatusUnauthorized, h.do(http.MethodGet, "/v1/me/stats?year=2026", "", nil).Code)
	assert.Equal(t, http.StatusUnauthorized, h.do(http.MethodGet, "/v1/me/profile/stats", "", nil).Code)
}
