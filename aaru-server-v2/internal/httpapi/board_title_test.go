package httpapi

import (
	"net/http"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Board posts on a title (BoardTests+Title.swift).

func TestBoardTitlePageListsFriendsPostsAboutItNewestFirst(t *testing.T) {
	env := newLibEnv(t)
	env.boardClaimHandle()
	ana := env.boardFriend()
	stranger := env.boardStranger()
	tmdb := env.stubMovie("Dune")
	ref := map[string]any{"type": "movie", "ids": map[string]string{"tmdb": tmdb}}

	post := func(body string, about bool, bearer string) string {
		json := map[string]any{"body": body}
		if about {
			json["title"] = ref
		}
		rec := env.send(http.MethodPost, "/v1/board/posts", json, bearer)
		require.Equal(t, http.StatusCreated, rec.Code, rec.Body.String())
		return decode[map[string]any](t, rec)["id"].(string)
	}
	anasFree := post("free", false, ana.token)
	post("stranger", true, stranger.token)
	first := post("ana on dune", true, ana.token)
	second := post("my dune", true, env.bearer)

	detail := env.boardGet("/v1/board/posts/" + first)
	titleID := detail["title"].(map[string]any)["id"].(string)

	got := env.boardIDs("/v1/titles/" + titleID + "/posts")
	assert.Equal(t, []string{second, first}, got)
	assert.NotContains(t, got, anasFree)

	assert.Len(t, env.boardIDs("/v1/titles/"+titleID+"/posts?limit=1"), 1)
	assert.Equal(t, http.StatusNotFound, env.send(http.MethodGet, "/v1/titles/nope/posts", nil).Code)
}
