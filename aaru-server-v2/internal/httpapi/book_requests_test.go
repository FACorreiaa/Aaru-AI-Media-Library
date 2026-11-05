package httpapi

import (
	"aaru-go-api/internal/api"
	"aaru-go-api/internal/capture"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/model"
	"encoding/json"
	"net/http"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// BOOK-003: asking for books, in the Books box or of the owl, is a capture the person reviews, and an
// order they asked for becomes a list.

// captureOrderReport is the model calling report_titles with these items and a list name.
func captureOrderReport(list string, items ...map[string]any) model.Response {
	block, err := json.Marshal(map[string]any{
		"type": "tool_use", "id": "toolu_1", "name": capture.ToolName,
		"input": map[string]any{"titles": items, "list_name": list},
	})
	if err != nil {
		panic(err)
	}
	return model.Response{Content: []model.Block{block}, Stop: model.StopToolUse, InputTokens: 1500, OutputTokens: 101}
}

// listNamed is the user's list of this name, or nil.
func (e *captureEnv) listNamed(name string) map[string]any {
	for _, l := range e.json(http.MethodGet, "/v1/lists", nil)["items"].([]any) {
		if list := l.(map[string]any); list["name"] == name {
			return list
		}
	}
	return nil
}

// listOrder is the titles of a list, in order.
func (e *captureEnv) listOrder(t *testing.T, list map[string]any) []string {
	t.Helper()
	detail := e.json(http.MethodGet, "/v1/lists/"+list["id"].(string), nil)
	names := []string{}
	for _, item := range detail["items"].([]any) {
		names = append(names, item.(map[string]any)["title"].(map[string]any)["title"].(string))
	}
	return names
}

func TestCaptureRequestIsAnsweredAndAnOrderBecomesAListOnApprove(t *testing.T) {
	suffix := uuid.NewString()
	first, skipped, last := "First "+suffix, "Skipped "+suffix, "Last "+suffix
	const list = "X-Men reading order"
	m := &captureModel{responses: []model.Response{captureOrderReport(list,
		map[string]any{"title": first, "type": "book", "author": "A"},
		map[string]any{"title": skipped, "type": "book", "author": "A"},
		map[string]any{"title": last, "type": "book", "author": "A"},
	)}}
	env := newCaptureEnv(t, m, nil)
	env.captureBook(first, "A")
	env.captureBook(skipped, "A")
	env.captureBook(last, "A")

	rec := env.send(http.MethodPost, "/v1/imports/capture?kind=book",
		map[string]any{"text": "recommend me X-Men books and the order to read them"})
	require.Equal(t, 202, rec.Code, rec.Body.String())
	id := decode[map[string]any](t, rec)["id"].(string)
	env.runImports()

	require.Len(t, m.requests, 1)
	assert.Contains(t, m.requests[0].System, "asking for titles", "the model may answer a request")
	assert.Contains(t, string(m.requests[0].Tools[0].InputSchema), "list_name")

	_, rows := env.importDetail(id)
	require.Len(t, rows, 3)
	assert.Equal(t, []any{list}, rows[0]["lists"], "the review can say which list")
	assert.Nil(t, env.listNamed(list), "nothing is written until Approve")

	left := env.send(http.MethodPost, "/v1/imports/"+id+"/rows/1/left-out", map[string]any{"leftOut": true})
	require.Equal(t, http.StatusOK, left.Code, left.Body.String())

	applied := env.json(http.MethodPost, "/v1/imports/"+id+"/apply", nil)
	saved := env.listNamed(list)
	require.NotNil(t, saved)
	assert.Equal(t, []string{first, last}, env.listOrder(t, saved), "in order, without the unticked book")
	items := env.json(http.MethodGet, "/v1/library/items", nil)["items"].([]any)
	require.Len(t, items, 2)
	assert.Equal(t, string(core.StatusWishlist), items[0].(map[string]any)["status"])

	undo := env.send(http.MethodPost, "/v1/actions/"+applied["actionId"].(string)+"/undo", nil)
	require.Equal(t, http.StatusOK, undo.Code, undo.Body.String())
	assert.Empty(t, env.json(http.MethodGet, "/v1/library/items", nil)["items"], "Undo takes the books back")
	assert.Nil(t, env.listNamed(list), "and the list it made")
}

func TestCaptureOrderTakesInABookAlreadyInTheLibrary(t *testing.T) {
	suffix := uuid.NewString()
	owned, added := "Owned "+suffix, "Added "+suffix
	const list = "An order"
	m := &captureModel{responses: []model.Response{
		captureBooksReport(map[string]any{"title": owned, "type": "book", "author": "A"}),
		captureOrderReport(list,
			map[string]any{"title": owned, "type": "book", "author": "A"},
			map[string]any{"title": added, "type": "book", "author": "A"},
		),
	}}
	env := newCaptureEnv(t, m, nil)
	env.captureBook(owned, "A")
	env.captureBook(added, "A")
	for _, text := range []string{"one book", "two books in order"} {
		rec := env.send(http.MethodPost, "/v1/imports/capture?kind=book", map[string]any{"text": text})
		require.Equal(t, 202, rec.Code, rec.Body.String())
		id := decode[map[string]any](t, rec)["id"].(string)
		env.runImports()
		env.json(http.MethodPost, "/v1/imports/"+id+"/apply", nil)
	}
	saved := env.listNamed(list)
	require.NotNil(t, saved)
	assert.Equal(t, []string{owned, added}, env.listOrder(t, saved))
}

func TestCaptureWithoutAnOrderMakesNoList(t *testing.T) {
	name := "Lone " + uuid.NewString()
	m := &captureModel{responses: []model.Response{captureBooksReport(map[string]any{"title": name, "type": "book", "author": "A"})}}
	env := newCaptureEnv(t, m, nil)
	env.captureBook(name, "A")
	rec := env.send(http.MethodPost, "/v1/imports/capture?kind=book", map[string]any{"text": name})
	require.Equal(t, 202, rec.Code, rec.Body.String())
	id := decode[map[string]any](t, rec)["id"].(string)
	env.runImports()
	_, rows := env.importDetail(id)
	assert.Nil(t, rows[0]["lists"])
	env.json(http.MethodPost, "/v1/imports/"+id+"/apply", nil)
	assert.Empty(t, env.json(http.MethodGet, "/v1/lists", nil)["items"])
}

func TestMatchAllKeepsARowInItsList(t *testing.T) {
	suffix := uuid.NewString()
	found := "Days of Future Past " + suffix
	listed := "X-Men: " + found
	const list = "X-Men reading order"
	m := &captureModel{responses: []model.Response{captureOrderReport(list,
		map[string]any{"title": listed, "type": "book", "author": "Chris Claremont"},
	)}}
	env := newCaptureEnv(t, m, nil)
	env.captureBook(found, "Chris Claremont")
	rec := env.send(http.MethodPost, "/v1/imports/capture?kind=book", map[string]any{"text": "x-men in order"})
	require.Equal(t, 202, rec.Code, rec.Body.String())
	id := decode[map[string]any](t, rec)["id"].(string)
	env.runImports()
	env.json(http.MethodPost, "/v1/imports/"+id+"/match-all", nil)
	env.json(http.MethodPost, "/v1/imports/"+id+"/apply", nil)
	saved := env.listNamed(list)
	require.NotNil(t, saved)
	assert.Equal(t, []string{found}, env.listOrder(t, saved))
}

func TestOwlSendsAListForReviewAndAddsNothing(t *testing.T) {
	m := &chatModel{}
	e := newChatEnv(t, m)
	suffix := uuid.NewString()
	first, second := "First "+suffix, "Second "+suffix
	e.captureBook(first, "A")
	e.captureBook(second, "A")
	m.script = []chatMainCall{
		callsTools(toolResponse("plan_title_list", map[string]any{
			"list_name": "X-Men reading order",
			"titles": []any{
				map[string]any{"title": first, "type": "book", "author": "A"},
				map[string]any{"title": second, "type": "book", "author": "A"},
			},
		}, "a"), toolResponse("plan_title_list", map[string]any{
			"titles": []any{map[string]any{"title": "Again " + suffix, "type": "book"}},
		}, "b")),
		says("They wait for your review."),
	}
	res := e.openTurn(chatDeadline(t), e.listen(), e.newChat(e.bearer), e.bearer,
		map[string]any{"body": "recommend x-men books and the order to read, and add them"})
	frames := sseOf(res.Body).rest()
	var parts api.ChatComponentsFrame
	found := false
	for _, frame := range frames {
		if frame.event == "components" {
			parts, found = frameData[api.ChatComponentsFrame](t, frame), true
		}
	}
	require.True(t, found, "%v", frameEvents(frames))
	require.NotNil(t, parts.ImportId)
	assert.Nil(t, parts.ActionId)

	// One a reply: the second call started nothing.
	assert.Equal(t, 1, e.count(`SELECT count(*) FROM import_jobs WHERE source = 'capture' AND user_id = $1`, e.user))
	assert.Empty(t, e.json(http.MethodGet, "/v1/library/items", nil)["items"])

	e.runImports()
	id := strings.ToUpper(parts.ImportId.String())
	job, rows := e.importDetail(id)
	assert.Equal(t, "planned", job["state"])
	require.Len(t, rows, 2)
	assert.Equal(t, first, rows[0]["title"])
	assert.Equal(t, []any{"X-Men reading order"}, rows[0]["lists"])
	e.json(http.MethodPost, "/v1/imports/"+id+"/apply", nil)
	saved := e.listNamed("X-Men reading order")
	require.NotNil(t, saved)
	assert.Equal(t, []string{first, second}, e.listOrder(t, saved))
}

func TestOwlListSpendsTheCaptureQuota(t *testing.T) {
	m := &chatModel{}
	e := newChatEnv(t, m)
	for range 30 {
		rec := e.send(http.MethodPost, "/v1/imports/capture", map[string]any{"url": "https://www.themoviedb.org/movie/603"})
		require.Equal(t, 202, rec.Code, rec.Body.String())
	}
	m.script = []chatMainCall{
		callsTools(toolResponse("plan_title_list", map[string]any{
			"titles": []any{map[string]any{"title": "One", "type": "book"}},
		}, "a")),
		says("Not today."),
	}
	res := e.openTurn(chatDeadline(t), e.listen(), e.newChat(e.bearer), e.bearer, map[string]any{"body": "add some books"})
	frames := sseOf(res.Body).rest()
	assert.NotContains(t, frameEvents(frames), "components")
	assert.Equal(t, 30, e.count(`SELECT count(*) FROM import_jobs WHERE source = 'capture' AND user_id = $1`, e.user))
}
