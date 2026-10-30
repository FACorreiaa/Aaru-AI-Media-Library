package httpapi

import (
	"aaru-go-api/internal/catalog"
	"context"
	"net/http"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// ListShelfTests (M6).

func titleIDs(detail map[string]any) []string { return ids(detail["titles"]) }

func movieRef(tmdb string) map[string]any {
	return map[string]any{"mediaRef": map[string]any{"type": "movie", "ids": map[string]string{"tmdb": tmdb}}}
}

func TestListsAreScoped(t *testing.T) { // LST-001
	env := newLibEnv(t)
	id := env.json(http.MethodPost, "/v1/lists", map[string]any{"name": "Noir"})["id"].(string)
	blank := env.send(http.MethodPost, "/v1/lists", map[string]any{"name": "  "})
	assert.Equal(t, http.StatusUnprocessableEntity, blank.Code)
	assert.Contains(t, blank.Body.String(), "List name must not be empty.")

	_, other := env.signIn()
	assert.Equal(t, http.StatusNotFound, env.send(http.MethodGet, "/v1/lists/"+id, nil, other).Code)
	assert.Equal(t, http.StatusNotFound, env.send(http.MethodPatch, "/v1/lists/"+id, map[string]any{"name": "Mine"}, other).Code)
	assert.Equal(t, http.StatusNotFound, env.send(http.MethodDelete, "/v1/lists/"+id, nil, other).Code)
	assert.Empty(t, decode[map[string]any](t, env.send(http.MethodGet, "/v1/lists", nil, other))["items"])
	missing := env.send(http.MethodGet, "/v1/lists/nope", nil)
	assert.Equal(t, http.StatusNotFound, missing.Code)
	assert.Contains(t, missing.Body.String(), "No such list.")

	_, err := env.pool.Exec(context.Background(), `UPDATE lists SET visibility = 'public' WHERE id = $1`, uuid.MustParse(id))
	assert.Error(t, err, "the database refuses anything but private")

	renamed := env.json(http.MethodPatch, "/v1/lists/"+id, map[string]any{"name": " Neo-noir "})
	assert.Equal(t, "Neo-noir", renamed["name"])
	lists := env.json(http.MethodGet, "/v1/lists", nil)["items"].([]any)
	require.Len(t, lists, 1)
	assert.InDelta(t, 0, lists[0].(map[string]any)["itemCount"], 0)
	assert.Equal(t, []string{"Renamed Noir to Neo-noir", "Created list Noir"}, summaries(env))
	require.Equal(t, http.StatusNoContent, env.send(http.MethodDelete, "/v1/lists/"+id, nil).Code)
	require.Equal(t, http.StatusOK, env.send(http.MethodPost, "/v1/actions/"+env.latestAction()+"/undo", nil).Code)
	assert.Equal(t, "Neo-noir", env.json(http.MethodGet, "/v1/lists/"+id, nil)["name"], "undo brings a deleted list back")
}

func TestListMembership(t *testing.T) { // LST-002
	env := newLibEnv(t)
	id := env.json(http.MethodPost, "/v1/lists", map[string]any{"name": "Watch with Ana"})["id"].(string)
	first, second := env.stubMovie("Chinatown"), env.stubMovie("Vertigo")
	for _, tmdb := range []string{first, second, first} {
		env.json(http.MethodPost, "/v1/lists/"+id+"/items", movieRef(tmdb))
	}
	got := titleIDs(env.json(http.MethodGet, "/v1/lists/"+id, nil))
	require.Len(t, got, 2, "adding a member again changes nothing")
	assert.Empty(t, env.json(http.MethodGet, "/v1/library/items", nil)["items"], "no library item was created")

	reversed := []string{got[1], got[0]}
	assert.Equal(t, reversed, titleIDs(env.json(http.MethodPut, "/v1/lists/"+id+"/order", map[string]any{"titleIds": reversed})))
	assert.Equal(t, reversed, titleIDs(env.json(http.MethodGet, "/v1/lists/"+id, nil)))
	assert.Equal(t, http.StatusUnprocessableEntity, env.send(http.MethodPut, "/v1/lists/"+id+"/order", map[string]any{"titleIds": []string{got[0]}}).Code)
	assert.Equal(t, http.StatusBadRequest, env.send(http.MethodPut, "/v1/lists/"+id+"/order", map[string]any{"titleIds": []string{"x", "y"}}).Code)

	env.json(http.MethodDelete, "/v1/lists/"+id+"/items/"+got[0], nil)
	assert.Equal(t, []string{got[1]}, titleIDs(env.json(http.MethodGet, "/v1/lists/"+id, nil)))
	assert.Equal(t, http.StatusNotFound, env.send(http.MethodDelete, "/v1/lists/"+id+"/items/"+got[0], nil).Code)
	require.Equal(t, http.StatusOK, env.send(http.MethodPost, "/v1/actions/"+env.latestAction()+"/undo", nil).Code)
	assert.ElementsMatch(t, got, titleIDs(env.json(http.MethodGet, "/v1/lists/"+id, nil)))
}

func TestListRowsCarryEntryAndAiring(t *testing.T) { // LST-003
	env := newLibEnv(t)
	id := env.json(http.MethodPost, "/v1/lists", map[string]any{"name": "Tonight"})["id"].(string)
	tracked := env.stubShow("Severance", catalog.StatusReturning, 2, 3, true)
	item := env.add("show", tracked, "in_progress")
	env.json(http.MethodPut, patchPath(item)+"/episodes/1/1", map[string]any{"watched": true})
	listOnly := env.stubShow("Slow Horses", catalog.StatusReturning, 2, 3, true)
	movie := env.stubMovie("Heat")
	for _, ref := range []struct{ typ, tmdb string }{{"show", tracked}, {"show", listOnly}, {"movie", movie}} {
		rec := env.send(http.MethodPost, "/v1/lists/"+id+"/items",
			map[string]any{"mediaRef": map[string]any{"type": ref.typ, "ids": map[string]string{"tmdb": ref.tmdb}}})
		require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	}
	items := env.json(http.MethodGet, "/v1/lists/"+id, nil)["items"].([]any)
	row := func(i int) map[string]any { return items[i].(map[string]any) }
	var names []string
	for i := range items {
		names = append(names, row(i)["title"].(map[string]any)["title"].(string))
	}
	assert.Equal(t, []string{"Severance", "Slow Horses", "Heat"}, names)

	entry := row(0)["entry"].(map[string]any)
	assert.Equal(t, item, entry["id"])
	watched, _ := progressOf(entry)
	assert.InDelta(t, 1, watched, 0)
	assert.Equal(t, "returning", row(0)["showStatus"])

	assert.NotContains(t, row(1), "entry", "on the list, not in the library")
	assert.Equal(t, "returning", row(1)["showStatus"], "episodes load when the show is added")
	next := row(1)["nextAiring"].(map[string]any)
	assert.InDelta(t, 2, next["season"], 0)
	assert.InDelta(t, 3, next["number"], 0)
	assert.Equal(t, false, next["airTimeKnown"])

	assert.NotContains(t, row(2), "entry")
	assert.NotContains(t, row(2), "showStatus")
	assert.NotContains(t, row(2), "nextAiring")
}

func TestAShelfIsAQuery(t *testing.T) { // SHF-001
	env := newLibEnv(t)
	shelf := env.json(http.MethodPost, "/v1/shelves", map[string]any{
		"name": "Unwatched films", "filter": map[string]any{"type": "movie", "status": "wishlist"},
	})
	shelfID := shelf["id"].(string)
	for _, name := range []string{"One", "Two"} {
		env.add("movie", env.stubMovie(name))
	}
	count := func() int {
		return len(env.json(http.MethodGet, "/v1/shelves/"+shelfID+"/items", nil)["items"].([]any))
	}
	assert.Equal(t, 2, count())
	env.add("movie", env.stubMovie("Three"))
	assert.Equal(t, 3, count())
	env.add("show", env.stubShow("Not a movie", catalog.StatusEnded, 1, 1, false))
	assert.Equal(t, 3, count())

	_, other := env.signIn()
	assert.Equal(t, http.StatusNotFound, env.send(http.MethodGet, "/v1/shelves/"+shelfID+"/items", nil, other).Code)
	assert.Equal(t, http.StatusUnprocessableEntity, env.send(http.MethodPost, "/v1/shelves", map[string]any{"name": " ", "filter": map[string]any{}}).Code)

	pinned := env.json(http.MethodPatch, "/v1/shelves/"+shelfID, map[string]any{"isPinned": true, "name": "Films"})
	assert.Equal(t, true, pinned["isPinned"])
	assert.Equal(t, "Films", pinned["name"])
	assert.Equal(t, map[string]any{"type": "movie", "status": "wishlist"}, pinned["filter"])
	assert.Len(t, env.json(http.MethodGet, "/v1/shelves", nil)["items"], 1)
	require.Equal(t, http.StatusNoContent, env.send(http.MethodDelete, "/v1/shelves/"+shelfID, nil).Code)
	gone := env.send(http.MethodDelete, "/v1/shelves/"+shelfID, nil)
	assert.Equal(t, http.StatusNotFound, gone.Code)
	assert.Contains(t, gone.Body.String(), "No such shelf.")
}

func TestAShelfMatchesItsFilter(t *testing.T) { // SHF-002
	env := newLibEnv(t)
	listID := env.json(http.MethodPost, "/v1/lists", map[string]any{"name": "Picks"})["id"].(string)
	for _, name := range []string{"A", "B", "C"} {
		tmdb := env.stubMovie(name)
		env.add("movie", tmdb)
		if name != "B" {
			env.json(http.MethodPost, "/v1/lists/"+listID+"/items", movieRef(tmdb))
		}
	}
	shelfID := env.json(http.MethodPost, "/v1/shelves", map[string]any{
		"name": "Picks I own nothing of", "filter": map[string]any{"type": "movie", "owned": false, "list": listID},
	})["id"].(string)
	viaShelf := env.send(http.MethodGet, "/v1/shelves/"+shelfID+"/items?limit=10", nil)
	viaFilter := env.send(http.MethodGet, "/v1/library/items?type=movie&owned=false&list="+listID+"&limit=10", nil)
	require.Equal(t, http.StatusOK, viaShelf.Code)
	assert.Equal(t, viaFilter.Body.String(), viaShelf.Body.String())
	assert.Len(t, decode[map[string]any](t, viaShelf)["items"], 2)

	// The stored filter is Swift's LibraryFilter encoding.
	var filter string
	require.NoError(t, env.pool.QueryRow(context.Background(), `SELECT filter::text FROM saved_queries WHERE id = $1`, uuid.MustParse(shelfID)).Scan(&filter))
	assert.JSONEq(t, `{"type":"movie","isOwned":false,"listID":"`+listID+`"}`, filter)
}
