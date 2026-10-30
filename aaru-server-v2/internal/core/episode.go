package core

import (
	"encoding/json"
	"fmt"
	"time"
)

// EpisodeKey is a season/episode coordinate.
//
// This is the identity used for progress. Provider episode ids are stored on
// Episode, never used as the progress key — a user can tick an episode Aaru
// has not hydrated yet. Season 0 holds specials.
type EpisodeKey struct {
	Season  int `json:"season"`
	Episode int `json:"episode"`
}

// NewEpisodeKey rejects a negative season or an episode below 1.
func NewEpisodeKey(season, episode int) (EpisodeKey, error) {
	if season < 0 || episode < 1 {
		return EpisodeKey{}, &ValidationError{Kind: InvalidEpisodeNumber, Season: season, Episode: episode}
	}
	return EpisodeKey{Season: season, Episode: episode}, nil
}

// Less orders by season, then episode.
func (k EpisodeKey) Less(other EpisodeKey) bool {
	if k.Season != other.Season {
		return k.Season < other.Season
	}
	return k.Episode < other.Episode
}

// Compare is -1, 0 or 1, for slices.SortFunc.
func (k EpisodeKey) Compare(other EpisodeKey) int {
	switch {
	case k.Less(other):
		return -1
	case other.Less(k):
		return 1
	}
	return 0
}

// String is `S01E02`. Stable enough to log and to show in a UI.
func (k EpisodeKey) String() string {
	return fmt.Sprintf("S%02dE%02d", k.Season, k.Episode)
}

// UnmarshalJSON validates the coordinate.
func (k *EpisodeKey) UnmarshalJSON(data []byte) error {
	var raw struct {
		Season  *int `json:"season"`
		Episode *int `json:"episode"`
	}
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	if raw.Season == nil || raw.Episode == nil {
		return fmt.Errorf("episode key needs a season and an episode")
	}
	key, err := NewEpisodeKey(*raw.Season, *raw.Episode)
	if err != nil {
		return err
	}
	*k = key
	return nil
}

// Episode is one episode of a show, as the catalog describes it.
type Episode struct {
	Key     EpisodeKey
	Name    *string
	AirDate *time.Time
	// TMDBID is the TMDB episode id, when hydration supplied one.
	TMDBID *string
}

// Season is one season of a show.
type Season struct {
	Number   int
	Name     *string
	Episodes []Episode
}
