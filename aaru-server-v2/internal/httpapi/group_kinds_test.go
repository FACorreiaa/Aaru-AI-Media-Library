package httpapi

import (
	"aaru-go-api/internal/apitime"
	"aaru-go-api/internal/catalog"
	"context"
	"encoding/json"
	"fmt"
	"math"
	"net/http"
	"sync"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// GroupKindTests.swift: title, shelf and watch channels (GRP-007…GRP-009).

// frames records what one socket was sent.
type frames struct {
	mu   sync.Mutex
	list []map[string]any
}

func (f *frames) sink(_ context.Context, frame []byte) error {
	var v map[string]any
	if err := json.Unmarshal(frame, &v); err != nil {
		return err
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	f.list = append(f.list, v)
	return nil
}

func (f *frames) all() []map[string]any {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]map[string]any(nil), f.list...)
}

func (f *frames) types() []string {
	out := []string{}
	for _, v := range f.all() {
		out = append(out, v["type"].(string))
	}
	return out
}

// listen opens a fake socket for a user on the hub.
func (e *groupEnv) listen(user uuid.UUID) *frames {
	f := &frames{}
	e.server.Realtime.Connect(user, f.sink)
	return f
}

type kindFixture struct {
	ana     groupMember
	group   string
	channel string
}

// setUpKind is a group with the harness user as owner and Ana as a member, plus a channel of kind.
func (e *groupEnv) setUpKind(kind string, title map[string]any) kindFixture {
	e.t.Helper()
	e.claimHandle()
	ana := e.friend(e.user)
	group, _ := e.createGroup("Film club")
	e.join(ana, group)
	body := map[string]any{"kind": kind}
	if title != nil {
		body["title"] = title
	} else {
		body["name"] = kind
	}
	rec := e.send(http.MethodPost, "/v1/groups/"+group+"/channels", body)
	require.Equal(e.t, http.StatusOK, rec.Code, rec.Body.String())
	return kindFixture{ana: ana, group: group, channel: decode[map[string]any](e.t, rec)["id"].(string)}
}

// watch adds a show to someone's library and ticks episodes; returns the item id.
func (e *groupEnv) watch(tmdb string, episodes [][2]int, token ...string) string {
	e.t.Helper()
	rec := e.send(http.MethodPost, "/v1/library/items", map[string]any{
		"mediaRef": map[string]any{"type": "show", "ids": map[string]any{"tmdb": tmdb}}, "status": "in_progress",
	}, token...)
	require.Equal(e.t, http.StatusOK, rec.Code, rec.Body.String())
	item := decode[map[string]any](e.t, rec)["id"].(string)
	for _, ep := range episodes {
		e.tick(item, ep, token...)
	}
	return item
}

func (e *groupEnv) tick(item string, ep [2]int, token ...string) {
	e.t.Helper()
	rec := e.send(http.MethodPut, fmt.Sprintf("/v1/library/items/%s/episodes/%d/%d", item, ep[0], ep[1]), map[string]any{"watched": true}, token...)
	require.Equal(e.t, http.StatusOK, rec.Code, rec.Body.String())
}

func TestGroupTitleChannelSpoilerGuard(t *testing.T) {
	env := newGroupEnv(t)
	tmdb := env.stubShow("Severance", catalog.StatusReturning, 2, 5, false)
	fx := env.setUpKind("title", map[string]any{"type": "show", "ids": map[string]any{"tmdb": tmdb}})
	path := channelPath(fx.group, fx.channel)
	var listed map[string]any
	for _, c := range maps(env.get("/v1/groups/" + fx.group)["channels"]) {
		if c["id"] == fx.channel {
			listed = c
		}
	}
	require.NotNil(t, listed)
	assert.Equal(t, "severance", listed["name"])
	assert.Equal(t, "Severance", listed["title"].(map[string]any)["title"])
	env.watch(tmdb, [][2]int{{1, 1}, {1, 2}, {1, 3}})
	anaItem := env.watch(tmdb, [][2]int{{1, 1}}, fx.ana.Token)
	// Auto-stamped where the author is: S1E3. Ana is at S1E1.
	auto := env.post(path, "the ending of episode 3!")
	assert.InDelta(t, 3, auto["spoiler"].(map[string]any)["episode"], 0)
	assert.Equal(t, false, auto["veiled"])
	// A hand stamp, a spoiler-free message, and one about the ending.
	env.send(http.MethodPost, path+"/messages", map[string]any{"body": "S1E5 twist", "spoiler": map[string]any{"season": 1, "episode": 5}})
	env.send(http.MethodPost, path+"/messages", map[string]any{"body": "who's in?", "spoilerFree": true})
	env.send(http.MethodPost, path+"/messages", map[string]any{"body": "that finale", "spoiler": map[string]any{"ending": true}})
	veiled := func(token ...string) []any {
		var out []any
		for _, m := range items(t, env.send(http.MethodGet, path+"/messages", nil, token...)) {
			out = append(out, m["veiled"])
		}
		return out
	}
	assert.Equal(t, []any{true, true, false, true}, veiled(fx.ana.Token))
	// Ana catches up to S2E1: everything up to there unveils, the ending does not.
	for _, ep := range [][2]int{{1, 2}, {1, 3}, {2, 1}} {
		env.tick(anaItem, ep, fx.ana.Token)
	}
	assert.Equal(t, []any{false, false, false, true}, veiled(fx.ana.Token))
	// The author never sees their own messages veiled.
	assert.Equal(t, []any{false, false, false, false}, veiled())
	// The stamp shows where its author is, so nobody else sees it.
	for _, m := range items(t, env.send(http.MethodGet, path+"/messages", nil, fx.ana.Token)) {
		assert.Nil(t, m["spoiler"])
	}
	// A stamp needs a whole episode or the ending.
	bad := env.send(http.MethodPost, path+"/messages", map[string]any{"body": "x", "spoiler": map[string]any{"season": 1}})
	assert.Equal(t, http.StatusUnprocessableEntity, bad.Code)
}

func TestGroupTitleChannelShareProgress(t *testing.T) {
	env := newGroupEnv(t)
	tmdb := env.stubShow("Andor", catalog.StatusReturning, 2, 5, false)
	fx := env.setUpKind("title", map[string]any{"type": "show", "ids": map[string]any{"tmdb": tmdb}})
	path := channelPath(fx.group, fx.channel) + "/progress"
	env.watch(tmdb, [][2]int{{1, 2}})
	env.watch(tmdb, [][2]int{{1, 1}}, fx.ana.Token)
	header := env.get(path, fx.ana.Token)
	assert.Empty(t, header["members"])
	assert.InDelta(t, 1, header["mine"].(map[string]any)["episode"], 0)
	shared := decode[map[string]any](t, env.send(http.MethodPut, "/v1/groups/"+fx.group+"/me", map[string]any{"shareProgress": true}))
	assert.Equal(t, true, shared["shareProgress"])
	members := maps(env.get(path, fx.ana.Token)["members"])
	require.Len(t, members, 1)
	assert.InDelta(t, 2, members[0]["episode"], 0)
	// Ana does not share, so she never appears for anyone.
	assert.Empty(t, env.get(path)["members"])
}

func TestGroupShelfChannel(t *testing.T) {
	env := newGroupEnv(t)
	fx := env.setUpKind("shelf", nil)
	path := channelPath(fx.group, fx.channel) + "/items"
	anaSocket := env.listen(fx.ana.uid)
	tmdb := env.stubMovie("Arrival")
	movie := map[string]any{"title": map[string]any{"type": "movie", "ids": map[string]any{"tmdb": tmdb}}}
	added := items(t, env.send(http.MethodPost, path, movie, fx.ana.Token))
	require.Len(t, added, 1)
	assert.Equal(t, fx.ana.Handle, added[0]["addedBy"].(map[string]any)["handle"])
	assert.Nil(t, added[0]["myStatus"])
	assert.Contains(t, anaSocket.types(), "shelf.updated")
	// Adding it again changes nothing.
	assert.Len(t, items(t, env.send(http.MethodPost, path, movie)), 1)
	titleID := added[0]["title"].(map[string]any)["id"].(string)
	before := env.actionCount()
	mine := env.send(http.MethodPost, "/v1/library/items", map[string]any{"mediaRef": map[string]any{"type": "movie", "titleId": titleID}})
	require.Equal(t, http.StatusOK, mine.Code, mine.Body.String())
	assert.Equal(t, before+1, env.actionCount())
	assert.Equal(t, "wishlist", items(t, env.send(http.MethodGet, path, nil))[0]["myStatus"])
	assert.Nil(t, items(t, env.send(http.MethodGet, path, nil, fx.ana.Token))[0]["myStatus"])
	assert.Equal(t, http.StatusNoContent, env.send(http.MethodDelete, path+"/"+titleID, nil).Code)
	assert.Equal(t, http.StatusNotFound, env.send(http.MethodDelete, path+"/"+titleID, nil).Code)
	text := env.get("/v1/groups/" + fx.group)["group"].(map[string]any)["defaultChannelId"].(string)
	assert.Equal(t, http.StatusUnprocessableEntity, env.send(http.MethodGet, channelPath(fx.group, text)+"/items", nil).Code)
}

func TestGroupWatchParty(t *testing.T) {
	env := newGroupEnv(t)
	tmdb := env.stubShow("Shogun", catalog.StatusEnded, 1, 5, false)
	fx := env.setUpKind("watch", nil)
	path := channelPath(fx.group, fx.channel) + "/party"
	show := map[string]any{"type": "show", "ids": map[string]any{"tmdb": tmdb}}
	assert.Nil(t, env.get(path)["party"])
	assert.Equal(t, http.StatusUnprocessableEntity, env.send(http.MethodPost, path, map[string]any{"title": show}).Code)
	opened := decode[map[string]any](t, env.send(http.MethodPost, path, map[string]any{"title": show, "season": 1, "episode": 2}))
	assert.Equal(t, "lobby", opened["party"].(map[string]any)["state"])
	assert.NotNil(t, opened["serverTime"])
	assert.Equal(t, http.StatusConflict, env.send(http.MethodPost, path, map[string]any{"title": show, "season": 1, "episode": 3}).Code)
	ready := decode[map[string]any](t, env.send(http.MethodPost, path+"/ready", map[string]any{"ready": true}, fx.ana.Token))
	assert.Len(t, ready["party"].(map[string]any)["ready"], 1)
	assert.Equal(t, http.StatusUnprocessableEntity, env.send(http.MethodPost, path+"/watched", nil, fx.ana.Token).Code)
	assert.Equal(t, http.StatusForbidden, env.send(http.MethodPost, path+"/start", map[string]any{}, fx.ana.Token).Code)
	started := decode[map[string]any](t, env.send(http.MethodPost, path+"/start", map[string]any{"countdownSeconds": 5}))
	party := started["party"].(map[string]any)
	assert.Equal(t, "countdown", party["state"])
	startsAt, err := apitime.Parse(party["startsAt"].(string))
	require.NoError(t, err)
	serverTime, err := apitime.Parse(started["serverTime"].(string))
	require.NoError(t, err)
	assert.Less(t, math.Abs(startsAt.Sub(serverTime).Seconds()-5), 1.5)
	// Reactions reach the others; anything outside the set is dropped.
	anaSocket := env.listen(fx.ana.uid)
	group, channel := uuid.MustParse(fx.group), uuid.MustParse(fx.channel)
	require.NoError(t, env.server.Groups.React(t.Context(), group, channel, "🔥", env.user))
	require.NoError(t, env.server.Groups.React(t.Context(), group, channel, "lol", env.user))
	assert.Equal(t, []string{"watch.reaction"}, anaSocket.types())
	ended := decode[map[string]any](t, env.send(http.MethodPost, path+"/end", nil))
	assert.Equal(t, "ended", ended["party"].(map[string]any)["state"])
	// After the end, Ana ticks it for herself; nobody else's library changes.
	assert.Equal(t, http.StatusNoContent, env.send(http.MethodPost, path+"/watched", nil, fx.ana.Token).Code)
	hers := items(t, env.send(http.MethodGet, "/v1/library/items?type=show", nil, fx.ana.Token))
	require.Len(t, hers, 1)
	assert.InDelta(t, 1, hers[0]["progress"].(map[string]any)["watchedCount"], 0)
	assert.Empty(t, items(t, env.send(http.MethodGet, "/v1/library/items?type=show", nil)))
}
