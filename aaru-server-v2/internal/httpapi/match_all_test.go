package httpapi

import (
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/model"
	"fmt"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// IMP-021: Match all proposes, and only Approve writes.

// matchAllSetup is a planned capture with one exact row and two rows the strict match refuses: one
// the catalog can guess, one it cannot.
func matchAllSetup(t *testing.T) (env *captureEnv, id, exact, listed, found, lost string) {
	t.Helper()
	suffix := uuid.NewString()
	exact = "Exact " + suffix
	found = "Days of Future Past " + suffix
	listed = "X-Men: " + found
	lost = "Nowhere " + suffix
	m := &captureModel{responses: []model.Response{captureBooksReport(
		map[string]any{"title": exact, "type": "book", "author": "A"},
		map[string]any{"title": listed, "type": "book", "author": "Chris Claremont"},
		map[string]any{"title": lost, "type": "book", "author": "Nobody"},
	)}}
	env = newCaptureEnv(t, m, nil)
	env.captureBook(exact, "A")
	env.captureBook(found, "Chris Claremont")
	rec := env.send("POST", "/v1/imports/capture?kind=book", map[string]any{"text": "three books"})
	require.Equal(t, 202, rec.Code, rec.Body.String())
	id = decode[map[string]any](t, rec)["id"].(string)
	env.runImports()
	return env, id, exact, listed, found, lost
}

func rowNamed(t *testing.T, rows []map[string]any, title string) map[string]any {
	t.Helper()
	for _, row := range rows {
		if row["title"] == title {
			return row
		}
	}
	t.Fatalf("no row %q", title)
	return nil
}

func TestMatchAllProposesAGuessAndOnlyApproveWritesIt(t *testing.T) {
	env, id, _, listed, found, lost := matchAllSetup(t)
	_, rows := env.importDetail(id)
	assert.Equal(t, "unmatched", rowNamed(t, rows, listed)["outcome"])
	assert.Equal(t, true, rowNamed(t, rows, listed)["guessable"])

	answer := env.json("POST", "/v1/imports/"+id+"/match-all", nil)
	assert.EqualValues(t, 0, answer["remaining"])
	assert.Len(t, answer["rows"], 2, "the guessed row and the one it could not place")
	assert.EqualValues(t, 2, answer["job"].(map[string]any)["stats"].(map[string]any)["created"])

	job, rows := env.importDetail(id)
	assert.Equal(t, "planned", job["state"], "nothing was approved")
	assert.Empty(t, env.json("GET", "/v1/library/items", nil)["items"], "nothing was written")
	guessed := rowNamed(t, rows, listed)
	assert.Equal(t, "create", guessed["outcome"])
	assert.Equal(t, listed, guessed["title"], "the row keeps what the person's list said")
	guess := guessed["guess"].(map[string]any)
	assert.Equal(t, found, guess["title"])
	assert.Equal(t, "Chris Claremont", guess["byline"])
	assert.Nil(t, guessed["guessable"])
	missed := rowNamed(t, rows, lost)
	assert.Equal(t, "unmatched", missed["outcome"])
	assert.Nil(t, missed["guess"])
	assert.Nil(t, missed["guessable"], "tried, so another tap does not search again")

	applied := env.json("POST", "/v1/imports/"+id+"/apply", nil)
	assert.EqualValues(t, 2, applied["stats"].(map[string]any)["created"])
	assert.Len(t, env.json("GET", "/v1/library/items", nil)["items"], 2)
	assert.Equal(t, 409, env.send("POST", "/v1/imports/"+id+"/match-all", nil).Code, "the plan is applied")
}

func TestMatchAllGuessCanBeUntickedOrChanged(t *testing.T) {
	env, id, exact, listed, _, _ := matchAllSetup(t)
	require.Equal(t, 200, env.send("POST", "/v1/imports/"+id+"/match-all", nil).Code)
	_, rows := env.importDetail(id)
	index := fmt.Sprint(rowNamed(t, rows, listed)["index"])

	left := env.send("POST", "/v1/imports/"+id+"/rows/"+index+"/left-out", map[string]any{"leftOut": true})
	require.Equal(t, 200, left.Code, left.Body.String())

	// The right book, picked over the guess: the guess goes and the row is ticked again.
	other := "The Right One " + uuid.NewString()
	env.captureBook(other, "Someone")
	hits := env.search.hits[other]
	require.Len(t, hits, 1)
	pick := env.send("POST", "/v1/imports/"+id+"/rows/"+index+"/resolve", map[string]any{"mediaRef": map[string]any{
		"type": string(core.MediaBook), "ids": map[string]any{"openLibrary": hits[0].IDs.OpenLibrary},
	}})
	require.Equal(t, 200, pick.Code, pick.Body.String())
	row := decode[map[string]any](t, pick)["row"].(map[string]any)
	assert.Nil(t, row["guess"])
	assert.Nil(t, row["leftOut"])
	assert.Equal(t, "create", row["outcome"])

	// A row matched exactly, with no guess, is still not open to a new pick.
	exactIndex := fmt.Sprint(rowNamed(t, rows, exact)["index"])
	refused := env.send("POST", "/v1/imports/"+id+"/rows/"+exactIndex+"/resolve", map[string]any{"mediaRef": map[string]any{
		"type": string(core.MediaBook), "ids": map[string]any{"openLibrary": hits[0].IDs.OpenLibrary},
	}})
	assert.Equal(t, 409, refused.Code)
}

func TestMatchAllOfAnUnknownImportIsNotFound(t *testing.T) {
	env, _, _, _, _, _ := matchAllSetup(t)
	assert.Equal(t, 404, env.send("POST", "/v1/imports/"+uuid.NewString()+"/match-all", nil).Code)
}
