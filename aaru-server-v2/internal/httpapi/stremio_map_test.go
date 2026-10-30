package httpapi

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/stremio"
	"context"
	"errors"
	"fmt"
	"math/rand/v2"
	"net/http"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

// StremioEpisodeMapTests.swift, through the addon: Stremio's numbers for another IMDb series put on the
// TMDB show by release day, with a fake Cinemeta (no network).

var mapStart = time.Unix(1_704_067_200, 0).UTC() // 2024-01-01, midnight UTC

func mapWeek(count int) *time.Time {
	t := mapStart.Add(time.Duration(count) * 7 * 24 * time.Hour)
	return &t
}

func randomIMDb() string { return fmt.Sprintf("tt%d", 10_000_000+rand.IntN(89_999_999)) } //nolint:gosec // a test id

// fakeCinemeta knows one IMDb series, `part`, seasons 1 and 2 of two episodes released weekly.
type fakeCinemeta struct {
	part string
	tvdb *string
	down bool
}

func (f fakeCinemeta) Series(_ context.Context, imdb string) (stremio.Series, error) {
	if f.down {
		return stremio.Series{}, errors.New("cinemeta: 500")
	}
	if imdb != f.part {
		return stremio.Series{}, nil
	}
	var videos []stremio.Video
	for i, pair := range [][2]int{{1, 1}, {1, 2}, {2, 1}, {2, 2}} {
		videos = append(videos, stremio.Video{
			ID: fmt.Sprintf("%s:%d:%d", f.part, pair[0], pair[1]), Season: pair[0], Episode: pair[1], Released: mapWeek(i + 1),
		})
	}
	return stremio.Series{TVDB: f.tvdb, Videos: videos}, nil
}

func newMapEnv(t *testing.T, source stremio.SeriesSource) *libEnv {
	t.Helper()
	fake := &libraryFake{episodes: map[string]catalog.Episodes{}}
	providers := catalog.Providers{TMDB: fake, AniList: fake, OpenLibrary: fake, Music: fake}
	h := newHarness(t, func(d *Deps) {
		d.Catalog = catalog.NewKit(d.Pool, providers, d.Log)
		d.StremioSeries = source
	})
	user, bearer := h.signIn()
	return &libEnv{harness: h, fake: fake, user: user, bearer: bearer}
}

func mapAired(season, episode int, airsAt *time.Time) catalog.Episode {
	runtime := 24
	return catalog.Episode{Season: season, Episode: episode, AirsAt: airsAt, RuntimeMinutes: &runtime}
}

func (e *libEnv) stubAnimeShow(name string, ids core.ExternalIDs) {
	year := 2004
	returning := catalog.StatusReturning
	runtime := 24
	e.fake.stubTitle(catalog.Record{
		Hit: catalog.Hit{Type: core.MediaShow, Title: name, Year: &year, IDs: ids, IsAnime: true}, Status: &returning, RuntimeMinutes: &runtime,
	})
}

// splitShow is a show (its own IMDb id) whose season 2 is IMDb series `part` in Cinemeta. Returns its tmdb id.
func (e *libEnv) splitShow(part string) string {
	tmdb := e.fake.uniqueID("tmdb")
	e.stubAnimeShow("Split Show", core.ExternalIDs{TMDB: tmdb, IMDB: randomIMDb()})
	// What TMDB answers for the part's IMDb id: the same show.
	e.stubAnimeShow("Split Show", core.ExternalIDs{TMDB: tmdb, IMDB: part})
	var episodes []catalog.Episode
	for n := 1; n <= 3; n++ {
		episodes = append(episodes, mapAired(1, n, mapWeek(n-10)))
	}
	for n := 1; n <= 4; n++ {
		episodes = append(episodes, mapAired(2, n, mapWeek(n)))
	}
	returning := catalog.StatusReturning
	e.fake.mu.Lock()
	e.fake.episodes[tmdb] = catalog.Episodes{Status: &returning, Episodes: episodes}
	e.fake.mu.Unlock()
	return tmdb
}

func TestStremioMapTicksTheTMDBEpisodesStremiosNumbersName(t *testing.T) {
	part := randomIMDb()
	env := newMapEnv(t, fakeCinemeta{part: part})
	secret, _ := env.connectStremio(false)
	item := env.add("show", env.splitShow(part), "in_progress")

	stop := env.stremioGet("/stremio/" + secret + "/player/series/" + part + "%3A2%3A1/action=stop&currentTime=1400000&duration=1440000.json")
	assert.Equal(t, http.StatusOK, stop.Code, stop.Body.String())
	assert.Equal(t, []string{"2x3"}, env.watchedText(item))

	videos := part + "%3A1%3A1," + part + "%3A1%3A2"
	env.stremioGet("/stremio/" + secret + "/library/series/" + part + "/action=watched&videoId=" + videos + ".json")
	assert.Equal(t, []string{"2x1", "2x2", "2x3"}, env.watchedText(item))
}

func TestStremioMapWithCinemetaDownTicksNothingRatherThanTheWrongEpisode(t *testing.T) {
	part := randomIMDb()
	env := newMapEnv(t, fakeCinemeta{part: part, down: true})
	secret, _ := env.connectStremio(false)
	item := env.add("show", env.splitShow(part), "in_progress")
	env.stremioGet("/stremio/" + secret + "/player/series/" + part + "%3A1%3A1/action=stop&currentTime=1400000&duration=1440000.json")
	assert.Empty(t, env.watchedText(item))
}

func TestStremioMapFindsANearEmptyDuplicateSeriesByItsTVDBID(t *testing.T) {
	part := randomIMDb()
	tvdb := fmt.Sprint(100_000 + rand.IntN(899_999)) //nolint:gosec // a test id
	env := newMapEnv(t, fakeCinemeta{part: part, tvdb: &tvdb})
	secret, _ := env.connectStremio(false)
	// The show, with TVDB's id, and TMDB's own entry for the part's IMDb id, as Bleach's `30984` and
	// `336301` (one episode).
	tmdb := env.fake.uniqueID("tmdb")
	duplicate := env.fake.uniqueID("tmdb")
	env.stubAnimeShow("Split Show", core.ExternalIDs{TMDB: tmdb, IMDB: randomIMDb(), TVDB: tvdb})
	env.stubAnimeShow("Split Show: Part", core.ExternalIDs{TMDB: duplicate, IMDB: part})
	var episodes []catalog.Episode
	for n := 1; n <= 4; n++ {
		episodes = append(episodes, mapAired(2, n, mapWeek(n)))
	}
	returning := catalog.StatusReturning
	env.fake.mu.Lock()
	env.fake.episodes[tmdb] = catalog.Episodes{Status: &returning, Episodes: episodes}
	env.fake.episodes[duplicate] = catalog.Episodes{Status: &returning, Episodes: []catalog.Episode{mapAired(1, 13, mapWeek(-40))}}
	env.fake.mu.Unlock()
	item := env.add("show", tmdb, "in_progress")

	stop := env.stremioGet("/stremio/" + secret + "/player/series/" + part + "%3A2%3A2/action=stop&currentTime=1400000&duration=1440000.json")
	assert.Equal(t, http.StatusOK, stop.Code)
	assert.Equal(t, []string{"2x4"}, env.watchedText(item))
	assert.Nil(t, env.titleID(duplicate, core.MediaShow), "TMDB's own entry for the part never becomes a title")
}
