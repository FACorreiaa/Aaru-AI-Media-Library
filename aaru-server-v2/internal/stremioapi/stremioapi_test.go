package stremioapi

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/provider"
	"context"
	"fmt"
	"math/rand/v2"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func key(season, episode int) core.EpisodeKey { return core.EpisodeKey{Season: season, Episode: episode} }

// StremioImportTests.bitfield
func TestWatchedBitfieldMarksTheRightEpisodesAndLeavesSpecialsOut(t *testing.T) {
	var videos []Video
	for _, p := range [][2]int{{0, 1}, {1, 1}, {1, 2}, {1, 3}, {2, 1}, {2, 2}, {2, 3}} {
		videos = append(videos, Video{ID: fmt.Sprintf("tt1:%d:%d", p[0], p[1]), Season: p[0], Episode: p[1]})
	}
	rand.Shuffle(len(videos), func(i, j int) { videos[i], videos[j] = videos[j], videos[i] })
	// Bits 1, 2 and 4 (0b10110) over S0E1, S1E1, S1E2, S1E3, S2E1…: S1E1, S1E2, S2E1.
	assert.Equal(t, []core.EpisodeKey{key(1, 1), key(1, 2), key(2, 1)}, Episodes("tt1:2:3:7:eJwTAwAAFwAX", videos))
	// Written when the list was S1E1–S1E3 (bits 0 and 2), read after a special and S2 appeared.
	assert.Equal(t, []core.EpisodeKey{key(1, 1), key(1, 3)}, Episodes("tt1:1:3:3:eJxjBQAABgAG", videos))
	// An anchor no longer in the list: nothing, as in Stremio.
	assert.Empty(t, Episodes("tt1:9:9:3:eJxjBQAABgAG", videos))
	assert.Empty(t, Episodes("garbage", videos))
}

func TestInflateRefusesPastTheLimit(t *testing.T) {
	_, err := Inflate([]byte("not zlib"), 10)
	require.ErrorIs(t, err, ErrInflate)
}

// MARK: StremioEpisodeMapTests (the static rule; the addon's cached wrapper is tested with the addon)

var start = time.Unix(1_704_067_200, 0).UTC() // 2024-01-01, midnight UTC

func week(count int, hours float64) *time.Time {
	t := start.Add(time.Duration(count)*7*24*time.Hour + time.Duration(hours*float64(time.Hour)))
	return &t
}

func video(season, episode int, released *time.Time) Video {
	return Video{ID: fmt.Sprintf("tt1:%d:%d", season, episode), Season: season, Episode: episode, Released: released}
}

func aired(season, episode int, airsAt *time.Time) catalog.Episode {
	runtime := 24
	return catalog.Episode{Season: season, Episode: episode, AirsAt: airsAt, RuntimeMinutes: &runtime}
}

func TestAnEpisodeMatchesTheTMDBEpisodeOutTheSameDay(t *testing.T) {
	listed := []Video{video(1, 1, week(10, 0)), video(2, 1, week(11, 0))}
	episodes := []catalog.Episode{aired(1, 1, week(0, 0)), aired(2, 1, week(10, 15)), aired(2, 2, week(11, -9))}
	assert.Equal(t, new(key(2, 2)), Match(key(2, 1), listed, episodes))
	assert.Equal(t, new(key(2, 1)), Match(key(1, 1), listed, episodes))
}

func TestTwoEpisodesOutOneDayPairUpInOrder(t *testing.T) {
	listed := []Video{video(1, 1, week(3, 0)), video(1, 2, week(3, 0))}
	both := []catalog.Episode{aired(4, 7, week(3, 0)), aired(4, 8, week(3, 0))}
	assert.Equal(t, new(key(4, 8)), Match(key(1, 2), listed, both))
	assert.Nil(t, Match(key(1, 2), listed, both[:1]))
}

func TestNoReleaseDayOrNoEpisodeThatDayPlacesNothing(t *testing.T) {
	listed := []Video{video(1, 1, nil), video(1, 2, week(5, 0))}
	episodes := []catalog.Episode{aired(2, 1, week(1, 0)), aired(0, 1, week(5, 0))}
	assert.Nil(t, Match(key(1, 1), listed, episodes))
	assert.Nil(t, Match(key(1, 2), listed, episodes))
	assert.Nil(t, Match(key(3, 1), listed, episodes))
}

func TestPlaceTrustsTheShowsOwnNumbersAndFallsBackWithoutCinemeta(t *testing.T) {
	own := core.Title{IDs: core.ExternalIDs{IMDB: "tt1"}}
	other := core.Title{IDs: core.ExternalIDs{IMDB: "tt2"}}
	episodes := []catalog.Episode{aired(1, 1, week(0, 0))}
	assert.Equal(t, new(key(1, 1)), Place(key(1, 1), "tt1", own, episodes, nil))
	assert.Equal(t, new(key(3, 1)), Place(key(3, 1), "tt1", own, episodes, nil), "the same series keeps its number")
	assert.Nil(t, Place(key(3, 1), "tt1", other, episodes, nil), "another series' number ticks nothing")
}

// MARK: Account

func TestSeriesReadsVideosAndALenientTVDBID(t *testing.T) {
	var asked []string
	transport := provider.TransportFunc(func(_ context.Context, req provider.Request) (*provider.Response, error) {
		asked = append(asked, req.URL)
		if req.URL == DefaultCinemetaBase+"/meta/series/tt404.json" {
			return &provider.Response{Status: 404}, nil
		}
		return &provider.Response{Status: 200, Body: []byte(`{"meta":{"tvdb_id":"0081189","videos":[` +
			`{"id":"tt9:1:1","season":1,"episode":1,"released":"2020-01-01T00:00:00.000Z"},` +
			`{"id":"tt9:1:2","season":1,"number":2},{"id":"tt9:x","season":1}]}}`)}, nil
	})
	account := NewAccount(transport)
	series, err := account.Series(context.Background(), "tt9")
	require.NoError(t, err)
	assert.Equal(t, "81189", series.TVDB)
	require.Len(t, series.Videos, 2)
	assert.Equal(t, 2, series.Videos[1].Episode, "older entries number episodes in `number`")
	assert.Equal(t, time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC), *series.Videos[0].Released)

	unknown, err := account.Series(context.Background(), "tt404")
	require.NoError(t, err)
	assert.Empty(t, unknown.Videos)
	none, err := account.Series(context.Background(), "kitsu:1")
	require.NoError(t, err)
	assert.NotNil(t, none.Videos)
	assert.Len(t, asked, 2, "an id that is not IMDb's is not asked about")
}
