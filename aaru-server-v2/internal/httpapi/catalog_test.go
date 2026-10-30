package httpapi

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/provider"
	"context"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Catalog routes against stub provider servers. No network, no real keys.

type catalogStubs struct {
	tmdb, anilist, musicbrainz *httptest.Server
	tmdbDown                   atomic.Bool
}

// catalogHarness serves TMDB from canned JSON, AniList as down, and MusicBrainz
// with one album and its tracklist.
func catalogHarness(t *testing.T) (*harness, *catalogStubs) {
	t.Helper()
	stubs := &catalogStubs{}
	stubs.tmdb = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if stubs.tmdbDown.Load() {
			w.WriteHeader(http.StatusServiceUnavailable)
			return
		}
		switch r.URL.Path {
		case "/search/movie":
			_, _ = w.Write([]byte(`{"results":[{"id":603,"title":"The Matrix","release_date":"1999-03-30","poster_path":"/p.jpg"}]}`))
		case "/search/multi":
			_, _ = w.Write([]byte(`{"results":[{"id":95396,"media_type":"tv","name":"Severance","first_air_date":"2022-02-17"}]}`))
		case "/search/tv":
			_, _ = w.Write([]byte(`{"results":[{"id":95396,"name":"Severance","first_air_date":"2022-02-17"}]}`))
		case "/movie/603":
			_, _ = w.Write([]byte(`{"id":603,"title":"The Matrix","release_date":"1999-03-30","runtime":136,"poster_path":"/p.jpg",
			 "genres":[{"id":28,"name":"Action"}],"external_ids":{"imdb_id":"tt0133093"}}`))
		case "/movie/603/external_ids":
			_, _ = w.Write([]byte(`{"imdb_id":"tt0133093"}`))
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	stubs.anilist = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	stubs.musicbrainz = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/release-group/mb-1":
			_, _ = w.Write([]byte(`{"id":"mb-1","title":"OK Computer","primary-type":"Album","first-release-date":"1997-05-21",
			 "artist-credit":[{"name":"Radiohead"}],"genres":[{"name":"art rock","count":3}]}`))
		case "/release":
			_, _ = w.Write([]byte(`{"releases":[{"date":"1997-05-21","media":[{"position":1,"tracks":[
			 {"position":1,"title":"Airbag","length":284000}]}]}]}`))
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	t.Cleanup(func() { stubs.tmdb.Close(); stubs.anilist.Close(); stubs.musicbrainz.Close() })
	client := func(name string) *provider.Client {
		c := provider.NewClient(name, provider.NewHTTPTransport(), provider.NewPacer(1000, 100))
		c.MaxAttempts = 1
		if name == "anilist" {
			c.Classify = catalog.ClassifyAniList
		}
		return c
	}
	music := &catalog.MusicBrainz{Client: client("musicbrainz"), BaseURL: stubs.musicbrainz.URL}
	providers := catalog.Providers{
		TMDB:        &catalog.TMDB{Client: client("tmdb"), APIKey: "test", BaseURL: stubs.tmdb.URL},
		AniList:     &catalog.AniList{Client: client("anilist"), Endpoint: stubs.anilist.URL},
		OpenLibrary: &catalog.OpenLibrary{Client: client("openlibrary"), BaseURL: stubs.tmdb.URL},
		Music:       music,
		Recordings:  music,
	}
	h := newHarness(t, func(d *Deps) { d.Catalog = catalog.NewKit(d.Pool, providers, d.Log) })
	h.server.Catalog.Service.AniListDeadline = time.Second
	return h, stubs
}

func TestSearchRoute(t *testing.T) {
	h, stubs := catalogHarness(t)
	_, bearer := h.signIn()
	rec := h.do(http.MethodGet, "/v1/search?q=matrix&type=movie", bearer, nil)
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	body := rec.Body.String()
	assert.Contains(t, body, `"tmdb":"603"`)
	assert.Contains(t, body, `"posterUrl":"https://image.tmdb.org/t/p/w500/p.jpg"`)
	assert.NotContains(t, body, "poster_path")
	assert.NotContains(t, body, "release_date")
	assert.NotContains(t, body, `"status"`, "no library fields on a hit")
	assert.NotContains(t, body, `"rating"`, "no library fields on a hit")

	assert.Equal(t, http.StatusBadRequest, h.do(http.MethodGet, "/v1/search?q=matrix", bearer, nil).Code, "type is required")
	short := h.do(http.MethodGet, "/v1/search?q=%20&type=movie", bearer, nil)
	assert.Equal(t, http.StatusUnprocessableEntity, short.Code)
	assert.Contains(t, short.Body.String(), "validation_failed")

	all := decode[map[string]any](t, h.do(http.MethodGet, "/v1/search?q=severance&type=all", bearer, nil))
	assert.Equal(t, true, all["incomplete"], "AniList is down")
	assert.Equal(t, "show", all["items"].([]any)[0].(map[string]any)["type"])
	assert.Equal(t, catalog.NoticeAniListDown, all["notice"])
	show := decode[map[string]any](t, h.do(http.MethodGet, "/v1/search?q=severance&type=show", bearer, nil))
	assert.Equal(t, false, show["incomplete"], "one kind asks TMDB alone: complete")

	stubs.tmdbDown.Store(true)
	down := h.do(http.MethodGet, "/v1/search?q=matrix&type=movie", bearer, nil)
	assert.Equal(t, http.StatusBadGateway, down.Code)
	assert.Contains(t, down.Body.String(), "provider_unavailable")
}

func TestResolveAndGetTitleRoutes(t *testing.T) {
	h, _ := catalogHarness(t)
	userID, bearer := h.signIn()
	rec := h.do(http.MethodPost, "/v1/titles/resolve", bearer, map[string]any{"type": "movie", "ids": map[string]string{"tmdb": "603"}})
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	preview := decode[map[string]any](t, rec)
	title := preview["title"].(map[string]any)
	assert.Equal(t, "The Matrix", title["title"])
	assert.Nil(t, preview["libraryItemId"], "resolving is not adding")
	assert.Nil(t, title["genres"], "genres are for albums only")
	id := title["id"].(string)
	assert.Equal(t, strings.ToUpper(id), id, "ids are upper-case on the wire")
	var items int
	require.NoError(t, h.pool.QueryRow(context.Background(), `SELECT count(*) FROM library_items`).Scan(&items))
	assert.Zero(t, items)

	itemID := uuid.New()
	_, err := h.pool.Exec(context.Background(), `INSERT INTO library_items (id, user_id, title_id, status, added_at, updated_at)
		VALUES ($1, $2, $3, 'wishlist', now(), now())`, itemID, userID, uuid.MustParse(id))
	require.NoError(t, err)
	again := decode[map[string]any](t, h.do(http.MethodPost, "/v1/titles/resolve", bearer, map[string]any{"type": "movie", "ids": map[string]string{"tmdb": "603"}}))
	assert.Equal(t, strings.ToUpper(itemID.String()), again["libraryItemId"])

	unknown := h.do(http.MethodPost, "/v1/titles/resolve", bearer, map[string]any{"type": "movie", "ids": map[string]string{"tmdb": "999999999"}})
	assert.Equal(t, http.StatusUnprocessableEntity, unknown.Code)
	assert.Contains(t, unknown.Body.String(), "unresolvable")

	got := h.do(http.MethodGet, "/v1/titles/"+id, bearer, nil)
	require.Equal(t, http.StatusOK, got.Code, got.Body.String())
	assert.Equal(t, http.StatusNotFound, h.do(http.MethodGet, "/v1/titles/not-a-uuid", bearer, nil).Code)
	assert.Equal(t, http.StatusNotFound, h.do(http.MethodGet, "/v1/titles/"+uuid.NewString(), bearer, nil).Code)
}

func TestAlbumDetailRoute(t *testing.T) {
	h, _ := catalogHarness(t)
	_, bearer := h.signIn()
	resolved := decode[map[string]any](t, h.do(http.MethodPost, "/v1/titles/resolve", bearer,
		map[string]any{"type": "album", "ids": map[string]string{"musicbrainz": "mb-1"}}))
	title := resolved["title"].(map[string]any)
	assert.Equal(t, "Radiohead", title["byline"])
	assert.Equal(t, []any{"art rock"}, title["genres"])
	tracks := title["tracks"].([]any)
	require.Len(t, tracks, 1)
	assert.Equal(t, "Airbag", tracks[0].(map[string]any)["name"])
	assert.InDelta(t, 284000, tracks[0].(map[string]any)["lengthMs"], 0)
	assert.Nil(t, title["seasons"])
}

func TestDiscoverRoutes(t *testing.T) {
	h, _ := catalogHarness(t)
	_, bearer := h.signIn()
	assert.Equal(t, http.StatusUnauthorized, h.do(http.MethodGet, "/v1/discover", "nope", nil).Code)
	rows := h.do(http.MethodGet, "/v1/discover", bearer, nil)
	require.Equal(t, http.StatusOK, rows.Code, rows.Body.String())
	assert.Contains(t, rows.Body.String(), `"rows":[`)

	year := catalog.CurrentSeason(time.Now()).Year
	season := decode[map[string]any](t, h.do(http.MethodGet, "/v1/discover/season?kind=anime&season=fall&year="+itoa(year), bearer, nil))
	assert.Equal(t, "Fall "+itoa(year), season["title"])
	assert.Equal(t, itoa(year)+"-10-01", season["from"])
	assert.Equal(t, itoa(year)+"-12-31", season["until"])
	assert.Equal(t, true, season["unavailable"], "AniList is down and nothing is cached")
	for _, q := range []string{"year=1969", "year=" + itoa(year+2), "year=" + itoa(year) + "&page=0", "year=" + itoa(year) + "&page=21"} {
		rec := h.do(http.MethodGet, "/v1/discover/season?kind=anime&season=fall&"+q, bearer, nil)
		assert.Equal(t, http.StatusUnprocessableEntity, rec.Code, q)
		assert.Contains(t, rec.Body.String(), "validation_failed", q)
	}
	assert.Equal(t, http.StatusOK, h.do(http.MethodGet, "/v1/discover/season?kind=anime&season=winter&year="+itoa(year+1), bearer, nil).Code)
	assert.Equal(t, http.StatusUnauthorized, h.do(http.MethodGet, "/v1/discover/season?kind=anime&season=fall&year="+itoa(year), "nope", nil).Code)

	onAir := h.do(http.MethodGet, "/v1/discover/on-air?region=us", bearer, nil)
	require.Equal(t, http.StatusOK, onAir.Code, onAir.Body.String())
	assert.Contains(t, onAir.Body.String(), `"channels":[]`)
	bad := h.do(http.MethodGet, "/v1/discover/on-air?region=usa", bearer, nil)
	assert.Equal(t, http.StatusUnprocessableEntity, bad.Code)
	assert.Contains(t, bad.Body.String(), "Two letters, as ISO 3166-1.")
}

func TestTitleDetailDTO(t *testing.T) {
	airs := time.Date(2026, 10, 20, 1, 0, 0, 0, time.UTC)
	status := catalog.StatusReturning
	dto := TitleDetailDTO(catalog.TitleDetail{
		Status: &status,
		Episodes: []catalog.Episode{
			{Season: 2, Episode: 1, AirsAt: &airs, AirTimeKnown: true},
			{Season: 1, Episode: 1},
			{Season: 1, Episode: 2},
		},
	})
	require.NotNil(t, dto.Seasons)
	seasons := *dto.Seasons
	require.Len(t, seasons, 2)
	assert.Equal(t, 1, seasons[0].Number)
	assert.Len(t, seasons[0].Episodes, 2)
	assert.Equal(t, 2, seasons[1].Number)
	assert.True(t, seasons[1].Episodes[0].AirTimeKnown)
	assert.Equal(t, "returning", string(*dto.Status))
	assert.Nil(t, dto.Genres)
	assert.Nil(t, dto.Tracks)
}

func itoa(n int) string { return strconv.Itoa(n) }
