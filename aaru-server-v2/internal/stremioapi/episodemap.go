package stremioapi

import (
	"aaru-go-api/internal/catalog"
	"aaru-go-api/internal/core"
	"slices"
	"sort"
	"time"
)

// Stremio names an episode by Cinemeta's numbers (`tt…:season:episode`, IMDb's seasons), and TMDB
// can number the same episodes differently: Bleach: Thousand-Year Blood War is its own IMDb series
// with seasons 1 to 4, while TMDB keeps it as season 2 of Bleach. Such an episode is found on the
// TMDB show by the day Cinemeta says it came out (StremioEpisodeMap's static rules; the addon's
// cached wrapper is the addon's own).

// Tolerance is how far TMDB's air date may sit from Cinemeta's release day: time zones, a day-late
// upload.
const Tolerance = 36 * time.Hour

// Trusted is true when Stremio's number is the show's own: the show is that IMDb series (or its
// IMDb id is unknown) and has the episode.
func Trusted(key core.EpisodeKey, imdb string, title core.Title, episodes []catalog.Episode) bool {
	if !sameSeries(imdb, title) {
		return false
	}
	return slices.ContainsFunc(episodes, func(e catalog.Episode) bool {
		return e.Season == key.Season && e.Episode == key.Episode
	})
}

// Place is the episode of title that Stremio's key of IMDb series imdb is, for a caller that has
// Cinemeta's list. listed nil means Cinemeta failed; an empty, non-nil list means it knows no
// episodes. nil when no episode matches, so nothing is ticked rather than a wrong one. The history
// import (IMP-016) and the addon share this rule.
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

// Match is the TMDB episode that aired when Cinemeta's key did. Two episodes out the same day pair
// up in order, and only when both lists have the same number of them that day.
func Match(key core.EpisodeKey, listed []Video, episodes []catalog.Episode) *core.EpisodeKey {
	i := slices.IndexFunc(listed, func(v Video) bool { return v.Season == key.Season && v.Episode == key.Episode })
	if i < 0 || listed[i].Released == nil {
		return nil
	}
	released := *listed[i].Released
	var same []Video
	for _, v := range listed {
		if v.Season > 0 && v.Released != nil && absDuration(v.Released.Sub(released)) < time.Hour {
			same = append(same, v)
		}
	}
	sameDay := Ordered(same)
	var aired []catalog.Episode
	for _, e := range episodes {
		if e.Season > 0 && e.AirsAt != nil && absDuration(e.AirsAt.Sub(released)) <= Tolerance {
			aired = append(aired, e)
		}
	}
	sort.SliceStable(aired, func(a, b int) bool {
		if aired[a].Season != aired[b].Season {
			return aired[a].Season < aired[b].Season
		}
		return aired[a].Episode < aired[b].Episode
	})
	order := slices.IndexFunc(sameDay, func(v Video) bool { return v.Season == key.Season && v.Episode == key.Episode })
	if order < 0 || len(aired) != len(sameDay) {
		return nil
	}
	placed, err := core.NewEpisodeKey(aired[order].Season, aired[order].Episode)
	if err != nil {
		return nil
	}
	return &placed
}

func absDuration(d time.Duration) time.Duration {
	if d < 0 {
		return -d
	}
	return d
}
