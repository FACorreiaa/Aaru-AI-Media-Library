package httpapi

import (
	"aaru-go-api/internal/catalog"
	"context"
	"net/http"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// FriendTests.swift: friend profiles and activity (SOC-001 / SOC-003).

func TestAFriendsProfileShowsShelvesAndWhatYouShareNeverNotes(t *testing.T) {
	e := newSocialEnv(t)
	ana := e.friendsByInvite()
	arrival, dune, heat := e.stubMovie("Arrival"), e.stubMovie("Dune"), e.stubMovie("Heat")
	show := e.addItem("show", e.stubShow("Severance", catalog.StatusReturning, 1, 3, false), "in_progress", ana.token)
	e.send(http.MethodPut, "/v1/library/items/"+show+"/episodes/1/2", map[string]any{"watched": true}, ana.token)
	anaArrival := e.addItem("movie", arrival, "finished", ana.token)
	e.send(http.MethodPatch, "/v1/library/items/"+anaArrival, map[string]any{"rating": 9, "notes": "secret note"}, ana.token)
	anaHeat := e.addItem("movie", heat, "finished", ana.token)
	e.send(http.MethodPatch, "/v1/library/items/"+anaHeat, map[string]any{"rating": 8.5}, ana.token)
	e.addItem("movie", dune, "wishlist", ana.token)
	e.addItem("movie", dune, "wishlist")
	e.addItem("movie", arrival, "finished")

	reply := e.send(http.MethodGet, "/v1/social/friends/"+ana.idString()+"/profile", nil)
	require.Equal(t, http.StatusOK, reply.Code, reply.Body.String())
	assert.NotContains(t, reply.Body.String(), "secret note")
	profile := decode[map[string]any](t, reply)
	assert.Equal(t, true, profile["sharing"])
	assert.Equal(t, ana.handle, profile["user"].(map[string]any)["handle"])
	watching := profile["watching"].([]any)
	assert.Equal(t, []string{"Severance"}, titleNames(watching))
	first := watching[0].(map[string]any)
	assert.InDelta(t, 1, first["lastSeason"], 0)
	assert.InDelta(t, 2, first["lastEpisode"], 0)
	assert.ElementsMatch(t, []string{"Arrival", "Heat"}, titleNames(profile["recentlyFinished"]))
	counts := profile["counts"].(map[string]any)
	assert.InDelta(t, 3, counts["movie"], 0)
	assert.InDelta(t, 1, counts["show"], 0)
	assert.InDelta(t, 0, counts["manga"], 0)
	compare := profile["compare"].(map[string]any)
	assert.Equal(t, []string{"Dune"}, names(compare["bothWant"]))
	assert.InDelta(t, 1, compare["bothFinished"], 0)
	// Arrival is loved too, but you already have it.
	assert.Equal(t, []string{"Heat"}, names(compare["theyLoved"]))
	assert.NotNil(t, profile["achievements"])
}

func TestOnlyFriendsSeeAProfileAndHidingTheLibraryLeavesTheName(t *testing.T) {
	e := newSocialEnv(t)
	ana := e.friendsByInvite()
	kai := e.friendlyUser()
	stranger := e.send(http.MethodGet, "/v1/social/friends/"+ana.idString()+"/profile", nil, kai.token)
	nobody := e.send(http.MethodGet, "/v1/social/friends/"+uuid.NewString()+"/profile", nil, kai.token)
	assert.Equal(t, http.StatusNotFound, stranger.Code)
	assert.Equal(t, nobody.Body.String(), stranger.Body.String())
	assert.Equal(t, http.StatusNotFound, e.send(http.MethodGet, "/v1/social/friends/"+e.user.String()+"/profile", nil).Code)

	assert.Equal(t, true, e.get("/v1/me/social-settings", ana.token)["shareLibraryWithFriends"])
	e.addItem("movie", e.stubMovie("Heat"), "finished", ana.token)
	assert.Equal(t, http.StatusOK, e.send(http.MethodPut, "/v1/me/social-settings", map[string]any{"shareLibraryWithFriends": false}, ana.token).Code)
	hidden := e.get("/v1/social/friends/" + ana.idString() + "/profile")
	assert.Equal(t, false, hidden["sharing"])
	assert.Nil(t, hidden["watching"])
	assert.Nil(t, hidden["compare"])
	assert.Nil(t, hidden["favorites"])
	assert.Empty(t, e.get("/v1/activity")["items"])

	// A block ends the friendship and the profile with it.
	e.send(http.MethodPut, "/v1/me/social-settings", map[string]any{"shareLibraryWithFriends": true}, ana.token)
	assert.Equal(t, http.StatusNoContent, e.send(http.MethodPut, "/v1/social/blocks/"+ana.idString(), nil).Code)
	assert.Equal(t, http.StatusNotFound, e.send(http.MethodGet, "/v1/social/friends/"+ana.idString()+"/profile", nil).Code)
}

func TestActivityIsDatedTicksAndFinishesOneRowPerTitleAndDay(t *testing.T) {
	e := newSocialEnv(t)
	ana := e.friendsByInvite()
	show := e.addItem("show", e.stubShow("Andor", catalog.StatusReturning, 1, 3, false), "in_progress", ana.token)
	for episode := 1; episode <= 3; episode++ {
		e.send(http.MethodPut, "/v1/library/items/"+show+"/episodes/1/"+string(rune('0'+episode)), map[string]any{"watched": true}, ana.token)
	}
	e.addItem("movie", e.stubMovie("Heat"), "finished", ana.token)
	// Your own rows are in your feed too, so you see what friends reacted to.
	e.addItem("movie", e.stubMovie("Arrival"), "finished")

	items := e.get("/v1/activity")["items"].([]any)
	assert.ElementsMatch(t, []string{"Andor", "Heat", "Arrival"}, titleNames(items))
	var andor map[string]any
	for _, item := range items {
		m := item.(map[string]any)
		if m["title"].(map[string]any)["title"] == "Andor" {
			andor = m
		}
	}
	require.NotNil(t, andor)
	assert.InDelta(t, 3, andor["episodes"], 0)
	assert.InDelta(t, 3, andor["lastEpisode"], 0)
	assert.Equal(t, false, andor["finished"])
	assert.Equal(t, ana.handle, andor["user"].(map[string]any)["handle"])
	id := andor["id"].(string)
	assert.True(t, strings.HasPrefix(id, ana.idString()+"-"), id)
	assert.ElementsMatch(t, []string{"Andor", "Heat", "Arrival"}, titleNames(e.get("/v1/activity", ana.token)["items"]))

	// A tick without a known date (an import, a restore) is not activity.
	_, err := e.pool.Exec(context.Background(), `UPDATE episode_progress SET watched_at_known = false WHERE library_item_id = $1`, uuid.MustParse(show))
	require.NoError(t, err)
	assert.ElementsMatch(t, []string{"Heat", "Arrival"}, titleNames(e.get("/v1/activity")["items"]))
}
