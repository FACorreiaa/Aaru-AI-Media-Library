package httpapi

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/library"
	"context"
	"net/http"
	"strconv"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// StatsTests.swift (+Rolling, +YearReview) with the library written through the routes, as Swift
// seeded it: a route tick is real watching, an import or an undone delete is not. stats_test.go
// covers the same numbers over SQL-seeded rows.

func (e *libEnv) execG6(sql string, args ...any) {
	e.t.Helper()
	_, err := e.pool.Exec(context.Background(), sql, args...)
	require.NoError(e.t, err)
}

func (e *libEnv) setWatchedAtG6(item string, season, episode int, at time.Time) {
	e.execG6(`UPDATE episode_progress SET watched_at = $1 WHERE library_item_id = $2 AND season = $3 AND episode = $4`,
		at, uuid.MustParse(item), season, episode)
}

func (e *libEnv) importTicksG6(item string, keys ...core.EpisodeKey) {
	e.t.Helper()
	_, err := e.server.Library.Store.Apply(context.Background(),
		library.Batch(library.SetEpisodes(uuid.MustParse(item), keys, nil)), e.user, library.UserCaller, "import", "Imported")
	require.NoError(e.t, err)
}

func (e *libEnv) statsG6(query string) (int, map[string]any) {
	e.t.Helper()
	rec := e.send(http.MethodGet, "/v1/me/stats?"+query, nil)
	if rec.Code != http.StatusOK {
		return rec.Code, nil
	}
	return rec.Code, decode[map[string]any](e.t, rec)
}

func (e *libEnv) statsTotalsG6(query string) map[string]int {
	e.t.Helper()
	code, body := e.statsG6(query)
	require.Equal(e.t, http.StatusOK, code, query)
	out := map[string]int{}
	for k, v := range body["totals"].(map[string]any) {
		out[k] = int(v.(float64))
	}
	return out
}

// seedStatsG6 is three real ticks (Mar 10, Mar 11, Dec 31 23:30 UTC), a date-only finished film
// (Jun 1, rated 8), a season imported today, and another user's tick.
func seedStatsG6(e *libEnv) {
	t := e.t
	show := e.add("show", e.stubShow("Severance", catalog.StatusEnded, 2, 3, false), "in_progress")
	for ep := 1; ep <= 3; ep++ {
		e.tickG6(show, 1, ep, true)
	}
	e.setWatchedAtG6(show, 1, 1, at(t, "2026-03-10T12:00:00Z"))
	e.setWatchedAtG6(show, 1, 2, at(t, "2026-03-11T12:00:00Z"))
	// New Year's Eve in UTC, already 2027 in Kiritimati (UTC+14).
	e.setWatchedAtG6(show, 1, 3, at(t, "2026-12-31T23:30:00Z"))
	// A date-only finish (a Letterboxd import) stays on its day west of UTC too.
	movie := e.add("movie", e.stubMovie("Arrival"), "finished")
	rec := e.send(http.MethodPatch, "/v1/library/items/"+movie, map[string]any{"rating": 8})
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	e.execG6(`UPDATE library_items SET finished_at = '2026-06-01T00:00:00Z' WHERE id = $1`, uuid.MustParse(movie))
	// Season 2 arrives by import: ticked today, but not watched today.
	e.importTicksG6(show, key(2, 1), key(2, 2), key(2, 3))
	// Another user's watching never shows.
	_, other := e.signIn()
	theirs := e.send(http.MethodPost, "/v1/library/items", map[string]any{
		"mediaRef": map[string]any{"type": "show", "ids": map[string]string{"tmdb": e.stubShow("Theirs", catalog.StatusEnded, 2, 3, false)}},
	}, other)
	require.Equal(t, http.StatusOK, theirs.Code, theirs.Body.String())
	theirID := decode[map[string]any](t, theirs)["id"].(string)
	rec = e.send(http.MethodPut, "/v1/library/items/"+theirID+"/episodes/1/1", map[string]any{"watched": true}, other)
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
}

// stats
func TestRouteStatsRealTicksAndDatedFinishesCountImportsAndOthersNever(t *testing.T) {
	e := newLibEnv(t)
	seedStatsG6(e)
	assert.Equal(t, map[string]int{
		"episodesWatched": 3, "minutesWatched": 3*45 + 100, "activeDays": 4, "moviesFinished": 1,
		"showsFinished": 0, "animeFinished": 0, "booksFinished": 0, "albumsFinished": 0, "mangaFinished": 0,
	}, e.statsTotalsG6("year=2026"))
	_, body := e.statsG6("year=2026")
	assert.Len(t, body["topTitles"], 2)
	assert.InDelta(t, 8.0, body["ratings"].(map[string]any)["mean"], 1e-9)
	assert.Equal(t, "2026-06-01", body["busiest"].(map[string]any)["start"])
	assert.InDelta(t, 2.0, body["longestRun"].(map[string]any)["days"], 0)
	assert.Equal(t, "2026-03-01", body["mostEpisodes"].(map[string]any)["start"])
}

// timeZones
func TestRouteStatsEdgesAreTheUsersTimeZone(t *testing.T) {
	e := newLibEnv(t)
	seedStatsG6(e)
	assert.Equal(t, 2, e.statsTotalsG6("year=2026&tz=Pacific/Kiritimati")["episodesWatched"])
	assert.Equal(t, 1, e.statsTotalsG6("year=2027&month=1&tz=Pacific/Kiritimati")["episodesWatched"])
	_, next := e.statsG6("year=2027&month=1&tz=Pacific/Kiritimati")
	assert.Len(t, next["buckets"], 31)
	assert.Equal(t, 1, e.statsTotalsG6("year=2026&month=6&tz=America/Los_Angeles")["moviesFinished"])
	code, _ := e.statsG6("year=2026&month=13")
	assert.Equal(t, http.StatusUnprocessableEntity, code)
	code, _ = e.statsG6("year=2026&tz=Nowhere")
	assert.Equal(t, http.StatusUnprocessableEntity, code)
}

// allTime
func TestRouteStatsAllTimeEqualsTheYearsSummed(t *testing.T) {
	e := newLibEnv(t)
	seedStatsG6(e)
	// An earlier year: a film finished in 2024, rated 7.5 (a half star rounds up to 8).
	heat := e.add("movie", e.stubMovie("Heat"), "finished")
	rec := e.send(http.MethodPatch, "/v1/library/items/"+heat, map[string]any{"rating": 7.5})
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	e.execG6(`UPDATE library_items SET finished_at = '2024-02-10T15:00:00Z' WHERE id = $1`, uuid.MustParse(heat))

	code, body := e.statsG6("span=all")
	require.Equal(t, http.StatusOK, code)
	thisYear := time.Now().UTC().Year()
	assert.Equal(t, "all", body["span"])
	assert.InDelta(t, float64(thisYear), body["year"], 0)
	assert.Equal(t, true, body["isPartial"])
	summed := map[string]int{}
	for y := 2024; y <= thisYear; y++ {
		for k, v := range e.statsTotalsG6("year=" + strconv.Itoa(y)) {
			summed[k] += v
		}
	}
	all := e.statsTotalsG6("span=all")
	assert.Equal(t, summed, all)
	assert.Equal(t, 3, all["episodesWatched"], "season 2's imported ticks never count")
	assert.InDelta(t, 2.0, body["byKind"].([]any)[0].(map[string]any)["finished"], 0)
	assert.Equal(t, []any{0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.0, 0.0, 0.0}, body["ratings"].(map[string]any)["distribution"])
}

// restoreIsNotActivity
func TestRouteUndoingADeleteRestoresTicksWithoutMakingThemTodaysWatching(t *testing.T) {
	e := newLibEnv(t)
	id := e.add("show", e.stubShow("Lost", catalog.StatusEnded, 2, 3, false))
	e.tickG6(id, 1, 1, true)
	rec := e.send(http.MethodDelete, "/v1/library/items/"+id, nil)
	require.Equal(t, http.StatusNoContent, rec.Code, rec.Body.String())
	e.undoLastG6()
	assert.Equal(t, 0, e.statsTotalsG6("year=" + strconv.Itoa(time.Now().UTC().Year()))["episodesWatched"])
}

// StatsTests+Rolling.swift rolling
func TestRouteStatsRollingWindowsLeaveImportsOut(t *testing.T) {
	e := newLibEnv(t)
	show := e.add("show", e.stubShow("Severance", catalog.StatusEnded, 2, 4, false), "in_progress")
	for ep := 1; ep <= 4; ep++ {
		e.tickG6(show, 1, ep, true)
	}
	today := time.Now().UTC()
	noon := func(daysAgo int) time.Time {
		d := today.AddDate(0, 0, -daysAgo)
		return time.Date(d.Year(), d.Month(), d.Day(), 12, 0, 0, 0, time.UTC)
	}
	// Today, three days ago, nine days ago (last week's window), forty days ago (neither).
	for i, days := range []int{0, 3, 9, 40} {
		e.setWatchedAtG6(show, 1, i+1, noon(days))
	}
	// A season imported today is not today's watching.
	e.importTicksG6(show, key(2, 1))

	code, body := e.statsG6("span=last7")
	require.Equal(t, http.StatusOK, code)
	assert.Equal(t, "last7", body["span"])
	assert.Equal(t, today.Format(time.DateOnly), body["until"])
	assert.Equal(t, today.AddDate(0, 0, -6).Format(time.DateOnly), body["from"])
	assert.Len(t, body["buckets"], 7)
	week := e.statsTotalsG6("span=last7")
	assert.Equal(t, 2, week["episodesWatched"])
	assert.Equal(t, 2, week["activeDays"])
	assert.InDelta(t, 1.0, body["prior"].(map[string]any)["episodesWatched"], 0)
	_, month := e.statsG6("span=last30")
	assert.Equal(t, 3, e.statsTotalsG6("span=last30")["episodesWatched"])
	assert.InDelta(t, 1.0, month["prior"].(map[string]any)["episodesWatched"], 0)
	assert.Len(t, month["buckets"], 30)
}

// StatsTests+YearReview.swift genresInStats
func TestRouteStatsStoredGenresReachTheStats(t *testing.T) {
	e := newLibEnv(t)
	show := e.add("show", e.stubShow("Severance", catalog.StatusEnded, 2, 3, false), "in_progress")
	e.tickG6(show, 1, 1, true)
	e.tickG6(show, 1, 2, true)
	e.setWatchedAtG6(show, 1, 1, at(t, "2026-03-10T12:00:00Z"))
	e.setWatchedAtG6(show, 1, 2, at(t, "2026-03-10T13:00:00Z"))
	e.execG6(`UPDATE titles SET genres = ARRAY['Drama', 'Mystery'] WHERE id = (SELECT title_id FROM library_items WHERE id = $1)`,
		uuid.MustParse(show))
	_, body := e.statsG6("year=2026")
	var names []string
	for _, g := range body["topGenres"].([]any) {
		names = append(names, g.(map[string]any)["name"].(string))
	}
	assert.Equal(t, []string{"Drama", "Mystery"}, names)
	assert.InDelta(t, 90.0, body["topGenres"].([]any)[0].(map[string]any)["minutes"], 0)
	assert.Equal(t, "2026-03-10", body["biggestDay"].(map[string]any)["start"])
	assert.Equal(t, "steady", body["persona"])
}
