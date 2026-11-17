package httpapi

import (
	"context"
	"net/http"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// GRAPH-007 over HTTP, against the relation harness's stub TMDB and Wikidata: three films and the
// novel the first adapts.

func (h *harness) buildWorlds() int {
	h.t.Helper()
	built := 0
	for {
		worked, err := h.server.Catalog.Worlds.BuildNext(context.Background())
		require.NoError(h.t, err)
		if !worked {
			return built
		}
		built++
	}
}

func TestTitleWorldRoute(t *testing.T) {
	h, _ := relationsHarness(t)
	userID, bearer := h.signIn()
	rec := h.do(http.MethodPost, "/v1/titles/resolve", bearer, map[string]any{"type": "movie", "ids": map[string]string{"tmdb": "121"}})
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	titleID := decode[map[string]any](t, rec)["title"].(map[string]any)["id"].(string)
	itemID := uuid.New()
	_, err := h.pool.Exec(context.Background(), `INSERT INTO library_items (id, user_id, title_id, status, added_at, updated_at)
		VALUES ($1, $2, $3, 'finished', now(), now())`, itemID, userID, uuid.MustParse(titleID))
	require.NoError(t, err)

	// Not built yet: the read queues it and says so, without lanes.
	rec = h.do(http.MethodGet, "/v1/titles/"+titleID+"/world", bearer, nil)
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	assert.JSONEq(t, `{"state":"building","total":0,"finished":0,"kinds":[],"lanes":[],"links":[],"truncated":false,"partial":false}`,
		rec.Body.String())
	empty := h.do(http.MethodPost, "/v1/titles/"+titleID+"/world/plan", bearer, nil)
	assert.Equal(t, http.StatusUnprocessableEntity, empty.Code, "nothing to add before there is a World")
	assert.Equal(t, 1, h.buildWorlds(), "the read queued the build")
	assert.Equal(t, 0, h.buildWorlds())

	rec = h.do(http.MethodGet, "/v1/titles/"+titleID+"/world", bearer, nil)
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	world := decode[map[string]any](t, rec)
	assert.Equal(t, "ready", world["state"])
	assert.Equal(t, "The Fellowship of the Ring", world["name"], "named after its first-released title")
	assert.InDelta(t, 4, world["total"], 0)
	assert.InDelta(t, 1, world["finished"], 0)
	assert.Equal(t, false, world["truncated"])
	assert.Equal(t, []any{"film", "book"}, world["kinds"], "the undated novel's lane comes after the dated films'")

	lanes := world["lanes"].([]any)
	require.Len(t, lanes, 2)
	films := lanes[0].(map[string]any)["titles"].([]any)
	require.Len(t, films, 3)
	titleOf := func(v any) string { return v.(map[string]any)["ref"].(map[string]any)["title"].(string) }
	assert.Equal(t, "The Fellowship of the Ring", titleOf(films[0]))
	assert.Equal(t, "The Two Towers", titleOf(films[1]))
	assert.Equal(t, "The Return of the King", titleOf(films[2]))
	fellowship, towers := films[0].(map[string]any), films[1].(map[string]any)
	assert.Equal(t, true, fellowship["next"], "the first film of the lane not finished")
	assert.Nil(t, fellowship["status"])
	assert.Equal(t, "finished", towers["status"])
	assert.Equal(t, uuidUpper(itemID), towers["libraryItemId"])
	assert.Equal(t, false, towers["next"])
	assert.Equal(t, towers["key"], world["anchor"])
	assert.Equal(t, fellowship["key"], world["startHere"], "the lane the caller is furthest into")
	novel := lanes[1].(map[string]any)["titles"].([]any)[0].(map[string]any)
	assert.Equal(t, "book", novel["ref"].(map[string]any)["type"])
	assert.Equal(t, true, novel["next"])
	assert.Contains(t, world["links"], map[string]any{"from": novel["key"], "to": fellowship["key"], "relation": "adaptation"})

	// The caller's list: one World, opened from their own title.
	rec = h.do(http.MethodGet, "/v1/me/worlds", bearer, nil)
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	mine := decode[map[string]any](t, rec)["worlds"].([]any)
	require.Len(t, mine, 1)
	summary := mine[0].(map[string]any)
	assert.Equal(t, world["id"], summary["id"])
	assert.Equal(t, "The Fellowship of the Ring", summary["name"])
	assert.InDelta(t, 4, summary["total"], 0)
	assert.InDelta(t, 1, summary["finished"], 0)
	assert.Equal(t, titleID, summary["titleId"])
	assert.Equal(t, "The Fellowship of the Ring", summary["startHere"].(map[string]any)["title"])
	assert.Equal(t, []any{"film", "book"}, summary["kinds"])

	// Add the rest: a capture of the three the caller does not have, by id, to review.
	rec = h.do(http.MethodPost, "/v1/titles/"+titleID+"/world/plan", bearer, nil)
	require.Equal(t, http.StatusAccepted, rec.Code, rec.Body.String())
	jobID := decode[map[string]any](t, rec)["id"].(string)
	var rows, items int
	require.NoError(t, h.pool.QueryRow(context.Background(),
		`SELECT count(*) FROM import_rows WHERE job_id = $1`, uuid.MustParse(jobID)).Scan(&rows))
	assert.Equal(t, 3, rows, "every title but the one already in the library")
	require.NoError(t, h.pool.QueryRow(context.Background(), `SELECT count(*) FROM library_items`).Scan(&items))
	assert.Equal(t, 1, items, "planning adds nothing")

	// Someone else sees the same World with none of this caller's marks, and no list.
	_, other := h.signIn()
	rec = h.do(http.MethodGet, "/v1/titles/"+titleID+"/world", other, nil)
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	theirs := decode[map[string]any](t, rec)
	assert.Equal(t, world["id"], theirs["id"])
	assert.InDelta(t, 0, theirs["finished"], 0)
	assert.NotContains(t, rec.Body.String(), `"libraryItemId"`)
	rec = h.do(http.MethodGet, "/v1/me/worlds", other, nil)
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	assert.JSONEq(t, `{"worlds":[]}`, rec.Body.String())

	assert.Equal(t, http.StatusNotFound, h.do(http.MethodGet, "/v1/titles/"+uuid.NewString()+"/world", bearer, nil).Code)
	assert.Equal(t, http.StatusNotFound, h.do(http.MethodGet, "/v1/titles/not-a-uuid/world", bearer, nil).Code)
	assert.Equal(t, http.StatusUnauthorized, h.do(http.MethodGet, "/v1/titles/"+titleID+"/world", "", nil).Code)
	assert.Equal(t, http.StatusUnauthorized, h.do(http.MethodGet, "/v1/me/worlds", "", nil).Code)
	assert.Equal(t, http.StatusUnauthorized, h.do(http.MethodPost, "/v1/titles/"+titleID+"/world/plan", "", nil).Code)
}

func TestATitleWithNoWorldReadsAsNoneOnceLookedAt(t *testing.T) {
	h, _ := catalogHarness(t)
	_, bearer := h.signIn()
	rec := h.do(http.MethodPost, "/v1/titles/resolve", bearer, map[string]any{"type": "movie", "ids": map[string]string{"tmdb": "603"}})
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	titleID := decode[map[string]any](t, rec)["title"].(map[string]any)["id"].(string)

	rec = h.do(http.MethodGet, "/v1/titles/"+titleID+"/world", bearer, nil)
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	assert.Equal(t, "building", decode[map[string]any](t, rec)["state"])
	assert.Equal(t, 1, h.buildWorlds())
	rec = h.do(http.MethodGet, "/v1/titles/"+titleID+"/world", bearer, nil)
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	assert.Equal(t, "none", decode[map[string]any](t, rec)["state"])
	assert.Equal(t, 0, h.buildWorlds(), "a fresh look is not asked for again")
}
