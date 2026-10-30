package httpapi

import (
	"net/http"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// InteractionTests.swift: reactions and recommendations (SOC-007 / SOC-006).

func rows(t *testing.T, body map[string]any) []map[string]any {
	t.Helper()
	out := []map[string]any{}
	list, _ := body["items"].([]any)
	for _, item := range list {
		out = append(out, item.(map[string]any))
	}
	return out
}

func TestAFriendReactsOnceCanChangeOrClearAndYouSeeIt(t *testing.T) {
	e := newSocialEnv(t)
	ana := e.friendsByInvite()
	e.addItem("movie", e.stubMovie("Heat"), "finished")
	mine := rows(t, e.get("/v1/activity"))
	require.NotEmpty(t, mine)
	id := mine[0]["id"].(string)
	path := "/v1/activity/" + id + "/reaction"

	assert.Equal(t, http.StatusNoContent, e.send(http.MethodPut, path, map[string]any{"emoji": "🔥"}, ana.token).Code)
	assert.Equal(t, http.StatusNoContent, e.send(http.MethodPut, path, map[string]any{"emoji": "❤️"}, ana.token).Code)
	row := rows(t, e.get("/v1/activity"))[0]
	counts := row["reactions"].([]any)
	require.Len(t, counts, 1)
	assert.Equal(t, "❤️", counts[0].(map[string]any)["emoji"])
	assert.InDelta(t, 1, counts[0].(map[string]any)["count"], 0)
	assert.Nil(t, row["myReaction"])
	theirs := rows(t, e.get("/v1/activity", ana.token))[0]
	assert.Equal(t, "❤️", theirs["myReaction"])

	// Lowercase ids read the same row.
	assert.Equal(t, http.StatusNoContent, e.send(http.MethodPut, "/v1/activity/"+strings.ToLower(id)+"/reaction", map[string]any{"emoji": "❤️"}, ana.token).Code)

	// Only the six, never on your own row, never on a stranger's.
	assert.Equal(t, http.StatusBadRequest, e.send(http.MethodPut, path, map[string]any{"emoji": "👍"}, ana.token).Code)
	assert.Equal(t, http.StatusNotFound, e.send(http.MethodPut, path, map[string]any{"emoji": "❤️"}).Code)
	kai := e.friendlyUser()
	assert.Equal(t, http.StatusNotFound, e.send(http.MethodPut, path, map[string]any{"emoji": "❤️"}, kai.token).Code)
	assert.Equal(t, http.StatusNotFound, e.send(http.MethodPut, "/v1/activity/nonsense/reaction", map[string]any{"emoji": "❤️"}, ana.token).Code)

	assert.Equal(t, http.StatusNoContent, e.send(http.MethodDelete, path, nil, ana.token).Code)
	assert.Nil(t, rows(t, e.get("/v1/activity"))[0]["reactions"])
}

func TestARecommendationReachesFriendsOnlyAndAddingIsOnePlanToWatchWrite(t *testing.T) {
	e := newSocialEnv(t)
	ana := e.friendsByInvite()
	kai := e.friendlyUser()
	tmdb := e.stubMovie("Arrival")
	title := map[string]any{"type": "movie", "ids": map[string]any{"tmdb": tmdb}}

	// A stranger anywhere in the list sends nothing.
	assert.Equal(t, http.StatusNotFound, e.send(http.MethodPost, "/v1/social/recommendations",
		map[string]any{"to": []string{ana.idString(), kai.idString()}, "title": title}).Code)
	assert.Empty(t, rows(t, e.get("/v1/me/recommendations", ana.token)))
	assert.Equal(t, http.StatusUnprocessableEntity, e.send(http.MethodPost, "/v1/social/recommendations",
		map[string]any{"to": []string{ana.idString()}, "title": title, "note": strings.Repeat("a", 141)}).Code)

	sent := e.send(http.MethodPost, "/v1/social/recommendations",
		map[string]any{"to": []string{ana.idString()}, "title": title, "note": " You'll love it "})
	assert.Equal(t, http.StatusNoContent, sent.Code, sent.Body.String())
	// Sending it again while it waits changes nothing.
	e.send(http.MethodPost, "/v1/social/recommendations", map[string]any{"to": []string{ana.idString()}, "title": title})
	inbox := rows(t, e.get("/v1/me/recommendations", ana.token))
	require.Len(t, inbox, 1)
	assert.Equal(t, "You'll love it", inbox[0]["note"])
	assert.Equal(t, "Arrival", inbox[0]["title"].(map[string]any)["title"])
	id := inbox[0]["id"].(string)

	assert.Equal(t, http.StatusNotFound, e.send(http.MethodPost, "/v1/me/recommendations/"+id+"/add", nil).Code)
	assert.Equal(t, http.StatusNoContent, e.send(http.MethodPost, "/v1/me/recommendations/"+id+"/add", nil, ana.token).Code)
	library := rows(t, e.get("/v1/library/items", ana.token))
	require.Len(t, library, 1)
	assert.Equal(t, "wishlist", library[0]["status"])
	assert.Empty(t, rows(t, e.get("/v1/me/recommendations", ana.token)))
	assert.Equal(t, http.StatusNotFound, e.send(http.MethodPost, "/v1/me/recommendations/"+id+"/add", nil, ana.token).Code)

	// Dismissing removes what is still waiting.
	e.send(http.MethodPost, "/v1/social/recommendations", map[string]any{"to": []string{ana.idString()}, "title": map[string]any{
		"type": "movie", "ids": map[string]any{"tmdb": e.stubMovie("Heat")},
	}})
	waiting := rows(t, e.get("/v1/me/recommendations", ana.token))
	require.Len(t, waiting, 1)
	assert.Equal(t, http.StatusNoContent, e.send(http.MethodDelete, "/v1/me/recommendations/"+waiting[0]["id"].(string), nil, ana.token).Code)
	assert.Empty(t, rows(t, e.get("/v1/me/recommendations", ana.token)))

	// Unfriending hides what is still waiting.
	e.send(http.MethodPost, "/v1/social/recommendations", map[string]any{"to": []string{ana.idString()}, "title": map[string]any{
		"type": "movie", "ids": map[string]any{"tmdb": e.stubMovie("Dune")},
	}})
	require.Len(t, rows(t, e.get("/v1/me/recommendations", ana.token)), 1)
	e.send(http.MethodDelete, "/v1/social/friends/"+ana.idString(), nil)
	assert.Empty(t, rows(t, e.get("/v1/me/recommendations", ana.token)))
}
