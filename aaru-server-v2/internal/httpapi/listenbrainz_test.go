package httpapi

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// ListenBrainzRouteTests.swift (MUS-005): ListenBrainz's submit API with a music token, and the
// listening log it fills.

func (e *libEnv) connectMusic(kind string) (id, secret string) {
	return e.connect(kind, map[string]any{"name": "Web Scrobbler"})
}

// submit sends a body as a ListenBrainz client does: `Authorization: Token …`.
func (e *libEnv) submit(body any, token, scheme string) *httptest.ResponseRecorder {
	e.t.Helper()
	data, err := json.Marshal(body)
	require.NoError(e.t, err)
	req := httptest.NewRequest(http.MethodPost, "/listenbrainz/1/submit-listens", bytes.NewReader(data))
	req.Header.Set("Authorization", scheme+" "+token)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	e.echo.ServeHTTP(rec, req)
	return rec
}

func (e *libEnv) validateToken(token *string) *httptest.ResponseRecorder {
	e.t.Helper()
	req := httptest.NewRequest(http.MethodGet, "/listenbrainz/1/validate-token", nil)
	if token != nil {
		req.Header.Set("Authorization", "Token "+*token)
	}
	rec := httptest.NewRecorder()
	e.echo.ServeHTTP(rec, req)
	return rec
}

// lbBase is a day ago, so every offset stays in the past.
var lbBase = time.Now().Unix() - 86400

func lbListen(artist, track string, offset int, album *string, durationMs *int) map[string]any {
	metadata := map[string]any{"artist_name": artist, "track_name": track}
	if album != nil {
		metadata["release_name"] = *album
	}
	info := map[string]any{"submission_client": "Web Scrobbler", "music_service_name": "YouTube Music"}
	if durationMs != nil {
		info["duration_ms"] = *durationMs
	}
	metadata["additional_info"] = info
	return map[string]any{"listened_at": lbBase + int64(offset), "track_metadata": metadata}
}

func single(listen map[string]any) map[string]any {
	return map[string]any{"listen_type": "single", "payload": []any{listen}}
}

func importOf(listens []map[string]any) map[string]any {
	return map[string]any{"listen_type": "import", "payload": listens}
}

func (e *libEnv) listenLog() []map[string]any {
	e.t.Helper()
	items := e.json(http.MethodGet, "/v1/me/listens?limit=100", nil)["items"].([]any)
	out := make([]map[string]any, len(items))
	for i, it := range items {
		out[i] = it.(map[string]any)
	}
	return out
}

func tracksOf(items []map[string]any) []string {
	out := []string{}
	for _, it := range items {
		out = append(out, it["track"].(string))
	}
	return out
}

func TestListenBrainzMusicTokenSendsAListenThatShowsInTheLogAndExport(t *testing.T) {
	env := newLibEnv(t)
	_, token := env.connectMusic("music")
	assert.True(t, strings.HasPrefix(token, "aaru_lb_"))
	before := env.actionCount()

	reply := env.submit(single(lbListen("Radiohead", "Paranoid Android", 0, ptr("OK Computer"), ptr(383_000))), token, "Token")
	require.Equal(t, http.StatusOK, reply.Code, reply.Body.String())
	assert.Equal(t, "ok", decode[map[string]any](t, reply)["status"])

	items := env.listenLog()
	require.Len(t, items, 1)
	first := items[0]
	assert.Equal(t, "Radiohead", first["artist"])
	assert.Equal(t, "Paranoid Android", first["track"])
	assert.Equal(t, "OK Computer", first["album"])
	assert.InDelta(t, 383_000, first["durationMs"], 0)
	assert.Equal(t, "Web Scrobbler", first["client"])
	assert.Equal(t, "YouTube Music", first["musicService"])
	assert.Equal(t, before, env.actionCount(), "a listen never writes the library")

	export := env.json(http.MethodGet, "/v1/me/export?format=json", nil)
	assert.Len(t, export["listens"], 1)
}

func TestListenBrainzOnlyALiveMusicTokenGetsIn(t *testing.T) {
	env := newLibEnv(t)
	body := single(lbListen("Björk", "Hyperballad", 0, nil, nil))
	assert.Equal(t, http.StatusUnauthorized, env.submit(body, env.bearer, "Bearer").Code)
	_, browser := env.connectMusic("browser")
	assert.Equal(t, http.StatusUnauthorized, env.submit(body, browser, "Token").Code)
	musicID, music := env.connectMusic("music")
	assert.Equal(t, http.StatusOK, env.submit(body, music, "Bearer").Code)
	scrobble := env.do(http.MethodPost, "/v1/scrobble/start", music, map[string]any{})
	assert.Equal(t, http.StatusUnauthorized, scrobble.Code, "a music token never scrobbles video")

	assert.Equal(t, http.StatusNoContent, env.send(http.MethodDelete, "/v1/agent/tokens/"+musicID, nil).Code)
	revoked := env.submit(body, music, "Token")
	assert.Equal(t, http.StatusUnauthorized, revoked.Code)
	assert.InDelta(t, 401, decode[map[string]any](t, revoked)["code"], 0)
	assert.Len(t, env.listenLog(), 1)
}

func TestListenBrainzTheSamePlayTwiceOrRespelledIsKeptOnce(t *testing.T) {
	env := newLibEnv(t)
	_, token := env.connectMusic("music")
	play := lbListen("Radiohead", "Airbag", 0, nil, ptr(284_000))
	env.submit(single(play), token, "Token")
	env.submit(single(play), token, "Token")
	// A second scrobbler on the same play: other spelling, a minute later.
	env.submit(single(lbListen("RADIOHEAD ", "airbag", 60, nil, ptr(284_000))), token, "Token")
	// Played again five minutes on.
	env.submit(single(lbListen("Radiohead", "Airbag", 300, nil, ptr(284_000))), token, "Token")
	// A short track repeated back to back: its window is half its length.
	env.submit(single(lbListen("Ramones", "Judy Is a Punk", 0, nil, ptr(90000))), token, "Token")
	env.submit(single(lbListen("Ramones", "Judy Is a Punk", 90, nil, ptr(90000))), token, "Token")
	count := map[string]int{}
	for _, track := range tracksOf(env.listenLog()) {
		count[track]++
	}
	assert.Equal(t, 2, count["Airbag"])
	assert.Equal(t, 2, count["Judy Is a Punk"])
}

func TestListenBrainzPlayingNowStoresNothingAndImportTakesUpTo1000(t *testing.T) {
	env := newLibEnv(t)
	_, token := env.connectMusic("music")
	now := map[string]any{
		"listen_type": "playing_now",
		"payload":     []any{map[string]any{"track_metadata": map[string]any{"artist_name": "Air", "track_name": "La femme d'argent"}}},
	}
	assert.Equal(t, http.StatusOK, env.submit(now, token, "Token").Code)
	assert.Empty(t, env.listenLog())

	var three []map[string]any
	for i := range 3 {
		three = append(three, lbListen("Air", fmt.Sprintf("Track %d", i), i*600, nil, nil))
	}
	assert.Equal(t, http.StatusOK, env.submit(importOf(three), token, "Token").Code)
	assert.Len(t, env.listenLog(), 3)

	var tooMany []map[string]any
	for i := range 1001 {
		tooMany = append(tooMany, lbListen("Air", fmt.Sprintf("Track %d", i), i*600, nil, nil))
	}
	refused := env.submit(importOf(tooMany), token, "Token")
	assert.Equal(t, http.StatusBadRequest, refused.Code)
	assert.InDelta(t, 400, decode[map[string]any](t, refused)["code"], 0)
	assert.Len(t, env.listenLog(), 3)
}

func TestListenBrainzRefusesAListenWithoutArtistTrackOrAPlausibleTime(t *testing.T) {
	env := newLibEnv(t)
	_, token := env.connectMusic("music")
	noTrack := lbListen("Air", "x", 0, nil, nil)
	noTrack["track_metadata"] = map[string]any{"artist_name": "Air"}
	ancient := lbListen("Air", "Sexy Boy", 0, nil, nil)
	ancient["listened_at"] = 631_152_000
	noTime := lbListen("Air", "Kelly Watch the Stars", 0, nil, nil)
	delete(noTime, "listened_at")
	for _, body := range []map[string]any{single(noTrack), single(ancient), single(noTime), {"listen_type": "radio", "payload": []any{}}} {
		reply := env.submit(body, token, "Token")
		assert.Equal(t, http.StatusBadRequest, reply.Code, body)
		assert.IsType(t, "", decode[map[string]any](t, reply)["error"])
	}
	two := map[string]any{"listen_type": "single", "payload": []any{lbListen("Air", "a", 0, nil, nil), lbListen("Air", "b", 0, nil, nil)}}
	assert.Equal(t, http.StatusBadRequest, env.submit(two, token, "Token").Code)
	assert.Empty(t, env.listenLog())
}

func TestListenBrainzValidateTokenSaysWhetherAMusicTokenWorks(t *testing.T) {
	env := newLibEnv(t)
	_, token := env.connectMusic("music")
	valid := env.validateToken(&token)
	assert.Equal(t, http.StatusOK, valid.Code)
	body := decode[map[string]any](t, valid)
	assert.Equal(t, true, body["valid"])
	assert.Equal(t, "Web Scrobbler", body["user_name"])

	nope := "aaru_lb_nope"
	wrong := env.validateToken(&nope)
	assert.Equal(t, http.StatusOK, wrong.Code)
	assert.Equal(t, false, decode[map[string]any](t, wrong)["valid"])
	assert.Equal(t, http.StatusBadRequest, env.validateToken(nil).Code)
}

func TestListensPagesGoBackInTimeWithNext(t *testing.T) {
	env := newLibEnv(t)
	_, token := env.connectMusic("music")
	var five []map[string]any
	for i := range 5 {
		five = append(five, lbListen("Air", fmt.Sprintf("Track %d", i), i*600, nil, nil))
	}
	env.submit(importOf(five), token, "Token")
	first := env.json(http.MethodGet, "/v1/me/listens?limit=3", nil)
	page := make([]map[string]any, 0)
	for _, it := range first["items"].([]any) {
		page = append(page, it.(map[string]any))
	}
	assert.Equal(t, []string{"Track 4", "Track 3", "Track 2"}, tracksOf(page))
	next := first["next"].(string)
	second := env.json(http.MethodGet, "/v1/me/listens?limit=3&before="+url.QueryEscape(next), nil)
	rest := make([]map[string]any, 0)
	for _, it := range second["items"].([]any) {
		rest = append(rest, it.(map[string]any))
	}
	assert.Equal(t, []string{"Track 1", "Track 0"}, tracksOf(rest))
	assert.NotContains(t, second, "next")
}

func TestListensTopCountsAcrossSpellings(t *testing.T) {
	env := newLibEnv(t)
	_, token := env.connectMusic("music")
	ok := ptr("OK Computer")
	plays := []map[string]any{
		lbListen("Radiohead", "Airbag", 0, ok, ptr(120_000)),
		lbListen("radiohead", "Airbag", 600, ok, ptr(120_000)),
		lbListen("Radiohead", "Karma Police", 1200, ok, ptr(120_000)),
		lbListen("Portishead", "Roads", 1800, ptr("Dummy"), ptr(60000)),
		lbListen("Portishead", "Glory Box", 2400, nil, nil),
	}
	env.submit(importOf(plays), token, "Token")

	artists := env.json(http.MethodGet, "/v1/me/listens/top?by=artist&span=all", nil)
	assert.InDelta(t, 5, artists["listens"], 0)
	assert.InDelta(t, 7, artists["minutes"], 0)
	items := artists["items"].([]any)
	var names []any
	for _, it := range items {
		names = append(names, it.(map[string]any)["artist"])
	}
	assert.Equal(t, []any{"Radiohead", "Portishead"}, names)
	assert.InDelta(t, 3, items[0].(map[string]any)["count"], 0)

	tracks := env.json(http.MethodGet, "/v1/me/listens/top?by=track&span=last7", nil)["items"].([]any)
	assert.Equal(t, "Airbag", tracks[0].(map[string]any)["track"])
	assert.InDelta(t, 2, tracks[0].(map[string]any)["count"], 0)

	albums := env.json(http.MethodGet, "/v1/me/listens/top?by=album&span=all", nil)["items"].([]any)
	var albumNames []any
	for _, it := range albums {
		albumNames = append(albumNames, it.(map[string]any)["album"])
	}
	assert.Equal(t, []any{"OK Computer", "Dummy"}, albumNames)
	assert.Equal(t, http.StatusUnprocessableEntity, env.send(http.MethodGet, "/v1/me/listens/top?by=artist", nil).Code)
}

func TestMusicTokenIsNamedForItsScrobblerAndComesWithItsSteps(t *testing.T) {
	env := newLibEnv(t)
	body := env.json(http.MethodPost, "/v1/agent/tokens", map[string]any{"kind": "music", "scrobbler": "web_scrobbler"})
	secret := body["secret"].(string)
	assert.Equal(t, "Web Scrobbler", body["token"].(map[string]any)["name"])
	music := body["music"].(map[string]any)
	assert.Equal(t, "web_scrobbler", music["scrobbler"])
	assert.Equal(t, "https://api.aaruapp.com/listenbrainz/1/submit-listens", music["submitUrl"])
	assert.Equal(t, "https://api.aaruapp.com/listenbrainz/", music["baseUrl"])
	var fields []map[string]any
	for _, step := range music["steps"].([]any) {
		list, _ := step.(map[string]any)["fields"].([]any)
		for _, f := range list {
			fields = append(fields, f.(map[string]any))
		}
	}
	var secretValue, hasSubmit any
	for _, f := range fields {
		if f["secret"] == true && secretValue == nil {
			secretValue = f["value"]
		}
		if f["value"] == music["submitUrl"] {
			hasSubmit = true
		}
	}
	assert.Equal(t, secret, secretValue, "the steps carry the real token")
	assert.Equal(t, true, hasSubmit)

	other := env.json(http.MethodPost, "/v1/agent/tokens", map[string]any{"kind": "music"})
	assert.Equal(t, "Music scrobbler", other["token"].(map[string]any)["name"])
	assert.Equal(t, "other", other["music"].(map[string]any)["scrobbler"])
	named := env.json(http.MethodPost, "/v1/agent/tokens", map[string]any{"kind": "music", "scrobbler": "pano_scrobbler", "name": "Pixel"})
	assert.Equal(t, "Pixel", named["token"].(map[string]any)["name"])
	stremio := env.json(http.MethodPost, "/v1/agent/tokens", map[string]any{"kind": "stremio", "scrobbler": "web_scrobbler"})
	assert.NotContains(t, stremio, "music", "only music tokens get music steps")
}
