package catalog

import "aaru-go-api/internal/core"

// NamedEpisode is an episode as a source names it: a season number when the source
// has one, and the episode's title. Netflix's viewing activity and its player both
// give these, never TMDB's numbering.
type NamedEpisode struct {
	Season *int   `json:"season,omitempty"`
	Name   string `json:"name"`
}

// EpisodeNames is one show's episodes by normalized name, so each name a source gives costs a map
// lookup, not a pass over the whole show (PERF-004). A Netflix history asks for many.
type EpisodeNames map[string][]Episode

// NewEpisodeNames indexes episodes, keeping their order within a name.
func NewEpisodeNames(episodes []Episode) EpisodeNames {
	names := make(EpisodeNames, len(episodes))
	for _, e := range episodes {
		if e.Name == nil {
			continue
		}
		name := core.NormalizeTitle(*e.Name)
		names[name] = append(names[name], e)
	}
	return names
}

// MatchEpisodeName (IMP-018, SCR-007) finds an episode named by a source in the
// catalog's episode list. Same season first; if the source's seasons differ from
// TMDB's (Netflix splits and merges them), the one episode in the whole show with
// that name. Two with the name is no answer.
func MatchEpisodeName(named NamedEpisode, episodes []Episode) (core.EpisodeKey, bool) {
	return NewEpisodeNames(episodes).Match(named)
}

// Match is MatchEpisodeName over the index.
func (n EpisodeNames) Match(named NamedEpisode) (core.EpisodeKey, bool) {
	wanted := core.NormalizeTitle(named.Name)
	if wanted == "" {
		return core.EpisodeKey{}, false
	}
	matches := n[wanted]
	key := func(e Episode) (core.EpisodeKey, bool) {
		k, err := core.NewEpisodeKey(e.Season, e.Episode)
		return k, err == nil
	}
	if named.Season != nil {
		var inSeason []Episode
		for _, e := range matches {
			if e.Season == *named.Season {
				inSeason = append(inSeason, e)
			}
		}
		if len(inSeason) == 1 {
			return key(inSeason[0])
		}
	}
	// Specials (season 0) only match when the source said season 0.
	var regular []Episode
	for _, e := range matches {
		if e.Season != 0 || (named.Season != nil && *named.Season == 0) {
			regular = append(regular, e)
		}
	}
	if len(regular) != 1 {
		return core.EpisodeKey{}, false
	}
	return key(regular[0])
}
