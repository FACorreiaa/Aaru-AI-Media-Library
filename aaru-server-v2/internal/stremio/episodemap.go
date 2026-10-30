package stremio

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"aaru-go-api/internal/stremioapi"
	"context"
	"sync"
	"time"
)

// Video is one entry of Cinemeta's episode list, shared with the history import (StremioWatched).
type Video = stremioapi.Video

// Series is Cinemeta's entry for an IMDb series, shared with the history import.
type Series = stremioapi.Series

// SeriesSource is Cinemeta's `meta/series/{imdb}.json`. An empty Series when Cinemeta does not know
// the series; an error when it failed. stremioapi.Account (the Stremio import's) implements it.
type SeriesSource interface {
	Series(ctx context.Context, imdb string) (Series, error)
}

// EpisodeMap puts Stremio's episode numbers on the TMDB show. Stremio names an episode by Cinemeta's
// numbers (`tt…:season:episode`, IMDb's seasons), and TMDB can number the same episodes differently:
// Bleach: Thousand-Year Blood War is its own IMDb series with seasons 1 to 4, while TMDB keeps it as
// season 2 of Bleach. Such an episode is found on the TMDB show by the day Cinemeta says it came out.
type EpisodeMap struct {
	source SeriesSource
	cache  *seriesCache
}

// NewEpisodeMap is a map over Cinemeta's series with a fresh cache.
func NewEpisodeMap(source SeriesSource) *EpisodeMap {
	return &EpisodeMap{source: source, cache: &seriesCache{entries: map[string]cachedSeries{}, now: time.Now}}
}

// TVDB is TVDB's id for IMDb series `imdb`, which names the show Aaru tracks when TMDB lists the series
// as an entry of its own (TMDB `336301` for `tt14986406`, a near-empty duplicate).
func (m *EpisodeMap) TVDB(ctx context.Context, imdb string) *string {
	s := m.cache.series(ctx, imdb, m.source)
	if s == nil || s.TVDB == "" {
		return nil
	}
	return &s.TVDB
}

// Episode is the episode of `title` that Stremio's `key` of IMDb series `imdb` is. `key` itself when the
// numbers can be trusted; nil when no episode matches, so nothing is ticked rather than a wrong one.
func (m *EpisodeMap) Episode(ctx context.Context, key core.EpisodeKey, imdb string, title core.Title, episodes []catalog.Episode) *core.EpisodeKey {
	if stremioapi.Trusted(key, imdb, title, episodes) {
		return &key
	}
	var listed []Video
	if s := m.cache.series(ctx, imdb, m.source); s != nil {
		listed = s.Videos
		if listed == nil {
			listed = []Video{}
		}
	}
	return stremioapi.Place(key, imdb, title, episodes, listed)
}

// Cache sizes: Cinemeta's entries for a few hours, since a player reports each episode several times.
const (
	SeriesLifetime = 6 * time.Hour
	SeriesCapacity = 200
)

type cachedSeries struct {
	fetched time.Time
	series  Series
}

type seriesCache struct {
	mu      sync.Mutex
	entries map[string]cachedSeries
	now     func() time.Time
}

// series is nil when Cinemeta failed; an empty entry when it does not know the series. Failures are not
// cached.
func (c *seriesCache) series(ctx context.Context, imdb string, source SeriesSource) *Series {
	c.mu.Lock()
	if e, ok := c.entries[imdb]; ok && c.now().Sub(e.fetched) < SeriesLifetime {
		c.mu.Unlock()
		return &e.series
	}
	c.mu.Unlock()
	fetched, err := source.Series(ctx, imdb)
	if err != nil {
		return nil
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if len(c.entries) >= SeriesCapacity {
		clear(c.entries)
	}
	c.entries[imdb] = cachedSeries{fetched: c.now(), series: fetched}
	return &fetched
}
