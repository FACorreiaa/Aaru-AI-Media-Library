package httpapi

import (
	"context"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Ported from ScheduleTests.swift and WatchingTests.swift. Library writes are not on this branch,
// so items, ticks and episodes are plain SQL, the way an add or a tick leaves them.

const day = 24 * time.Hour

// seedShow is a hydrated show whose season 1 episodes air at these offsets (in days) from now.
func (h *harness) seedShow(name string, anime bool, status string, runtime int, days ...float64) uuid.UUID {
	h.t.Helper()
	ctx := context.Background()
	id := uuid.New()
	_, err := h.pool.Exec(ctx, `INSERT INTO titles (id, type, title, year, tmdb, is_anime, status, episodes_hydrated_at)
VALUES ($1, 'show', $2, 2026, $3, $4, $5, now())`, id, name, uuid.NewString(), anime, status)
	require.NoError(h.t, err)
	now := time.Now()
	for i, offset := range days {
		_, err := h.pool.Exec(ctx, `INSERT INTO show_episodes (id, title_id, season, episode, name, airs_at, runtime_minutes)
VALUES ($1, $2, 1, $3, $4, $5, $6)`, uuid.New(), id, i+1, name+" "+strconv.Itoa(i+1),
			now.Add(time.Duration(offset*float64(day))), runtime)
		require.NoError(h.t, err)
	}
	return id
}

// seedTitle is a title of another kind.
func (h *harness) seedTitle(kind, name string) uuid.UUID {
	h.t.Helper()
	id := uuid.New()
	_, err := h.pool.Exec(context.Background(), `INSERT INTO titles (id, type, title, year, tmdb) VALUES ($1, $2, $3, 2016, $4)`,
		id, kind, name, uuid.NewString())
	require.NoError(h.t, err)
	return id
}

// addItem puts a title in a user's library; byHand is a status chosen by a tap.
func (h *harness) addItem(user, title uuid.UUID, status string, byHand bool) uuid.UUID {
	h.t.Helper()
	id := uuid.New()
	_, err := h.pool.Exec(context.Background(), `INSERT INTO library_items (id, user_id, title_id, status, added_at, updated_at, status_by_hand)
VALUES ($1, $2, $3, $4, clock_timestamp(), clock_timestamp(), $5)`, id, user, title, status, byHand)
	require.NoError(h.t, err)
	return id
}

// tick marks an episode watched; known is a live tick (an import's is not).
func (h *harness) tick(item uuid.UUID, season, episode int, known bool) {
	h.t.Helper()
	_, err := h.pool.Exec(context.Background(), `INSERT INTO episode_progress (id, library_item_id, season, episode, watched_at_known)
VALUES ($1, $2, $3, $4, $5)`, uuid.New(), item, season, episode, known)
	require.NoError(h.t, err)
	_, err = h.pool.Exec(context.Background(), `UPDATE library_items SET updated_at = clock_timestamp() WHERE id = $1`, item)
	require.NoError(h.t, err)
}

// touch backdates an item's last change by days.
func (h *harness) touch(item uuid.UUID, days int) {
	h.t.Helper()
	_, err := h.pool.Exec(context.Background(),
		`UPDATE library_items SET updated_at = now() - $2::int * interval '1 day' WHERE id = $1`, item, days)
	require.NoError(h.t, err)
}

func calendarPath(from, to time.Time) string {
	return "/v1/calendar?from=" + url.QueryEscape(from.UTC().Format(time.RFC3339)) + "&to=" + url.QueryEscape(to.UTC().Format(time.RFC3339))
}

type obj = map[string]any

func TestCalendarWeek(t *testing.T) {
	h := newHarness(t)
	user, bearer := h.signIn()
	other, _ := h.signIn()
	// Season premieres in 1 day; episodes 2 and 3 (the finale) air in 3 and 5 days.
	h.addItem(user, h.seedShow("Arcane", false, "returning", 50, 1, 3, 5), "wishlist", true)
	// Aired long ago: not in this week.
	h.addItem(user, h.seedShow("Old", false, "returning", 50, -200, -199), "in_progress", true)
	// Airing this week, but dropped: not tracked.
	h.addItem(user, h.seedShow("Dropped", false, "returning", 50, 2), "dropped", true)
	// Another user's show airing this week.
	h.addItem(other, h.seedShow("Theirs", false, "returning", 50, 2), "wishlist", true)

	now := time.Now()
	rec := h.do(http.MethodGet, calendarPath(now, now.Add(7*day)), bearer, nil)
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	body := decode[obj](t, rec)
	rows := body["items"].([]any)
	var numbers []float64
	var kinds []string
	for _, r := range rows {
		row := r.(obj)
		numbers = append(numbers, row["number"].(float64))
		kinds = append(kinds, row["kind"].(string))
		assert.Equal(t, "Arcane", row["title"].(obj)["title"])
	}
	assert.Equal(t, []float64{1, 2, 3}, numbers)
	assert.Equal(t, []string{"premiere", "regular", "finale"}, kinds)
	assert.InDelta(t, 0, body["pendingShows"], 0)

	tooLong := h.do(http.MethodGet, calendarPath(now, now.Add(43*day)), bearer, nil)
	assert.Equal(t, http.StatusUnprocessableEntity, tooLong.Code)
	errBody := decode[obj](t, tooLong)
	assert.Equal(t, "validation_failed", errBody["code"])
	assert.Equal(t, "The range must be positive and at most 42 days.", errBody["details"].(obj)["to"])
	backwards := h.do(http.MethodGet, calendarPath(now, now), bearer, nil)
	assert.Equal(t, http.StatusUnprocessableEntity, backwards.Code)

	// A browser's `toISOString()` carries milliseconds; the server reads it the same.
	fractional := h.do(http.MethodGet, "/v1/calendar?from=2026-10-18T00:00:00.000Z&to=2026-10-25T00:00:00.000Z", bearer, nil)
	assert.Equal(t, http.StatusOK, fractional.Code, fractional.Body.String())
}

func TestCalendarPendingShows(t *testing.T) {
	h := newHarness(t)
	user, bearer := h.signIn()
	waiting := h.seedTitle("show", "Imported")
	gone := h.seedTitle("show", "Gone")
	// As an import leaves them: no episodes yet. "Gone" was tried once and the provider failed.
	_, err := h.pool.Exec(context.Background(), `UPDATE titles SET episodes_attempted_at = now() WHERE id = $1`, gone)
	require.NoError(t, err)
	h.addItem(user, waiting, "wishlist", true)
	h.addItem(user, gone, "wishlist", true)
	// A film is never waited for.
	h.addItem(user, h.seedTitle("movie", "Arrival"), "wishlist", true)

	now := time.Now()
	body := decode[obj](t, h.do(http.MethodGet, calendarPath(now, now.Add(7*day)), bearer, nil))
	assert.Empty(t, body["items"])
	assert.InDelta(t, 1, body["pendingShows"], 0, "a show the provider failed on is not waited for")
}

func TestCalendarArtworkAndAirTime(t *testing.T) {
	h := newHarness(t)
	user, bearer := h.signIn()
	show := h.seedShow("Andor", false, "returning", 50, 1, 2)
	ctx := context.Background()
	_, err := h.pool.Exec(ctx, `UPDATE titles SET backdrop_url = 'https://image.tmdb.org/t/p/w780/andor.jpg',
    network = 'Disney+', byline = 'never on a schedule row' WHERE id = $1`, show)
	require.NoError(t, err)
	_, err = h.pool.Exec(ctx, `UPDATE show_episodes SET airs_at_exact = true, overview = 'Cassian meets Luthen.',
    still_url = 'https://image.tmdb.org/t/p/w300/two.jpg' WHERE title_id = $1 AND episode = 2`, show)
	require.NoError(t, err)
	h.addItem(user, show, "wishlist", true)

	now := time.Now()
	rows := decode[obj](t, h.do(http.MethodGet, calendarPath(now, now.Add(7*day)), bearer, nil))["items"].([]any)
	require.Len(t, rows, 2)
	first, last := rows[0].(obj), rows[1].(obj)
	assert.Equal(t, false, first["airTimeKnown"])
	assert.Equal(t, true, last["airTimeKnown"])
	assert.Equal(t, "Cassian meets Luthen.", last["episodeOverview"])
	assert.Equal(t, "https://image.tmdb.org/t/p/w300/two.jpg", last["stillUrl"])
	assert.NotContains(t, first, "stillUrl")
	assert.Equal(t, false, first["watched"])
	assert.InDelta(t, 50, first["runtimeMinutes"], 0)
	title := first["title"].(obj)
	assert.Equal(t, "https://image.tmdb.org/t/p/w780/andor.jpg", title["backdropUrl"])
	assert.Equal(t, "Disney+", title["network"])
	assert.NotContains(t, title, "byline", "schedule rows read the same title columns as Swift")
}

func TestUpNextAdvances(t *testing.T) {
	h := newHarness(t)
	user, bearer := h.signIn()
	// Three aired episodes and one airing next week.
	item := h.addItem(user, h.seedShow("Severance", false, "returning", 50, -30, -23, -16, 7), "in_progress", true)
	h.tick(item, 1, 1, true)
	movie := h.addItem(user, h.seedTitle("movie", "Arrival"), "wishlist", true)

	home := decode[obj](t, h.do(http.MethodGet, "/v1/up-next", bearer, nil))
	row := home["continueWatching"].([]any)[0].(obj)
	assert.InDelta(t, 2, row["next"].(obj)["number"], 0)
	assert.Equal(t, "Severance 2", row["nextName"])
	assert.InDelta(t, 2, row["remainingCount"], 0)
	assert.InDelta(t, 100, row["remainingMinutes"], 0, "two aired episodes of 50 minutes")
	assert.Equal(t, false, row["isFinale"])
	start := home["startWatching"].([]any)
	require.Len(t, start, 1)
	assert.Equal(t, movie.String(), strings.ToLower(start[0].(obj)["libraryItemId"].(string)))

	h.tick(item, 1, 2, true)
	home = decode[obj](t, h.do(http.MethodGet, "/v1/up-next", bearer, nil))
	assert.InDelta(t, 3, home["continueWatching"].([]any)[0].(obj)["next"].(obj)["number"], 0)

	h.tick(item, 1, 3, true)
	home = decode[obj](t, h.do(http.MethodGet, "/v1/up-next", bearer, nil))
	assert.Empty(t, home["continueWatching"], "caught up until episode 4 airs")
}

func TestUpNextFinaleFlag(t *testing.T) {
	h := newHarness(t)
	user, bearer := h.signIn()
	item := h.addItem(user, h.seedShow("Shogun", false, "ended", 50, -20, -13), "in_progress", true)
	h.tick(item, 1, 1, true)
	home := decode[obj](t, h.do(http.MethodGet, "/v1/up-next", bearer, nil))
	assert.Equal(t, true, home["continueWatching"].([]any)[0].(obj)["isFinale"])
}

func TestUpNextCounts(t *testing.T) {
	h := newHarness(t)
	user, bearer := h.signIn()
	other, _ := h.signIn()
	h.addItem(user, h.seedTitle("movie", "Plan"), "wishlist", true)
	h.addItem(user, h.seedTitle("movie", "Seen"), "finished", true)
	h.addItem(user, h.seedTitle("movie", "Quit"), "dropped", true)
	h.addItem(user, h.seedTitle("book", "Reading"), "in_progress", true)
	h.addItem(user, h.seedTitle("book", "Paused"), "on_hold", true)
	h.addItem(other, h.seedTitle("movie", "Theirs"), "dropped", true)

	counts := decode[obj](t, h.do(http.MethodGet, "/v1/up-next", bearer, nil))["counts"]
	assert.Equal(t, obj{"wishlist": 1.0, "inProgress": 1.0, "onHold": 1.0, "finished": 1.0, "dropped": 1.0}, counts)
}

func TestUpNextUnfinished(t *testing.T) {
	h := newHarness(t)
	user, bearer := h.signIn()
	other, _ := h.signIn()
	dropped := h.addItem(user, h.seedShow("Lost Cause", false, "returning", 50, -30, -23), "dropped", true)
	stale := h.addItem(user, h.seedTitle("book", "Old Book"), "in_progress", true)
	fresh := h.addItem(user, h.seedTitle("book", "Recent Book"), "in_progress", true)
	// In progress, untouched for 40 days, but with an aired episode to watch: Continue watching.
	continuing := h.addItem(user, h.seedShow("Paused Show", false, "returning", 50, -60, -50), "in_progress", true)
	h.touch(stale, 31)
	h.touch(fresh, 29)
	h.touch(continuing, 40)
	h.touch(dropped, 2)
	h.addItem(other, h.seedTitle("movie", "Their Drop"), "dropped", true)

	home := decode[obj](t, h.do(http.MethodGet, "/v1/up-next", bearer, nil))
	rows := home["unfinished"].([]any)
	require.Len(t, rows, 2)
	first, last := rows[0].(obj), rows[1].(obj)
	assert.Equal(t, []string{dropped.String(), stale.String()},
		[]string{strings.ToLower(first["libraryItemId"].(string)), strings.ToLower(last["libraryItemId"].(string))}, "newest change first")
	assert.Equal(t, "dropped", first["reason"])
	assert.Equal(t, "stalled", last["reason"])
	assert.InDelta(t, 1, first["next"].(obj)["number"], 0, "a show resumes where it stopped")
	assert.NotContains(t, last, "next")
	assert.IsType(t, "", first["since"])
	continued := home["continueWatching"].([]any)
	require.Len(t, continued, 1)
	assert.Equal(t, continuing.String(), strings.ToLower(continued[0].(obj)["libraryItemId"].(string)))
}

func TestOnHoldLeavesUpNextAndCalendar(t *testing.T) {
	h := newHarness(t)
	user, bearer := h.signIn()
	item := h.addItem(user, h.seedShow("Pluribus", false, "returning", 50, -23, -16, -9, 2), "on_hold", true)
	h.tick(item, 1, 1, true)
	now := time.Now()
	week := calendarPath(now, now.Add(7*day))

	home := decode[obj](t, h.do(http.MethodGet, "/v1/up-next", bearer, nil))
	assert.Empty(t, home["continueWatching"])
	assert.Empty(t, decode[obj](t, h.do(http.MethodGet, week, bearer, nil))["items"])

	// What a tick does to it (back to in progress) is the library's; once back, it shows again.
	_, err := h.pool.Exec(context.Background(), `UPDATE library_items SET status = 'in_progress' WHERE id = $1`, item)
	require.NoError(t, err)
	home = decode[obj](t, h.do(http.MethodGet, "/v1/up-next", bearer, nil))
	assert.InDelta(t, 2, home["continueWatching"].([]any)[0].(obj)["next"].(obj)["number"], 0)
	assert.Len(t, decode[obj](t, h.do(http.MethodGet, week, bearer, nil))["items"], 1)
}

func TestWatching(t *testing.T) {
	h := newHarness(t)
	user, bearer := h.signIn()
	// Three aired, one next week: two left after ticking the first.
	airing := h.addItem(user, h.seedShow("Severance", false, "returning", 25, -30, -23, -16, 7), "in_progress", true)
	h.tick(airing, 1, 1, true)
	// Caught up: the next episode has not aired.
	caughtUp := h.addItem(user, h.seedShow("Andor", false, "returning", 25, -9, 5), "in_progress", true)
	h.tick(caughtUp, 1, 1, true)
	film := h.addItem(user, h.seedTitle("movie", "Arrival"), "in_progress", true)
	h.addItem(user, h.seedShow("Later", false, "returning", 25, -9), "wishlist", true)
	h.addItem(user, h.seedTitle("book", "Dune"), "in_progress", true)
	// An imported anime: imported status and an imported tick only.
	backlog := h.addItem(user, h.seedShow("Gintama", true, "returning", 25, -90, -80), "in_progress", false)
	h.tick(backlog, 1, 1, false)
	// Set to watching by hand: never backlog.
	byHand := h.addItem(user, h.seedShow("Dandadan", true, "returning", 25, -9, -2), "in_progress", true)
	// Imported, then one live tick: active again.
	started := h.addItem(user, h.seedShow("Mushishi", true, "returning", 25, -60, -53), "in_progress", false)
	h.tick(started, 1, 1, true)

	rec := h.do(http.MethodGet, "/v1/library/watching", bearer, nil)
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	byID := map[string]obj{}
	for _, r := range decode[obj](t, rec)["items"].([]any) {
		row := r.(obj)
		byID[strings.ToLower(row["entry"].(obj)["id"].(string))] = row
	}
	assert.ElementsMatch(t, []string{airing.String(), caughtUp.String(), film.String(), backlog.String(), byHand.String(), started.String()},
		keys(byID), "no wishlist, no other kinds")
	row := byID[airing.String()]
	assert.Equal(t, "returning", row["showStatus"])
	assert.InDelta(t, 4, row["nextAiring"].(obj)["number"], 0)
	assert.Equal(t, "Severance 2", row["nextName"])
	assert.InDelta(t, 2, row["remainingCount"], 0)
	assert.InDelta(t, 50, row["remainingMinutes"], 0)
	entry := row["entry"].(obj)
	assert.Equal(t, obj{"watchedCount": 1.0, "airedCount": 3.0, "nextEpisode": obj{"season": 1.0, "number": 2.0}}, entry["progress"])
	assert.IsType(t, "", entry["lastWatchedAt"])
	waiting := byID[caughtUp.String()]
	assert.InDelta(t, 2, waiting["nextAiring"].(obj)["number"], 0)
	assert.NotContains(t, waiting, "nextName")
	assert.NotContains(t, waiting, "remainingCount")
	backlogEntry := byID[backlog.String()]["entry"].(obj)
	assert.Equal(t, true, backlogEntry["inBacklog"])
	assert.NotContains(t, backlogEntry, "lastWatchedAt", "an imported tick is not a live one")
	assert.Equal(t, false, byID[byHand.String()]["entry"].(obj)["inBacklog"])
	assert.Equal(t, false, byID[started.String()]["entry"].(obj)["inBacklog"])
	assert.NotContains(t, byID[film.String()], "showStatus")

	_, otherBearer := h.signIn()
	assert.Empty(t, decode[obj](t, h.do(http.MethodGet, "/v1/library/watching", otherBearer, nil))["items"])
}

func keys(m map[string]obj) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	return out
}
