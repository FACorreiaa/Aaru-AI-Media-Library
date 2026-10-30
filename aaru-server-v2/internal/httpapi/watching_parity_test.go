package httpapi

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/imports"
	"context"
	"fmt"
	"net/http"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// stubShowDaysParity is a show whose season 1 episodes air these many days from now (WatchingTests'
// and ScheduleTests' stub). It returns the tmdb id.
func (e *libEnv) stubShowDaysParity(name string, anime bool, days ...float64) string {
	tmdb := e.fake.uniqueID("")
	year := 2026
	status := catalog.StatusReturning
	e.fake.stubTitle(catalog.Record{
		Hit:    catalog.Hit{Type: core.MediaShow, Title: name, Year: &year, IDs: core.ExternalIDs{TMDB: tmdb}, IsAnime: anime},
		Status: &status,
	})
	now := time.Now()
	episodes := make([]catalog.Episode, len(days))
	for i, d := range days {
		airs := now.Add(time.Duration(d * float64(24*time.Hour)))
		epName := fmt.Sprintf("%s %d", name, i+1)
		runtime := 25
		episodes[i] = catalog.Episode{Season: 1, Episode: i + 1, Name: &epName, AirsAt: &airs, RuntimeMinutes: &runtime}
	}
	e.fake.mu.Lock()
	e.fake.episodes[tmdb] = catalog.Episodes{Status: &status, Episodes: episodes}
	e.fake.mu.Unlock()
	return tmdb
}

// importShowParity imports one show in progress with these episodes ticked, as a MAL export
// would, applies it, and returns the item id.
func (e *libEnv) importShowParity(tmdb string, watched ...int) string {
	e.t.Helper()
	ctx := context.Background()
	keys := []core.EpisodeKey{}
	for _, n := range watched {
		keys = append(keys, core.EpisodeKey{Season: 1, Episode: n})
	}
	status := core.StatusInProgress
	job := core.ImportJob{
		ID: uuid.New(), UserID: e.user, Source: core.SourceMALXML, State: core.JobQueued,
		CreatedAt: time.Unix(0, 0).UTC(), UpdatedAt: time.Now().UTC().Truncate(time.Second),
	}
	require.NoError(e.t, imports.NewStore(e.pool).Insert(ctx, job, []imports.Row{{
		Type: core.MediaShow, Title: "Row", IDs: core.ExternalIDs{TMDB: tmdb}, Status: &status, Watched: keys,
	}}))
	e.runImports()
	e.json(http.MethodPost, "/v1/imports/"+job.ID.String()+"/apply", nil)
	var item uuid.UUID
	require.NoError(e.t, e.pool.QueryRow(ctx, `SELECT li.id FROM library_items li JOIN titles t ON t.id = li.title_id
		WHERE li.user_id = $1 AND t.type = 'show' AND t.tmdb = $2`, e.user, tmdb).Scan(&item))
	return item.String()
}

// WatchingTests.importedAnime: an imported anime with no tick made in Aaru is in the backlog until
// the first live tick.
func TestAnImportedAnimeIsBacklogUntilTheFirstLiveTick(t *testing.T) {
	env := newLibEnv(t)
	id := env.importShowParity(env.stubShowDaysParity("Frieren", true, -30, -23, -16), 1)
	body := env.json(http.MethodGet, patchPath(id), nil)
	assert.Equal(t, true, body["inBacklog"])
	assert.NotContains(t, body, "lastWatchedAt", "an imported tick is not a live one")

	env.json(http.MethodPut, patchPath(id)+"/episodes/1/2", map[string]any{"watched": true})
	body = env.json(http.MethodGet, patchPath(id), nil)
	assert.Equal(t, false, body["inBacklog"])
	assert.IsType(t, "", body["lastWatchedAt"])
	assert.Equal(t, "in_progress", body["status"], "the status never moves")
}

// WatchingTests.notBacklog: an anime set to watching by hand, an imported show and a later import
// never count as backlog.
func TestByHandImportedShowsAndLaterImportsAreNotBacklog(t *testing.T) {
	env := newLibEnv(t)
	byHand := env.add("show", env.stubShowDaysParity("Dandadan", true, -9, -2), "in_progress")
	assert.Equal(t, false, env.json(http.MethodGet, patchPath(byHand), nil)["inBacklog"])

	show := env.importShowParity(env.stubShowDaysParity("Severance", false, -30, -23), 1)
	assert.Equal(t, false, env.json(http.MethodGet, patchPath(show), nil)["inBacklog"])

	// Started in Aaru, then the same title imported again: still active.
	tmdb := env.stubShowDaysParity("Mushishi", true, -60, -53, -46)
	started := env.importShowParity(tmdb)
	env.json(http.MethodPut, patchPath(started)+"/episodes/1/1", map[string]any{"watched": true})
	again := env.importShowParity(tmdb, 1, 2)
	assert.Equal(t, started, again)
	assert.Equal(t, false, env.json(http.MethodGet, patchPath(started), nil)["inBacklog"])
}

// ScheduleTests.pending (CAL-004): the calendar never loads episodes; it counts shows still waiting
// until the refresher tries them.
func TestTheCalendarWaitsForTheRefresherAndLoadsNothing(t *testing.T) {
	env := newLibEnv(t)
	ctx := context.Background()
	imported := env.add("show", env.stubShowDaysParity("Imported", false, 1, 2))
	gone := env.add("show", env.stubShowDaysParity("Gone", false, 3))
	// As an import leaves them: no episodes yet. "Gone" was tried once and the provider failed.
	var importedTitle uuid.UUID
	for _, item := range []string{imported, gone} {
		var title uuid.UUID
		require.NoError(t, env.pool.QueryRow(ctx, `SELECT title_id FROM library_items WHERE id = $1`, uuid.MustParse(item)).Scan(&title))
		_, err := env.pool.Exec(ctx, `DELETE FROM show_episodes WHERE title_id = $1`, title)
		require.NoError(t, err)
		var attempted *time.Time
		if item == gone {
			now := time.Now()
			attempted = &now
		} else {
			importedTitle = title
		}
		_, err = env.pool.Exec(ctx, `UPDATE titles SET episodes_hydrated_at = NULL, episodes_attempted_at = $2 WHERE id = $1`, title, attempted)
		require.NoError(t, err)
	}
	episodeCount := func() int {
		var n int
		require.NoError(t, env.pool.QueryRow(ctx, `SELECT count(*)::int FROM show_episodes WHERE title_id = $1`, importedTitle).Scan(&n))
		return n
	}

	now := time.Now()
	path := calendarPath(now, now.Add(7*24*time.Hour))
	before := env.json(http.MethodGet, path, nil)
	assert.Empty(t, before["items"])
	assert.InDelta(t, 1, before["pendingShows"], 0, "a show the provider failed on is not waited for")
	assert.Equal(t, 0, episodeCount(), "the read loaded nothing")

	store := catalog.NewStore(env.pool)
	providers := catalog.Providers{TMDB: env.fake, AniList: env.fake, OpenLibrary: env.fake, Music: env.fake}
	refresher := catalog.NewRefresher(store, catalog.NewService(store, providers))
	refresher.PassLimit = 100_000
	_, err := refresher.RunOnce(ctx)
	require.NoError(t, err)

	after := env.json(http.MethodGet, path, nil)
	assert.Len(t, after["items"], 2)
	assert.InDelta(t, 0, after["pendingShows"], 0)
}
