package httpapi

import (
	"aaru-go-api/internal/auth"
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/stremio"
	"aaru-go-api/internal/token"
	"context"
	"fmt"
	"math/rand/v2"
	"net/http"
	"net/http/httptest"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// StremioTests.swift (SCR-003).

func (e *libEnv) stremioGet(path string, method ...string) *httptest.ResponseRecorder {
	e.t.Helper()
	m := http.MethodGet
	if len(method) > 0 {
		m = method[0]
	}
	return e.do(m, path, "", nil)
}

func (e *libEnv) connectStremio(libraryWrites bool) (secret, id string) {
	id, secret = e.connectAgent("stremio", map[string]any{"allowLibraryWrites": libraryWrites})
	return secret, id
}

// itemTitle is the title id of a library item.
func (e *libEnv) itemTitle(item string) string {
	e.t.Helper()
	var id uuid.UUID
	require.NoError(e.t, e.pool.QueryRow(context.Background(), `SELECT title_id FROM library_items WHERE id = $1`,
		uuid.MustParse(item)).Scan(&id))
	return strings.ToLower(id.String())
}

// stubIMDbShow is an ended show with an IMDb id (so Stremio names it `tt…`) and two aired seasons of three.
func (e *libEnv) stubIMDbShow(name string) (tmdb, imdb string) {
	tmdb = e.fake.uniqueID("tmdb")
	imdb = fmt.Sprintf("tt%d", 10_000_000+rand.IntN(89_999_999)) //nolint:gosec // a test id
	year := 2020
	ended := catalog.StatusEnded
	e.fake.stubTitle(catalog.Record{
		Hit: catalog.Hit{Type: core.MediaShow, Title: name, Year: &year, IDs: core.ExternalIDs{TMDB: tmdb, IMDB: imdb}}, Status: &ended,
	})
	aired := time.Now().Add(-400 * 24 * time.Hour)
	var episodes []catalog.Episode
	for season := 1; season <= 2; season++ {
		for n := 1; n <= 3; n++ {
			name := fmt.Sprintf("S%dE%d", season, n)
			runtime := 45
			episodes = append(episodes, catalog.Episode{Season: season, Episode: n, Name: &name, AirsAt: &aired, RuntimeMinutes: &runtime})
		}
	}
	e.fake.mu.Lock()
	e.fake.episodes[tmdb] = catalog.Episodes{Status: &ended, Episodes: episodes}
	e.fake.mu.Unlock()
	return tmdb, imdb
}

func (e *libEnv) watchedText(item string) []string {
	e.t.Helper()
	out := []string{}
	for _, k := range e.watchedKeys(uuid.MustParse(item)) {
		out = append(out, fmt.Sprintf("%dx%d", k.Season, k.Episode))
	}
	sort.Strings(out)
	return out
}

func TestStremioPathsParseWithEncodedIDsAndExtraSegments(t *testing.T) {
	player, ok := stremio.ParseRequest("/stremio/aaru_st_x/player/series/tt0903747%3A1%3A2/action=stop&currentTime=1200&duration=2400.json")
	require.True(t, ok)
	assert.Equal(t, stremio.Request{
		Token: "aaru_st_x", Kind: stremio.RouteResource, Name: "player", Type: "series", ID: "tt0903747:1:2",
		Extra: map[string]string{"action": "stop", "currentTime": "1200", "duration": "2400"},
	}, player)
	library, ok := stremio.ParseRequest("/stremio/t/library/series/tt1/action=watched&videoId=tt1%3A1%3A1%2Ctt1%3A1%3A2.json")
	require.True(t, ok)
	assert.Equal(t, map[string]string{"action": "watched", "videoId": "tt1:1:1,tt1:1:2"}, library.Extra)
	assert.Equal(t, "tt1", library.ID)
	skip, ok := stremio.ParseRequest("/stremio/t/catalog/movie/aaru-wishlist/skip=100.json")
	require.True(t, ok)
	assert.Equal(t, stremio.Request{
		Token: "t", Kind: stremio.RouteResource, Name: "catalog", Type: "movie", ID: "aaru-wishlist",
		Extra: map[string]string{"skip": "100"},
	}, skip)
	manifest, _ := stremio.ParseRequest("/stremio/t/manifest.json")
	assert.Equal(t, stremio.RouteManifest, manifest.Kind)
	configure, _ := stremio.ParseRequest("/stremio/t/configure")
	assert.Equal(t, stremio.RouteConfigure, configure.Kind)
	_, ok = stremio.ParseRequest("/stremio/t/meta/series/x")
	assert.False(t, ok, "no .json")
	_, ok = stremio.ParseRequest("/stremio/t/action%3Dstop%26currentTime%3D5.json")
	assert.False(t, ok)
	assert.Equal(t, map[string]string{"action": "stop", "currentTime": "5"}, stremio.Extra("action%3Dstop%26currentTime%3D5"))

	id, ok := stremio.ParseID("tt0903747:1:2")
	require.True(t, ok)
	ep := key(1, 2)
	assert.Equal(t, stremio.ID{IMDB: "tt0903747", Episode: &ep}, id)
	plain, _ := stremio.ParseID("tt0903747")
	assert.Nil(t, plain.Episode)
	u := uuid.New()
	aaru, ok := stremio.ParseID("aaru:" + strings.ToUpper(u.String()) + ":0:3")
	require.True(t, ok)
	assert.Equal(t, u, *aaru.TitleID)
	_, ok = stremio.ParseID("kitsu:123:4")
	assert.False(t, ok)
	_, ok = stremio.ParseID("tt12:x:1")
	assert.False(t, ok)
}

func TestStremioManifestDeclaresNoStreamAndCORSIsOnEveryAnswer(t *testing.T) {
	env := newLibEnv(t)
	secret, id := env.connectStremio(false)
	got := env.stremioGet("/stremio/" + secret + "/manifest.json")
	require.Equal(t, http.StatusOK, got.Code)
	assert.Equal(t, "*", got.Header().Get("Access-Control-Allow-Origin"))
	assert.NotContains(t, got.Body.String(), "stream")
	manifest := decode[map[string]any](t, got)
	var resources []string
	for _, r := range manifest["resources"].([]any) {
		resources = append(resources, r.(map[string]any)["name"].(string))
	}
	assert.Equal(t, []string{"catalog", "meta", "player", "library"}, resources)
	catalogs := manifest["catalogs"].([]any)
	assert.Len(t, catalogs, 4)
	var wishlist []string
	for _, c := range catalogs {
		if m := c.(map[string]any); m["id"] == "aaru-wishlist" {
			wishlist = append(wishlist, m["name"].(string))
		}
	}
	assert.Equal(t, []string{"Aaru · Plan to watch", "Aaru · Plan to watch"}, wishlist)

	options := env.stremioGet("/stremio/"+secret+"/manifest.json", http.MethodOptions)
	assert.Equal(t, "*", options.Header().Get("Access-Control-Allow-Origin"))
	stream := env.stremioGet("/stremio/" + secret + "/stream/movie/tt0133093.json")
	assert.Equal(t, http.StatusNotFound, stream.Code)
	assert.Equal(t, "*", stream.Header().Get("Access-Control-Allow-Origin"))
	configure := env.stremioGet("/stremio/" + secret + "/configure")
	assert.Equal(t, http.StatusFound, configure.Code)
	assert.Equal(t, stremio.ConfigureURL, configure.Header().Get("Location"))

	assert.Equal(t, http.StatusNoContent, env.send(http.MethodDelete, "/v1/agent/tokens/"+id, nil).Code)
	revoked := env.stremioGet("/stremio/" + secret + "/manifest.json")
	assert.Equal(t, http.StatusNotFound, revoked.Code)
	assert.Equal(t, "*", revoked.Header().Get("Access-Control-Allow-Origin"))
}

func metaField(t *testing.T, rec *httptest.ResponseRecorder, field string) []string {
	t.Helper()
	var out []string
	for _, m := range decode[map[string]any](t, rec)["metas"].([]any) {
		out = append(out, m.(map[string]any)[field].(string))
	}
	return out
}

func TestStremioCatalogsContinueWishlistSkipMetaAndEmptyOnceRevoked(t *testing.T) {
	env := newLibEnv(t)
	secret, id := env.connectStremio(false)
	tmdb, imdb := env.stubIMDbShow("Breaking Point")
	env.add("show", tmdb, "in_progress")
	plain := env.add("show", env.stubShow("No IMDb", catalog.StatusEnded, 2, 3, false), "in_progress")
	plainTitle := env.itemTitle(plain)
	env.add("movie", env.stubMovie("Wishlisted"))

	continuing := metaField(t, env.stremioGet("/stremio/"+secret+"/catalog/series/aaru-continue.json"), "id")
	assert.Contains(t, continuing, imdb)
	assert.Contains(t, continuing, "aaru:"+plainTitle)

	assert.Equal(t, []string{"Wishlisted"}, metaField(t, env.stremioGet("/stremio/"+secret+"/catalog/movie/aaru-wishlist.json"), "name"))
	assert.Empty(t, metaField(t, env.stremioGet("/stremio/"+secret+"/catalog/movie/aaru-wishlist/skip=100.json"), "name"))

	meta := env.stremioGet("/stremio/" + secret + "/meta/series/aaru%3A" + plainTitle + ".json")
	require.Equal(t, http.StatusOK, meta.Code, meta.Body.String())
	videos := decode[map[string]any](t, meta)["meta"].(map[string]any)["videos"].([]any)
	assert.Len(t, videos, 6)
	assert.Equal(t, "aaru:"+plainTitle+":1:1", videos[0].(map[string]any)["id"])

	env.send(http.MethodDelete, "/v1/agent/tokens/"+id, nil)
	revoked := env.stremioGet("/stremio/" + secret + "/catalog/series/aaru-continue.json")
	assert.Equal(t, http.StatusOK, revoked.Code)
	assert.Empty(t, metaField(t, revoked, "id"))
}

func TestStremioPlayerStopTicksTheEpisodeByIMDbAndAaruIDs(t *testing.T) {
	env := newLibEnv(t)
	secret, _ := env.connectStremio(false)
	tmdb, imdb := env.stubIMDbShow("Played Show")
	item := env.add("show", tmdb, "in_progress")
	start := env.stremioGet("/stremio/" + secret + "/player/series/" + imdb + "%3A1%3A2/action=start&currentTime=0&duration=0.json")
	assert.Equal(t, http.StatusOK, start.Code, start.Body.String())
	stop := env.stremioGet("/stremio/" + secret + "/player/series/" + imdb + "%3A1%3A2/action=stop&currentTime=2700000&duration=3000000.json")
	assert.Equal(t, http.StatusOK, stop.Code)
	assert.Equal(t, []string{"1x2"}, env.watchedText(item))

	title := env.itemTitle(item)
	env.stremioGet("/stremio/" + secret + "/player/series/aaru%3A" + title + "%3A1%3A3/action=stop&currentTime=95&duration=100.json")
	assert.Equal(t, []string{"1x2", "1x3"}, env.watchedText(item))
}

func TestStremioLibraryEventsWatchedIsOneActionAndWritesNeedOptIn(t *testing.T) {
	env := newLibEnv(t)
	secret, _ := env.connectStremio(false)
	tmdb, imdb := env.stubIMDbShow("Marked Show")
	item := env.add("show", tmdb, "in_progress")
	before := env.actionCount()
	var parts []string
	for _, ep := range []string{"1%3A1", "1%3A2", "1%3A3"} {
		parts = append(parts, imdb+"%3A"+ep)
	}
	videos := strings.Join(parts, "%2C")
	marked := env.stremioGet("/stremio/" + secret + "/library/series/" + imdb + "/action=watched&videoId=" + videos + ".json")
	assert.Equal(t, http.StatusOK, marked.Code)
	assert.Equal(t, []string{"1x1", "1x2", "1x3"}, env.watchedText(item))
	assert.Equal(t, before+1, env.actionCount())

	env.stremioGet("/stremio/" + secret + "/library/series/" + imdb + "/action=libraryRemove.json")
	env.stremioGet("/stremio/" + secret + "/library/series/" + imdb + "/action=unwatched&videoId=" + videos + ".json")
	_, other := env.stubIMDbShow("Not Added")
	env.stremioGet("/stremio/" + secret + "/library/series/" + other + "/action=libraryAdd.json")
	assert.Equal(t, before+1, env.actionCount(), "remove ignored; unwatched and add need library:write")
	assert.Equal(t, http.StatusOK, env.send(http.MethodGet, "/v1/library/items/"+item, nil).Code, "still in the library")

	writer, _ := env.connectStremio(true)
	env.stremioGet("/stremio/" + writer + "/library/series/" + other + "/action=libraryAdd.json")
	assert.Equal(t, before+2, env.actionCount(), "added to the watchlist with the opt-in")
}

func TestStremioTokenWithoutScrobbleWriteIsRefusedPlayerEvents(t *testing.T) {
	env := newLibEnv(t)
	secret := auth.StremioPrefix + token.Generate()
	_, err := env.pool.Exec(context.Background(),
		`INSERT INTO agent_tokens (id, user_id, name, kind, token_hash, scopes) VALUES ($1, $2, 'Read only', 'stremio', $3, $4)`,
		uuid.New(), env.user, token.Hash(secret), []string{"library:read"})
	require.NoError(t, err)
	got := env.stremioGet("/stremio/" + secret + "/player/movie/tt0133093/action=stop&currentTime=9&duration=10.json")
	assert.Equal(t, http.StatusForbidden, got.Code, got.Body.String())
	assert.Equal(t, "*", got.Header().Get("Access-Control-Allow-Origin"))
}
