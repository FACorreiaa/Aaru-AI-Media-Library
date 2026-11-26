package httpapi

import (
	"aaru-go-api/internal/capture"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/model"
	"context"
	"encoding/json"
	"net/http"
	"sync"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// GRAPH-003: a roadmap the model writes in steps becomes a list that keeps them.

func roadmapReport(list string, steps []map[string]any, items ...map[string]any) model.Response {
	block, err := json.Marshal(map[string]any{
		"type": "tool_use", "id": "toolu_1", "name": capture.ToolName,
		"input": map[string]any{"titles": items, "list_name": list, "steps": steps},
	})
	if err != nil {
		panic(err)
	}
	return model.Response{Content: []model.Block{block}, Stop: model.StopToolUse, InputTokens: 1500, OutputTokens: 101}
}

func TestRoadmapKeepsItsStepsNotesPairsAndWhatWasNotFound(t *testing.T) {
	suffix := uuid.NewString()
	dark, ff, fourth, ultimates, unknown := "Dark Reign "+suffix, "FF "+suffix, "Fantastic Four "+suffix,
		"Ultimates "+suffix, "Nowhere "+suffix
	const list = "Secret Wars roadmap"
	m := &captureModel{responses: []model.Response{roadmapReport(list,
		[]map[string]any{{"heading": "Hickman Fantastic Four", "note": "Start here."}, {"heading": "Extras"}},
		map[string]any{"title": dark, "type": "book", "author": "A", "step": 1, "note": "FF #1-5"},
		map[string]any{"title": ff, "type": "book", "author": "A", "step": 1, "pair": 1},
		map[string]any{"title": fourth, "type": "book", "author": "A", "step": 1, "pair": 1, "note": "#600-611"},
		map[string]any{"title": ultimates, "type": "book", "author": "A", "step": 2, "optional": true},
		map[string]any{"title": unknown, "type": "book", "author": "A", "step": 2, "note": "#1-12"},
	)}}
	env := newCaptureEnv(t, m, nil)
	for _, name := range []string{dark, ff, fourth, ultimates} {
		env.captureBook(name, "A")
	}

	rec := env.send(http.MethodPost, "/v1/imports/capture?kind=book",
		map[string]any{"text": "what should I read to be prepared for Secret Wars? full roadmap"})
	require.Equal(t, 202, rec.Code, rec.Body.String())
	id := decode[map[string]any](t, rec)["id"].(string)
	env.runImports()
	assert.Contains(t, string(m.requests[0].Tools[0].InputSchema), `"steps"`)

	_, rows := env.importDetail(id)
	require.Len(t, rows, 5)
	first := rows[0]["roadmap"].(map[string]any)
	assert.Equal(t, "Hickman Fantastic Four", first["heading"], "the review can show the step")
	assert.Equal(t, "FF #1-5", first["note"])
	assert.Equal(t, "unmatched", rows[4]["outcome"])

	applied := env.json(http.MethodPost, "/v1/imports/"+id+"/apply", nil)
	saved := env.listNamed(list)
	require.NotNil(t, saved)
	assert.Equal(t, []string{dark, ff, fourth, ultimates}, env.listOrder(t, saved))

	detail := env.json(http.MethodGet, "/v1/lists/"+saved["id"].(string), nil)
	steps := detail["roadmap"].(map[string]any)["steps"].([]any)
	require.Len(t, steps, 2)
	hickman := steps[0].(map[string]any)
	assert.Equal(t, "Hickman Fantastic Four", hickman["heading"])
	assert.Equal(t, "Start here.", hickman["note"])
	items := hickman["items"].([]any)
	require.Len(t, items, 3)
	assert.Equal(t, "FF #1-5", items[0].(map[string]any)["note"])
	assert.InDelta(t, 1, items[1].(map[string]any)["pair"], 0)
	assert.InDelta(t, 1, items[2].(map[string]any)["pair"], 0)
	extras := steps[1].(map[string]any)
	assert.Equal(t, true, extras["items"].([]any)[0].(map[string]any)["optional"])
	assert.Equal(t, []any{unknown + " (#1-12)"}, extras["missing"], "what Aaru could not find stays as text")

	library := env.json(http.MethodGet, "/v1/library/items", nil)["items"].([]any)
	assert.Len(t, library, 3, "the optional title joins the list, not Plan to read")

	// GRAPH-004: the roadmap as a graph. A column per title, the pair in one column, the optional
	// title hanging under the one before it, off the main chain.
	g := env.json(http.MethodGet, "/v1/lists/"+saved["id"].(string)+"/graph", nil)
	place := map[string][2]float64{}
	chain := map[string]bool{}
	keys := map[string]string{}
	for _, n := range g["nodes"].([]any) {
		node := n.(map[string]any)
		name := node["ref"].(map[string]any)["title"].(string)
		place[name] = [2]float64{node["rank"].(float64), node["lane"].(float64)}
		chain[name] = node["mainChain"].(bool)
		keys[name] = node["key"].(string)
	}
	assert.Equal(t, [2]float64{0, 0}, place[dark])
	assert.Equal(t, [2]float64{1, 0}, place[ff])
	assert.Equal(t, [2]float64{1, 1}, place[fourth], "read side by side with FF")
	assert.Equal(t, [2]float64{1, 2}, place[ultimates])
	assert.False(t, chain[ultimates], "optional is off the main chain")
	assert.Equal(t, keys[dark], g["startHere"])
	assert.Contains(t, g["edges"], map[string]any{"from": keys[dark], "to": keys[fourth], "relation": "sequel"})

	// A member removed by hand leaves its step.
	ultimatesID := ""
	for _, item := range detail["items"].([]any) {
		title := item.(map[string]any)["title"].(map[string]any)
		if title["title"] == ultimates {
			ultimatesID = title["id"].(string)
		}
	}
	require.NotEmpty(t, ultimatesID)
	remove := env.send(http.MethodDelete, "/v1/lists/"+saved["id"].(string)+"/items/"+ultimatesID, nil)
	require.Less(t, remove.Code, 300, remove.Body.String())
	steps = env.json(http.MethodGet, "/v1/lists/"+saved["id"].(string), nil)["roadmap"].(map[string]any)["steps"].([]any)
	require.Len(t, steps, 2, "the Extras step still holds what was not found")
	assert.Empty(t, steps[1].(map[string]any)["items"])

	undo := env.send(http.MethodPost, "/v1/actions/"+applied["actionId"].(string)+"/undo", nil)
	require.Equal(t, http.StatusOK, undo.Code, undo.Body.String())
	assert.Nil(t, env.listNamed(list), "Undo takes the list, and its steps, back")
	var left int
	require.NoError(t, env.pool.QueryRow(context.Background(),
		`SELECT count(*) FROM list_roadmaps WHERE list_id = $1`, uuid.MustParse(saved["id"].(string))).Scan(&left))
	assert.Zero(t, left)
}

func TestPlainOrderHasNoRoadmap(t *testing.T) {
	name := "Plain " + uuid.NewString()
	m := &captureModel{responses: []model.Response{captureOrderReport("Plain order",
		map[string]any{"title": name, "type": "book", "author": "A"})}}
	env := newCaptureEnv(t, m, nil)
	env.captureBook(name, "A")
	rec := env.send(http.MethodPost, "/v1/imports/capture?kind=book", map[string]any{"text": "in order"})
	require.Equal(t, 202, rec.Code, rec.Body.String())
	id := decode[map[string]any](t, rec)["id"].(string)
	env.runImports()
	env.json(http.MethodPost, "/v1/imports/"+id+"/apply", nil)
	saved := env.listNamed("Plain order")
	require.NotNil(t, saved)
	assert.NotContains(t, env.json(http.MethodGet, "/v1/lists/"+saved["id"].(string), nil), "roadmap")
}

// ASK-012: a roadmap is always its own list. The same roadmap asked for twice makes a second list
// and leaves the first one's steps as they were; a plain order still joins its list.

func (e *captureEnv) approvedCapture(text string) (id string, applied map[string]any) {
	e.t.Helper()
	rec := e.send(http.MethodPost, "/v1/imports/capture?kind=book", map[string]any{"text": text})
	require.Equal(e.t, 202, rec.Code, rec.Body.String())
	id = decode[map[string]any](e.t, rec)["id"].(string)
	e.runImports()
	return id, e.json(http.MethodPost, "/v1/imports/"+id+"/apply", nil)
}

func (e *captureEnv) roadmapSteps(list map[string]any) []any {
	e.t.Helper()
	detail := e.json(http.MethodGet, "/v1/lists/"+list["id"].(string), nil)
	return detail["roadmap"].(map[string]any)["steps"].([]any)
}

// storedSteps counts the steps a list keeps in list_roadmaps, hidden or not.
func (e *captureEnv) storedSteps(list map[string]any) int {
	e.t.Helper()
	var steps int
	require.NoError(e.t, e.pool.QueryRow(context.Background(),
		`SELECT coalesce(jsonb_array_length(roadmap->'steps'), 0) FROM list_roadmaps WHERE list_id = $1`,
		uuid.MustParse(list["id"].(string))).Scan(&steps))
	return steps
}

func repeatedRoadmap(t *testing.T) (env *captureEnv, list, first, second string) {
	t.Helper()
	first, second = "Dune "+uuid.NewString(), "Children of Dune "+uuid.NewString()
	list = "Road to Dune " + uuid.NewString()[:8]
	steps := []map[string]any{{"heading": "The books"}}
	m := &captureModel{responses: []model.Response{
		roadmapReport(list, steps, map[string]any{"title": first, "type": "book", "author": "A", "step": 1}),
		// Aaru cannot find the second title here, so its step keeps text even with no title in it.
		roadmapReport(list, steps, map[string]any{"title": second, "type": "book", "author": "A", "step": 1},
			map[string]any{"title": "Nowhere " + uuid.NewString(), "type": "book", "author": "A", "step": 1}),
	}}
	env = newCaptureEnv(t, m, nil)
	env.captureBook(first, "A")
	env.captureBook(second, "A")
	return env, list, first, second
}

func TestSameRoadmapTwiceMakesASecondList(t *testing.T) {
	env, list, first, second := repeatedRoadmap(t)
	env.approvedCapture("the roadmap to read Dune")
	id, _ := env.approvedCapture("the roadmap to read Dune")

	original := env.listNamed(list)
	require.NotNil(t, original)
	assert.Equal(t, []string{first}, env.listOrder(t, original))
	assert.Len(t, env.roadmapSteps(original), 1, "the first list's steps are not doubled")
	assert.Equal(t, 1, env.storedSteps(original))

	again := env.listNamed(list + " (2)")
	require.NotNil(t, again, "the second roadmap has a list of its own")
	assert.Equal(t, []string{second}, env.listOrder(t, again))
	assert.Len(t, env.roadmapSteps(again), 1)

	detail := env.json(http.MethodGet, "/v1/imports/"+id, nil)
	assert.Equal(t, again["id"], detail["listId"], "the review opens the new list")
}

func TestUndoOfARepeatedRoadmapLeavesTheFirstListAsItWas(t *testing.T) {
	env, list, first, _ := repeatedRoadmap(t)
	env.approvedCapture("the roadmap to read Dune")
	_, applied := env.approvedCapture("the roadmap to read Dune")

	undo := env.send(http.MethodPost, "/v1/actions/"+applied["actionId"].(string)+"/undo", nil)
	require.Equal(t, http.StatusOK, undo.Code, undo.Body.String())
	assert.Nil(t, env.listNamed(list+" (2)"), "Undo takes the second list back")
	original := env.listNamed(list)
	require.NotNil(t, original)
	assert.Equal(t, []string{first}, env.listOrder(t, original))
	assert.Len(t, env.roadmapSteps(original), 1)
	assert.Equal(t, 1, env.storedSteps(original), "no step of the undone roadmap is left on the first list")
}

func TestPlainOrderOfTheSameNameStillJoinsItsList(t *testing.T) {
	first, second := "Plain one "+uuid.NewString(), "Plain two "+uuid.NewString()
	list := "Plain order " + uuid.NewString()[:8]
	m := &captureModel{responses: []model.Response{
		captureOrderReport(list, map[string]any{"title": first, "type": "book", "author": "A"}),
		captureOrderReport(list, map[string]any{"title": second, "type": "book", "author": "A"}),
	}}
	env := newCaptureEnv(t, m, nil)
	env.captureBook(first, "A")
	env.captureBook(second, "A")
	env.approvedCapture("in order")
	env.approvedCapture("in order")

	saved := env.listNamed(list)
	require.NotNil(t, saved)
	assert.Equal(t, []string{first, second}, env.listOrder(t, saved), "a list without steps still gathers")
	assert.Nil(t, env.listNamed(list+" (2)"))
}

// plannedCapture is a capture of text, matched and waiting for approval.
func (e *captureEnv) plannedCapture(text string) string {
	e.t.Helper()
	rec := e.send(http.MethodPost, "/v1/imports/capture?kind=book", map[string]any{"text": text})
	require.Equal(e.t, 202, rec.Code, rec.Body.String())
	id := decode[map[string]any](e.t, rec)["id"].(string)
	e.runImports()
	return id
}

// reviewList is the list name a review shows: the first row's that names one.
func (e *captureEnv) reviewList(id string) string {
	e.t.Helper()
	for _, r := range e.json(http.MethodGet, "/v1/imports/"+id, nil)["rows"].([]any) {
		if lists, _ := r.(map[string]any)["lists"].([]any); len(lists) > 0 {
			return lists[0].(string)
		}
	}
	return ""
}

func TestTwoRoadmapsOfOneNameApprovedAtOnceGetTwoLists(t *testing.T) {
	env, list, first, second := repeatedRoadmap(t)
	ids := []string{env.plannedCapture("the roadmap to read Dune"), env.plannedCapture("the roadmap to read Dune")}

	codes := make([]int, len(ids))
	var wg sync.WaitGroup
	for i, id := range ids {
		wg.Go(func() { codes[i] = env.send(http.MethodPost, "/v1/imports/"+id+"/apply", nil).Code })
	}
	wg.Wait()
	assert.Equal(t, []int{http.StatusOK, http.StatusOK}, codes)

	original, again := env.listNamed(list), env.listNamed(list+" (2)")
	require.NotNil(t, original)
	require.NotNil(t, again, "the second approval waited for the first one's list and named its own")
	assert.ElementsMatch(t, []string{first, second}, append(env.listOrder(t, original), env.listOrder(t, again)...))
	assert.Equal(t, 1, env.storedSteps(original), "each list keeps its own roadmap's step")
	assert.Equal(t, 1, env.storedSteps(again))
}

func TestReviewShowsTheNameApprovalWillGive(t *testing.T) {
	env, list, _, _ := repeatedRoadmap(t)
	env.approvedCapture("the roadmap to read Dune")
	id := env.plannedCapture("the roadmap to read Dune")

	assert.Equal(t, list+" (2)", env.reviewList(id), "the review names the list approval makes")
	env.json(http.MethodPost, "/v1/imports/"+id+"/apply", nil)
	assert.Equal(t, list+" (2)", env.reviewList(id))
	assert.NotNil(t, env.listNamed(list+" (2)"))
}

func TestATitleMatchedByHandJoinsItsOwnImportsList(t *testing.T) {
	lost, found, later := "Lost "+uuid.NewString(), "Found "+uuid.NewString(), "Later "+uuid.NewString()
	list := "Road to Arrakis " + uuid.NewString()[:8]
	steps := []map[string]any{{"heading": "The books"}}
	m := &captureModel{responses: []model.Response{
		// Aaru finds nothing of the first roadmap, so approving it makes no list.
		roadmapReport(list, steps, map[string]any{"title": lost, "type": "book", "author": "A", "step": 1}),
		roadmapReport(list, steps, map[string]any{"title": later, "type": "book", "author": "A", "step": 1}),
	}}
	env := newCaptureEnv(t, m, nil)
	env.captureBook(later, "A")
	firstID, _ := env.approvedCapture("the roadmap to Arrakis")
	assert.Nil(t, env.json(http.MethodGet, "/v1/imports/"+firstID, nil)["listId"], "nothing matched, no list")
	env.approvedCapture("the roadmap to Arrakis")
	newer := env.listNamed(list)
	require.NotNil(t, newer)
	assert.Nil(t, env.json(http.MethodGet, "/v1/imports/"+firstID, nil)["listId"],
		"the first review does not open a later import's list of its name")

	env.captureBook(found, "A")
	pick := env.send(http.MethodPost, "/v1/imports/"+firstID+"/rows/0/resolve", map[string]any{"mediaRef": map[string]any{
		"type": string(core.MediaBook), "ids": map[string]any{"openLibrary": env.search.hits[found][0].IDs.OpenLibrary},
	}})
	require.Equal(t, http.StatusOK, pick.Code, pick.Body.String())

	assert.Equal(t, []string{later}, env.listOrder(t, newer), "the later list is left as it was")
	own := env.listNamed(list + " (2)")
	require.NotNil(t, own, "the first roadmap gets a list of its own")
	assert.Equal(t, []string{found}, env.listOrder(t, own))
	assert.Equal(t, own["id"], env.json(http.MethodGet, "/v1/imports/"+firstID, nil)["listId"])
}

func TestAHandMatchOnALaterRowRenamesTheListOnEveryRow(t *testing.T) {
	lostA, lostB, found, later := "Lost "+uuid.NewString(), "Lost "+uuid.NewString(), "Found "+uuid.NewString(), "Later "+uuid.NewString()
	list := "Road to Caladan " + uuid.NewString()[:8]
	steps := []map[string]any{{"heading": "The books"}}
	m := &captureModel{responses: []model.Response{
		roadmapReport(list, steps,
			map[string]any{"title": lostA, "type": "book", "author": "A", "step": 1},
			map[string]any{"title": lostB, "type": "book", "author": "A", "step": 1}),
		roadmapReport(list, steps, map[string]any{"title": later, "type": "book", "author": "A", "step": 1}),
	}}
	env := newCaptureEnv(t, m, nil)
	env.captureBook(later, "A")
	firstID, _ := env.approvedCapture("the roadmap to Caladan")
	env.approvedCapture("the roadmap to Caladan")

	env.captureBook(found, "A")
	pick := env.send(http.MethodPost, "/v1/imports/"+firstID+"/rows/1/resolve", map[string]any{"mediaRef": map[string]any{
		"type": string(core.MediaBook), "ids": map[string]any{"openLibrary": env.search.hits[found][0].IDs.OpenLibrary},
	}})
	require.Equal(t, http.StatusOK, pick.Code, pick.Body.String())
	assert.Equal(t, list+" (2)", env.reviewList(firstID), "the first row names the list the match made")
}

func TestLeavingOutARowKeepsTheNameApprovalWillGive(t *testing.T) {
	env, list, _, _ := repeatedRoadmap(t)
	env.approvedCapture("the roadmap to read Dune")
	id := env.plannedCapture("the roadmap to read Dune")

	left := env.send(http.MethodPost, "/v1/imports/"+id+"/rows/0/left-out", map[string]any{"leftOut": true})
	require.Equal(t, http.StatusOK, left.Code, left.Body.String())
	row := decode[map[string]any](t, left)["row"].(map[string]any)
	assert.Equal(t, []any{list + " (2)"}, row["lists"], "the row the client patches in keeps the new name")
}
