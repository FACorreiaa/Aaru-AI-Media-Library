package stremio

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"context"
	"errors"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

// StremioEpisodeMapTests.swift, the map side: Stremio's episode numbers put on the TMDB show by release
// day (live test, 2026-10-22: Bleach: Thousand-Year Blood War is its own IMDb series, seasons 1 to 4;
// TMDB keeps it as Bleach S2).

var start = time.Unix(1_704_067_200, 0).UTC() // 2024-01-01, midnight UTC

// week is `count` weeks after start, at `hours` past midnight.
func week(count int, hours float64) *time.Time {
	t := start.Add(time.Duration(count)*7*24*time.Hour + time.Duration(hours*float64(time.Hour)))
	return &t
}

func video(season, episode int, released *time.Time) Video {
	return Video{ID: "tt1", Season: season, Episode: episode, Released: released}
}

func aired(season, episode int, airsAt *time.Time) catalog.Episode {
	runtime := 24
	return catalog.Episode{Season: season, Episode: episode, AirsAt: airsAt, RuntimeMinutes: &runtime}
}

func k(season, episode int) *core.EpisodeKey { return &core.EpisodeKey{Season: season, Episode: episode} }

func TestMatchIsTheTMDBEpisodeOutTheSameDayAFewHoursEitherWay(t *testing.T) {
	listed := []Video{video(1, 1, week(10, 0)), video(2, 1, week(11, 0))}
	episodes := []catalog.Episode{aired(1, 1, week(0, 0)), aired(2, 1, week(10, 15)), aired(2, 2, week(11, -9))}
	assert.Equal(t, k(2, 2), Match(*k(2, 1), listed, episodes))
	assert.Equal(t, k(2, 1), Match(*k(1, 1), listed, episodes))
}

func TestMatchPairsTwoEpisodesOneDayInOrderOnlyWhenBothListsHaveTwo(t *testing.T) {
	listed := []Video{video(1, 1, week(3, 0)), video(1, 2, week(3, 0))}
	both := []catalog.Episode{aired(4, 7, week(3, 0)), aired(4, 8, week(3, 0))}
	assert.Equal(t, k(4, 8), Match(*k(1, 2), listed, both))
	assert.Nil(t, Match(*k(1, 2), listed, both[:1]))
}

func TestMatchPlacesNothingWithoutAReleaseDayOrAnEpisodeThatDay(t *testing.T) {
	listed := []Video{video(1, 1, nil), video(1, 2, week(5, 0))}
	episodes := []catalog.Episode{aired(2, 1, week(1, 0)), aired(0, 1, week(5, 0))}
	assert.Nil(t, Match(*k(1, 1), listed, episodes))
	assert.Nil(t, Match(*k(1, 2), listed, episodes))
	assert.Nil(t, Match(*k(3, 1), listed, episodes))
}

func TestPlaceTrustsTheShowsOwnNumbersAndFallsBackOnlyForTheSameSeries(t *testing.T) {
	show := core.Title{IDs: core.ExternalIDs{IMDB: "tt1"}}
	episodes := []catalog.Episode{aired(1, 1, week(0, 0))}
	assert.Equal(t, k(1, 1), Place(*k(1, 1), "tt1", show, episodes, nil))
	assert.Equal(t, k(1, 5), Place(*k(1, 5), "tt1", show, episodes, nil), "same series: kept as it came")
	assert.Nil(t, Place(*k(1, 1), "tt2", show, episodes, nil), "another series with Cinemeta down")
}

type countingSource struct {
	calls int
	fail  bool
}

func (c *countingSource) Series(context.Context, string) (Series, error) {
	c.calls++
	if c.fail {
		return Series{}, errors.New("down")
	}
	tvdb := "42"
	return Series{TVDB: &tvdb}, nil
}

func TestSeriesAreCachedAndFailuresAreNot(t *testing.T) {
	source := &countingSource{}
	m := NewEpisodeMap(source)
	assert.Equal(t, "42", *m.TVDB(context.Background(), "tt1"))
	assert.Equal(t, "42", *m.TVDB(context.Background(), "tt1"))
	assert.Equal(t, 1, source.calls)

	failing := &countingSource{fail: true}
	m = NewEpisodeMap(failing)
	assert.Nil(t, m.TVDB(context.Background(), "tt1"))
	assert.Nil(t, m.TVDB(context.Background(), "tt1"))
	assert.Equal(t, 2, failing.calls)
}
