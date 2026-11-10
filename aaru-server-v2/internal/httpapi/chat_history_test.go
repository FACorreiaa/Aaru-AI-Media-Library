package httpapi

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"context"
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// ASK-011: chat history, the roadmap a chat shows, and films named without a year.

// ask sends one turn and reads it to its end.
func (e *chatEnv) ask(chat, body string) []sseFrame {
	e.t.Helper()
	res := e.openTurn(chatDeadline(e.t), e.listen(), chat, e.bearer, map[string]any{"body": body})
	require.Equal(e.t, http.StatusOK, res.StatusCode)
	return sseOf(res.Body).rest()
}

func (e *chatEnv) history(bearer ...string) []map[string]any {
	e.t.Helper()
	rec := e.send(http.MethodGet, "/v1/chats", nil, bearer...)
	require.Equal(e.t, http.StatusOK, rec.Code, rec.Body.String())
	var out []map[string]any
	for _, c := range decode[map[string]any](e.t, rec)["items"].([]any) {
		out = append(out, c.(map[string]any))
	}
	return out
}

func TestChatHistoryListsChatsWithTurnsLatestFirst(t *testing.T) {
	m := &chatModel{script: []chatMainCall{says("One."), says("Two.")}}
	e := newChatEnv(t, m)
	first, second, empty := e.newChat(e.bearer), e.newChat(e.bearer), e.newChat(e.bearer)
	e.ask(first, "what is airing tonight?")
	e.ask(second, "  how many films\ndid I finish?  ")

	chats := e.history()
	require.Len(t, chats, 2, "a chat nobody asked anything in is left out: %s", empty)
	assert.Equal(t, strings.ToUpper(second), chats[0]["id"])
	assert.Equal(t, "how many films did I finish?", chats[0]["title"])
	assert.Equal(t, strings.ToUpper(first), chats[1]["id"])
	assert.NotEmpty(t, chats[0]["updatedAt"])

	stranger := e.boardStranger()
	assert.Empty(t, e.history(stranger.token), "another user sees none of them")
}

func TestChatHistoryPages(t *testing.T) {
	e := newChatEnv(t, &chatModel{})
	base := time.Now().UTC().Truncate(time.Second)
	for i := range 32 {
		id := uuid.New()
		at := base.Add(time.Duration(i) * time.Minute)
		_, err := e.pool.Exec(context.Background(),
			`INSERT INTO chats (id, user_id, title, created_at, updated_at) VALUES ($1, $2, $3, $4, $4)`,
			id, e.user, fmt.Sprintf("chat %02d", i), at)
		require.NoError(t, err)
		_, err = e.pool.Exec(context.Background(), `INSERT INTO chat_turns (id, chat_id, user_id, role, body, state, created_at, updated_at)
VALUES ($1, $2, $3, 'user', 'hello', 'done', $4, $4)`, uuid.New(), id, e.user, at)
		require.NoError(t, err)
	}
	page := e.json(http.MethodGet, "/v1/chats", nil)
	items := page["items"].([]any)
	require.Len(t, items, 30)
	assert.Equal(t, "chat 31", items[0].(map[string]any)["title"])
	next, _ := page["page"].(map[string]any)["nextCursor"].(string)
	require.NotEmpty(t, next)

	page = e.json(http.MethodGet, "/v1/chats?cursor="+next, nil)
	items = page["items"].([]any)
	require.Len(t, items, 2)
	assert.Equal(t, "chat 01", items[0].(map[string]any)["title"])
	assert.Equal(t, "chat 00", items[1].(map[string]any)["title"])
	assert.Nil(t, page["page"].(map[string]any)["nextCursor"])

	rec := e.send(http.MethodGet, "/v1/chats?cursor=nonsense", nil)
	assert.Equal(t, http.StatusUnprocessableEntity, rec.Code, rec.Body.String())
}

func TestChatReadsBackItsTurnsAndIsOnlyItsOwners(t *testing.T) {
	m := &chatModel{script: []chatMainCall{says("Nothing ", "tonight.")}}
	e := newChatEnv(t, m)
	chat := e.newChat(e.bearer)
	e.ask(chat, "what is airing tonight?")

	got := e.json(http.MethodGet, "/v1/chats/"+chat, nil)
	assert.Equal(t, "what is airing tonight?", got["title"])
	turns := got["turns"].([]any)
	require.Len(t, turns, 2)
	user, agent := turns[0].(map[string]any), turns[1].(map[string]any)
	assert.Equal(t, "user", user["role"])
	assert.Equal(t, "what is airing tonight?", user["body"])
	assert.Equal(t, "agent", agent["role"])
	assert.Equal(t, "Nothing tonight.", agent["body"])
	assert.Equal(t, "done", agent["state"])
	assert.NotContains(t, agent, "components")

	stranger := e.boardStranger()
	assert.Equal(t, http.StatusNotFound, e.send(http.MethodGet, "/v1/chats/"+chat, nil, stranger.token).Code)
	assert.Equal(t, http.StatusNotFound, e.send(http.MethodGet, "/v1/chats/"+uuid.NewString(), nil).Code)
	assert.Equal(t, http.StatusUnauthorized, e.send(http.MethodGet, "/v1/chats/"+chat, nil, "").Code)
}

func TestDeleteChatRemovesOneAndOnlyTheCallers(t *testing.T) {
	m := &chatModel{script: []chatMainCall{says("One."), says("Two.")}}
	e := newChatEnv(t, m)
	keep, gone := e.newChat(e.bearer), e.newChat(e.bearer)
	e.ask(keep, "first")
	e.ask(gone, "second")

	stranger := e.boardStranger()
	assert.Equal(t, http.StatusNoContent, e.send(http.MethodDelete, "/v1/chats/"+gone, nil, stranger.token).Code)
	require.Len(t, e.history(), 2, "someone else's delete touches nothing")

	assert.Equal(t, http.StatusNoContent, e.send(http.MethodDelete, "/v1/chats/"+gone, nil).Code)
	chats := e.history()
	require.Len(t, chats, 1)
	assert.Equal(t, strings.ToUpper(keep), chats[0]["id"])
	assert.Zero(t, e.count(`SELECT count(*) FROM chat_turns WHERE chat_id = $1`, gone))
	assert.Equal(t, http.StatusNoContent, e.send(http.MethodDelete, "/v1/chats/"+gone, nil).Code, "already gone")
}

// The first screenshot, end to end: a watch order from a chat is shown in the reply, read back from
// history, reviewed, approved, and saved as a list with its steps.
func TestChatRoadmapIsShownReviewedAndSavedAsAList(t *testing.T) {
	m := &chatModel{}
	e := newChatEnv(t, m)
	suffix := uuid.NewString()
	loki, strange, unknown := "Loki "+suffix, "Strange "+suffix, "Nowhere "+suffix
	e.captureFilm(loki)
	e.captureFilm(strange)
	const list = "Before Secret Wars"
	m.script = []chatMainCall{
		callsTools(toolResponse("plan_title_list", map[string]any{
			"list_name": list,
			"steps":     []any{map[string]any{"heading": "The Multiverse", "note": "Start here."}, map[string]any{"heading": "Doom"}},
			"titles": []any{
				// No year: matched by its exact name.
				map[string]any{"title": loki, "type": "movie", "step": 1, "note": "All of it"},
				map[string]any{"title": strange, "type": "movie", "year": 2001, "step": 1},
				map[string]any{"title": unknown, "type": "movie", "step": 2, "optional": true},
			},
		}, "a")),
		says("Three titles in two steps, waiting for your review."),
	}
	chat := e.newChat(e.bearer)
	frames := e.ask(chat, "what do I watch before Secret Wars?")

	var parts map[string]any
	for _, f := range frames {
		if f.event == "components" {
			parts = frameData[map[string]any](t, f)
		}
	}
	require.NotNil(t, parts, "%v", frameEvents(frames))
	roadmap := parts["roadmap"].(map[string]any)
	assert.Equal(t, list, roadmap["listName"])
	steps := roadmap["steps"].([]any)
	require.Len(t, steps, 2)
	one := steps[0].(map[string]any)
	assert.Equal(t, "The Multiverse", one["heading"])
	assert.Equal(t, "Start here.", one["note"])
	items := one["items"].([]any)
	require.Len(t, items, 2)
	assert.Equal(t, map[string]any{"title": loki, "type": "movie", "note": "All of it"}, items[0])
	assert.Equal(t, true, steps[1].(map[string]any)["items"].([]any)[0].(map[string]any)["optional"])
	id := parts["importId"].(string)
	assert.Empty(t, e.json(http.MethodGet, "/v1/library/items", nil)["items"], "nothing is added before the review")

	// History shows the same roadmap and still points at the import.
	stored := e.json(http.MethodGet, "/v1/chats/"+chat, nil)["turns"].([]any)[1].(map[string]any)["components"].(map[string]any)
	assert.Equal(t, roadmap, stored["roadmap"])
	assert.Equal(t, id, stored["importId"])

	e.runImports()
	detail := e.json(http.MethodGet, "/v1/imports/"+id, nil)
	assert.NotContains(t, detail, "listId", "no list before approval")
	_, rows := e.importDetail(id)
	require.Len(t, rows, 3)
	assert.NotEqual(t, "unmatched", rows[0]["outcome"], "a film named with no year is found by its name: %v", rows[0]["reason"])
	assert.NotEqual(t, "unmatched", rows[1]["outcome"])
	assert.Equal(t, "unmatched", rows[2]["outcome"])

	e.json(http.MethodPost, "/v1/imports/"+id+"/apply", nil)
	saved := e.listNamed(list)
	require.NotNil(t, saved)
	assert.Equal(t, []string{loki, strange}, e.listOrder(t, saved))
	assert.Equal(t, saved["id"], e.json(http.MethodGet, "/v1/imports/"+id, nil)["listId"], "the review can open the list it made")

	// The import deleted, history keeps the roadmap and drops the dead link.
	require.Equal(t, http.StatusNoContent, e.send(http.MethodDelete, "/v1/imports/"+id, nil).Code)
	stored = e.json(http.MethodGet, "/v1/chats/"+chat, nil)["turns"].([]any)[1].(map[string]any)["components"].(map[string]any)
	assert.Equal(t, roadmap, stored["roadmap"])
	assert.NotContains(t, stored, "importId")
}

// Two films of one name and no year to tell them apart: never a guess.
func TestAFilmNamedWithNoYearIsNotGuessedBetweenTwo(t *testing.T) {
	m := &chatModel{}
	e := newChatEnv(t, m)
	name := "Twins " + uuid.NewString()
	e.captureFilm(name)
	later := 2019
	twin := catalog.Hit{Type: core.MediaMovie, Title: name, Year: &later, IDs: core.ExternalIDs{TMDB: e.fake.uniqueID("")}}
	e.fake.stubTitle(catalog.Record{Hit: twin})
	e.search.searchMu.Lock()
	e.search.hits[name] = append(e.search.hits[name], twin)
	e.search.searchMu.Unlock()
	m.script = []chatMainCall{
		callsTools(toolResponse("plan_title_list", map[string]any{
			"list_name": "One film", "titles": []any{map[string]any{"title": name, "type": "movie"}},
		}, "a")),
		says("Waiting for your review."),
	}
	frames := e.ask(e.newChat(e.bearer), "add that film")
	var id string
	for _, f := range frames {
		if f.event == "components" {
			id = frameData[map[string]any](t, f)["importId"].(string)
		}
	}
	require.NotEmpty(t, id)
	e.runImports()
	_, rows := e.importDetail(id)
	require.Len(t, rows, 1)
	assert.Equal(t, "unmatched", rows[0]["outcome"])
	assert.Contains(t, rows[0]["reason"], "Pick the right one by hand")
}
