package httpapi

import (
	"aaru-go-api/internal/catalog"
	"net/http"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// The end of a party marks its title for everyone who joined, and reading sessions (ROOM-005).

// partyFixture is a watch channel with the harness user as host, Ana and Bea as members.
type partyFixture struct {
	kindFixture
	bea  groupMember
	path string
}

func (e *groupEnv) setUpParty() partyFixture {
	e.t.Helper()
	fx := e.setUpKind("watch", nil)
	bea := e.friend(e.user)
	e.join(bea, fx.group)
	return partyFixture{kindFixture: fx, bea: bea, path: channelPath(fx.group, fx.channel) + "/party"}
}

// run opens a party, joins everyone as asked, starts the countdown and ends it.
func (e *groupEnv) runParty(fx partyFixture, open map[string]any, join func()) {
	e.t.Helper()
	require.Equal(e.t, http.StatusOK, e.send(http.MethodPost, fx.path, open).Code)
	join()
	require.Equal(e.t, http.StatusOK, e.send(http.MethodPost, fx.path+"/start", map[string]any{"countdownSeconds": 3}).Code)
	require.Equal(e.t, http.StatusOK, e.send(http.MethodPost, fx.path+"/end", nil).Code)
}

func (e *groupEnv) ready(fx partyFixture, body map[string]any, token ...string) map[string]any {
	e.t.Helper()
	rec := e.send(http.MethodPost, fx.path+"/ready", body, token...)
	require.Equal(e.t, http.StatusOK, rec.Code, rec.Body.String())
	return decode[map[string]any](e.t, rec)
}

func (e *groupEnv) library(kind string, token ...string) []map[string]any {
	e.t.Helper()
	return items(e.t, e.send(http.MethodGet, "/v1/library/items?type="+kind, nil, token...))
}

func watchedCount(item map[string]any) float64 {
	return item["progress"].(map[string]any)["watchedCount"].(float64)
}

func TestPartyEndMarksEveryoneWhoJoined(t *testing.T) {
	env := newGroupEnv(t)
	fx := env.setUpParty()
	tmdb := env.stubShow("Shogun", catalog.StatusEnded, 1, 5, false)
	show := map[string]any{"type": "show", "ids": map[string]any{"tmdb": tmdb}}

	env.runParty(fx, map[string]any{"title": show, "season": 1, "episode": 2}, func() {
		assert.Equal(t, true, env.ready(fx, map[string]any{"ready": true})["autoMark"], "on for a first join")
		env.ready(fx, map[string]any{"ready": true}, fx.ana.Token)
		assert.Equal(t, false, env.ready(fx, map[string]any{"ready": true, "autoMark": false}, fx.bea.Token)["autoMark"])
		// Joining again without a word keeps what Bea chose.
		assert.Equal(t, false, env.ready(fx, map[string]any{"ready": true}, fx.bea.Token)["autoMark"])
	})

	// Ana and the host left it on: the episode is ticked for each, as their own action.
	hers := env.library("show", fx.ana.Token)
	require.Len(t, hers, 1)
	assert.InDelta(t, 1, watchedCount(hers[0]), 0)
	assert.Equal(t, "in_progress", hers[0]["status"])
	require.Len(t, env.library("show"), 1)
	anaView := env.get(fx.path, fx.ana.Token)
	assert.Equal(t, true, anaView["markedForYou"])
	action, _ := anaView["actionId"].(string)
	require.NotEmpty(t, action)
	journal := items(t, env.send(http.MethodGet, "/v1/actions?limit=5", nil, fx.ana.Token))
	assert.Equal(t, "Watch party: marked S01E02 of Shogun watched", journal[0]["summary"])
	assert.Equal(t, "user", journal[0]["actor"])

	// Bea switched it off: nothing was written for her, and she can still tap.
	assert.Empty(t, env.library("show", fx.bea.Token))
	beaView := env.get(fx.path, fx.bea.Token)
	assert.Equal(t, false, beaView["markedForYou"])
	assert.NotContains(t, beaView, "actionId")
	require.Equal(t, http.StatusNoContent, env.send(http.MethodPost, fx.path+"/watched", nil, fx.bea.Token).Code)
	assert.InDelta(t, 1, watchedCount(env.library("show", fx.bea.Token)[0]), 0)
	assert.Equal(t, true, env.get(fx.path, fx.bea.Token)["markedForYou"])

	// Undo is Ana's own: it takes back her tick and nobody else's.
	require.Equal(t, http.StatusOK, env.send(http.MethodPost, "/v1/actions/"+action+"/undo", nil, fx.ana.Token).Code)
	assert.InDelta(t, 0, watchedCount(env.library("show", fx.ana.Token)[0]), 0)
	assert.InDelta(t, 1, watchedCount(env.library("show")[0]), 0)
	// Nobody undoes another member's action.
	hostAction := env.get(fx.path)["actionId"].(string)
	assert.GreaterOrEqual(t, env.send(http.MethodPost, "/v1/actions/"+hostAction+"/undo", nil, fx.ana.Token).Code, 400)

	// The party is over: a second end finds none open, and a tap by someone already marked
	// writes nothing more.
	assert.Equal(t, http.StatusNotFound, env.send(http.MethodPost, fx.path+"/end", nil).Code)
	before := len(items(t, env.send(http.MethodGet, "/v1/actions?limit=50", nil, fx.ana.Token)))
	require.Equal(t, http.StatusNoContent, env.send(http.MethodPost, fx.path+"/watched", nil, fx.ana.Token).Code)
	assert.Len(t, items(t, env.send(http.MethodGet, "/v1/actions?limit=50", nil, fx.ana.Token)), before)
}

func TestPartyEndLeavesAloneWhatItShould(t *testing.T) {
	env := newGroupEnv(t)
	fx := env.setUpParty()
	tmdb := env.stubShow("Andor", catalog.StatusEnded, 1, 5, false)
	show := map[string]any{"type": "show", "ids": map[string]any{"tmdb": tmdb}}
	open := map[string]any{"title": show, "season": 1, "episode": 3}

	// Ended in the lobby, before any countdown: nothing is written, even for those who joined.
	require.Equal(t, http.StatusOK, env.send(http.MethodPost, fx.path, open).Code)
	env.ready(fx, map[string]any{"ready": true}, fx.ana.Token)
	require.Equal(t, http.StatusOK, env.send(http.MethodPost, fx.path+"/end", nil).Code)
	assert.Empty(t, env.library("show", fx.ana.Token))
	assert.Equal(t, false, env.get(fx.path, fx.ana.Token)["markedForYou"])

	// Ana dropped the show; Bea already ticked that episode. Neither is touched. A member who
	// never joined is not either.
	anas := env.watch(tmdb, nil, fx.ana.Token)
	require.Equal(t, http.StatusOK, env.send(http.MethodPatch, patchPath(anas), map[string]any{"status": "dropped"}, fx.ana.Token).Code)
	env.watch(tmdb, [][2]int{{1, 3}}, fx.bea.Token)
	beaActions := len(items(t, env.send(http.MethodGet, "/v1/actions?limit=50", nil, fx.bea.Token)))
	env.runParty(fx, open, func() {
		env.ready(fx, map[string]any{"ready": true}, fx.ana.Token)
		env.ready(fx, map[string]any{"ready": true}, fx.bea.Token)
	})
	dropped := env.library("show", fx.ana.Token)[0]
	assert.Equal(t, "dropped", dropped["status"])
	assert.InDelta(t, 0, watchedCount(dropped), 0)
	assert.Equal(t, false, env.get(fx.path, fx.ana.Token)["markedForYou"])
	assert.Len(t, items(t, env.send(http.MethodGet, "/v1/actions?limit=50", nil, fx.bea.Token)), beaActions)
	assert.Empty(t, env.library("show"), "the host did not join")
}

func TestReadingSessionReadsToAChapterOrAPage(t *testing.T) {
	env := newGroupEnv(t)
	fx := env.setUpParty()
	manga := map[string]any{"type": "manga", "ids": map[string]any{"anilist": env.stubManga("Berserk")}}

	// Ana is already past chapter 12; the end never moves her back.
	added := env.send(http.MethodPost, "/v1/library/items", map[string]any{"mediaRef": manga}, fx.ana.Token)
	require.Equal(t, http.StatusOK, added.Code, added.Body.String())
	anas := decode[map[string]any](t, added)["id"].(string)
	require.Equal(t, http.StatusOK, env.send(http.MethodPatch, patchPath(anas), map[string]any{"status": "in_progress", "mangaChapter": 40}, fx.ana.Token).Code)

	opened := decode[map[string]any](t, env.send(http.MethodPost, fx.path, map[string]any{"title": manga, "chapter": 12, "volume": 2}))
	party := opened["party"].(map[string]any)
	assert.InDelta(t, 12, party["chapter"], 0)
	assert.InDelta(t, 2, party["volume"], 0)
	env.ready(fx, map[string]any{"ready": true})
	env.ready(fx, map[string]any{"ready": true}, fx.ana.Token)
	require.Equal(t, http.StatusOK, env.send(http.MethodPost, fx.path+"/start", map[string]any{}).Code)
	require.Equal(t, http.StatusOK, env.send(http.MethodPost, fx.path+"/end", nil).Code)

	mine := env.library("manga")
	require.Len(t, mine, 1)
	assert.Equal(t, "in_progress", mine[0]["status"])
	assert.Equal(t, map[string]any{"chapter": 12.0, "volume": 2.0}, mine[0]["mangaProgress"])
	journal := items(t, env.send(http.MethodGet, "/v1/actions?limit=5", nil))
	assert.Contains(t, journal[0]["summary"], "Reading session: ")
	assert.InDelta(t, 40, env.library("manga", fx.ana.Token)[0]["mangaProgress"].(map[string]any)["chapter"], 0)

	// A book reads to a page; a session with no target marks the film watched, and Undo takes
	// back the mark, leaving the film planned.
	pages := 400
	book := map[string]any{"type": "book", "ids": map[string]any{"openLibrary": env.stubBook("Dune", &pages)}}
	env.runParty(fx, map[string]any{"title": book, "page": 120}, func() { env.ready(fx, map[string]any{"ready": true}) })
	assert.Equal(t, map[string]any{"page": 120.0}, env.library("book")[0]["bookProgress"])

	film := map[string]any{"type": "movie", "ids": map[string]any{"tmdb": env.stubMovie("Heat")}}
	env.runParty(fx, map[string]any{"title": film}, func() { env.ready(fx, map[string]any{"ready": true}) })
	assert.Equal(t, "finished", env.library("movie")[0]["status"])
	undo := env.get(fx.path)["actionId"].(string)
	require.Equal(t, http.StatusOK, env.send(http.MethodPost, "/v1/actions/"+undo+"/undo", nil).Code)
	assert.Equal(t, "wishlist", env.library("movie")[0]["status"])

	assert.Equal(t, http.StatusUnprocessableEntity, env.send(http.MethodPost, fx.path, map[string]any{"title": manga, "chapter": -1}).Code)
}
