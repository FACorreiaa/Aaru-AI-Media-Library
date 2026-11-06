package httpapi

import (
	"aaru-go-api/internal/capture"
	"aaru-go-api/internal/model"
	"context"
	"encoding/json"
	"net/http"
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
