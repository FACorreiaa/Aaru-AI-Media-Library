package core

import (
	"encoding/json"
	"fmt"
	"slices"
)

// ShowProgress is the episode ticks for a show.
type ShowProgress struct {
	// Watched is every episode the user has marked watched.
	Watched        map[EpisodeKey]struct{}
	CurrentSeason  *int
	CurrentEpisode *int
}

// WatchedCount is how many episodes are ticked.
func (p ShowProgress) WatchedCount() int { return len(p.Watched) }

// FurthestWatched is the furthest episode ticked, by season then episode.
func (p ShowProgress) FurthestWatched() (EpisodeKey, bool) {
	var best EpisodeKey
	found := false
	for key := range p.Watched {
		if !found || best.Less(key) {
			best, found = key, true
		}
	}
	return best, found
}

// WatchedSorted is the ticks in episode order.
func (p ShowProgress) WatchedSorted() []EpisodeKey {
	keys := make([]EpisodeKey, 0, len(p.Watched))
	for key := range p.Watched {
		keys = append(keys, key)
	}
	slices.SortFunc(keys, EpisodeKey.Compare)
	return keys
}

type showProgressJSON struct {
	Watched        []EpisodeKey `json:"watched"`
	CurrentSeason  *int         `json:"currentSeason,omitempty"`
	CurrentEpisode *int         `json:"currentEpisode,omitempty"`
}

// MarshalJSON encodes the ticks as an array, in episode order.
func (p ShowProgress) MarshalJSON() ([]byte, error) {
	return json.Marshal(showProgressJSON{Watched: p.WatchedSorted(), CurrentSeason: p.CurrentSeason, CurrentEpisode: p.CurrentEpisode})
}

// UnmarshalJSON reads the ticks as a set.
func (p *ShowProgress) UnmarshalJSON(data []byte) error {
	var raw showProgressJSON
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	p.Watched = make(map[EpisodeKey]struct{}, len(raw.Watched))
	for _, key := range raw.Watched {
		p.Watched[key] = struct{}{}
	}
	p.CurrentSeason, p.CurrentEpisode = raw.CurrentSeason, raw.CurrentEpisode
	return nil
}

// BookProgress is an optional reading position for a book.
type BookProgress struct {
	Page    *int     `json:"page,omitempty"`
	Percent *float64 `json:"percent,omitempty"`
}

// NewBookProgress rejects a negative page or a percent outside 0…100.
func NewBookProgress(page *int, percent *float64) (BookProgress, error) {
	if page != nil && *page < 0 {
		return BookProgress{}, &ValidationError{Kind: InvalidBookProgress}
	}
	if percent != nil && (*percent < 0 || *percent > 100) {
		return BookProgress{}, &ValidationError{Kind: InvalidBookProgress}
	}
	return BookProgress{Page: page, Percent: percent}, nil
}

// MangaProgress is the reading position for a manga (MNG-001): the last chapter and
// volume read. Either or both, since some readers count chapters and others volumes.
type MangaProgress struct {
	Chapter *int `json:"chapter,omitempty"`
	Volume  *int `json:"volume,omitempty"`
}

// NewMangaProgress rejects a negative chapter or volume.
func NewMangaProgress(chapter, volume *int) (MangaProgress, error) {
	if (chapter != nil && *chapter < 0) || (volume != nil && *volume < 0) {
		return MangaProgress{}, &ValidationError{Kind: InvalidMangaProgress}
	}
	return MangaProgress{Chapter: chapter, Volume: volume}, nil
}

// Progress is a library item's progress, if its media type has any. Exactly one
// field is set. Movies carry none: `finished` is the whole signal.
type Progress struct {
	Show  *ShowProgress
	Book  *BookProgress
	Manga *MangaProgress
}

type progressJSON struct {
	Kind  string         `json:"kind"`
	Show  *ShowProgress  `json:"show,omitempty"`
	Book  *BookProgress  `json:"book,omitempty"`
	Manga *MangaProgress `json:"manga,omitempty"`
}

// MarshalJSON writes `{"kind": "show", "show": {…}}`, as AaruCore does.
func (p Progress) MarshalJSON() ([]byte, error) {
	switch {
	case p.Show != nil:
		return json.Marshal(progressJSON{Kind: "show", Show: p.Show})
	case p.Book != nil:
		return json.Marshal(progressJSON{Kind: "book", Book: p.Book})
	case p.Manga != nil:
		return json.Marshal(progressJSON{Kind: "manga", Manga: p.Manga})
	}
	return nil, fmt.Errorf("progress has no kind")
}

// UnmarshalJSON reads the tagged form.
func (p *Progress) UnmarshalJSON(data []byte) error {
	var raw progressJSON
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	*p = Progress{}
	switch raw.Kind {
	case "show":
		if raw.Show == nil {
			return fmt.Errorf("progress kind show has no show")
		}
		p.Show = raw.Show
	case "book":
		if raw.Book == nil {
			return fmt.Errorf("progress kind book has no book")
		}
		p.Book = raw.Book
	case "manga":
		if raw.Manga == nil {
			return fmt.Errorf("progress kind manga has no manga")
		}
		p.Manga = raw.Manga
	default:
		return fmt.Errorf("unknown progress kind %q", raw.Kind)
	}
	return nil
}
