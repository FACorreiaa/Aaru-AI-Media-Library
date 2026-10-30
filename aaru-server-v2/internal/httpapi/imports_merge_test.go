package httpapi

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/imports"
	"aaru-go-api/internal/library"
	"context"
	"net/http"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// ImportMergeTests: IMP-004 across sources (2026-10-20). A later import fills gaps and moves a
// status forward, never backward, never out of dropped, never past a status the user chose; anime
// from MAL lands on the TMDB show a Trakt import made; AniList seasons tick the TMDB seasons they
// map to.

// importRun plans and approves one import of these rows; it returns the plan as approved.
func (e *libEnv) importRun(source core.ImportSource, rows []imports.Row) []imports.PlannedRow {
	e.t.Helper()
	ctx := context.Background()
	svc := e.server.Imports
	job := core.ImportJob{
		ID: uuid.New(), UserID: e.user, Source: source, State: core.JobQueued,
		CreatedAt: time.Unix(0, 0).UTC(), UpdatedAt: time.Unix(0, 0).UTC(),
	}
	require.NoError(e.t, svc.Store.Insert(ctx, job, rows))
	for range 50 {
		stored, err := svc.Store.Job(ctx, job.ID, e.user)
		require.NoError(e.t, err)
		if stored.State != core.JobQueued && stored.State != core.JobRunning {
			break
		}
		worked, err := svc.RunNext(ctx, &e.user)
		require.NoError(e.t, err)
		if !worked {
			break
		}
	}
	_, err := svc.Apply(ctx, job.ID, e.user)
	require.NoError(e.t, err)
	planned, err := svc.Store.Rows(ctx, job.ID)
	require.NoError(e.t, err)
	return planned
}

func (e *libEnv) mergeMovie(name string) core.ExternalIDs {
	ids := core.ExternalIDs{TMDB: e.fake.uniqueID("m"), IMDB: e.fake.uniqueID("tt")}
	year, runtime := 2020, 100
	e.fake.stubTitle(catalog.Record{
		Hit: catalog.Hit{Type: core.MediaMovie, Title: name, Year: &year, IDs: ids}, RuntimeMinutes: &runtime,
	})
	return ids
}

func (e *libEnv) mergeShow(name string) string {
	tmdb := e.fake.uniqueID("s")
	year, runtime := 2020, 24
	status := catalog.StatusEnded
	e.fake.stubTitle(catalog.Record{
		Hit:    catalog.Hit{Type: core.MediaShow, Title: name, Year: &year, IDs: core.ExternalIDs{TMDB: tmdb}, IsAnime: true},
		Status: &status, RuntimeMinutes: &runtime,
	})
	return tmdb
}

func mergeRow(mediaType core.MediaType, ids core.ExternalIDs, status *core.LibraryStatus) imports.Row {
	return imports.Row{Type: mediaType, Title: "Row", IDs: ids, Status: status, Lists: []string{}}
}

func statusPtr(s core.LibraryStatus) *core.LibraryStatus { return &s }

func episodeRange(season, from, to int) []core.EpisodeKey {
	var out []core.EpisodeKey
	for e := from; e <= to; e++ {
		out = append(out, core.EpisodeKey{Season: season, Episode: e})
	}
	return out
}

func outcomes(rows []imports.PlannedRow) []imports.Outcome {
	out := make([]imports.Outcome, len(rows))
	for i, r := range rows {
		out[i] = r.Outcome
	}
	return out
}

// mergeItem is the user's item for the title with these ids.
func (e *libEnv) mergeItem(ids core.ExternalIDs, mediaType core.MediaType) library.Entry {
	e.t.Helper()
	ctx := context.Background()
	title, err := e.server.Catalog.Store.Find(ctx, ids, mediaType)
	require.NoError(e.t, err)
	require.NotNil(e.t, title)
	entry, err := e.server.Library.Store.EntryForTitle(ctx, e.user, title.ID, time.Now())
	require.NoError(e.t, err)
	require.NotNil(e.t, entry)
	return *entry
}

func (e *libEnv) libraryCount() int {
	e.t.Helper()
	var n int
	require.NoError(e.t, e.pool.QueryRow(context.Background(), `SELECT count(*)::int FROM library_items WHERE user_id = $1`, e.user).Scan(&n))
	return n
}

func TestImportMergeSameSourceTwice(t *testing.T) {
	env := newLibEnv(t)
	film := env.mergeMovie("Twice")
	row := mergeRow(core.MediaMovie, film, statusPtr(core.StatusFinished))
	row.Rating = importPtr(8.0)
	env.importRun(core.SourceLetterboxdCSV, []imports.Row{row})
	again := env.importRun(core.SourceLetterboxdCSV, []imports.Row{row})
	assert.Equal(t, []imports.Outcome{imports.OutcomeSkip}, outcomes(again))
	assert.Equal(t, 1, env.libraryCount())
}

func TestImportMergeWishlistMovesForward(t *testing.T) {
	env := newLibEnv(t)
	film := env.mergeMovie("Forward")
	watched := time.Unix(1_700_000_000, 0).UTC()
	env.importRun(core.SourceIMDbCSV, []imports.Row{mergeRow(core.MediaMovie, film, statusPtr(core.StatusWishlist))})
	row := mergeRow(core.MediaMovie, film, statusPtr(core.StatusFinished))
	row.Rating, row.FinishedAt = importPtr(7.0), &watched
	plan := env.importRun(core.SourceLetterboxdCSV, []imports.Row{row})
	assert.Equal(t, imports.OutcomeUpdate, plan[0].Outcome)
	assert.Equal(t, "Moves it to Watched and adds the rating and finish date.", *plan[0].Reason)
	item := env.mergeItem(film, core.MediaMovie)
	assert.Equal(t, core.StatusFinished, item.Item.Status)
	require.NotNil(t, item.Item.FinishedAt)
	assert.True(t, item.Item.FinishedAt.Equal(watched))
	require.NotNil(t, item.Item.Rating)
	assert.InDelta(t, 7.0, item.Item.Rating.Value(), 0)
}

func TestImportMergeNeverBackwardNorOutOfDropped(t *testing.T) {
	env := newLibEnv(t)
	done, dropped := env.mergeMovie("Done"), env.mergeMovie("Dropped")
	env.importRun(core.SourceLetterboxdCSV, []imports.Row{
		mergeRow(core.MediaMovie, done, statusPtr(core.StatusFinished)),
		mergeRow(core.MediaMovie, dropped, statusPtr(core.StatusDropped)),
	})
	plan := env.importRun(core.SourceIMDbCSV, []imports.Row{
		mergeRow(core.MediaMovie, done, statusPtr(core.StatusWishlist)),
		mergeRow(core.MediaMovie, dropped, statusPtr(core.StatusFinished)),
	})
	assert.Equal(t, []imports.Outcome{imports.OutcomeSkip, imports.OutcomeSkip}, outcomes(plan))
	assert.Equal(t, core.StatusFinished, env.mergeItem(done, core.MediaMovie).Item.Status)
	assert.Equal(t, core.StatusDropped, env.mergeItem(dropped, core.MediaMovie).Item.Status)
}

func TestImportMergeHandSetStatusStays(t *testing.T) {
	env := newLibEnv(t)
	chosen, added := env.mergeMovie("Chosen"), env.mergeMovie("Added")
	for _, ids := range []core.ExternalIDs{chosen, added} {
		env.add("movie", ids.TMDB, "wishlist")
	}
	chosenItem := env.mergeItem(chosen, core.MediaMovie)
	rec := env.send(http.MethodPatch, "/v1/library/items/"+chosenItem.Item.ID.String(), map[string]any{"status": "in_progress"})
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	env.importRun(core.SourceLetterboxdCSV, []imports.Row{
		mergeRow(core.MediaMovie, chosen, statusPtr(core.StatusFinished)),
		mergeRow(core.MediaMovie, added, statusPtr(core.StatusFinished)),
	})
	assert.Equal(t, core.StatusInProgress, env.mergeItem(chosen, core.MediaMovie).Item.Status, "the user's choice stays")
	assert.Equal(t, core.StatusFinished, env.mergeItem(added, core.MediaMovie).Item.Status, "a wishlist add moves on")
}

func TestImportMergeUndoRestoresTheFlag(t *testing.T) {
	env := newLibEnv(t)
	ctx := context.Background()
	film := env.mergeMovie("Undone")
	env.importRun(core.SourceIMDbCSV, []imports.Row{mergeRow(core.MediaMovie, film, statusPtr(core.StatusWishlist))})
	id := env.mergeItem(film, core.MediaMovie).Item.ID
	rec := env.send(http.MethodPatch, "/v1/library/items/"+id.String(), map[string]any{"status": "in_progress"})
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	byHand, err := env.server.Library.Store.StatusSetByHand(ctx, id)
	require.NoError(t, err)
	assert.True(t, byHand)
	rec = env.send(http.MethodPost, "/v1/actions/"+env.latestAction()+"/undo", nil)
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	byHand, err = env.server.Library.Store.StatusSetByHand(ctx, id)
	require.NoError(t, err)
	assert.False(t, byHand)
}

func TestImportMergeOnHoldMovesSideways(t *testing.T) {
	decide := func(current, incoming core.LibraryStatus, byHand bool, knowsOnHold *bool) *core.LibraryStatus {
		row := imports.Row{
			Type: core.MediaShow, Title: "Frieren", IDs: core.ExternalIDs{MAL: "1"}, Status: &incoming, Lists: []string{},
			KnowsOnHold: knowsOnHold,
		}
		item := library.ImportItemState{
			ItemID: uuid.New(), Fields: library.ItemFields{Status: current}, StatusByHand: byHand,
			Watched: map[core.EpisodeKey]bool{},
		}
		d := imports.Decide(row, &item)
		if d.Fields == nil {
			return nil
		}
		return &d.Fields.Status
	}
	yes := importPtr(true)
	assert.Equal(t, statusPtr(core.StatusOnHold), decide(core.StatusInProgress, core.StatusOnHold, false, yes), "MAL paused it")
	assert.Equal(t, statusPtr(core.StatusInProgress), decide(core.StatusOnHold, core.StatusInProgress, false, yes), "MAL resumed it")
	assert.Nil(t, decide(core.StatusInProgress, core.StatusOnHold, true, yes), "the user's choice stays")
	assert.Nil(t, decide(core.StatusOnHold, core.StatusInProgress, true, yes), "the user's choice stays")
	assert.Nil(t, decide(core.StatusOnHold, core.StatusInProgress, false, nil), "Trakt's in progress never resumes")
	assert.Nil(t, decide(core.StatusDropped, core.StatusOnHold, false, yes), "never out of dropped")
	assert.Nil(t, decide(core.StatusFinished, core.StatusOnHold, false, yes), "never backward")
	assert.Equal(t, statusPtr(core.StatusOnHold), decide(core.StatusWishlist, core.StatusOnHold, false, yes), "forward from a plan")
	assert.Equal(t, statusPtr(core.StatusFinished), decide(core.StatusOnHold, core.StatusFinished, false, yes), "forward to finished")
	assert.Nil(t, decide(core.StatusOnHold, core.StatusWishlist, false, yes), "never backward")
}

func TestImportMergeMALAfterTraktIsOneTitle(t *testing.T) {
	env := newLibEnv(t)
	ctx := context.Background()
	tmdb := env.mergeShow("Frieren")
	mal := env.fake.uniqueID("mal")
	season := 1
	require.NoError(t, env.server.Catalog.Store.UpsertMapping(ctx, catalog.AnimeMapping{
		AniList: env.fake.uniqueID("al"), MAL: &mal, TMDB: &tmdb, TMDBSeason: &season,
	}))
	trakt := mergeRow(core.MediaShow, core.ExternalIDs{TMDB: tmdb}, statusPtr(core.StatusInProgress))
	trakt.Watched = episodeRange(1, 1, 2)
	env.importRun(core.SourceTrakt, []imports.Row{trakt})
	malRow := mergeRow(core.MediaShow, core.ExternalIDs{MAL: mal}, statusPtr(core.StatusFinished))
	malRow.Watched = episodeRange(1, 1, 4)
	plan := env.importRun(core.SourceMALXML, []imports.Row{malRow})
	assert.Equal(t, imports.OutcomeUpdate, plan[0].Outcome)
	assert.Equal(t, 1, env.libraryCount(), "one show, not a TMDB copy and an AniList copy")
	item := env.mergeItem(core.ExternalIDs{TMDB: tmdb}, core.MediaShow)
	assert.Equal(t, core.StatusFinished, item.Item.Status)
	assert.Equal(t, 4, env.watchedCount(item.Item.ID.String()))
}

func TestImportMergeAniListSeasonsTickTheirSeason(t *testing.T) {
	env := newLibEnv(t)
	ctx := context.Background()
	tmdb := env.mergeShow("Mob")
	first, second := env.fake.uniqueID("al"), env.fake.uniqueID("al")
	one, two := 1, 2
	require.NoError(t, env.server.Catalog.Store.UpsertMapping(ctx, catalog.AnimeMapping{AniList: first, TMDB: &tmdb, TMDBSeason: &one}))
	require.NoError(t, env.server.Catalog.Store.UpsertMapping(ctx, catalog.AnimeMapping{AniList: second, TMDB: &tmdb, TMDBSeason: &two}))
	a := mergeRow(core.MediaShow, core.ExternalIDs{AniList: first}, statusPtr(core.StatusFinished))
	a.Watched = episodeRange(1, 1, 3)
	b := mergeRow(core.MediaShow, core.ExternalIDs{AniList: second}, statusPtr(core.StatusInProgress))
	b.Watched = episodeRange(1, 1, 2)
	plan := env.importRun(core.SourceAniList, []imports.Row{a, b})
	assert.Equal(t, []imports.Outcome{imports.OutcomeCreate, imports.OutcomeSkip}, outcomes(plan))
	assert.Equal(t, "Merged into an earlier row.", *plan[1].Reason)
	item := env.mergeItem(core.ExternalIDs{TMDB: tmdb}, core.MediaShow)
	ticked, err := env.server.Library.Store.WatchedSorted(ctx, item.Item.ID)
	require.NoError(t, err)
	assert.Equal(t, append(episodeRange(1, 1, 3), episodeRange(2, 1, 2)...), ticked)
}
