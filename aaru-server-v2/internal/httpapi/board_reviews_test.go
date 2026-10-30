package httpapi

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"aaru-go-api/internal/catalog"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Board reviews and spoilers (BoardTests+Reviews.swift, BOARD-001).

func (e *libEnv) boardReview(typ, tmdb string, rating *float64, bearer ...string) *httptest.ResponseRecorder {
	e.t.Helper()
	json := map[string]any{"body": "thoughts", "title": map[string]any{"type": typ, "ids": map[string]string{"tmdb": tmdb}}}
	if rating != nil {
		json["rating"] = *rating
	}
	return e.send(http.MethodPost, "/v1/board/posts", json, bearer...)
}

func boardRating(v float64) *float64 { return &v }

func TestBoardReviewOfANewTitleAddsItAsWatchedWithTheRating(t *testing.T) {
	env := newLibEnv(t)
	env.boardClaimHandle()
	tmdb := env.stubMovie("Dune")
	posted := env.boardReview("movie", tmdb, boardRating(9))
	require.Equal(t, http.StatusCreated, posted.Code, posted.Body.String())

	items, _ := env.boardGet("/v1/library/items")["items"].([]any)
	var mine map[string]any
	for _, it := range items {
		entry := it.(map[string]any)
		if title, _ := entry["title"].(map[string]any); title["title"] == "Dune" {
			mine = entry
		}
	}
	require.NotNil(t, mine)
	assert.Equal(t, "finished", mine["status"])
	assert.InDelta(t, 9, mine["rating"], 0)

	actions, _ := env.boardGet("/v1/actions")["items"].([]any)
	var kinds []any
	for _, a := range actions {
		kinds = append(kinds, a.(map[string]any)["kind"])
	}
	assert.Contains(t, kinds, "add")
	assert.Contains(t, kinds, "update")
}

func TestBoardReviewOfATitleInProgressKeepsItsStatus(t *testing.T) {
	env := newLibEnv(t)
	env.boardClaimHandle()
	tmdb := env.stubShow("Severance", catalog.StatusReturning, 2, 3, false)
	id := env.add("show", tmdb, "in_progress")
	require.Equal(t, http.StatusCreated, env.boardReview("show", tmdb, boardRating(7)).Code)
	entry := env.boardGet("/v1/library/items/" + id)
	assert.Equal(t, "in_progress", entry["status"])
	assert.InDelta(t, 7, entry["rating"], 0)
}

func TestBoardNoRatingMeansNoLibraryWriteABadRatingFails(t *testing.T) {
	env := newLibEnv(t)
	env.boardClaimHandle()
	tmdb := env.stubMovie("Heat")
	assert.Equal(t, http.StatusCreated, env.boardReview("movie", tmdb, nil).Code)
	assert.Equal(t, []any{}, env.boardGet("/v1/library/items")["items"])
	assert.Equal(t, http.StatusUnprocessableEntity, env.boardReview("movie", tmdb, boardRating(11)).Code)
}

func TestBoardSpoilersVeilFriendsWhoAreBehind(t *testing.T) {
	env := newLibEnv(t)
	env.boardClaimHandle()
	ana := env.boardFriend()
	ben := env.boardFriend()
	tmdb := env.stubShow("Andor", catalog.StatusReturning, 2, 6, false)
	env.boardWatch(tmdb, [][2]int{{1, 1}, {1, 2}, {1, 3}, {1, 4}, {1, 5}})
	env.boardWatch(tmdb, [][2]int{{1, 1}, {1, 2}}, ana.token)
	benItem := env.boardWatch(tmdb, [][2]int{{1, 1}}, ben.token)
	done := env.send(http.MethodPatch, "/v1/library/items/"+benItem, map[string]any{"status": "finished"}, ben.token)
	require.Equal(t, http.StatusOK, done.Code, done.Body.String())

	posted := env.boardReview("show", tmdb, nil)
	require.Equal(t, http.StatusCreated, posted.Code, posted.Body.String())
	json := decode[map[string]any](t, posted)
	spoiler, _ := json["spoiler"].(map[string]any)
	assert.InDelta(t, 5, spoiler["episode"], 0)
	assert.Equal(t, false, json["veiled"])
	id := json["id"].(string)

	for _, c := range []struct {
		token  string
		veiled bool
	}{{ana.token, true}, {ben.token, false}, {env.bearer, false}} {
		feed, _ := env.boardGet("/v1/board", c.token)["items"].([]any)
		var row map[string]any
		for _, it := range feed {
			if it.(map[string]any)["id"] == id {
				row = it.(map[string]any)
			}
		}
		require.NotNil(t, row)
		assert.Equal(t, c.veiled, row["veiled"])
		single := env.boardGet("/v1/board/posts/"+id, c.token)
		assert.Equal(t, c.veiled, single["veiled"])
	}
}
