package httpapi

import (
	"aaru-go-api/internal/auth"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/library"
	"context"
	"net/http"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// LibraryTests, ProgressTests, ShowWatchedTests (library parts), ProvenanceTests, TitlePreviewTests,
// PageCountTests (add), MangaTests and MusicTests (library and label parts), and LIB-007 on hold.

func patchPath(id string) string { return "/v1/library/items/" + id }

func TestAddIsIdempotent(t *testing.T) { // LIB-001
	env := newLibEnv(t)
	tmdb := env.stubMovie("Dune")
	first := env.add("movie", tmdb)
	second := env.add("movie", tmdb)
	assert.Equal(t, first, second)
	assert.Equal(t, 1, env.actionCount(), "the repeat add writes nothing")
	assert.Equal(t, strings.ToUpper(first), first, "ids are uppercase on the wire")
}

func TestFiltersAndPagination(t *testing.T) { // LIB-002
	env := newLibEnv(t)
	var movies []string
	for _, name := range []string{"M0", "M1", "M2", "M3", "M4"} {
		movies = append(movies, env.add("movie", env.stubMovie(name)))
	}
	show := env.add("show", env.stubShow("Show", catalog.StatusReturning, 2, 3, false), "in_progress")

	filtered := env.json(http.MethodGet, "/v1/library/items?status=in_progress&type=show", nil)
	assert.Equal(t, []string{show}, ids(filtered["items"]))

	_, other := env.signIn()
	rec := env.send(http.MethodGet, "/v1/library/items", nil, other)
	assert.Empty(t, decode[map[string]any](t, rec)["items"])

	var seen []string
	cursor := ""
	for {
		uri := "/v1/library/items?type=movie&limit=2"
		if cursor != "" {
			uri += "&cursor=" + cursor
		}
		page := env.json(http.MethodGet, uri, nil)
		seen = append(seen, ids(page["items"])...)
		if len(seen) == 2 {
			env.json(http.MethodPatch, patchPath(movies[0]), map[string]any{"isOwned": true})
		}
		next, _ := page["page"].(map[string]any)["nextCursor"].(string)
		if next == "" {
			break
		}
		cursor = next
	}
	unique := map[string]bool{}
	for _, id := range seen {
		assert.False(t, unique[id], "no duplicates across pages")
		unique[id] = true
	}
	for _, id := range movies[1:] {
		assert.True(t, unique[id], "no unchanged row skipped")
	}

	assert.Equal(t, http.StatusBadRequest, env.send(http.MethodGet, "/v1/library/items?cursor=nope", nil).Code)
	assert.Equal(t, http.StatusBadRequest, env.send(http.MethodGet, "/v1/library/items?list=nope", nil).Code)
}

func TestPatchRules(t *testing.T) { // LIB-003
	env := newLibEnv(t)
	id := env.add("movie", env.stubMovie("Heat"))
	bad := env.send(http.MethodPatch, patchPath(id), map[string]any{"rating": 11})
	assert.Equal(t, http.StatusUnprocessableEntity, bad.Code)
	assert.Contains(t, bad.Body.String(), "rating")
	assert.Equal(t, http.StatusUnprocessableEntity, env.send(http.MethodPatch, patchPath(id), map[string]any{"rating": 7.3}).Code)

	owned := env.json(http.MethodPatch, patchPath(id), map[string]any{"isOwned": true})
	assert.Equal(t, "wishlist", owned["status"])
	assert.Equal(t, true, owned["isOwned"])

	finished := env.json(http.MethodPatch, patchPath(id), map[string]any{"status": "finished", "rating": 8.5})
	assert.NotNil(t, finished["finishedAt"])
	assert.InDelta(t, 8.5, finished["rating"], 0)

	_, other := env.signIn()
	assert.Equal(t, http.StatusNotFound, env.send(http.MethodPatch, patchPath(id), map[string]any{"isOwned": false}, other).Code)
	assert.Equal(t, http.StatusNotFound, env.send(http.MethodGet, patchPath(id), nil, other).Code)
	assert.Equal(t, http.StatusNotFound, env.send(http.MethodGet, patchPath("not-an-id"), nil).Code)
}

func TestSyncDeletes(t *testing.T) { // LIB-004
	env := newLibEnv(t)
	keep := env.add("movie", env.stubMovie("Keep"))
	drop := env.add("movie", env.stubMovie("Drop"))
	first := env.json(http.MethodGet, "/v1/library/sync", nil)
	assert.ElementsMatch(t, []string{keep, drop}, ids(first["items"]))
	token := first["token"].(string)

	assert.Equal(t, http.StatusNoContent, env.send(http.MethodDelete, patchPath(drop), nil).Code)
	next := env.json(http.MethodGet, "/v1/library/sync?since="+token, nil)
	assert.Equal(t, []any{drop}, next["deleted"])
	assert.Equal(t, http.StatusBadRequest, env.send(http.MethodGet, "/v1/library/sync?since=!!", nil).Code)
}

func TestJournalOneRowPerWrite(t *testing.T) { // AUD-001
	env := newLibEnv(t)
	id := env.add("show", env.stubShow("Severance", catalog.StatusReturning, 2, 3, false))
	assert.Equal(t, 1, env.actionCount())
	env.json(http.MethodPatch, patchPath(id), map[string]any{"rating": 9})
	assert.Equal(t, 2, env.actionCount())
	env.json(http.MethodPost, patchPath(id)+"/seasons/1/watched", nil)
	assert.Equal(t, 3, env.actionCount(), "a season of episodes is one action")
	assert.Equal(t, http.StatusUnprocessableEntity, env.send(http.MethodPatch, patchPath(id), map[string]any{"rating": 42}).Code)
	assert.Equal(t, 3, env.actionCount(), "a rejected write leaves no row")
}

func TestPatchAndTickNameTheirAction(t *testing.T) {
	env := newLibEnv(t)
	id := env.add("show", env.stubShow("Andor", catalog.StatusReturning, 2, 3, false))
	rated := env.send(http.MethodPatch, patchPath(id), map[string]any{"rating": 8})
	action := rated.Header().Get("Aaru-Action")
	require.NotEmpty(t, action)
	assert.Equal(t, strings.ToUpper(action), action)
	same := env.send(http.MethodPatch, patchPath(id), map[string]any{"rating": 8})
	assert.Equal(t, http.StatusOK, same.Code)
	assert.Empty(t, same.Header().Get("Aaru-Action"))
	require.Equal(t, http.StatusOK, env.send(http.MethodPost, "/v1/actions/"+action+"/undo", nil).Code)
	assert.Nil(t, env.json(http.MethodGet, patchPath(id), nil)["rating"])

	tick := env.send(http.MethodPut, patchPath(id)+"/episodes/1/1", map[string]any{"watched": true})
	tickAction := tick.Header().Get("Aaru-Action")
	require.NotEmpty(t, tickAction)
	require.Equal(t, http.StatusOK, env.send(http.MethodPost, "/v1/actions/"+tickAction+"/undo", nil).Code)
	assert.Equal(t, 0, env.watchedCount(id))

	season := env.send(http.MethodPost, patchPath(id)+"/seasons/1/watched", nil)
	seasonAction := season.Header().Get("Aaru-Action")
	require.NotEmpty(t, seasonAction)
	require.Equal(t, http.StatusOK, env.send(http.MethodPost, "/v1/actions/"+seasonAction+"/undo", nil).Code)
	assert.Equal(t, 0, env.watchedCount(id))
}

func TestUndoSeasonRestoresExactlyAndTwiceIsConflict(t *testing.T) { // AUD-002
	env := newLibEnv(t)
	id := env.add("show", env.stubShow("Andor", catalog.StatusReturning, 2, 3, false))
	env.json(http.MethodPut, patchPath(id)+"/episodes/1/2", map[string]any{"watched": true})
	env.json(http.MethodPost, patchPath(id)+"/seasons/1/watched", nil)
	watched, _ := progressOf(env.json(http.MethodGet, patchPath(id), nil))
	assert.InDelta(t, 3, watched, 0)

	action := env.latestAction()
	require.Equal(t, http.StatusOK, env.send(http.MethodPost, "/v1/actions/"+action+"/undo", nil).Code)
	item := env.json(http.MethodGet, patchPath(id), nil)
	assert.Equal(t, []any{map[string]any{"season": 1.0, "number": 2.0}}, item["watchedEpisodes"], "the earlier tick stays")
	again := env.send(http.MethodPost, "/v1/actions/"+action+"/undo", nil)
	assert.Equal(t, http.StatusConflict, again.Code)
	assert.Contains(t, again.Body.String(), "That action was already undone.")
	assert.Equal(t, http.StatusNotFound, env.send(http.MethodPost, "/v1/actions/"+uuid.NewString()+"/undo", nil).Code)
}

func TestUndoDeleteRestoresProgress(t *testing.T) { // AUD-002
	env := newLibEnv(t)
	id := env.add("show", env.stubShow("Lost", catalog.StatusEnded, 2, 3, false))
	env.json(http.MethodPut, patchPath(id)+"/episodes/1/1", map[string]any{"watched": true})
	require.Equal(t, http.StatusNoContent, env.send(http.MethodDelete, patchPath(id), nil).Code)
	require.Equal(t, http.StatusOK, env.send(http.MethodPost, "/v1/actions/"+env.latestAction()+"/undo", nil).Code)
	watched, _ := progressOf(env.json(http.MethodGet, patchPath(id), nil))
	assert.InDelta(t, 1, watched, 0)

	// The undo of the undo removes it again; undoing that restore conflicts once the item is gone.
	undo := env.latestAction()
	require.Equal(t, http.StatusNoContent, env.send(http.MethodDelete, patchPath(id), nil).Code)
	assert.Equal(t, http.StatusConflict, env.send(http.MethodPost, "/v1/actions/"+undo+"/undo", nil).Code)
}

func TestTickRules(t *testing.T) { // PROG-001
	env := newLibEnv(t)
	id := env.add("show", env.stubShow("Dark", catalog.StatusEnded, 2, 3, false))
	assert.Equal(t, http.StatusUnprocessableEntity, env.send(http.MethodPut, patchPath(id)+"/episodes/9/9", map[string]any{"watched": true}).Code)
	for range 2 {
		watched, _ := progressOf(env.json(http.MethodPut, patchPath(id)+"/episodes/1/1", map[string]any{"watched": true}))
		assert.InDelta(t, 1, watched, 0)
	}
	movie := env.add("movie", env.stubMovie("Heat"))
	assert.Equal(t, http.StatusUnprocessableEntity, env.send(http.MethodPut, patchPath(movie)+"/episodes/1/1", map[string]any{"watched": true}).Code)
}

func TestWatchedEpisodesOnSingleItemOnly(t *testing.T) { // APP-005
	env := newLibEnv(t)
	id := env.add("show", env.stubShow("Severance", catalog.StatusEnded, 2, 3, false))
	tick := env.json(http.MethodPut, patchPath(id)+"/episodes/1/2", map[string]any{"watched": true})
	assert.Equal(t, []any{map[string]any{"season": 1.0, "number": 2.0}}, tick["watchedEpisodes"])
	assert.Len(t, env.json(http.MethodGet, patchPath(id), nil)["watchedEpisodes"], 1)
	assert.Len(t, env.json(http.MethodPost, patchPath(id)+"/seasons/1/watched", nil)["watchedEpisodes"], 3)
	synced := env.json(http.MethodGet, "/v1/library/sync", nil)["items"].([]any)
	assert.NotContains(t, synced[0].(map[string]any), "watchedEpisodes", "sync stays lean")
}

func TestSeasonSkipsUnaired(t *testing.T) { // PROG-002
	env := newLibEnv(t)
	id := env.add("show", env.stubShow("Airing", catalog.StatusReturning, 1, 3, true))
	watched, aired := progressOf(env.json(http.MethodPost, patchPath(id)+"/seasons/1/watched", nil))
	assert.InDelta(t, 2, watched, 0)
	assert.InDelta(t, 2, aired, 0)
	assert.Equal(t, http.StatusUnprocessableEntity, env.send(http.MethodPost, patchPath(id)+"/seasons/7/watched", nil).Code)
}

func TestStatusTransitions(t *testing.T) { // PROG-003
	env := newLibEnv(t)
	ended := env.add("show", env.stubShow("Ended", catalog.StatusEnded, 1, 3, false))
	first := env.json(http.MethodPut, patchPath(ended)+"/episodes/1/1", map[string]any{"watched": true})
	assert.Equal(t, "in_progress", first["status"])
	assert.Equal(t, "finished", env.json(http.MethodPost, patchPath(ended)+"/seasons/1/watched", nil)["status"])

	running := env.add("show", env.stubShow("Running", catalog.StatusReturning, 1, 3, false))
	caughtUp := env.json(http.MethodPost, patchPath(running)+"/seasons/1/watched", nil)
	assert.Equal(t, "in_progress", caughtUp["status"])
	assert.NotContains(t, caughtUp["progress"].(map[string]any), "nextEpisode")
}

func TestATickResumesAShowOnHold(t *testing.T) { // LIB-007
	env := newLibEnv(t)
	id := env.add("show", env.stubShow("Paused", catalog.StatusReturning, 1, 3, false), "in_progress")
	held := env.json(http.MethodPatch, patchPath(id), map[string]any{"status": "on_hold"})
	assert.Equal(t, "on_hold", held["status"])
	assert.Equal(t, "in_progress", env.json(http.MethodPut, patchPath(id)+"/episodes/1/1", map[string]any{"watched": true})["status"])
	env.json(http.MethodPatch, patchPath(id), map[string]any{"status": "on_hold"})
	assert.Equal(t, "on_hold", env.json(http.MethodPut, patchPath(id)+"/episodes/1/1", map[string]any{"watched": false})["status"],
		"unticking is not reading on")
	onHold := env.json(http.MethodGet, "/v1/library/items?status=on_hold", nil)
	assert.Equal(t, []string{id}, ids(onHold["items"]))
}

func (e *libEnv) stubBook(name string, pages *int) string {
	olid := e.fake.uniqueID("OL")
	year := 1965
	e.fake.stubTitle(catalog.Record{Hit: catalog.Hit{
		Type: core.MediaBook, Title: name, Year: &year, IDs: core.ExternalIDs{OpenLibrary: olid}, PageCount: pages,
	}})
	return olid
}

func TestBookProgress(t *testing.T) { // PROG-004, LIB-007, APP-017
	env := newLibEnv(t)
	pages := 412
	id := env.addBody(map[string]any{"mediaRef": map[string]any{"type": "book", "ids": map[string]string{"openLibrary": env.stubBook("A Book", &pages)}}})
	assert.InDelta(t, 412, env.json(http.MethodGet, patchPath(id), nil)["title"].(map[string]any)["pageCount"], 0)
	assert.Equal(t, http.StatusUnprocessableEntity, env.send(http.MethodPatch, patchPath(id), map[string]any{"bookPercent": 150}).Code)
	assert.Equal(t, http.StatusUnprocessableEntity, env.send(http.MethodPatch, patchPath(id), map[string]any{"bookPage": 10, "bookPercent": 5}).Code)
	env.json(http.MethodPatch, patchPath(id), map[string]any{"bookPage": 120})
	percent := env.json(http.MethodPatch, patchPath(id), map[string]any{"bookPercent": 33.3})
	progress := percent["bookProgress"].(map[string]any)
	assert.InDelta(t, 33.3, progress["percent"], 0, "a Double, not a float32")
	assert.NotContains(t, progress, "page", "setting one clears the other")

	assert.Equal(t, "on_hold", env.json(http.MethodPatch, patchPath(id), map[string]any{"status": "on_hold"})["status"])
	assert.Equal(t, "on_hold", env.json(http.MethodPatch, patchPath(id), map[string]any{"status": "on_hold", "bookPage": 130})["status"])
	assert.Equal(t, "in_progress", env.json(http.MethodPatch, patchPath(id), map[string]any{"bookPage": 140})["status"])

	cleared := env.json(http.MethodPatch, patchPath(id), map[string]any{"clear": []string{"bookProgress"}})
	assert.NotContains(t, cleared, "bookProgress")
	movie := env.add("movie", env.stubMovie("Dune"))
	assert.Equal(t, http.StatusUnprocessableEntity, env.send(http.MethodPatch, patchPath(movie), map[string]any{"bookPage": 3}).Code)
}

func summaries(env *libEnv) []string {
	var out []string
	for _, a := range env.json(http.MethodGet, "/v1/actions?limit=10", nil)["items"].([]any) {
		out = append(out, a.(map[string]any)["summary"].(string))
	}
	return out
}

func TestStatusLabelsInTheJournal(t *testing.T) { // APP-014
	env := newLibEnv(t)
	movie := env.add("movie", env.stubMovie("Dune"))
	book := env.addBody(map[string]any{"mediaRef": map[string]any{"type": "book", "ids": map[string]string{"openLibrary": env.stubBook("The Hobbit", nil)}}})
	env.json(http.MethodPatch, patchPath(book), map[string]any{"status": "in_progress"})
	env.json(http.MethodPatch, patchPath(book), map[string]any{"status": "finished"})
	env.json(http.MethodPatch, patchPath(movie), map[string]any{"status": "finished"})
	assert.Equal(t, []string{
		"Moved Dune to Watched", "Moved The Hobbit to Read", "Moved The Hobbit to Reading",
		"Added The Hobbit to Plan to read", "Added Dune to Plan to watch",
	}, summaries(env))
	assert.Equal(t, "finished", env.json(http.MethodGet, patchPath(movie), nil)["status"])
	assert.Empty(t, env.json(http.MethodGet, "/v1/library/items?status=wishlist", nil)["items"])
}

func (e *libEnv) stubManga(name string) string {
	anilist := e.fake.uniqueID("al")
	byline := "Kentarou Miura"
	chapters, volumes := 364, 41
	e.fake.stubTitle(catalog.Record{Hit: catalog.Hit{
		Type: core.MediaManga, Title: name, Byline: &byline, IDs: core.ExternalIDs{AniList: anilist},
		ChapterCount: &chapters, VolumeCount: &volumes,
	}})
	return anilist
}

func TestMangaProgressAndLabels(t *testing.T) { // MNG-001
	env := newLibEnv(t)
	added := env.send(http.MethodPost, "/v1/library/items", map[string]any{"mediaRef": map[string]any{"type": "manga", "ids": map[string]string{"anilist": env.stubManga("Berserk")}}})
	require.Equal(t, http.StatusOK, added.Code, added.Body.String())
	entry := decode[map[string]any](t, added)
	title := entry["title"].(map[string]any)
	assert.Equal(t, "manga", title["type"])
	assert.Equal(t, "Kentarou Miura", title["byline"])
	assert.InDelta(t, 364, title["chapterCount"], 0)
	assert.Equal(t, "wishlist", entry["status"])
	item := entry["id"].(string)

	read := env.json(http.MethodPatch, patchPath(item), map[string]any{"status": "in_progress", "mangaChapter": 112, "mangaVolume": 12})
	assert.Equal(t, map[string]any{"chapter": 112.0, "volume": 12.0}, read["mangaProgress"])
	assert.NotContains(t, read, "bookProgress")
	more := env.json(http.MethodPatch, patchPath(item), map[string]any{"mangaChapter": 120})
	assert.Equal(t, map[string]any{"chapter": 120.0, "volume": 12.0}, more["mangaProgress"], "the volume stays")
	assert.Equal(t, "Read Berserk to chapter 120", summaries(env)[0])
	require.Equal(t, http.StatusOK, env.send(http.MethodPost, "/v1/actions/"+env.latestAction()+"/undo", nil).Code)
	assert.InDelta(t, 112, env.json(http.MethodGet, patchPath(item), nil)["mangaProgress"].(map[string]any)["chapter"], 0)

	assert.NotContains(t, env.json(http.MethodPatch, patchPath(item), map[string]any{"clear": []string{"mangaProgress"}}), "mangaProgress")
	assert.Equal(t, http.StatusUnprocessableEntity, env.send(http.MethodPatch, patchPath(item), map[string]any{"mangaChapter": -1}).Code)
	movie := env.add("movie", env.stubMovie("Dune"))
	assert.Equal(t, http.StatusUnprocessableEntity, env.send(http.MethodPatch, patchPath(movie), map[string]any{"mangaChapter": 3}).Code)

	env.json(http.MethodPatch, patchPath(item), map[string]any{"status": "finished"})
	assert.Equal(t, "Moved Berserk to Read", summaries(env)[0])
	assert.Equal(t, []string{item}, ids(env.json(http.MethodGet, "/v1/library/items?type=manga", nil)["items"]))
}

func TestAlbumLabels(t *testing.T) { // MUS-001
	env := newLibEnv(t)
	movie := env.add("movie", env.stubMovie("Dune"))
	mbid := env.fake.uniqueID("mb-")
	byline := "Radiohead"
	env.fake.stubTitle(catalog.Record{Hit: catalog.Hit{Type: core.MediaAlbum, Title: "OK Computer", Byline: &byline, IDs: core.ExternalIDs{MusicBrainz: mbid}}})
	album := env.addBody(map[string]any{"mediaRef": map[string]any{"type": "album", "ids": map[string]string{"musicbrainz": mbid}}})
	env.json(http.MethodPatch, patchPath(album), map[string]any{"status": "in_progress"})
	env.json(http.MethodPatch, patchPath(album), map[string]any{"status": "finished"})
	assert.Equal(t, []string{
		"Moved OK Computer to Listened", "Moved OK Computer to Listening",
		"Added OK Computer to Plan to listen", "Added Dune to Plan to watch",
	}, summaries(env))
	assert.Equal(t, []string{album}, ids(env.json(http.MethodGet, "/v1/library/items?type=album", nil)["items"]))
	assert.Equal(t, []string{movie}, ids(env.json(http.MethodGet, "/v1/library/items?type=movie", nil)["items"]))
}

func (e *libEnv) undatedTicks(itemID string) int {
	e.t.Helper()
	var n int
	require.NoError(e.t, e.pool.QueryRow(context.Background(),
		`SELECT count(*)::int FROM episode_progress WHERE library_item_id = $1 AND NOT watched_at_known`, uuid.MustParse(itemID)).Scan(&n))
	return n
}

func TestEndedShowWatchedInOneUndatedAction(t *testing.T) { // PROG-005
	env := newLibEnv(t)
	id := env.add("show", env.stubShow("Severance", catalog.StatusEnded, 2, 3, false))
	env.json(http.MethodPut, patchPath(id)+"/episodes/1/1", map[string]any{"watched": true})
	before := env.actionCount()
	reply := env.json(http.MethodPost, patchPath(id)+"/watched", nil)
	entry := reply["entry"].(map[string]any)
	assert.Equal(t, "finished", entry["status"])
	watched, _ := progressOf(entry)
	assert.InDelta(t, 6, watched, 0)
	assert.InDelta(t, 5, reply["episodes"], 0)
	assert.Equal(t, before+1, env.actionCount())
	assert.Equal(t, 5, env.undatedTicks(id), "not today's activity: only the one real tick is dated")

	action := reply["action"].(map[string]any)["id"].(string)
	require.Equal(t, http.StatusOK, env.send(http.MethodPost, "/v1/actions/"+action+"/undo", nil).Code)
	undone := env.json(http.MethodGet, patchPath(id), nil)
	assert.Equal(t, "in_progress", undone["status"])
	watched, _ = progressOf(undone)
	assert.InDelta(t, 1, watched, 0)
}

func TestSeasonMarkIsUndated(t *testing.T) {
	env := newLibEnv(t)
	id := env.add("show", env.stubShow("Severance", catalog.StatusEnded, 2, 3, false))
	env.json(http.MethodPut, patchPath(id)+"/episodes/1/1", map[string]any{"watched": true})
	env.json(http.MethodPost, patchPath(id)+"/seasons/2/watched", nil)
	assert.Equal(t, 3, env.undatedTicks(id))
	assert.Equal(t, 4, env.watchedCount(id))
}

func TestRunningShowWatchedStaysInProgressAndAgainIsANoOp(t *testing.T) { // PROG-005
	env := newLibEnv(t)
	id := env.add("show", env.stubShow("Airing", catalog.StatusReturning, 2, 3, true))
	entry := env.json(http.MethodPost, patchPath(id)+"/watched", nil)["entry"].(map[string]any)
	assert.Equal(t, "in_progress", entry["status"])
	watched, aired := progressOf(entry)
	assert.InDelta(t, 5, watched, 0)
	assert.InDelta(t, 5, aired, 0)
	count := env.actionCount()
	again := env.json(http.MethodPost, patchPath(id)+"/watched", nil)
	assert.NotContains(t, again, "action")
	assert.InDelta(t, 0, again["episodes"], 0)
	assert.Equal(t, count, env.actionCount())
}

func TestPatchFinishedOnAShowIsTheWholeShow(t *testing.T) { // PROG-005
	env := newLibEnv(t)
	id := env.add("show", env.stubShow("Dark", catalog.StatusEnded, 2, 3, false))
	before := env.actionCount()
	reply := env.json(http.MethodPatch, patchPath(id), map[string]any{"status": "finished", "rating": 9})
	assert.Equal(t, "finished", reply["status"])
	assert.InDelta(t, 9, reply["rating"], 0)
	watched, _ := progressOf(reply)
	assert.InDelta(t, 6, watched, 0)
	assert.Equal(t, before+1, env.actionCount())

	running := env.add("show", env.stubShow("Running", catalog.StatusReturning, 2, 3, false))
	caughtUp := env.json(http.MethodPatch, patchPath(running), map[string]any{"status": "finished"})
	assert.Equal(t, "in_progress", caughtUp["status"])
	watched, _ = progressOf(caughtUp)
	assert.InDelta(t, 6, watched, 0)
}

func TestAddAShowAsWatched(t *testing.T) { // PROG-005
	env := newLibEnv(t)
	ended := env.add("show", env.stubShow("Ended", catalog.StatusEnded, 2, 3, false), "finished")
	entry := env.json(http.MethodGet, patchPath(ended), nil)
	assert.Equal(t, "finished", entry["status"])
	watched, _ := progressOf(entry)
	assert.InDelta(t, 6, watched, 0)

	running := env.add("show", env.stubShow("Running", catalog.StatusReturning, 2, 3, false), "finished")
	assert.Equal(t, "in_progress", env.json(http.MethodGet, patchPath(running), nil)["status"])

	movie := env.add("movie", env.stubMovie("Heat"))
	assert.Equal(t, http.StatusUnprocessableEntity, env.send(http.MethodPost, patchPath(movie)+"/watched", nil).Code)
}

func TestAnAgentWriteNamesItsTokenAndUndoes(t *testing.T) { // OUT-002
	env := newLibEnv(t)
	itemID := env.add("show", env.stubShow("Severance", catalog.StatusEnded, 2, 3, false))
	item := uuid.MustParse(itemID)
	ctx := context.Background()
	minted, err := env.server.AgentTokens.Create(ctx, env.user, auth.KindStremio, nil, false, false)
	require.NoError(t, err)
	caller := library.AgentCaller(minted.Token)
	keys := []core.EpisodeKey{{Season: 1, Episode: 1}, {Season: 1, Episode: 2}, {Season: 9, Episode: 9}}
	before := env.actionCount()

	entry, err := env.server.Library.SetEpisodes(ctx, item, env.user, keys, true, caller)
	require.NoError(t, err)
	require.NotNil(t, entry)
	assert.Equal(t, core.StatusInProgress, entry.Item.Status)
	assert.Equal(t, before+1, env.actionCount(), "one action for the batch; unknown episodes skipped")
	again, err := env.server.Library.SetEpisodes(ctx, item, env.user, keys, true, caller)
	require.NoError(t, err)
	assert.Nil(t, again, "already watched: no write")
	assert.Equal(t, before+1, env.actionCount())

	require.NoError(t, env.server.AgentTokens.Revoke(ctx, minted.Token.ID, env.user))
	latest := env.json(http.MethodGet, "/v1/actions?limit=1", nil)["items"].([]any)[0].(map[string]any)
	assert.Equal(t, "external_agent", latest["actor"])
	assert.Equal(t, "Stremio", latest["agentName"])
	assert.Equal(t, "Stremio: marked 2 episodes of Severance watched", latest["summary"])
	require.Equal(t, http.StatusOK, env.send(http.MethodPost, "/v1/actions/"+latest["id"].(string)+"/undo", nil).Code)
	assert.Equal(t, 0, env.watchedCount(itemID))
}

func TestResolvingIsNotAdding(t *testing.T) { // LIB-006
	env := newLibEnv(t)
	tmdb := env.stubMovie("Dune")
	body := env.json(http.MethodPost, "/v1/titles/resolve", map[string]any{"type": "movie", "ids": map[string]string{"tmdb": tmdb}})
	assert.Equal(t, "Dune", body["title"].(map[string]any)["title"])
	assert.NotContains(t, body, "libraryItemId")
	assert.Empty(t, env.json(http.MethodGet, "/v1/library/items", nil)["items"], "resolving is not adding")
	assert.Empty(t, env.json(http.MethodGet, "/v1/actions?limit=5", nil)["items"], "nothing journaled")

	item := env.add("movie", tmdb)
	again := env.json(http.MethodPost, "/v1/titles/resolve", map[string]any{"type": "movie", "ids": map[string]string{"tmdb": tmdb}})
	assert.Equal(t, item, again["libraryItemId"])
	assert.Equal(t, http.StatusUnprocessableEntity, env.send(http.MethodPost, "/v1/titles/resolve",
		map[string]any{"type": "movie", "ids": map[string]string{"tmdb": "999999999"}}).Code)
}
