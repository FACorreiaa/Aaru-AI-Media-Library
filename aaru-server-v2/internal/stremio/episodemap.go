package stremio

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"cmp"
	"context"
	"slices"
	"sync"
	"time"
)

// Video is one entry of Cinemeta's episode list for a series (StremioWatched.Video).
type Video struct {
	ID       string
	Season   int
	Episode  int
	Released *time.Time
}

// Series is Cinemeta's entry for an IMDb series: the episode list and TVDB's id for the show. TVDB, like
// TMDB, can keep as one show's season what IMDb lists as a series of its own (Bleach: Thousand-Year
// Blood War), so the TVDB id names the show Aaru tracks.
type Series struct {
	TVDB   *string
	Videos []Video
}

// SeriesSource is Cinemeta's `meta/series/{imdb}.json`. An empty Series when Cinemeta does not know
// the series; an error when it failed. The Stremio import (StremioAccount) implements it.
type SeriesSource interface {
	Series(ctx context.Context, imdb string) (Series, error)
}

// Ordered is Cinemeta's videos in show order: season, episode, then release day (undated first).
func Ordered(videos []Video) []Video {
	out := slices.Clone(videos)
	slices.SortStableFunc(out, func(a, b Video) int {
		if c := cmp.Compare(a.Season, b.Season); c != 0 {
			return c
		}
		if c := cmp.Compare(a.Episode, b.Episode); c != 0 {
			return c
		}
		return releasedOrPast(a.Released).Compare(releasedOrPast(b.Released))
	})
	return out
}

func releasedOrPast(t *time.Time) time.Time {
	if t == nil {
		return time.Time{}
	}
	return *t
}

// EpisodeMap puts Stremio's episode numbers on the TMDB show. Stremio names an episode by Cinemeta's
// numbers (`tt…:season:episode`, IMDb's seasons), and TMDB can number the same episodes differently:
// Bleach: Thousand-Year Blood War is its own IMDb series with seasons 1 to 4, while TMDB keeps it as
// season 2 of Bleach. Such an episode is found on the TMDB show by the day Cinemeta says it came out.
type EpisodeMap struct {
	source SeriesSource
	cache  *seriesCache
}

// Tolerance is how far TMDB's air date may sit from Cinemeta's release day: time zones, a day-late upload.
const Tolerance = 36 * time.Hour

// NewEpisodeMap is a map over Cinemeta's series with a fresh cache.
func NewEpisodeMap(source SeriesSource) *EpisodeMap {
	return &EpisodeMap{source: source, cache: &seriesCache{entries: map[string]cachedSeries{}, now: time.Now}}
}

// TVDB is TVDB's id for IMDb series `imdb`, which names the show Aaru tracks when TMDB lists the series
// as an entry of its own (TMDB `336301` for `tt14986406`, a near-empty duplicate).
func (m *EpisodeMap) TVDB(ctx context.Context, imdb string) *string {
	s := m.cache.series(ctx, imdb, m.source)
	if s == nil {
		return nil
	}
	return s.TVDB
}

// Episode is the episode of `title` that Stremio's `key` of IMDb series `imdb` is. `key` itself when the
// numbers can be trusted; nil when no episode matches, so nothing is ticked rather than a wrong one.
func (m *EpisodeMap) Episode(ctx context.Context, key core.EpisodeKey, imdb string, title core.Title, episodes []catalog.Episode) *core.EpisodeKey {
	if Trusted(key, imdb, title, episodes) {
		return &key
	}
	var listed []Video
	if s := m.cache.series(ctx, imdb, m.source); s != nil {
		listed = s.Videos
		if listed == nil {
			listed = []Video{}
		}
	}
	return Place(key, imdb, title, episodes, listed)
}

// Trusted is true when Stremio's number is the show's own: the show is that IMDb series (or its IMDb id
// is unknown) and has the episode.
func Trusted(key core.EpisodeKey, imdb string, title core.Title, episodes []catalog.Episode) bool {
	return sameSeries(imdb, title) && slices.ContainsFunc(episodes, func(e catalog.Episode) bool {
		return e.Season == key.Season && e.Episode == key.Episode
	})
}

// Place is Episode without the fetch, for a caller that has Cinemeta's list (`listed`, nil when Cinemeta
// failed): the history import (IMP-016) and the addon share one rule.
func Place(key core.EpisodeKey, imdb string, title core.Title, episodes []catalog.Episode, listed []Video) *core.EpisodeKey {
	if Trusted(key, imdb, title, episodes) {
		return &key
	}
	var fallback *core.EpisodeKey
	if sameSeries(imdb, title) {
		fallback = &key
	}
	if listed == nil {
		return fallback
	}
	if matched := Match(key, listed, episodes); matched != nil {
		return matched
	}
	return fallback
}

func sameSeries(imdb string, title core.Title) bool {
	return title.IDs.IMDB == "" || title.IDs.IMDB == imdb
}

func absDuration(d time.Duration) time.Duration {
	if d < 0 {
		return -d
	}
	return d
}

// Match is the TMDB episode that aired when Cinemeta's `key` did. Two episodes out the same day pair up
// in order, and only when both lists have the same number of them that day.
func Match(key core.EpisodeKey, listed []Video, episodes []catalog.Episode) *core.EpisodeKey {
	var released *time.Time
	for _, v := range listed {
		if v.Season == key.Season && v.Episode == key.Episode {
			released = v.Released
			break
		}
	}
	if released == nil {
		return nil
	}
	var sameDay []Video
	for _, v := range listed {
		if v.Season > 0 && v.Released != nil && absDuration(v.Released.Sub(*released)) < time.Hour {
			sameDay = append(sameDay, v)
		}
	}
	sameDay = Ordered(sameDay)
	var aired []catalog.Episode
	for _, e := range episodes {
		if e.Season > 0 && e.AirsAt != nil && absDuration(e.AirsAt.Sub(*released)) <= Tolerance {
			aired = append(aired, e)
		}
	}
	slices.SortStableFunc(aired, func(a, b catalog.Episode) int {
		if c := cmp.Compare(a.Season, b.Season); c != 0 {
			return c
		}
		return cmp.Compare(a.Episode, b.Episode)
	})
	order := slices.IndexFunc(sameDay, func(v Video) bool { return v.Season == key.Season && v.Episode == key.Episode })
	if order < 0 || len(aired) != len(sameDay) {
		return nil
	}
	mapped, err := core.NewEpisodeKey(aired[order].Season, aired[order].Episode)
	if err != nil {
		return nil
	}
	return &mapped
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
